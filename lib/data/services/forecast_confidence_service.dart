import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/forecast_confidence.dart';
import 'weather_service.dart';

/// Ensemble-weer (Open-Meteo, gratis) voor "Hoe zeker is dit moment?".
class EnsembleService {
  EnsembleService([http.Client? c]) : _client = c ?? http.Client();
  final http.Client _client;

  List<EnsembleHour>? _cache;
  String? _cacheKey;
  DateTime? _cacheAt;

  Future<List<EnsembleHour>> hours(double lat, double lon) async {
    final key = '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
    if (_cache != null && _cacheKey == key && DateTime.now().difference(_cacheAt!).inMinutes < 30) return _cache!;
    final uri = Uri.https('ensemble-api.open-meteo.com', '/v1/ensemble', {
      'latitude': lat.toStringAsFixed(3),
      'longitude': lon.toStringAsFixed(3),
      'hourly': 'precipitation,temperature_2m',
      'models': 'icon_seamless',
      'forecast_days': '3',
      'timezone': 'auto',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('Ensemble ${res.statusCode}');
    final h = parseEnsemble(jsonDecode(res.body) as Map<String, dynamic>);
    _cache = h;
    _cacheKey = key;
    _cacheAt = DateTime.now();
    return h;
  }
}

final ensembleServiceProvider = Provider<EnsembleService>((ref) => EnsembleService());

typedef ConfidenceArgs = ({double lat, double lon, DateTime start, int minutes});

final forecastConfidenceProvider = FutureProvider.family<ForecastConfidence?, ConfidenceArgs>((ref, a) async {
  final hours = await ref.read(ensembleServiceProvider).hours(a.lat, a.lon);
  return confidenceFor(hours, a.start, a.minutes);
});

/// Bewaart wat Kadans voorspelde en controleert dat achteraf met het echte weer.
class ForecastCheckStore {
  static const _key = 'forecast_checks';

  static Future<List<ForecastSnapshot>> _load(SharedPreferences p) async {
    final raw = p.getString(_key);
    if (raw == null) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          if (ForecastSnapshot.fromJson((e as Map).cast<String, dynamic>()) case final s?) s,
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(SharedPreferences p, List<ForecastSnapshot> all) async {
    all.sort((a, b) => a.time.compareTo(b.time));
    final keep = all.length > 60 ? all.sublist(all.length - 60) : all;
    await p.setString(_key, jsonEncode([for (final s in keep) s.toJson()]));
  }

  /// Eén voorspelling per dag: de laatste vóór het moment zelf telt.
  static Future<void> remember(ForecastSnapshot s) async {
    if (s.time.isBefore(DateTime.now().subtract(const Duration(minutes: 30)))) return;
    final p = await SharedPreferences.getInstance();
    final all = await _load(p);
    all.removeWhere((o) => o.ok == null && _sameDay(o.time, s.time));
    if (all.any((o) => o.ok != null && _sameDay(o.time, s.time))) return;
    all.add(s);
    await _save(p, all);
  }

  /// Controleert momenten die minstens een uur voorbij zijn en geeft (goed, totaal) over 30 dagen.
  static Future<(int, int)> verifyAndScore(WeatherService weather) async {
    final p = await SharedPreferences.getInstance();
    final all = await _load(p);
    var changed = false;
    final now = DateTime.now();
    for (var i = 0; i < all.length; i++) {
      final s = all[i];
      if (s.ok != null || now.difference(s.time).inMinutes < 75) continue;
      try {
        final hours = await weather.dayHours(s.lat, s.lon, s.time);
        final h = hours.where((h) => h.time.hour == s.time.hour).firstOrNull;
        if (h == null) continue;
        all[i] = s.withResult(forecastWasRight(s, actualTemp: h.temperature, actualMm: h.precipitation ?? 0));
        changed = true;
      } catch (_) {
        break; // Geen internet: later opnieuw.
      }
    }
    if (changed) await _save(p, all);
    return forecastScore(all, now: now);
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

final forecastScoreProvider = FutureProvider<(int, int)>((ref) => ForecastCheckStore.verifyAndScore(ref.read(weatherServiceProvider)));
