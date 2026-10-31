import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/hrr.dart';

/// Hartslagherstel-metingen (alleen op dit toestel, maximaal de laatste 60).
class HrrStore {
  static const _key = 'hrr_results';

  static Future<List<HrrResult>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return const [];
      return [
        for (final x in jsonDecode(raw) as List)
          if (HrrResult.fromJson(x) case final r?) r,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> add(HrrResult r) async {
    final list = [...await load(), r];
    final keep = list.length > 60 ? list.sublist(list.length - 60) : list;
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final x in keep) x.toJson()]));
  }

  /// De meting bij een run (binnen 6 uur na de start).
  static HrrResult? forRun(List<HrrResult> all, DateTime start, int movingSeconds) {
    final end = start.add(Duration(seconds: movingSeconds));
    for (final r in all.reversed) {
      if (!r.at.isBefore(start) && r.at.difference(end).inHours.abs() <= 6) return r;
    }
    return null;
  }
}
