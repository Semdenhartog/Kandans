import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/race_calendar.dart';
import 'location_service.dart';

/// Wedstrijden uit de wedstrijdkalender (open overheidsdata), 12 uur bewaard op het toestel.
class RaceCalendarService {
  static const _kCache = 'race_calendar_cache', _kAt = 'race_calendar_at';

  Future<List<RaceListing>> upcoming({bool force = false}) async {
    final p = await SharedPreferences.getInstance();
    final at = DateTime.tryParse(p.getString(_kAt) ?? '');
    if (!force && at != null && DateTime.now().difference(at) < const Duration(hours: 12)) {
      final cached = _decode(p.getString(_kCache));
      if (cached.isNotEmpty) return cached;
    }
    try {
      final today = DateTime.now();
      final from = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final rows = await Supabase.instance.client
          .from('race_calendar')
          .select('key,name,race_date,municipality,place,lat,lon,kind,status,source_url')
          .gte('race_date', from)
          .order('race_date')
          .limit(2000);
      final list = (rows as List).cast<Map<String, dynamic>>().map(RaceListing.fromRow).whereType<RaceListing>().toList();
      await p.setString(_kCache, jsonEncode([for (final r in list) r.toRow()]));
      await p.setString(_kAt, DateTime.now().toIso8601String());
      return list;
    } catch (_) {
      return _decode(p.getString(_kCache)); // offline: de laatst bekende lijst
    }
  }

  List<RaceListing> _decode(String? s) {
    if (s == null) return const [];
    try {
      return (jsonDecode(s) as List).cast<Map<String, dynamic>>().map(RaceListing.fromRow).whereType<RaceListing>().toList();
    } catch (_) {
      return const [];
    }
  }
}

final raceCalendarServiceProvider = Provider((ref) => RaceCalendarService());

class RaceCalendarState {
  const RaceCalendarState(this.races, this.lat, this.lon, this.placeLabel);
  final List<RaceListing> races;
  final double? lat, lon;
  final String? placeLabel;
}

/// Alle komende wedstrijden + je plek (voor de afstand). Zonder plek: heel Nederland op datum.
final raceCalendarProvider = FutureProvider<RaceCalendarState>((ref) async {
  final races = await ref.read(raceCalendarServiceProvider).upcoming();
  Coordinates? at;
  try {
    at = await ref.watch(weatherLocationProvider.future);
  } catch (_) {}
  return RaceCalendarState(races, at?.latitude, at?.longitude, at?.label);
});
