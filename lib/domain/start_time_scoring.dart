import 'dart:math' as math;

import '../data/models/models.dart';
import 'geo.dart';
import 'performance_model.dart';

/// Soort training. Elke soort reageert anders op hitte, wind en regen.
enum TrainingType {
  easy('Rustige duurloop', 'Ontspannen tempo, praten moet kunnen.'),
  quality('Tempotraining', 'Intervallen of tempo: koel en windstil is ideaal.'),
  long('Lange duurloop', 'Lang onderweg: droog en niet te warm telt zwaar.'),
  recovery('Herstelloopje', 'Kort en rustig: het weer maakt minder uit.');

  const TrainingType(this.label, this.description);
  final String label;
  final String description;
}

/// Wind ten opzichte van de looprichting, over de hele route.
class RouteWind {
  const RouteWind({
    required this.headwindAvg,
    required this.tailwindAvg,
    required this.firstHalfHead,
    required this.secondHalfHead,
  });

  /// Gemiddelde tegenwindcomponent (km/u) over de route.
  final double headwindAvg;
  final double tailwindAvg;
  final double firstHalfHead;
  final double secondHalfHead;

  /// Wind die je "voelt": tegenwind kost meer dan rugwind oplevert.
  double get effective => math.max(0.0, headwindAvg - 0.4 * tailwindAvg);
}

/// Berekent tegen- en rugwind langs een route.
///
/// [windFromDegrees] is de richting waar de wind VANDAAN komt (meteorologisch).
RouteWind routeWind(
  List<({double bearing, double meters, double startKm})> segments,
  double windSpeed,
  double windFromDegrees,
) {
  if (segments.isEmpty || windSpeed <= 0) {
    return const RouteWind(headwindAvg: 0, tailwindAvg: 0, firstHalfHead: 0, secondHalfHead: 0);
  }
  final totalM = segments.fold<double>(0, (s, e) => s + e.meters);
  var head = 0.0, tail = 0.0, firstHead = 0.0, secondHead = 0.0;
  var firstM = 0.0, secondM = 0.0, travelled = 0.0;
  for (final seg in segments) {
    // Loop je richting waar de wind vandaan komt, dan heb je volle tegenwind.
    final delta = (windFromDegrees - seg.bearing) * math.pi / 180;
    final component = windSpeed * math.cos(delta);
    final h = math.max(0.0, component);
    final t = math.max(0.0, -component);
    head += h * seg.meters;
    tail += t * seg.meters;
    if (travelled + seg.meters / 2 < totalM / 2) {
      firstHead += h * seg.meters;
      firstM += seg.meters;
    } else {
      secondHead += h * seg.meters;
      secondM += seg.meters;
    }
    travelled += seg.meters;
  }
  return RouteWind(
    headwindAvg: head / totalM,
    tailwindAvg: tail / totalM,
    firstHalfHead: firstM == 0 ? 0 : firstHead / firstM,
    secondHalfHead: secondM == 0 ? 0 : secondHead / secondM,
  );
}

/// Score voor één mogelijke vertrektijd.
class StartTimeScore {
  StartTimeScore({
    required this.start,
    required this.score,
    required this.weather,
    required this.reasons,
    this.routeWind,
  });

  final DateTime start;

  /// 0–100, hoger is beter.
  final int score;
  final HourWeather weather;

  /// Uitleg waarom de score zo is (belangrijkste eerst).
  final List<String> reasons;
  final RouteWind? routeWind;

  String get verdict {
    if (score >= 85) return 'Top';
    if (score >= 70) return 'Goed';
    if (score >= 55) return 'Prima';
    if (score >= 40) return 'Matig';
    return 'Lastig';
  }
}

class StartTimePlanner {
  StartTimePlanner({
    required this.forecast,
    required this.profile,
    this.track = const [],
    this.durationMinutes = 60,
  }) : _segments = trackSegments(track);

  final Forecast forecast;
  final PerformanceInsights profile;

  /// Route als lijst punten. Leeg = geen route, wind wordt dan algemeen meegewogen.
  final List<LatLng> track;
  final int durationMinutes;
  final List<({double bearing, double meters, double startKm})> _segments;

  bool get hasRoute => _segments.isNotEmpty;

  /// Score per uur waarop je zou kunnen vertrekken, vanaf nu tot [horizon].
  List<StartTimeScore> scoreAll(
    TrainingType type, {
    DateTime? from,
    Duration horizon = const Duration(hours: 36),
    int earliestHour = 5,
    int latestHour = 22,
  }) {
    final now = from ?? DateTime.now();
    final startFrom = DateTime(now.year, now.month, now.day, now.hour);
    final end = now.add(horizon);
    final results = <StartTimeScore>[];
    for (final h in forecast.hours) {
      if (h.time.isBefore(startFrom) || h.time.isAfter(end)) continue;
      if (h.time.hour < earliestHour || h.time.hour > latestHour) continue;
      results.add(scoreAt(h.time, type));
    }
    return results;
  }

  /// Beste vertrektijd binnen de horizon (of null als er geen weerdata is).
  StartTimeScore? best(TrainingType type, {DateTime? from, Duration? horizon}) {
    final all = scoreAll(type, from: from, horizon: horizon ?? const Duration(hours: 36));
    if (all.isEmpty) return null;
    return all.reduce((a, b) => b.score > a.score ? b : a);
  }

  /// Score voor vertrekken op [start]: het gemiddelde over de uren die je onderweg bent.
  StartTimeScore scoreAt(DateTime start, TrainingType type) {
    final hoursOnRoad = math.max(1, (durationMinutes / 60).ceil());
    final slices = <HourWeather>[];
    for (var i = 0; i < hoursOnRoad; i++) {
      final w = forecast.at(start.add(Duration(minutes: i * 60 + 15)));
      if (w != null) slices.add(w);
    }
    final main = forecast.at(start) ?? (slices.isNotEmpty ? slices.first : forecast.hours.first);
    if (slices.isEmpty) slices.add(main);

    var total = 0.0;
    final reasonWeights = <String, double>{};
    RouteWind? mainWind;
    for (final w in slices) {
      final r = _scoreHour(w, type);
      total += r.score;
      mainWind ??= r.wind;
      r.penalties.forEach((k, v) => reasonWeights[k] = (reasonWeights[k] ?? 0) + v);
    }
    final score = (total / slices.length).clamp(0, 100).round();

    final reasons = reasonWeights.entries.where((e) => e.value / slices.length >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final texts = reasons.take(3).map((e) => e.key).toList();
    if (texts.isEmpty) texts.add('Prima omstandigheden voor jou');

    return StartTimeScore(
      start: start,
      score: score,
      weather: main,
      reasons: texts,
      routeWind: mainWind,
    );
  }

  ({double score, Map<String, double> penalties, RouteWind? wind}) _scoreHour(
    HourWeather w,
    TrainingType type,
  ) {
    final p = <String, double>{};
    final feels = w.feelsLike ?? w.temperature;
    final optMin = profile.optimalMin;
    final optMax = profile.optimalMax;

    // Temperatuur: hitte weegt zwaarder dan kou.
    final heatMul = switch (type) {
      TrainingType.quality => 6.5,
      TrainingType.long => 6.0,
      TrainingType.easy => 4.5,
      TrainingType.recovery => 3.0,
    };
    if (feels > optMax) {
      p['Warm (${feels.round()}°C gevoel)'] = (feels - optMax) * heatMul;
    } else if (feels < optMin) {
      p['Koud (${feels.round()}°C gevoel)'] = (optMin - feels) * (type == TrainingType.recovery ? 1.5 : 2.5);
    }

    // Regen.
    final rainMul = switch (type) {
      TrainingType.long => 0.45,
      TrainingType.quality => 0.35,
      TrainingType.easy => 0.3,
      TrainingType.recovery => 0.15,
    };
    final rainProb = w.precipitationProbability ?? ((w.precipitation ?? 0) > 0.1 ? 60.0 : 0.0);
    final rainPenalty = rainProb * rainMul + math.min(20.0, (w.precipitation ?? 0) * 8);
    if (rainPenalty > 0) p['Kans op regen (${rainProb.round()}%)'] = rainPenalty;

    // Wind: met route rekenen we met tegenwind op jouw looprichting.
    RouteWind? rw;
    double effectiveWind;
    if (_segments.isNotEmpty && w.windDirection != null) {
      rw = routeWind(_segments, w.windSpeed, w.windDirection!);
      effectiveWind = rw.effective + 0.2 * w.windSpeed;
    } else {
      effectiveWind = 0.55 * w.windSpeed;
    }
    final windMul = switch (type) {
      TrainingType.quality => 2.2,
      TrainingType.long => 1.6,
      TrainingType.easy => 1.2,
      TrainingType.recovery => 0.6,
    };
    final windPenalty = math.max(0.0, effectiveWind - 4) * windMul;
    if (windPenalty > 0) {
      final label = rw != null && rw.headwindAvg >= 8
          ? 'Tegenwind op je route (${rw.headwindAvg.round()} km/u)'
          : 'Wind (${w.windSpeed.round()} km/u)';
      p[label] = windPenalty;
    }
    if ((w.windGusts ?? 0) > 50) p['Harde windstoten'] = 10.0;

    // Donker.
    if (!w.isDay) p['Donker'] = type == TrainingType.quality ? 14.0 : 10.0;

    // UV en benauwdheid.
    final uv = w.uvIndex ?? 0;
    if (uv > 6) p['Hoge UV-index (${uv.round()})'] = (uv - 6) * 2.5;
    final hum = w.humidity ?? 0;
    if (hum > 80 && feels > 16) p['Benauwd'] = (hum - 80) * 0.4;

    // Gladheid.
    if (w.temperature <= 0.5 && (w.precipitation ?? 0) > 0) p['Kans op gladheid'] = 20.0;

    final total = p.values.fold<double>(0, (s, v) => s + v);
    return (score: 100 - total, penalties: p, wind: rw);
  }
}
