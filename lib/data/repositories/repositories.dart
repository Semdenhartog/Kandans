import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import '../models/models.dart';

/// Alle database-toegang via Supabase. Row Level Security zorgt ervoor
/// dat elke gebruiker alleen zijn eigen rijen kan zien en wijzigen.
class RunWiseRepository {
  RunWiseRepository(this._db);

  final SupabaseClient _db;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw Exception('Je bent niet ingelogd.');
    return id;
  }

  // ---------- Profiel ----------

  Future<Profile?> profile() async {
    final row = await _db.from('profiles').select().eq('id', _uid).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<void> updateHome(double lat, double lon) async {
    await _db
        .from('profiles')
        .update({'home_latitude': lat, 'home_longitude': lon}).eq('id', _uid);
  }

  // ---------- Runs ----------

  Future<List<Activity>> activities() async {
    final rows = await _db
        .from('activities')
        .select()
        .eq('user_id', _uid)
        .order('started_at', ascending: false)
        .limit(500);
    return rows.map(Activity.fromJson).toList();
  }

  Future<void> addActivity(Activity a) async {
    await _db.from('activities').insert(a.toInsert(_uid));
  }

  Future<void> deleteActivity(String id) async {
    await _db.from('activities').delete().eq('id', id);
  }

  /// Koppelt een run aan een route (of los met null).
  Future<void> setActivityRoute(String activityId, String? routeId) async {
    await _db.from('activities').update({'route_id': routeId}).eq('id', activityId);
  }

  // ---------- Routes ----------

  Future<List<RunRoute>> routes() async {
    final rows = await _db
        .from('routes')
        .select()
        .eq('user_id', _uid)
        .order('is_favorite', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(RunRoute.fromJson).toList();
  }

  Future<RunRoute> routeWithPoints(String id) async {
    final row = await _db.from('routes').select().eq('id', id).single();
    final pts = await _db
        .from('route_points')
        .select()
        .eq('route_id', id)
        .order('sequence_index');
    return RunRoute.fromJson(row)
        .copyWith(points: pts.map(RoutePoint.fromJson).toList());
  }

  /// Slaat een route op met de punten per kilometer.
  Future<String> addRoute(RunRoute route) async {
    final row = await _db
        .from('routes')
        .insert(route.toInsert(_uid))
        .select('id')
        .single();
    final routeId = row['id'] as String;
    if (route.points.isNotEmpty) {
      final points = <Map<String, dynamic>>[];
      for (var i = 0; i < route.points.length; i++) {
        final p = route.points[i];
        points.add({
          'route_id': routeId,
          'sequence_index': i,
          'km_marker': double.parse(p.kmMarker.toStringAsFixed(3)),
          'latitude': p.latitude,
          'longitude': p.longitude,
          'elevation_meters': p.elevation,
          'bearing_degrees': p.bearing,
        });
      }
      await _db.from('route_points').insert(points);
    }
    return routeId;
  }

  Future<void> setFavorite(String id, bool favorite) async {
    await _db.from('routes').update({'is_favorite': favorite}).eq('id', id);
  }

  Future<void> deleteRoute(String id) async {
    await _db.from('routes').delete().eq('id', id);
  }

  // ---------- Maanduitdaging ----------

  static String _monthKey(DateTime m) =>
      '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}-01';

  /// Doel (km) voor de maand van [month], of null als er nog geen is.
  Future<double?> monthlyGoal(DateTime month) async {
    final row = await _db
        .from('monthly_goals')
        .select('target_km')
        .eq('user_id', _uid)
        .eq('month', _monthKey(month))
        .maybeSingle();
    final v = row?['target_km'];
    return v == null ? null : (v as num).toDouble();
  }

  Future<void> setMonthlyGoal(DateTime month, double km) async {
    await _db.from('monthly_goals').upsert({
      'user_id': _uid,
      'month': _monthKey(month),
      'target_km': km,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> deleteMonthlyGoal(DateTime month) async {
    await _db.from('monthly_goals').delete().eq('user_id', _uid).eq('month', _monthKey(month));
  }

  // ---------- Wedstrijden ----------

  Future<List<RaceEvent>> races() async {
    final rows = await _db
        .from('race_events')
        .select()
        .eq('user_id', _uid)
        .order('race_date');
    return rows.map(RaceEvent.fromJson).toList();
  }

  Future<RaceEvent> race(String id) async {
    final row = await _db.from('race_events').select().eq('id', id).single();
    return RaceEvent.fromJson(row);
  }

  Future<void> addRace(RaceEvent r) async {
    await _db.from('race_events').insert(r.toInsert(_uid));
  }

  Future<void> saveRaceAdvice(
    String id, {
    required int predictedFinishSeconds,
    required int temperatureImpactSeconds,
    required int windImpactSeconds,
    required String clothing,
    required String hydration,
    required String pacing,
  }) async {
    await _db.from('race_events').update({
      'predicted_finish_seconds': predictedFinishSeconds,
      'temperature_impact_seconds': temperatureImpactSeconds,
      'wind_impact_seconds': windImpactSeconds,
      'clothing_advice': clothing,
      'hydration_advice': hydration,
      'pacing_advice': pacing,
      'advice_computed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> deleteRace(String id) async {
    await _db.from('race_events').delete().eq('id', id);
  }

  // ---------- AI-coach ----------

  Future<List<CoachMessage>> coachMessages() async {
    final rows = await _db
        .from('coach_messages')
        .select()
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(CoachMessage.fromJson).toList().reversed.toList();
  }

  /// Stuurt een vraag naar de coach (server-functie `coach`).
  Future<CoachReply> askCoach(String message) async {
    try {
      final res = await _db.functions.invoke('coach', body: {'message': message});
      final data = (res.data as Map).cast<String, dynamic>();
      return CoachReply(
        reply: data['reply'] as String,
        freeLeft: (data['free_left'] as num?)?.toInt(),
      );
    } on FunctionException catch (e) {
      final details = e.details is Map ? (e.details as Map).cast<String, dynamic>() : <String, dynamic>{};
      if (e.status == 402 || details['paywall'] == true) throw const PaywallRequired();
      throw Exception(details['error'] ?? 'De coach is even niet bereikbaar. Probeer het zo opnieuw.');
    }
  }

  Future<void> clearCoachChat() async {
    await _db.from('coach_messages').delete().eq('user_id', _uid);
  }

  // ---------- Account ----------

  /// Alle eigen gegevens als één overzicht (AVG: recht op inzage).
  Future<Map<String, dynamic>> exportAll() async {
    final uid = _uid;
    final profile = await _db.from('profiles').select().eq('id', uid).maybeSingle();
    final activities = await _db.from('activities').select().eq('user_id', uid);
    final routes = await _db.from('routes').select().eq('user_id', uid);
    final races = await _db.from('race_events').select().eq('user_id', uid);
    final coach = await _db.from('coach_messages').select().eq('user_id', uid);
    final goals = await _db.from('monthly_goals').select().eq('user_id', uid);
    return {
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'email': _db.auth.currentUser?.email,
      'profile': profile,
      'activities': activities,
      'routes': routes,
      'race_events': races,
      'coach_messages': coach,
      'monthly_goals': goals,
    };
  }

  /// Verwijdert het account definitief via de Edge Function `delete-account`.
  Future<void> deleteAccount() async {
    final res = await _db.functions.invoke('delete-account');
    if (res.status != 200) {
      throw Exception('Account verwijderen is mislukt. Probeer het later opnieuw.');
    }
    await _db.auth.signOut();
  }
}

/// Antwoord van de coach.
class CoachReply {
  CoachReply({required this.reply, this.freeLeft});
  final String reply;

  /// Aantal gratis vragen dat nog over is (null bij premium).
  final int? freeLeft;
}

/// De gratis vragen zijn op: toon de paywall.
class PaywallRequired implements Exception {
  const PaywallRequired();
}

final repositoryProvider = Provider<RunWiseRepository>(
  (ref) => RunWiseRepository(ref.watch(supabaseProvider)),
);

// Gegevens die schermen gebruiken. Na een wijziging: ref.invalidate(...).

final profileProvider = FutureProvider<Profile?>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(repositoryProvider).profile();
});

final activitiesProvider = FutureProvider<List<Activity>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(repositoryProvider).activities();
});

final routesProvider = FutureProvider<List<RunRoute>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(repositoryProvider).routes();
});

final routeDetailProvider = FutureProvider.family<RunRoute, String>(
  (ref, id) => ref.watch(repositoryProvider).routeWithPoints(id),
);

final racesProvider = FutureProvider<List<RaceEvent>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(repositoryProvider).races();
});

final raceDetailProvider = FutureProvider.family<RaceEvent, String>(
  (ref, id) => ref.watch(repositoryProvider).race(id),
);

final coachMessagesProvider = FutureProvider<List<CoachMessage>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(repositoryProvider).coachMessages();
});
