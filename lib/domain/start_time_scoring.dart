import 'dart:math' as math;

import '../data/models/models.dart';
import 'availability.dart';
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
    this.factors = const {},
  });

  final DateTime start;

  /// 0–100, hoger is beter.
  final int score;
  final HourWeather weather;

  /// Uitleg waarom de score zo is (belangrijkste eerst).
  final List<String> reasons;
  final RouteWind? routeWind;

  /// Strafpunten per soort (warm, koud, regen, wind, …), gemiddeld over de looptijd.
  /// Om twee tijden eerlijk met elkaar te vergelijken.
  final Map<WeatherFactor, double> factors;

  String get verdict {
    if (score >= 85) return 'Top';
    if (score >= 70) return 'Goed';
    if (score >= 55) return 'Prima';
    if (score >= 40) return 'Matig';
    return 'Lastig';
  }
}

/// Soort weerfactor achter de strafpunten.
enum WeatherFactor { warm, cold, rain, wind, gusts, dark, uv, humid, ice, thunder }

/// Soort bij een uitleg-tekst uit de score (de tekst bevat getallen, de soort niet).
WeatherFactor? factorOf(String label) {
  if (label.startsWith('Warm')) return WeatherFactor.warm;
  if (label.startsWith('Koud')) return WeatherFactor.cold;
  if (label.startsWith('Buien') || label.startsWith('Kans op regen')) return WeatherFactor.rain;
  if (label.startsWith('Tegenwind') || label.startsWith('Wind')) return WeatherFactor.wind;
  if (label.startsWith('Harde windstoten')) return WeatherFactor.gusts;
  if (label.startsWith('Donker')) return WeatherFactor.dark;
  if (label.startsWith('Hoge UV')) return WeatherFactor.uv;
  if (label.startsWith('Benauwd')) return WeatherFactor.humid;
  if (label.startsWith('Kans op gladheid')) return WeatherFactor.ice;
  if (label.startsWith('Onweer')) return WeatherFactor.thunder;
  return null;
}

class StartTimePlanner {
  StartTimePlanner({
    required this.forecast,
    required this.profile,
    this.track = const [],
    this.durationMinutes = 60,
    this.rain,
    this.availability = Availability.always,
  }) : _segments = trackSegments(track);

  /// Wanneer je kunt lopen; daarbuiten wordt geen tijd voorgesteld.
  final Availability availability;

  final Forecast forecast;

  /// Live buienverwachting (komende 2 uur, per 5 minuten). Gaat voor de gewone verwachting.
  final RainNowcast? rain;
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
      if (availability.isAlways) {
        results.add(scoreAt(h.time, type));
      } else {
        // Eerste moment in dit uur dat binnen je looptijden valt.
        final t = availability.firstAllowedInHour(h.time, durationMinutes);
        if (t != null && !t.isBefore(now.subtract(const Duration(minutes: 1)))) results.add(scoreAt(t, type));
      }
    }
    return results;
  }

  /// Beste vertrektijd binnen de horizon, afgerond op het hele uur.
  StartTimeScore? best(TrainingType type, {DateTime? from, Duration? horizon}) {
    final all = scoreAll(type, from: from, horizon: horizon ?? const Duration(hours: 36));
    if (all.isEmpty) return null;
    return all.reduce((a, b) => b.score > a.score ? b : a);
  }

  /// Beste vertrektijd op [stepMinutes] minuten nauwkeurig.
  ///
  /// Eerst per uur, daarna rond de drie beste uren en in de komende 2 uur
  /// (waar de buienradar meekijkt) per [stepMinutes] minuten verfijnd.
  StartTimeScore? bestPrecise(
    TrainingType type, {
    DateTime? from,
    Duration horizon = const Duration(hours: 36),
    int stepMinutes = 5,
    int earliestHour = 5,
    int latestHour = 22,
  }) {
    final now = from ?? DateTime.now();
    final hourly = scoreAll(type, from: now, horizon: horizon, earliestHour: earliestHour, latestHour: latestHour);
    if (hourly.isEmpty) return null;

    final first = roundUp(now, stepMinutes);
    final end = now.add(horizon);
    bool allowed(DateTime t) =>
        !t.isBefore(first) &&
        !t.isAfter(end) &&
        t.hour >= earliestHour &&
        t.hour <= latestHour &&
        availability.allows(t, durationMinutes);

    final candidates = <DateTime>{};
    final top = [...hourly]..sort((a, b) => b.score.compareTo(a.score));
    for (final h in top.take(3)) {
      for (var m = -55; m <= 55; m += stepMinutes) {
        candidates.add(h.start.add(Duration(minutes: m)));
      }
    }
    for (var m = 0; m <= 120; m += stepMinutes) {
      candidates.add(first.add(Duration(minutes: m)));
    }

    StartTimeScore? best;
    final sorted = candidates.where(allowed).toList()..sort();
    for (final t in sorted) {
      final s = scoreAt(t, type);
      if (best == null || s.score > best.score) best = s;
    }
    return best ?? top.first;
  }

  /// [t] naar boven afgerond op [step] minuten (14:02 → 14:05).
  static DateTime roundUp(DateTime t, int step) {
    final base = DateTime(t.year, t.month, t.day, t.hour);
    final minutes = t.minute + (t.second > 0 || t.millisecond > 0 ? 1 : 0);
    final rounded = ((minutes + step - 1) ~/ step) * step;
    return base.add(Duration(minutes: rounded));
  }

  /// Weer op precies [t]: kwartierdata geïnterpoleerd, en waar Buienradar
  /// iets zegt over de komende 2 uur gaat de regen daarvan voor.
  HourWeather? weatherAt(DateTime t) {
    final w = forecast.precise(t) ?? forecast.at(t);
    final mm = rain?.at(t);
    if (w == null || mm == null) return w;
    return HourWeather(
      time: w.time,
      temperature: w.temperature,
      feelsLike: w.feelsLike,
      humidity: w.humidity,
      precipitationProbability: mm >= 0.1 ? 95 : 0,
      precipitation: mm,
      windSpeed: w.windSpeed,
      windDirection: w.windDirection,
      windGusts: w.windGusts,
      uvIndex: w.uvIndex,
      weatherCode: w.weatherCode,
      isDay: w.isDay,
    );
  }

  /// Score voor vertrekken op [start]: het gemiddelde over de tijd dat je onderweg bent,
  /// elke 10 minuten bekeken.
  StartTimeScore scoreAt(DateTime start, TrainingType type) {
    final slices = <HourWeather>[];
    for (var m = 0; m < math.max(10, durationMinutes); m += 10) {
      final w = weatherAt(start.add(Duration(minutes: m)));
      if (w != null) slices.add(w);
    }
    final main = weatherAt(start) ?? (slices.isNotEmpty ? slices.first : forecast.hours.first);
    if (slices.isEmpty) slices.add(main);

    var total = 0.0;
    final reasonWeights = <String, double>{};
    final factorWeights = <WeatherFactor, double>{};
    RouteWind? mainWind;
    for (final w in slices) {
      final r = _scoreHour(w, type);
      total += r.score;
      mainWind ??= r.wind;
      r.penalties.forEach((k, v) {
        reasonWeights[k] = (reasonWeights[k] ?? 0) + v;
        final f = factorOf(k);
        if (f != null) factorWeights[f] = (factorWeights[f] ?? 0) + v;
      });
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
      factors: {for (final e in factorWeights.entries) e.key: e.value / slices.length},
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
    final rainPenalty = (rainProb * rainMul + math.min(20.0, (w.precipitation ?? 0) * 8)) * profile.rainWeight;
    if (rainPenalty > 0) {
      final label = rainProb >= 95 && (w.precipitation ?? 0) >= 0.1
          ? 'Buien volgens Buienradar (${(w.precipitation ?? 0).toStringAsFixed(1)} mm/u)'
          : 'Kans op regen (${rainProb.round()}%)';
      p[label] = rainPenalty;
    }

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

    // Onweer (weercode 95–99): onveilig, telt altijd zwaar mee, ook als je regen niet erg vindt.
    final code = w.weatherCode ?? 0;
    if (code >= 95 && code <= 99) p['Onweer'] = 40.0;

    final total = p.values.fold<double>(0, (s, v) => s + v);
    return (score: 100 - total, penalties: p, wind: rw);
  }
}
