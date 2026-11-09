import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/i18n.dart';
import '../models/models.dart';

/// Samen-extra's: loopmaatjes, weddenschappen en loopgroepen (SQL in 0037).
class Buddy {
  const Buddy(this.nickname, this.km, this.paceSec, this.times, this.note);
  final String nickname;
  final int km;
  final int paceSec;
  final List<String> times;
  final String? note;
}

class Bet {
  const Bet({
    required this.id,
    required this.other,
    required this.iCreated,
    required this.stake,
    required this.startsOn,
    required this.endsOn,
    required this.status,
    required this.myKm,
    required this.theirKm,
  });
  final int id;
  final String other;
  final bool iCreated;
  final String stake;
  final DateTime startsOn, endsOn;
  final String status;
  final double myKm, theirKm;

  bool get open => status == 'open';
  bool get finished => DateTime.now().isAfter(endsOn.add(const Duration(days: 1)));
}

class RunGroup {
  const RunGroup(this.id, this.name, this.code, this.members, this.isOwner, this.routeName, this.routePolyline);
  final int id;
  final String name, code;
  final int members;
  final bool isOwner;
  final String? routeName, routePolyline;
}

class GroupRow {
  const GroupRow(this.nickname, this.isMe, this.weekKm, this.monthKm);
  final String nickname;
  final bool isMe;
  final double weekKm, monthKm;
}

String _msg(Object e) {
  if (e is PostgrestException) return e.message;
  return e.toString().replaceFirst('Exception: ', '');
}

/// Een geplande groepsrun in de agenda van een loopgroep (0040).
class GroupRun {
  const GroupRun({
    required this.id,
    required this.startsAt,
    this.place,
    this.distanceKm,
    this.note,
    this.planner = '',
    this.going = 0,
    this.notGoing = 0,
    this.goingNames = const [],
    this.myAnswer,
    this.canDelete = false,
  });
  final int id;
  final DateTime startsAt;
  final String? place;
  final double? distanceKm;
  final String? note;
  final String planner;
  final int going;
  final int notGoing;
  final List<String> goingNames;
  final bool? myAnswer;
  final bool canDelete;

  factory GroupRun.fromJson(Map<String, dynamic> j) => GroupRun(
        id: (j['id'] as num).toInt(),
        startsAt: DateTime.tryParse(j['starts_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        place: j['place'] as String?,
        distanceKm: (j['distance_km'] as num?)?.toDouble(),
        note: j['note'] as String?,
        planner: j['planner'] as String? ?? '',
        going: (j['going'] as num?)?.toInt() ?? 0,
        notGoing: (j['not_going'] as num?)?.toInt() ?? 0,
        goingNames: [for (final n in (j['going_names'] as List?) ?? const []) n.toString()],
        myAnswer: j['my_answer'] as bool?,
        canDelete: j['can_delete'] == true,
      );
}

class TogetherService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw Exception(_msg(e));
    }
  }

  // Loopmaatjes
  Future<({bool on, int? pace, List<String> times, String? note})> buddyMine() => _call(() async {
        final rows = await _db.rpc('buddy_mine') as List;
        if (rows.isEmpty) return (on: false, pace: null, times: const <String>[], note: null);
        final r = rows.first as Map<String, dynamic>;
        return (on: true, pace: (r['pace_sec'] as num?)?.toInt(), times: ((r['times'] as List?) ?? const []).cast<String>(), note: r['note'] as String?);
      });

  Future<void> buddySet({required bool on, double lat = 0, double lon = 0, int pace = 360, List<String> times = const [], String? note}) =>
      _call(() => _db.rpc('buddy_set', params: {'p_on': on, 'p_lat': lat, 'p_lon': lon, 'p_pace': pace, 'p_times': times, 'p_note': note}));

  Future<List<Buddy>> buddies() => _call(() async {
        final rows = await _db.rpc('buddy_find') as List;
        return [
          for (final r in rows.cast<Map<String, dynamic>>())
            Buddy(r['nickname'] as String, (r['km'] as num).toInt(), (r['pace_sec'] as num).toInt(), ((r['times'] as List?) ?? const []).cast<String>(), r['note'] as String?),
        ];
      });

  // Weddenschappen
  Future<List<Bet>> bets() => _call(() async {
        final rows = await _db.rpc('bets_list') as List;
        return [
          for (final r in rows.cast<Map<String, dynamic>>())
            Bet(
              id: (r['id'] as num).toInt(),
              other: r['other_nickname'] as String,
              iCreated: r['i_created'] as bool,
              stake: r['stake'] as String,
              startsOn: DateTime.parse(r['starts_on'] as String),
              endsOn: DateTime.parse(r['ends_on'] as String),
              status: r['status'] as String,
              myKm: (r['my_km'] as num).toDouble(),
              theirKm: (r['their_km'] as num).toDouble(),
            ),
        ];
      });

  Future<void> betCreate(String nickname, String stake, int days) =>
      _call(() => _db.rpc('bet_create', params: {'p_nickname': nickname, 'p_stake': stake, 'p_days': days}));

  Future<void> betAnswer(int id, bool accept) => _call(() => _db.rpc('bet_answer', params: {'p_id': id, 'p_accept': accept}));

  // Loopgroepen
  Future<List<RunGroup>> groups() => _call(() async {
        final rows = await _db.rpc('groups_mine') as List;
        return [
          for (final r in rows.cast<Map<String, dynamic>>())
            RunGroup((r['id'] as num).toInt(), r['name'] as String, r['code'] as String, (r['members'] as num).toInt(), r['is_owner'] as bool,
                r['route_name'] as String?, r['route_polyline'] as String?),
        ];
      });

  Future<String> groupCreate(String name) => _call(() async => await _db.rpc('group_create', params: {'p_name': name}) as String);
  Future<String> groupJoin(String code) => _call(() async {
        // De server geeft null bij een onbekende code (zo telt de poging mee voor de daglimiet).
        final name = await _db.rpc('group_join', params: {'p_code': code}) as String?;
        if (name == null) throw Exception(tr('Geen groep gevonden met deze code.'));
        return name;
      });
  Future<void> groupLeave(int id) => _call(() => _db.rpc('group_leave', params: {'p_id': id}));
  Future<void> groupSetRoute(int id, String? name, String? polyline) =>
      _call(() => _db.rpc('group_set_route', params: {'p_id': id, 'p_name': name, 'p_polyline': polyline}));

  Future<List<GroupRow>> board(int id) => _call(() async {
        final rows = await _db.rpc('group_board', params: {'p_id': id}) as List;
        return [
          for (final r in rows.cast<Map<String, dynamic>>())
            GroupRow(r['nickname'] as String, r['is_me'] as bool, (r['week_km'] as num).toDouble(), (r['month_km'] as num).toDouble()),
        ];
      });
  // Loopgroep-agenda (0040)
  Future<List<GroupRun>> groupRuns(int groupId) => _call(() async {
        final rows = await _db.rpc('group_runs_of', params: {'p_group': groupId}) as List;
        return [for (final r in rows.cast<Map<String, dynamic>>()) GroupRun.fromJson(r)];
      });

  Future<void> planGroupRun(int groupId, DateTime startsAt, {String? place, double? km, String? note}) => _call(() => _db.rpc('group_run_plan', params: {
        'p_group': groupId,
        'p_starts': startsAt.toUtc().toIso8601String(),
        'p_place': place,
        'p_km': km,
        'p_note': note,
      }));

  /// [going] null = antwoord intrekken.
  Future<void> answerGroupRun(int runId, bool? going) => _call(() => _db.rpc('group_run_answer', params: {'p_run': runId, 'p_going': going}));

  Future<void> deleteGroupRun(int runId) => _call(() => _db.rpc('group_run_delete', params: {'p_run': runId}));
}

final togetherServiceProvider = Provider((ref) => TogetherService());

/// Je gewone tempo en loopmomenten uit je eigen Kadans-runs (zonder Strava), voor het loopmaatje-profiel.
({int pace, List<String> times}) buddyStats(List<Activity> runs) {
  final own = runs
      .where((a) => a.source != 'strava' && !(a.externalId ?? '').startsWith('viastrava-') && a.distanceMeters >= 2000 && a.movingTimeSeconds > 0)
      .toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  final recent = own.take(20).toList();
  if (recent.isEmpty) return (pace: 360, times: const []);
  final paces = [for (final a in recent) a.movingTimeSeconds / (a.distanceMeters / 1000)]..sort();
  final pace = paces[paces.length ~/ 2].round().clamp(150, 1200);
  final counts = <String, int>{};
  for (final a in recent) {
    final t = a.startedAt.toLocal();
    final key = t.weekday >= DateTime.saturday ? 'weekend' : (t.hour < 12 ? 'ochtend' : t.hour < 17 ? 'middag' : 'avond');
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final times = [for (final e in counts.entries) if (e.value >= recent.length * 0.25) e.key];
  return (pace: pace, times: times);
}
