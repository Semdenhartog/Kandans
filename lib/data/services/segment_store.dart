import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/run_streams.dart';
import '../../domain/segments.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';

class SegmentBest {
  const SegmentBest(this.seconds, this.runId, this.date, this.efforts);
  final double seconds;
  final String runId;
  final DateTime date;

  /// Hoe vaak je dit stuk liep (in de gescande runs).
  final int efforts;
}

class SegmentState {
  const SegmentState(this.segments, this.bests, {this.scannedAt});
  final List<Segment> segments;
  final Map<String, SegmentBest> bests;
  final DateTime? scannedAt;
}

/// Bewaart je stukken en beste tijden op de telefoon.
class SegmentStore {
  static const _key = 'segments_v1';

  static Future<SegmentState> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return const SegmentState([], {});
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return SegmentState(
        [for (final s in (j['segs'] as List)) if (Segment.fromJson((s as Map).cast<String, dynamic>()) case final x?) x],
        {
          for (final e in ((j['best'] as Map?) ?? const {}).entries)
            e.key as String: SegmentBest(
              ((e.value as Map)['t'] as num).toDouble(),
              (e.value as Map)['r'] as String,
              DateTime.parse((e.value as Map)['d'] as String),
              ((e.value as Map)['n'] as num?)?.toInt() ?? 1,
            ),
        },
        scannedAt: DateTime.tryParse(j['at'] as String? ?? ''),
      );
    } catch (_) {
      return const SegmentState([], {});
    }
  }

  static Future<void> save(SegmentState s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key,
      jsonEncode({
        'segs': [for (final x in s.segments) x.toJson()],
        'best': {
          for (final e in s.bests.entries) e.key: {'t': e.value.seconds, 'r': e.value.runId, 'd': e.value.date.toIso8601String(), 'n': e.value.efforts},
        },
        if (s.scannedAt != null) 'at': s.scannedAt!.toIso8601String(),
      }),
    );
  }

  /// Bekijkt je laatste (hooguit [limit]) eigen opnames en zoekt je vaste stukken. Strava-runs tellen niet mee.
  static Future<SegmentState> scan(RunWiseRepository repo, List<Activity> runs, {int limit = 40, void Function(double)? progress}) async {
    final own = runs
        .where((a) => a.id != null && a.source != 'strava' && !(a.externalId ?? '').startsWith('viastrava-') && a.hasTrack)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final tracks = <SegTrack>[];
    final pick = own.take(limit).toList();
    for (final (i, a) in pick.indexed) {
      progress?.call(i / pick.length);
      try {
        final st = RunStreams.fromJson(await repo.activityStreams(a.id!));
        final pos = st?.positions;
        if (st == null || pos == null || pos.length < 10) continue;
        tracks.add(SegTrack(a.id!, a.startedAt, pos, st.time, st.distance));
      } catch (_) {}
    }
    final old = await load();
    final names = {for (final s in old.segments) s.id: s.name};
    final segs = [for (final s in findSegments(tracks)) s.named(names[s.id])];
    final bests = <String, SegmentBest>{};
    for (final s in segs) {
      SegmentBest? b;
      var n = 0;
      for (final t in tracks) {
        final sec = effortTime(t, s);
        if (sec == null) continue;
        n++;
        if (b == null || sec < b.seconds) b = SegmentBest(sec, t.id, t.date, 0);
      }
      if (b != null) bests[s.id] = SegmentBest(b.seconds, b.runId, b.date, n);
    }
    final state = SegmentState(segs, bests, scannedAt: DateTime.now());
    await save(state);
    progress?.call(1);
    return state;
  }

  static Future<void> rename(String id, String? name) async {
    final s = await load();
    await save(SegmentState([for (final x in s.segments) x.id == id ? x.named(name?.trim().isEmpty ?? true ? null : name!.trim()) : x], s.bests,
        scannedAt: s.scannedAt));
  }

  /// Na een nieuwe run: tijden op je stukken, en of het een nieuw record is (dan meteen bijwerken).
  static Future<List<({Segment seg, double seconds, SegmentBest? best, bool record})>> effortsFor(Activity a, RunStreams st) async {
    final state = await load();
    final pos = st.positions;
    if (state.segments.isEmpty || pos == null || a.id == null) return const [];
    final track = SegTrack(a.id!, a.startedAt, pos, st.time, st.distance);
    final out = <({Segment seg, double seconds, SegmentBest? best, bool record})>[];
    final bests = Map.of(state.bests);
    var changed = false;
    for (final s in state.segments) {
      final sec = effortTime(track, s);
      if (sec == null) continue;
      final b = bests[s.id];
      final record = b == null || (sec < b.seconds - 0.5 && b.runId != a.id);
      out.add((seg: s, seconds: sec, best: b, record: record && b != null));
      if (b == null || sec < b.seconds) {
        bests[s.id] = SegmentBest(sec, a.id!, a.startedAt, (b?.efforts ?? 0) + (b?.runId == a.id ? 0 : 1));
        changed = true;
      }
    }
    if (changed) await save(SegmentState(state.segments, bests, scannedAt: state.scannedAt));
    return out;
  }
}

final segmentStateProvider = FutureProvider<SegmentState>((ref) => SegmentStore.load());
