import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Haalt weerdata op bij Open-Meteo (gratis, geen API-key nodig).
class WeatherService {
  WeatherService([http.Client? client]) : _client = client ?? http.Client();

  final http.Client _client;

  static const _forecastHourly = [
    'temperature_2m',
    'apparent_temperature',
    'relative_humidity_2m',
    'precipitation_probability',
    'precipitation',
    'wind_speed_10m',
    'wind_direction_10m',
    'wind_gusts_10m',
    'uv_index',
    'weather_code',
    'is_day',
  ];

  static const _historyHourly = [
    'temperature_2m',
    'apparent_temperature',
    'relative_humidity_2m',
    'precipitation',
    'wind_speed_10m',
    'wind_direction_10m',
  ];

  /// Verwachting per uur voor de komende [days] dagen (max. 16).
  Future<Forecast> forecast(double lat, double lon, {int days = 2}) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'hourly': _forecastHourly.join(','),
      'timezone': 'auto',
      'forecast_days': days.clamp(1, 16).toString(),
    });
    return _parse(await _get(uri), lat, lon);
  }

  /// Weer op een moment in het verleden, voor het automatisch invullen
  /// van het weer bij een gelogde run. Geeft null als het niet lukt.
  Future<HourWeather?> historical(double lat, double lon, DateTime at) async {
    try {
      final daysAgo = DateTime.now().difference(at).inDays;
      final Uri uri;
      if (daysAgo <= 6) {
        uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': lat.toStringAsFixed(4),
          'longitude': lon.toStringAsFixed(4),
          'hourly': _historyHourly.join(','),
          'timezone': 'auto',
          'past_days': '7',
          'forecast_days': '1',
        });
      } else {
        final day = _isoDate(at);
        uri = Uri.https('archive-api.open-meteo.com', '/v1/archive', {
          'latitude': lat.toStringAsFixed(4),
          'longitude': lon.toStringAsFixed(4),
          'hourly': _historyHourly.join(','),
          'timezone': 'auto',
          'start_date': day,
          'end_date': day,
        });
      }
      return _parse(await _get(uri), lat, lon).at(at);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Weerdata kon niet worden opgehaald (${res.statusCode}).');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Zet het Open-Meteo-antwoord om naar een [Forecast].
  /// Publiek zodat het in tests gebruikt kan worden.
  static Forecast parse(Map<String, dynamic> json, double lat, double lon) =>
      _parse(json, lat, lon);

  static Forecast _parse(Map<String, dynamic> json, double lat, double lon) {
    final hourly = (json['hourly'] as Map?)?.cast<String, dynamic>() ?? {};
    final times = (hourly['time'] as List?)?.cast<String>() ?? const [];

    double? val(String key, int i) {
      final list = hourly[key] as List?;
      if (list == null || i >= list.length) return null;
      final v = list[i];
      return v == null ? null : (v as num).toDouble();
    }

    final hours = <HourWeather>[];
    for (var i = 0; i < times.length; i++) {
      final temp = val('temperature_2m', i);
      final wind = val('wind_speed_10m', i);
      if (temp == null || wind == null) continue;
      hours.add(HourWeather(
        // Open-Meteo geeft lokale tijd zonder tijdzone, bijv. "2026-10-17T14:00".
        time: DateTime.parse(times[i]),
        temperature: temp,
        feelsLike: val('apparent_temperature', i),
        humidity: val('relative_humidity_2m', i),
        precipitationProbability: val('precipitation_probability', i),
        precipitation: val('precipitation', i),
        windSpeed: wind,
        windDirection: val('wind_direction_10m', i),
        windGusts: val('wind_gusts_10m', i),
        uvIndex: val('uv_index', i),
        weatherCode: val('weather_code', i)?.round(),
        isDay: (val('is_day', i) ?? 1) >= 1,
      ));
    }
    return Forecast(latitude: lat, longitude: lon, hours: hours);
  }
}

final weatherServiceProvider = Provider<WeatherService>((ref) => WeatherService());

/// Omschrijving van een WMO-weercode.
String weatherLabel(int? code) {
  if (code == null) return 'Onbekend';
  if (code == 0) return 'Onbewolkt';
  if (code <= 2) return 'Licht bewolkt';
  if (code == 3) return 'Bewolkt';
  if (code == 45 || code == 48) return 'Mist';
  if (code >= 51 && code <= 57) return 'Motregen';
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return 'Regen';
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) return 'Sneeuw';
  if (code >= 95) return 'Onweer';
  return 'Wisselend';
}
