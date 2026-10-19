import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/models.dart';
import '../../data/services/location_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/availability.dart';

const _key = 'availability_v1';

/// Je looptijden (op dit toestel bewaard).
final availabilityProvider = FutureProvider<Availability>((ref) async {
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    return raw == null ? Availability.always : Availability.fromJson(jsonDecode(raw));
  } catch (_) {
    return Availability.always;
  }
});

Future<void> saveAvailability(WidgetRef ref, Availability a) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (a.isAlways) {
      await p.remove(_key);
    } else {
      await p.setString(_key, jsonEncode(a.toJson()));
    }
  } catch (_) {}
  ref.invalidate(availabilityProvider);
}

/// Verwachting voor 7 dagen, voor de weekplanner.
final weekForecastProvider = FutureProvider<Forecast>((ref) async {
  final loc = await ref.watch(weatherLocationProvider.future);
  return ref.watch(weatherServiceProvider).forecast(loc.latitude, loc.longitude, days: 7);
});
