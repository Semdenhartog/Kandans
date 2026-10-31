import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/hindsight.dart';

/// Wat Kadans je per run opleverde (uit de terugblik "Goed gekozen?"), op dit toestel bewaard.
class EffectEntry {
  const EffectEntry({required this.good, required this.rain, required this.heat, required this.at});
  final bool good;
  final double rain;
  final double heat;
  final DateTime at;

  Map<String, dynamic> toJson() => {'g': good, 'r': double.parse(rain.toStringAsFixed(1)), 'h': double.parse(heat.toStringAsFixed(1)), 't': at.toIso8601String()};

  static EffectEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = DateTime.tryParse('${j['t']}');
    if (t == null) return null;
    return EffectEntry(good: j['g'] == true, rain: (j['r'] as num?)?.toDouble() ?? 0, heat: (j['h'] as num?)?.toDouble() ?? 0, at: t);
  }
}

class KadansEffect {
  const KadansEffect(this.entries);
  final Map<String, EffectEntry> entries;

  Iterable<EffectEntry> inYear(int year) => entries.values.where((e) => e.at.year == year);
  int runs(int year) => inYear(year).length;
  int wellChosen(int year) => inYear(year).where((e) => e.good).length;
  double rainAvoided(int year) => inYear(year).fold<double>(0, (s, e) => s + e.rain);
  int dryRuns(int year) => inYear(year).where((e) => e.rain >= 1).length;
  double heatAvoided(int year) => inYear(year).fold<double>(0, (s, e) => s + e.heat);

  /// Run-id's die goed gekozen waren (voor de badge).
  Set<String> get wellChosenIds => {for (final e in entries.entries) if (e.value.good) e.key};
}

class KadansEffectStore {
  static const _key = 'kadans_effect';

  static Future<Map<String, EffectEntry>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return {};
      final m = jsonDecode(raw) as Map;
      return {
        for (final e in m.entries)
          if (EffectEntry.fromJson(e.value) case final v?) '${e.key}': v,
      };
    } catch (_) {
      return {};
    }
  }

  /// Bewaart de terugblik van een run. Geeft true als hij nieuw was.
  static Future<bool> save(String activityId, Hindsight h, DateTime at) async {
    final all = await load();
    if (all.containsKey(activityId)) return false;
    all[activityId] = EffectEntry(good: h.good, rain: h.rainAvoided, heat: h.heatAvoided, at: at);
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}));
    return true;
  }
}

final kadansEffectProvider = FutureProvider<KadansEffect>((ref) async => KadansEffect(await KadansEffectStore.load()));
