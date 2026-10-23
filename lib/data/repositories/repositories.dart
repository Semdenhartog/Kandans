import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import '../models/models.dart';
import '../services/elevation_service.dart';
import '../services/offline_cache.dart';
import '../../domain/best_efforts.dart';
import '../../domain/geo.dart';
import '../../domain/run_streams.dart';
import '../../domain/training_plan.dart';

/// Alle database-toegang via Supabase. Row Level Security zorgt ervoor
/// dat elke gebruiker alleen zijn eigen rijen kan zien en wijzigen.
class RunWiseRepository {
  RunWiseRepository(this._db);

  final SupabaseClient _db;

  /// Kolommen voor de runlijst (zonder het zware verloop per seconde).
  static const _activityColumns =
      'id, started_at, distance_meters, moving_time_seconds, source, route_id, average_heart_rate, '
      'elevation_gain_meters, temperature_celsius, feels_like_celsius, wind_speed_kmh, wind_direction_degrees, '
      'humidity_pct, track_polyline, route_link_locked, shoe_id, feel, note, best_efforts, photos, ai_summary, external_id';

  /// Verloop van een run (tijden per km, grafiek). Eigen opnames hebben het al; bij Strava-runs
  /// wordt het eenmalig bij Strava opgehaald. De snelste stukken worden er meteen bij berekend.
  Future<Map<String, dynamic>?> activityStreams(String activityId) async {
    final row = await _db.from('activities').select('streams, source, best_efforts').eq('id', activityId).maybeSingle();
    var streams = row?['streams'] is Map ? (row!['streams'] as Map).cast<String, dynamic>() : null;
    if (streams == null && row?['source'] == 'strava') {
      try {
        final res = await _db.functions.invoke('strava', body: {'action': 'streams', 'activity_id': activityId});
        final data = (res.data as Map?)?['streams'];
        streams = data is Map ? data.cast<String, dynamic>() : null;
      } on FunctionException catch (e) {
        final details = e.details is Map ? (e.details as Map).cast<String, dynamic>() : <String, dynamic>{};
        throw Exception(details['error'] ?? 'Tijden per km konden niet worden opgehaald.');
      }
    }
    if (streams != null && row?['best_efforts'] == null) {
      final parsed = RunStreams.fromJson(streams);
      if (parsed != null) {
        setActivityBestEfforts(activityId, bestEffortsToJson(bestEfforts(parsed))).ignore();
      }
    }
    return streams;
  }

  /// Rijen ophalen; zonder internet de laatst bewaarde rijen.
  Future<List<Map<String, dynamic>>> _rows(String key, Future<List<Map<String, dynamic>>> Function() fresh) =>
      OfflineCache.fetch<List<Map<String, dynamic>>>(
        '${_db.auth.currentUser?.id ?? 'anon'}_$key',
        fresh,
        encode: (v) => v,
        decode: (d) => [for (final m in (d as List).cast<Map>()) m.cast<String, dynamic>()],
      );

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw Exception('Je bent niet ingelogd.');
    return id;
  }

  // ---------- Profiel ----------

  Future<Profile?> profile() async {
    final uid = _uid;
    final rows = await _rows('profile', () async {
      final row = await _db.from('profiles').select().eq('id', uid).maybeSingle();
      return row == null ? <Map<String, dynamic>>[] : [row];
    });
    return rows.isEmpty ? null : Profile.fromJson(rows.first);
  }

  Future<void> updateHome(double lat, double lon) async {
    await _db
        .from('profiles')
        .update({'home_latitude': lat, 'home_longitude': lon}).eq('id', _uid);
  }

  // ---------- Runs ----------

  Future<List<Activity>> activities() async {
    final uid = _uid;
    final rows = await _rows(
      'activities',
      () => _db
          .from('activities')
          .select(_activityColumns)
          .eq('user_id', uid)
          .order('started_at', ascending: false)
          .limit(500),
    );
    return rows.map(Activity.fromJson).toList();
  }

  Future<void> addActivity(Activity a) async {
    await _db.from('activities').insert(a.toInsert(_uid));
  }

  /// Slaat een run op en geeft het id terug.
  Future<String> addActivityReturningId(Activity a) async {
    final row = await _db.from('activities').insert(a.toInsert(_uid)).select('id').single();
    return row['id'] as String;
  }

  /// Een in RunWise opgenomen run opslaan. Met een vaste [externalId] maakt opnieuw
  /// versturen (na een verbroken verbinding) nooit een tweede run.
  Future<String> addRecordedRun(Activity a, String externalId) async {
    final row = await _db
        .from('activities')
        .upsert({...a.toInsert(_uid), 'external_id': externalId}, onConflict: 'user_id,source,external_id')
        .select('id')
        .single()
        .timeout(const Duration(seconds: 20));
    return row['id'] as String;
  }

  Future<void> deleteActivity(String id) async {
    // Eerst de foto's bij deze run uit de opslag halen.
    try {
      final row = await _db.from('activities').select('photos').eq('id', id).maybeSingle();
      final photos = (row?['photos'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
      if (photos.isNotEmpty) await _db.storage.from(_photoBucket).remove(photos);
    } catch (_) {}
    await _db.from('activities').delete().eq('id', id);
  }

  // ---------- Trainingsschema ----------

  Future<List<PlanSession>> planSessions() async {
    final rows = await _rows('plan', () async {
      final r = await _db.from('plan_sessions').select().order('session_date');
      return List<Map<String, dynamic>>.from(r);
    });
    return [for (final r in rows) PlanSession.fromRow(r)].whereType<PlanSession>().toList();
  }

  /// Vervangt het hele schema.
  Future<void> savePlan(List<PlanSession> sessions) async {
    final uid = _db.auth.currentUser!.id;
    await _db.from('plan_sessions').delete().eq('user_id', uid);
    if (sessions.isEmpty) return;
    await _db.from('plan_sessions').insert([for (final s in sessions) s.toRow(uid)]);
  }

  // ---------- Foto's bij runs ----------

  static const _photoBucket = 'run-photos';

  /// Slaat een foto op bij een run en geeft het pad terug.
  Future<String> addActivityPhoto(String activityId, Uint8List jpeg) async {
    final uid = _db.auth.currentUser!.id;
    final path = '$uid/$activityId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage.from(_photoBucket).uploadBinary(
          path,
          jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
        );
    final row = await _db.from('activities').select('photos').eq('id', activityId).single();
    final list = [...((row['photos'] as List?) ?? const []).map((e) => e.toString()), path];
    await _db.from('activities').update({'photos': list}).eq('id', activityId);
    return path;
  }

  Future<void> removeActivityPhoto(String activityId, String path) async {
    await _db.storage.from(_photoBucket).remove([path]);
    final row = await _db.from('activities').select('photos').eq('id', activityId).single();
    final list = [...((row['photos'] as List?) ?? const []).map((e) => e.toString())]..remove(path);
    await _db.from('activities').update({'photos': list}).eq('id', activityId);
  }

  /// Tijdelijke links (1 uur) om foto's te tonen.
  Future<Map<String, String>> photoUrls(List<String> paths) async {
    if (paths.isEmpty) return const {};
    final signed = await _db.storage.from(_photoBucket).createSignedUrls(paths, 3600);
    return {for (final s in signed) s.path: s.signedUrl};
  }

  Future<Uint8List> downloadPhoto(String path) => _db.storage.from(_photoBucket).download(path);

  /// Koppelt een run aan een route (of los met null), door de gebruiker zelf.
  /// Daarna koppelt RunWise deze run niet meer automatisch.
  Future<void> setActivityRoute(String activityId, String? routeId) async {
    await _db.from('activities').update({'route_id': routeId, 'route_link_locked': true}).eq('id', activityId);
  }

  /// Automatische koppeling (blijft aanpasbaar door de gebruiker).
  Future<void> autoLinkActivity(String activityId, String routeId) async {
    await _db
        .from('activities')
        .update({'route_id': routeId})
        .eq('id', activityId)
        .isFilter('route_id', null)
        .eq('route_link_locked', false);
  }

  /// Hoe voelde de run (1 zwaar, 2 oké, 3 top) en een notitie.
  Future<void> setActivityFeel(String id, {int? feel, String? note}) async {
    await _db.from('activities').update({'feel': feel, 'note': (note ?? '').trim().isEmpty ? null : note!.trim()}).eq('id', id);
  }

  /// Verloop en snelste stukken van een run opslaan (eigen opnames, of berekend uit Strava-tijden).
  Future<void> setActivityStreams(String id, Map<String, dynamic> streams, {Map<String, double>? bestEfforts}) async {
    await _db.from('activities').update({
      'streams': streams,
      if (bestEfforts != null) 'best_efforts': bestEfforts,
    }).eq('id', id);
  }

  Future<void> setActivityElevation(String id, Map<String, dynamic> streams, double gain) async {
    await _db.from('activities').update({'streams': streams, 'elevation_gain_meters': double.parse(gain.toStringAsFixed(1))}).eq('id', id);
  }

  /// Hoogte van een run verbeteren met de hoogtekaart (op de achtergrond, fouten zijn niet erg).
  Future<void> improveElevation(String id, Map<String, dynamic> streams) async {
    try {
      final r = await ElevationService().correct(streams);
      if (r != null) await setActivityElevation(id, r.streams, r.gain);
    } catch (_) {}
  }

  /// Een eigen opname bijsnijden (vergeten te stoppen): nieuwe afstand, tijd, spoor en verloop.
  Future<void> saveTrimmedActivity(
    String id, {
    required DateTime startedAt,
    required double distanceMeters,
    required int movingSeconds,
    required int? averageHeartRate,
    required String trackPolyline,
    required Map<String, dynamic> streams,
    required Map<String, double> bestEfforts,
  }) async {
    await _db.from('activities').update({
      'started_at': startedAt.toUtc().toIso8601String(),
      'distance_meters': distanceMeters,
      'moving_time_seconds': movingSeconds,
      'average_pace_seconds_per_km':
          distanceMeters <= 0 ? null : double.parse((movingSeconds / (distanceMeters / 1000)).toStringAsFixed(2)),
      'average_heart_rate': averageHeartRate,
      'track_polyline': trackPolyline,
      'streams': streams,
      'best_efforts': bestEfforts,
      // Hoogtemeters en coachanalyse horen bij de oude run; worden opnieuw bepaald.
      'elevation_gain_meters': null,
      'ai_summary': null,
    }).eq('id', id);
  }

  Future<void> setActivityBestEfforts(String id, Map<String, double> bestEfforts) async {
    await _db.from('activities').update({'best_efforts': bestEfforts}).eq('id', id);
  }

  Future<void> setActivityShoe(String id, String? shoeId) async {
    await _db.from('activities').update({'shoe_id': shoeId}).eq('id', id);
  }

  // ---------- Schoenen ----------

  Future<List<Shoe>> shoes() async {
    final uid = _uid;
    final rows = await _rows('shoes', () => _db.from('shoes').select().eq('user_id', uid).order('created_at'));
    return rows.map(Shoe.fromJson).toList();
  }

  Future<void> addShoe(Shoe s) async {
    if (s.isDefault) await _clearDefaultShoe();
    await _db.from('shoes').insert(s.toInsert());
  }

  Future<void> _clearDefaultShoe() async {
    await _db.from('shoes').update({'is_default': false}).eq('user_id', _uid).eq('is_default', true);
  }

  Future<void> setDefaultShoe(String id) async {
    await _clearDefaultShoe();
    await _db.from('shoes').update({'is_default': true, 'retired': false}).eq('id', id);
  }

  Future<void> retireShoe(String id, bool retired) async {
    await _db.from('shoes').update({'retired': retired, if (retired) 'is_default': false}).eq('id', id);
  }

  Future<void> deleteShoe(String id) async {
    await _db.from('shoes').delete().eq('id', id);
  }

  // ---------- Routes ----------

  Future<List<RunRoute>> routes() async {
    final uid = _uid;
    final rows = await _rows(
      'routes',
      () => _db
          .from('routes')
          .select()
          .eq('user_id', uid)
          .order('is_favorite', ascending: false)
          .order('created_at', ascending: false),
    );
    return rows.map(RunRoute.fromJson).toList();
  }

  Future<RunRoute> routeWithPoints(String id) async {
    // Eerste rij = de route, de rest = punten per kilometer (zo in één keer te bewaren).
    final rows = await _rows('route_$id', () async {
      final row = await _db.from('routes').select().eq('id', id).single();
      final pts = await _db.from('route_points').select().eq('route_id', id).order('sequence_index');
      return [row, ...pts];
    });
    return RunRoute.fromJson(rows.first).copyWith(points: rows.skip(1).map(RoutePoint.fromJson).toList());
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

  /// Korte analyse van één run door de coach (wordt op de server bewaard).
  Future<String> summarizeRun(String activityId) async {
    try {
      final res = await _db.functions.invoke('coach', body: {'mode': 'summary', 'activity_id': activityId});
      final data = (res.data as Map).cast<String, dynamic>();
      return data['summary'] as String;
    } on FunctionException catch (e) {
      final details = e.details is Map ? (e.details as Map).cast<String, dynamic>() : <String, dynamic>{};
      if (e.status == 402 || details['paywall'] == true) throw const PaywallRequired();
      throw Exception(details['error'] ?? 'De coach is even niet bereikbaar. Probeer het zo opnieuw.');
    }
  }

  /// Ondergrond langs een route (asfalt, klinkers, halfverhard, onverhard), in meters per soort.
  /// Eenmaal opgehaald wordt het op de telefoon bewaard (een route verandert niet).
  Future<Map<String, double>> routeSurface(String routeId, String polyline) async {
    final key = 'surface_${routeId}_${polyline.length}';
    Map<String, double> decode(Object? d) => {for (final e in (d as Map).entries) e.key.toString(): (e.value as num).toDouble()};
    final cached = await OfflineCache.load(key);
    if (cached != null) return decode(cached.data);
    final pts = decodePolyline(polyline);
    if (pts.length < 2) return <String, double>{};
    final step = (pts.length / 49).ceil().clamp(1, pts.length);
    final sample = [for (var i = 0; i < pts.length; i += step) pts[i]];
    if (sample.last != pts.last) sample.add(pts.last);
    try {
      final res = await _db.functions.invoke('route-generator', body: {
        'mode': 'surface',
        'points': [
          for (final p in sample.take(50)) [p.lat, p.lon],
        ],
      });
      final list = ((res.data as Map)['surface'] as List?) ?? const [];
      final out = {
        for (final e in list.cast<Map>()) e['type'].toString(): (e['meters'] as num).toDouble(),
      };
      if (out.isNotEmpty) await OfflineCache.save(key, out);
      return out;
    } on FunctionException catch (e) {
      final details = e.details is Map ? (e.details as Map).cast<String, dynamic>() : <String, dynamic>{};
      throw Exception(details['error'] ?? 'Ondergrond ophalen is niet gelukt.');
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
    final shoes = await _db.from('shoes').select().eq('user_id', uid);
    return {
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'email': _db.auth.currentUser?.email,
      'profile': profile,
      'activities': activities,
      'routes': routes,
      'race_events': races,
      'coach_messages': coach,
      'monthly_goals': goals,
      'shoes': shoes,
    };
  }

  /// Verwijdert het account definitief via de Edge Function `delete-account`.
  Future<void> deleteAccount() async {
    final res = await _db.functions.invoke('delete-account');
    if (res.status != 200) {
      throw Exception('Account verwijderen is mislukt. Probeer het later opnieuw.');
    }
    await OfflineCache.clear();
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

/// Verloop van een run (alleen runs uit Strava).
/// Links naar de foto's van een run (sleutel: paden gescheiden door komma's).
final activityPhotoUrlsProvider = FutureProvider.family<Map<String, String>, String>((ref, joined) {
  if (joined.isEmpty) return const {};
  return ref.watch(repositoryProvider).photoUrls(joined.split(','));
});

final planProvider = FutureProvider<List<PlanSession>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(repositoryProvider).planSessions();
});

final activityStreamsProvider = FutureProvider.family<Map<String, dynamic>?, String>(
  (ref, id) => ref.watch(repositoryProvider).activityStreams(id),
);

final shoesProvider = FutureProvider<List<Shoe>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(repositoryProvider).shoes();
});

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

/// Ondergrond per route (sleutel: "routeId|polyline").
final routeSurfaceProvider = FutureProvider.family<Map<String, double>, ({String id, String polyline})>((ref, r) {
  return ref.watch(repositoryProvider).routeSurface(r.id, r.polyline);
});
