import 'dart:math' as math;

// Stand van de zon (hoogte boven de horizon en kompasrichting), naar de bekende formules
// die ook SunCalc gebruikt. Nauwkeurig genoeg (± 0,5°) om lage zon in je gezicht te voorspellen.

const _rad = math.pi / 180;
const _e = _rad * 23.4397; // scheefstand van de aardas

/// Zonnestand op tijdstip [t] op [lat], [lon].
/// `elevation` in graden boven de horizon (negatief = onder), `azimuth` in graden vanaf het noorden, met de klok mee.
({double elevation, double azimuth}) sunPosition(DateTime t, double lat, double lon) {
  final d = t.toUtc().millisecondsSinceEpoch / 86400000.0 - 0.5 + 2440588 - 2451545;
  final m = _rad * (357.5291 + 0.98560028 * d);
  final c = _rad * (1.9148 * math.sin(m) + 0.02 * math.sin(2 * m) + 0.0003 * math.sin(3 * m));
  final l = m + c + _rad * 102.9372 + math.pi;
  final dec = math.asin(math.sin(l) * math.sin(_e));
  final ra = math.atan2(math.sin(l) * math.cos(_e), math.cos(l));
  final lw = _rad * -lon, phi = _rad * lat;
  final h = _rad * (280.16 + 360.9856235 * d) - lw - ra;
  final alt = math.asin(math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.cos(h));
  final az = math.atan2(math.sin(h), math.cos(h) * math.sin(phi) - math.tan(dec) * math.cos(phi));
  return (elevation: alt / _rad, azimuth: (az / _rad + 180) % 360);
}

/// Kleinste hoek tussen twee richtingen (0–180°).
double angleBetween(double a, double b) {
  final d = ((a - b) % 360 + 360) % 360;
  return d > 180 ? 360 - d : d;
}

/// Lage zon: tussen net boven de horizon en 12° hoog. Dan schijnt hij recht in je ogen (en in die van automobilisten).
bool isLowSun(double elevation) => elevation > 0.5 && elevation < 12;

/// Deel van de route (0–1) dat je binnen [cone] graden recht op de zon af loopt.
double fractionTowardSun(List<({double bearing, double meters, double startKm})> route, double sunAzimuth, {double cone = 35}) {
  final total = route.fold<double>(0, (a, s) => a + s.meters);
  if (total <= 0) return 0;
  final toward = route.where((s) => angleBetween(s.bearing, sunAzimuth) <= cone).fold<double>(0, (a, s) => a + s.meters);
  return toward / total;
}
