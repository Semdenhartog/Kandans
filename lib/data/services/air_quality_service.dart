import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../domain/run_warnings.dart';
import 'location_service.dart';
import 'offline_cache.dart';

/// Luchtkwaliteit en pollen per uur (Open-Meteo, gratis, Europese CAMS-gegevens).
class AirQualityService {
  AirQualityService([http.Client? client]) : _http = client ?? http.Client();
  final http.Client _http;

  static const _fields = [
    'european_aqi',
    'grass_pollen',
    'birch_pollen',
    'alder_pollen',
    'mugwort_pollen',
    'ragweed_pollen',
  ];

  Future<List<AirQuality>> forecast(double lat, double lon) async {
    final uri = Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
      'latitude': lat.toStringAsFixed(2),
      'longitude': lon.toStringAsFixed(2),
      'hourly': _fields.join(','),
      'timezone': 'auto',
      'forecast_days': '3',
    });
    final json = await OfflineCache.fetch<Map<String, dynamic>>(
      'air_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}',
      () async {
        final res = await _http.get(uri).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) throw Exception('Luchtkwaliteit niet beschikbaar (${res.statusCode}).');
        return jsonDecode(res.body) as Map<String, dynamic>;
      },
      encode: (v) => v,
      decode: (d) => (d as Map).cast<String, dynamic>(),
      maxAge: const Duration(hours: 12),
    );
    return parse(json);
  }

  /// Publiek voor tests.
  static List<AirQuality> parse(Map<String, dynamic> json) {
    final h = (json['hourly'] as Map?)?.cast<String, dynamic>() ?? const {};
    final times = (h['time'] as List?)?.cast<String>() ?? const [];
    double? v(String k, int i) {
      final l = h[k] as List?;
      if (l == null || i >= l.length || l[i] == null) return null;
      return (l[i] as num).toDouble();
    }

    return [
      for (var i = 0; i < times.length; i++)
        AirQuality(
          time: DateTime.parse(times[i]),
          europeanAqi: v('european_aqi', i),
          grass: v('grass_pollen', i),
          birch: v('birch_pollen', i),
          alder: v('alder_pollen', i),
          mugwort: v('mugwort_pollen', i),
          ragweed: v('ragweed_pollen', i),
        ),
    ];
  }
}

/// Het uur dat het dichtst bij [t] ligt (binnen 90 minuten).
AirQuality? airAt(List<AirQuality> list, DateTime t) {
  AirQuality? best;
  var diff = 1 << 30;
  for (final a in list) {
    final d = a.time.difference(t).inMinutes.abs();
    if (d < diff) {
      diff = d;
      best = a;
    }
  }
  return diff <= 90 ? best : null;
}

final airQualityServiceProvider = Provider<AirQualityService>((ref) => AirQualityService());

/// Luchtkwaliteit op je weerlocatie. Leeg als het niet lukt (de app werkt dan gewoon door).
final airQualityProvider = FutureProvider<List<AirQuality>>((ref) async {
  final loc = await ref.watch(weatherLocationProvider.future);
  try {
    return await ref.watch(airQualityServiceProvider).forecast(loc.latitude, loc.longitude);
  } catch (_) {
    return const [];
  }
});
