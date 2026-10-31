import '../data/models/models.dart';

/// Ideaal weer voor een snelle run (persoonlijk record): koel, windstil en droog.
/// Onderzoek naar marathontijden: het snelst rond 6–12 °C; elke graad erboven kost tijd.
bool isRecordWeather(HourWeather w) {
  final feels = w.feelsLike ?? w.temperature;
  return feels >= 4 &&
      feels <= 13 &&
      w.windSpeed < 15 &&
      (w.windGusts ?? w.windSpeed) < 28 &&
      (w.precipitation ?? 0) < 0.1 &&
      (w.precipitationProbability ?? 0) < 25 &&
      (w.weatherCode ?? 0) < 45;
}

/// Welk record het meest voor de hand ligt om aan te vallen: 5 km, anders 10 km, anders 3 km.
({double meters, double seconds, String label})? recordTarget(Map<int, double> bestSecondsByMeters) {
  for (final (m, label) in const [(5000, '5 km'), (10000, '10 km'), (3000, '3 km')]) {
    final s = bestSecondsByMeters[m];
    if (s != null && s > 0) return (meters: m.toDouble(), seconds: s, label: label);
  }
  return null;
}
