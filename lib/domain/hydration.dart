import 'dart:math' as math;

/// Schatting van zweetverlies (liter per uur) uit weer, tempo en lichaamsgewicht.
/// Grof model op basis van sportwetenschappelijke vuistregels: ±0,5 L/u bij 15 °C en 10 km/u voor 70 kg,
/// meer bij warmte, vocht en snelheid. Altijd een schatting: wegen voor en na de run is het nauwkeurigst.
double sweatRateLph({required double feelsLike, double? humidity, required double speedKmh, double weightKg = 75}) {
  var rate = 0.5;
  rate += feelsLike >= 15 ? (feelsLike - 15) * 0.045 : (feelsLike - 15) * 0.015;
  if (humidity != null && humidity > 60) rate += (humidity - 60) * 0.004;
  rate *= (speedKmh.clamp(5, 20) / 10);
  rate *= weightKg.clamp(40, 140) / 70;
  return rate.clamp(0.2, 2.2).toDouble();
}

class HydrationAdvice {
  const HydrationAdvice(this.lossLiters, this.drinkLiters, this.salt);

  /// Geschat vochtverlies tijdens de run.
  final double lossLiters;

  /// Aanbevolen om de komende uren te drinken (± 1,25 × het verlies).
  final double drinkLiters;

  /// Bij veel verlies ook zout aanvullen (soep, sportdrank, iets hartigs).
  final bool salt;

  String get text {
    String l(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    if (lossLiters < 0.3) return 'Ongeveer ${l(lossLiters)} L vocht verloren. Gewoon een glas water is genoeg.';
    return 'Ongeveer ${l(lossLiters)} L vocht verloren. Drink de komende uren zo\'n ${l(drinkLiters)} L, rustig verspreid'
        '${salt ? ', en neem iets zouts (soep, sportdrank of een hartige snack).' : '.'}';
  }
}

/// Advies na een run van [minutes] minuten over [meters] meter.
HydrationAdvice? hydrationAfter({required int minutes, required double meters, required double feelsLike, double? humidity, double weightKg = 75}) {
  if (minutes < 20 || meters < 2000) return null;
  final speed = meters / 1000 / (minutes / 60);
  final loss = sweatRateLph(feelsLike: feelsLike, humidity: humidity, speedKmh: speed, weightKg: weightKg) * minutes / 60;
  return HydrationAdvice(loss, math.max(0.3, loss * 1.25), loss >= 1.2);
}

/// Hoeveel drinken mee (ml) voor een run, of null als dat niet nodig is (korter dan een uur of koel).
int? carryMl({required int minutes, required double feelsLike, double? humidity, double speedKmh = 10, double weightKg = 75}) {
  if (minutes < 60 || feelsLike < 15) return null;
  final loss = sweatRateLph(feelsLike: feelsLike, humidity: humidity, speedKmh: speedKmh, weightKg: weightKg) * minutes / 60;
  // Onderweg ongeveer de helft aanvullen; afronden op 50 ml.
  final ml = (loss * 500 / 50).round() * 50;
  return ml < 250 ? 250 : ml;
}
