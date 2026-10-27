import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'location_service.dart';

/// Live buienverwachting van Buienradar: per 5 minuten, voor de komende 2 uur.
///
/// Bron: https://gpsgadget.buienradar.nl/data/raintext — geeft regels als "077|20:35",
/// waarbij de waarde (0–255) de neerslagintensiteit is: mm/u = 10^((waarde - 109) / 32).
class RainService {
  RainService([http.Client? client]) : _client = client ?? http.Client();
  final http.Client _client;

  Future<RainNowcast> nowcast(double lat, double lon) async {
    final uri = Uri.https('gpsgadget.buienradar.nl', '/data/raintext', {
      'lat': lat.toStringAsFixed(2),
      'lon': lon.toStringAsFixed(2),
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('De buienverwachting is even niet bereikbaar (${res.statusCode}).');
    }
    return parse(res.body, DateTime.now());
  }

  /// Zet de tekst van Buienradar om. Publiek voor tests.
  static RainNowcast parse(String body, DateTime now) {
    final points = <({DateTime time, double mmPerHour})>[];
    var day = DateTime(now.year, now.month, now.day);
    DateTime? previous;
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      final parts = line.split('|');
      if (parts.length != 2) continue;
      final value = int.tryParse(parts[0].trim());
      final hm = parts[1].trim().split(':');
      if (value == null || hm.length != 2) continue;
      final h = int.tryParse(hm[0]);
      final m = int.tryParse(hm[1]);
      if (h == null || m == null) continue;

      var t = DateTime(day.year, day.month, day.day, h, m);
      // Over middernacht heen: de tijd springt terug, dus de volgende dag.
      if (previous == null && t.isAfter(now.add(const Duration(hours: 12)))) {
        t = t.subtract(const Duration(days: 1));
        day = day.subtract(const Duration(days: 1));
      }
      if (previous != null && t.isBefore(previous)) {
        day = day.add(const Duration(days: 1));
        t = DateTime(day.year, day.month, day.day, h, m);
      }
      previous = t;

      final mm = value <= 0 ? 0.0 : math.pow(10, (value - 109) / 32).toDouble();
      points.add((time: t, mmPerHour: mm < 0.05 ? 0.0 : double.parse(mm.toStringAsFixed(2))));
    }
    return RainNowcast(points: points, fetchedAt: now);
  }
}

final rainServiceProvider = Provider<RainService>((ref) => RainService());

/// Buienverwachting op de weerlocatie. Het Vandaag-scherm ververst dit elke 5 minuten.
final rainNowcastProvider = FutureProvider.autoDispose<RainNowcast?>((ref) async {
  final loc = await ref.watch(weatherLocationProvider.future);
  try {
    return await ref.watch(rainServiceProvider).nowcast(loc.latitude, loc.longitude);
  } catch (_) {
    return null; // zonder buienradar rekenen we met de gewone verwachting
  }
});
