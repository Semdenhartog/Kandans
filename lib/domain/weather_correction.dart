import 'dart:math' as math;

import '../data/models/models.dart';

/// Schatting hoeveel tijd het weer je kostte tijdens een run.
///
/// Bewust eenvoudig en uitlegbaar:
/// - Wind: tegenwind kost meer dan wind mee oplevert. Zonder route nemen we aan
///   dat je de helft van de tijd tegenwind en de helft wind mee had. Bij 20 km/u
///   kost dat zo'n 3 s/km, bij 30 km/u zo'n 7 s/km.
/// - Warmte: boven 15 °C (gevoelstemperatuur) ongeveer 0,35% trager per graad.
/// - Kou: onder 2 °C ongeveer 0,15% trager per graad.
class WeatherCost {
  const WeatherCost({required this.windSeconds, required this.heatSeconds, required this.coldSeconds});

  final double windSeconds;
  final double heatSeconds;
  final double coldSeconds;

  double get totalSeconds => windSeconds + heatSeconds + coldSeconds;

  /// Is de invloed groot genoeg om te noemen (meer dan 5 seconden)?
  bool get matters => totalSeconds >= 5;

  /// Korte uitleg, bijv. "wind ~40 s, warmte ~25 s".
  String get explanation {
    final parts = <String>[
      if (windSeconds >= 3) 'wind ~${windSeconds.round()} s',
      if (heatSeconds >= 3) 'warmte ~${heatSeconds.round()} s',
      if (coldSeconds >= 3) 'kou ~${coldSeconds.round()} s',
    ];
    return parts.isEmpty ? 'nauwelijks invloed' : parts.join(', ');
  }

  static const zero = WeatherCost(windSeconds: 0, heatSeconds: 0, coldSeconds: 0);
}

/// Extra seconden per km door tegenwind van [headwindKmh].
double headwindSecPerKm(double headwindKmh) => 0.03 * headwindKmh * headwindKmh;

/// Seconden per km die wind mee oplevert (ongeveer de helft van wat tegenwind kost).
double tailwindSecPerKm(double tailwindKmh) => 0.015 * tailwindKmh * tailwindKmh;

/// Netto windkosten per km als je de helft tegen- en de helft meewind hebt.
double netWindSecPerKm(double windKmh) => 0.5 * headwindSecPerKm(windKmh) - 0.5 * tailwindSecPerKm(windKmh);

WeatherCost weatherCost(Activity a) {
  final km = a.distanceMeters / 1000;
  if (km <= 0 || a.movingTimeSeconds <= 0) return WeatherCost.zero;

  final wind = a.windSpeedKmh ?? 0;
  final windSec = wind < 5 ? 0.0 : netWindSecPerKm(wind) * km;

  final feels = a.feelsLikeCelsius ?? a.temperatureCelsius;
  var heatPct = 0.0, coldPct = 0.0;
  if (feels != null) {
    heatPct = math.max(0, feels - 15) * 0.0035;
    coldPct = math.max(0, 2 - feels) * 0.0015;
  }
  // Percentage van de tijd zonder weerinvloed.
  final base = math.max(0.0, a.movingTimeSeconds - windSec);
  return WeatherCost(
    windSeconds: windSec,
    heatSeconds: base * heatPct / (1 + heatPct),
    coldSeconds: base * coldPct / (1 + coldPct),
  );
}

/// Tijd die je bij ideaal loopweer (rond 10 °C, windstil) had gelopen.
int correctedSeconds(Activity a) =>
    math.max(1, (a.movingTimeSeconds - weatherCost(a).totalSeconds).round());
