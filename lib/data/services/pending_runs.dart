import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/geo.dart';
import '../models/models.dart';

/// Een opgenomen run die nog niet in de database staat (meestal: geen internet na de run).
class PendingRun {
  PendingRun({
    required this.localId,
    required this.activity,
    required this.createdAt,
    this.streams,
    this.bestEfforts,
  });

  /// Vaste sleutel van deze run. Gaat mee als external_id, zodat opnieuw versturen
  /// nooit een tweede run maakt.
  final String localId;
  final Activity activity;
  final DateTime createdAt;
  final Map<String, dynamic>? streams;
  final Map<String, double>? bestEfforts;

  /// Weer ontbreekt nog (ophalen lukte niet zonder internet).
  bool get needsWeather => activity.temperatureCelsius == null && activity.hasTrack;

  Map<String, dynamic> toJson() => {
        'local_id': localId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'activity': {...activity.toInsert('')}..remove('user_id'),
        if (streams != null) 'streams': streams,
        if (bestEfforts != null) 'best_efforts': bestEfforts,
      };

  static PendingRun? fromJson(Object? raw) {
    try {
      final j = raw as Map<String, dynamic>;
      final be = j['best_efforts'];
      return PendingRun(
        localId: j['local_id'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        activity: Activity.fromJson(Map<String, dynamic>.from(j['activity'] as Map)),
        streams: j['streams'] is Map ? Map<String, dynamic>.from(j['streams'] as Map) : null,
        bestEfforts: be is Map
            ? {
                for (final e in be.entries)
                  if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
              }
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Startpunt van de run (voor het weer achteraf), of null zonder spoor.
  LatLng? get startPoint {
    if (!activity.hasTrack) return null;
    final pts = decodePolyline(activity.trackPolyline!);
    return pts.isEmpty ? null : pts.first;
  }

  /// Nieuwe, willekeurige sleutel (letters en cijfers).
  static String newLocalId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = math.Random.secure();
    return 'rw${DateTime.now().millisecondsSinceEpoch}${List.generate(10, (_) => chars[r.nextInt(chars.length)]).join()}';
  }
}

/// Wat de wachtrij nodig heeft om een run te versturen. Los gehouden zodat het te testen is.
abstract class PendingRunUploader {
  /// Slaat de run op (idempotent op [localId]) en geeft het database-id terug.
  Future<String> upload(PendingRun run);

  /// Extra's na het opslaan (verloop, hoogte). Fouten zijn niet erg.
  Future<void> afterUpload(String id, PendingRun run);

  /// Weer achteraf, of null.
  Future<Activity?> withWeather(PendingRun run);
}

/// Bewaart runs op de telefoon tot ze in de database staan.
class PendingRunStore {
  PendingRunStore._();

  /// Aantal runs dat nog wacht (voor de balk onderaan).
  static final count = ValueNotifier<int>(0);

  static bool _flushing = false;

  /// Alleen voor tests: map in plaats van de app-map.
  @visibleForTesting
  static Directory? testDir;

  static Future<Directory> _dir() async {
    final t = testDir;
    if (t != null) {
      if (!await t.exists()) await t.create(recursive: true);
      return t;
    }
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/pending_runs');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<void> add(PendingRun run) async {
    final d = await _dir();
    final f = File('${d.path}/${run.localId}.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(run.toJson()), flush: true);
    await tmp.rename(f.path);
    await refreshCount();
  }

  static Future<List<(File, PendingRun)>> _all() async {
    final d = await _dir();
    final out = <(File, PendingRun)>[];
    await for (final e in d.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final run = PendingRun.fromJson(jsonDecode(await e.readAsString()));
        if (run != null) out.add((e, run));
      } catch (_) {}
    }
    out.sort((a, b) => a.$2.createdAt.compareTo(b.$2.createdAt));
    return out;
  }

  static Future<void> refreshCount() async {
    try {
      count.value = (await _all()).length;
    } catch (_) {}
  }

  /// Verstuurt alles wat wacht, oudste eerst. Stopt bij de eerste fout (meestal nog geen internet).
  /// Geeft het aantal verstuurde runs terug.
  static Future<int> flush(PendingRunUploader up) async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      for (final (file, run) in await _all()) {
        final ready = run.needsWeather ? (await up.withWeather(run) ?? run.activity) : run.activity;
        final toSend = PendingRun(
          localId: run.localId,
          activity: ready,
          createdAt: run.createdAt,
          streams: run.streams,
          bestEfforts: run.bestEfforts,
        );
        String? id;
        try {
          id = await up.upload(toSend);
        } catch (_) {
          id = null;
        }
        if (id == null) break;
        try {
          await file.delete();
        } catch (_) {}
        sent++;
        await up.afterUpload(id, toSend).catchError((Object _) {});
      }
    } catch (_) {
      // Lezen van de map mislukt: volgende keer opnieuw.
    } finally {
      _flushing = false;
      await refreshCount();
    }
    return sent;
  }
}
