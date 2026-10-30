import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/models.dart';
import '../../data/services/location_service.dart';
import '../../data/services/roster_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/availability.dart';

const _key = 'availability_v1';

/// Je looptijden (op dit toestel bewaard).
/// Met een gekoppeld rooster vallen je diensten, reistijd en slaap na een nachtdienst er ook af.
final availabilityProvider = FutureProvider<Availability>((ref) async {
  final roster = await ref.watch(rosterProvider.future);
  Availability base;
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    base = raw == null ? Availability.always : Availability.fromJson(jsonDecode(raw));
  } catch (_) {
    base = Availability.always;
  }
  return roster.linked ? base.withBusy(roster.blocks) : base;
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
