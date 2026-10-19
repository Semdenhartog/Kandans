import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';

class Coordinates {
  const Coordinates(this.latitude, this.longitude, this.label);
  final double latitude;
  final double longitude;

  /// Waar de locatie vandaan komt, voor uitleg in de app.
  final String label;
}

/// Mag de app om locatie vragen? Pas nadat de gebruiker de uitleg heeft gezien
/// (rondleiding of uitlegvenster), zodat de vraag nooit uit het niets komt.
const locationExplainedKey = 'location_explained';

Future<bool> locationExplained() async {
  try {
    return (await SharedPreferences.getInstance()).getBool(locationExplainedKey) ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> markLocationExplained() async {
  try {
    await (await SharedPreferences.getInstance()).setBool(locationExplainedKey, true);
  } catch (_) {}
}

/// Vraagt de GPS-locatie op. Geeft null als dat niet mag of niet lukt.
/// Om toestemming wordt alleen gevraagd als de uitleg al is getoond.
Future<Coordinates?> currentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && await locationExplained()) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
    ).timeout(const Duration(seconds: 12));
    return Coordinates(pos.latitude, pos.longitude, 'Je huidige locatie');
  } catch (_) {
    final last = await _safe(Geolocator.getLastKnownPosition);
    if (last == null) return null;
    return Coordinates(last.latitude, last.longitude, 'Je laatst bekende locatie');
  }
}

/// Locatie voor het weer: GPS → thuislocatie in profiel → favoriete route → Barneveld.
final weatherLocationProvider = FutureProvider<Coordinates>((ref) async {
  final gps = await currentPosition();
  if (gps != null) {
    final profile = await _safe(() => ref.read(profileProvider.future));
    // Bewaar een grove thuislocatie (afgerond op ~1 km) als die nog niet bekend is.
    if (profile != null && profile.homeLatitude == null) {
      ref
          .read(repositoryProvider)
          .updateHome(
            double.parse(gps.latitude.toStringAsFixed(2)),
            double.parse(gps.longitude.toStringAsFixed(2)),
          )
          .ignore();
    }
    return gps;
  }
  final profile = await _safe(() => ref.read(profileProvider.future));
  if (profile?.homeLatitude != null && profile?.homeLongitude != null) {
    return Coordinates(profile!.homeLatitude!, profile.homeLongitude!, 'Je thuislocatie');
  }
  final routes =
      await _safe(() => ref.read(routesProvider.future)) ?? const <RunRoute>[];
  if (routes.isNotEmpty) {
    return Coordinates(routes.first.startLatitude, routes.first.startLongitude,
        'Start van ${routes.first.name}');
  }
  return const Coordinates(
    AppConfig.fallbackLatitude,
    AppConfig.fallbackLongitude,
    'Barneveld (standaard)',
  );
});

Future<T?> _safe<T>(Future<T> Function() f) async {
  try {
    return await f();
  } catch (_) {
    return null;
  }
}
