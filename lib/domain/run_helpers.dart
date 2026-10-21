import 'dart:math' as math;

import 'geo.dart';

/// Zonsopkomst en -ondergang (lokale tijd) voor een plek en datum.
/// Vereenvoudigde NOAA-berekening; nauwkeurig tot op een paar minuten, ruim genoeg voor "neem een lampje mee".
({DateTime? sunrise, DateTime? sunset}) sunTimes(DateTime date, double lat, double lon) {
  final day = DateTime.utc(date.year, date.month, date.day);
  final n = day.difference(DateTime.utc(date.year, 1, 1)).inDays + 1;
  final gamma = 2 * math.pi / 365 * (n - 1);
  final eqTime = 229.18 *
      (0.000075 + 0.001868 * math.cos(gamma) - 0.032077 * math.sin(gamma) - 0.014615 * math.cos(2 * gamma) - 0.040849 * math.sin(2 * gamma));
  final decl = 0.006918 -
      0.399912 * math.cos(gamma) +
      0.070257 * math.sin(gamma) -
      0.006758 * math.cos(2 * gamma) +
      0.000907 * math.sin(2 * gamma) -
      0.002697 * math.cos(3 * gamma) +
      0.00148 * math.sin(3 * gamma);
  final latR = lat * math.pi / 180;
  final cosHa = math.cos(90.833 * math.pi / 180) / (math.cos(latR) * math.cos(decl)) - math.tan(latR) * math.tan(decl);
  if (cosHa > 1 || cosHa < -1) return (sunrise: null, sunset: null); // poolnacht of middernachtzon
  final ha = math.acos(cosHa) * 180 / math.pi;
  DateTime at(double minutesUtc) => day.add(Duration(seconds: (minutesUtc * 60).round())).toLocal();
  return (sunrise: at(720 - 4 * (lon + ha) - eqTime), sunset: at(720 - 4 * (lon - ha) - eqTime));
}

/// Waarschuwing als je pas na zonsondergang terug bent (null = je bent ruim op tijd terug).
String? darkWarning(DateTime start, Duration duration, double lat, double lon) {
  final end = start.add(duration);
  final sun = sunTimes(start, lat, lon);
  final set = sun.sunset, rise = sun.sunrise;
  if (set == null || rise == null) return null;
  String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (start.isBefore(set) && end.isAfter(set.add(const Duration(minutes: 10)))) {
    return 'Het wordt om ${hm(set)} donker en je bent rond ${hm(end)} terug. Neem een lampje en iets reflecterends mee.';
  }
  if (start.isBefore(rise) && start.hour < 12) {
    return 'Het is nog donker tot ${hm(rise)}. Neem een lampje en iets reflecterends mee.';
  }
  return null;
}

/// Richting en afstand terug naar je startpunt, ten opzichte van de kant die je nu op loopt.
/// [relative] in graden: 0 = recht vooruit, 90 = rechts, 180 = achter je. Null zonder looprichting.
({double meters, double? relative})? backToStart(List<LatLng> track) {
  if (track.length < 2) return null;
  final here = track.last;
  final start = track.first;
  final meters = distanceMeters(here, start);
  // Looprichting: vanaf een punt minstens 15 m terug in je spoor.
  LatLng? from;
  for (var i = track.length - 2; i >= 0 && i >= track.length - 60; i--) {
    if (distanceMeters(track[i], here) >= 15) {
      from = track[i];
      break;
    }
  }
  if (from == null) return (meters: meters, relative: null);
  final course = bearingDegrees(from, here);
  final toStart = bearingDegrees(here, start);
  var rel = (toStart - course) % 360;
  if (rel < 0) rel += 360;
  return (meters: meters, relative: rel);
}

/// Zelfde vraag in gewone woorden, voor de stem ("links achter je").
String directionWords(double rel) {
  if (rel < 25 || rel > 335) return 'recht voor je';
  if (rel < 70) return 'rechts voor je';
  if (rel < 110) return 'rechts van je';
  if (rel < 155) return 'rechts achter je';
  if (rel < 205) return 'achter je';
  if (rel < 250) return 'links achter je';
  if (rel < 290) return 'links van je';
  return 'links voor je';
}

/// Voorstellen voor een weekdoel op basis van je gemiddelde van de laatste weken.
List<double> weekGoalSuggestions(double avgKm) {
  if (avgKm < 3) return const [10, 15, 20];
  double r(double v) => (v / 5).round() * 5.0 < 5 ? 5 : (v / 5).round() * 5.0;
  final s = {r(avgKm * 0.9), r(avgKm), r(avgKm * 1.1 + 2)}.toList()..sort();
  return s;
}
