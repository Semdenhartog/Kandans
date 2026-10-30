import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/run_pause.dart';

/// Pauzes (blessure, ziek, vakantie) staan alleen op de telefoon.
class RunPauseStore {
  static const _key = 'run_pauses_v1';

  static Future<List<PausePeriod>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = jsonDecode(p.getString(_key) ?? '[]') as List;
      return [for (final j in raw) PausePeriod.fromJson(j)].whereType<PausePeriod>().toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<PausePeriod> pauses) async {
    try {
      final p = await SharedPreferences.getInstance();
      // Alleen het afgelopen jaar bewaren (genoeg voor reeksen en badges).
      final cutoff = DateTime.now().subtract(const Duration(days: 400));
      final keep = [for (final x in pauses) if (x.end == null || x.end!.isAfter(cutoff)) x];
      await p.setString(_key, jsonEncode([for (final x in keep) x.toJson()]));
    } catch (_) {}
  }

  /// Loopt er nu een pauze? (Voor meldingen en de coach, buiten Riverpod om.)
  static Future<PausePeriod?> current() async => currentPause(await load(), DateTime.now());
}

/// Al je pauzes (oud en lopend).
class RunPauses extends Notifier<List<PausePeriod>> {
  @override
  List<PausePeriod> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    state = await RunPauseStore.load();
  }

  /// Pauze starten vanaf vandaag. [until] = laatste dag, of null = tot je zelf weer begint.
  Future<void> start(PauseReason reason, {DateTime? until}) async {
    final now = DateTime.now();
    // Een lopende pauze eerst afsluiten (gisteren), zodat er nooit twee tegelijk lopen.
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final rest = [for (final p in state) p.activeOn(now) ? p.endedOn(yesterday) : p];
    state = [
      for (final p in rest) if (p.end == null || !p.end!.isBefore(p.start)) p,
      PausePeriod(reason: reason, start: now, end: until),
    ];
    await RunPauseStore.save(state);
  }

  /// Pauze stoppen: vandaag ben je weer begonnen (vandaag telt niet meer als pauze).
  Future<void> stop() async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    state = [
      for (final p in state)
        if (!p.activeOn(now))
          p
        else if (!yesterday.isBefore(DateTime(p.start.year, p.start.month, p.start.day)))
          p.endedOn(yesterday),
    ];
    await RunPauseStore.save(state);
  }
}

final runPausesProvider = NotifierProvider<RunPauses, List<PausePeriod>>(RunPauses.new);

/// De pauze die nu loopt (of null).
final currentPauseProvider = Provider<PausePeriod?>((ref) => currentPause(ref.watch(runPausesProvider), DateTime.now()));

/// Weken die als pauze tellen (voor reeksen en badges).
final pausedWeeksProvider = Provider<Set<DateTime>>((ref) => pausedWeeks(ref.watch(runPausesProvider), DateTime.now()));
