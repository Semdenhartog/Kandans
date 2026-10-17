import 'dart:math' as math;

import '../data/models/models.dart';
import 'performance_model.dart';
import 'start_time_scoring.dart';

/// Voorspelling en advies voor een wedstrijd.
class RaceAdvice {
  RaceAdvice({
    required this.baseFinishSeconds,
    required this.basedOn,
    this.weather,
    this.temperatureImpactSeconds = 0,
    this.windImpactSeconds = 0,
    required this.clothing,
    required this.hydration,
    required this.pacing,
  });

  /// Verwachte tijd bij ideaal weer.
  final int baseFinishSeconds;

  /// Uitleg waar de basistijd op gebaseerd is.
  final String basedOn;

  /// Weer bij de start (null als de wedstrijd nog te ver weg is).
  final HourWeather? weather;
  final int temperatureImpactSeconds;
  final int windImpactSeconds;
  final String clothing;
  final String hydration;
  final String pacing;

  int get predictedFinishSeconds =>
      baseFinishSeconds + temperatureImpactSeconds + windImpactSeconds;
}

/// Open-Meteo voorspelt tot 16 dagen vooruit.
const forecastHorizonDays = 15;

/// Voorspelt de eindtijd met de formule van Riegel op basis van je beste
/// recente run, en corrigeert voor het verwachte weer.
RaceAdvice adviseRace({
  required RaceEvent race,
  required List<Activity> activities,
  required PerformanceInsights profile,
  Forecast? forecast,
  RouteWind? routeWind,
}) {
  // 1. Basistijd uit recente runs (laatste 120 dagen, minimaal 3 km).
  final cutoff = DateTime.now().subtract(const Duration(days: 120));
  final recent = activities
      .where((a) => a.startedAt.isAfter(cutoff) && a.distanceMeters >= 3000)
      .toList();

  int base;
  String basedOn;
  if (recent.isEmpty) {
    base = race.goalTimeSeconds;
    basedOn = 'Je doeltijd (nog geen recente runs van 3 km of meer)';
  } else {
    Activity? bestRun;
    var bestPrediction = double.infinity;
    for (final a in recent) {
      final ratio = race.distanceMeters / a.distanceMeters;
      final t = a.movingTimeSeconds * math.pow(ratio, 1.06);
      // Hoe verder de afstanden uit elkaar liggen, hoe onzekerder; licht straffen.
      final penalty = 1 + 0.02 * (math.log(ratio).abs());
      final adjusted = t * penalty;
      if (adjusted < bestPrediction) {
        bestPrediction = adjusted.toDouble();
        bestRun = a;
      }
    }
    base = bestPrediction.round();
    final km = (bestRun!.distanceMeters / 1000).toStringAsFixed(1).replaceAll('.', ',');
    basedOn = 'Je beste recente run: $km km';
  }

  // 2. Weer bij de start.
  final weather = forecast?.at(race.startDateTime);
  var tempImpact = 0;
  var windImpact = 0;
  if (weather != null) {
    final feels = weather.feelsLike ?? weather.temperature;
    final upper = math.max(profile.optimalMax, 12.0);
    if (feels > upper) {
      // Ongeveer 0,35% trager per graad boven je ideale temperatuur.
      tempImpact = (base * 0.0035 * (feels - upper)).round();
    } else if (feels < 0) {
      tempImpact = (base * 0.0015 * (0 - feels)).round();
    }
    final effectiveWind = routeWind != null
        ? routeWind.effective + 0.2 * weather.windSpeed
        : 0.55 * weather.windSpeed;
    if (effectiveWind > 5) {
      // Ongeveer 0,12% per km/u effectieve wind boven 5 km/u.
      windImpact = (base * 0.0012 * (effectiveWind - 5)).round();
    }
  }

  // 3. Advies.
  final feels = weather == null ? null : (weather.feelsLike ?? weather.temperature);
  final distanceKm = race.distanceMeters / 1000;

  final String clothing;
  if (feels == null) {
    clothing = 'Zodra de weersverwachting beschikbaar is (ongeveer 2 weken vooraf), krijg je hier kledingadvies.';
  } else if (feels < 2) {
    clothing = 'Lange tight, thermoshirt met lange mouwen, dunne muts en handschoenen. Neem een oud shirt mee voor bij de start dat je weg kunt gooien.';
  } else if (feels < 8) {
    clothing = 'Lange of 3/4 tight, shirt met lange mouwen en eventueel dunne handschoenen.';
  } else if (feels < 14) {
    clothing = 'Korte broek en shirt met korte of lange mouwen. Je warmt snel op, kleed je niet te dik.';
  } else if (feels < 20) {
    clothing = 'Korte broek en singlet of T-shirt. Een pet tegen de zon kan handig zijn.';
  } else {
    clothing = 'Zo luchtig mogelijk: singlet, korte broek, pet en zonnebrand.';
  }

  final hot = feels != null && feels >= 18;
  final String hydration;
  if (distanceKm <= 10) {
    hydration = hot
        ? 'Drink de 2 uur voor de start ongeveer een halve liter en pak onderweg een slokje bij de drankpost.'
        : 'Voor deze afstand is drinken onderweg niet nodig. Drink normaal in de uren voor de start.';
  } else if (distanceKm <= 21.1) {
    hydration = hot
        ? 'Neem bij elke drankpost een paar slokken en overweeg sportdrank. Begin goed gehydrateerd.'
        : 'Neem om de 5 km een paar slokken. Bij een halve marathon kan een gel rond km 12–14 helpen.';
  } else {
    hydration = 'Plan je drinken en energie: ongeveer elke 5 km drinken en elke 30–40 minuten een gel. Oefen dit vooraf in je lange duurlopen.';
  }

  final goalPace = race.goalTimeSeconds / distanceKm;
  final buffer = <String>[];
  if (tempImpact > 30) {
    buffer.add('Het wordt warm: start ongeveer 5–10 seconden per km rustiger dan je doeltempo.');
  }
  if (routeWind != null && (routeWind.firstHalfHead - routeWind.secondHalfHead).abs() > 4) {
    buffer.add(routeWind.firstHalfHead > routeWind.secondHalfHead
        ? 'Tegenwind in de eerste helft: laat je tempo daar iets zakken, je haalt het terug met rugwind.'
        : 'Tegenwind in de tweede helft: bewaar wat energie en loop de eerste helft niet te hard.');
  } else if (windImpact > 30) {
    buffer.add('Er staat flink wind: zoek beschutting in een groepje lopers.');
  }
  final paceTotal = goalPace.round();
  final paceMin = paceTotal ~/ 60;
  final paceSec = (paceTotal % 60).toString().padLeft(2, '0');
  final pacing = [
    'Je doeltempo is $paceMin:$paceSec per km. Loop de eerste kilometers bewust niet sneller.',
    ...buffer,
  ].join(' ');

  return RaceAdvice(
    baseFinishSeconds: base,
    basedOn: basedOn,
    weather: weather,
    temperatureImpactSeconds: tempImpact,
    windImpactSeconds: windImpact,
    clothing: clothing,
    hydration: hydration,
    pacing: pacing,
  );
}
