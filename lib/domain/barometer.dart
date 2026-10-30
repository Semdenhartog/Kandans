import 'dart:math' as math;

// Hoogte uit de luchtdrukmeter (barometer) van de telefoon.
// Rekenregels overgenomen van OpenTracks (Apache License 2.0, PressureSensorUtils):
// licht afvlakken (0,3) en alleen per stap van 3 m tellen, zodat ruis geen klimmen maakt.

/// Standaard luchtdruk op zeeniveau (hPa).
const standardPressureHpa = 1013.25;

/// Internationale hoogteformule: hoogte (m) bij luchtdruk [hpa].
/// Alleen de verschillen zijn betrouwbaar (het weer verschuift de absolute waarde).
double pressureToAltitude(double hpa, {double p0 = standardPressureHpa}) =>
    44330.0 * (1 - math.pow(hpa / p0, 1 / 5.255).toDouble());

/// Houdt een gladgestreken barometerhoogte bij uit losse luchtdrukmetingen.
class BarometricAltimeter {
  static const smoothing = 0.3;

  double? _hpa;

  /// Gladgestreken hoogte in meters (null = nog geen meting).
  double? get altitude => _hpa == null ? null : pressureToAltitude(_hpa!);

  void add(double hpa) {
    // Onzin-metingen (sensorfout) overslaan: op aarde zit je tussen ±300 en ±1100 hPa.
    if (hpa.isNaN || hpa < 300 || hpa > 1100) return;
    final prev = _hpa;
    _hpa = prev == null ? hpa : smoothing * hpa + (1 - smoothing) * prev;
  }

  void reset() => _hpa = null;
}

/// Hoogtemeters omhoog uit een reeks barometerhoogtes: een klim telt pas per [step] meter.
/// Daalt de hoogte [step] meter, dan schuift het vergelijkingspunt mee omlaag.
double barometricGain(List<double> altitudes, {double step = 3}) {
  if (altitudes.length < 2) return 0;
  var ref = altitudes.first;
  var gain = 0.0;
  for (final a in altitudes.skip(1)) {
    while (a - ref >= step) {
      gain += step;
      ref += step;
    }
    while (ref - a >= step) {
      ref -= step;
    }
  }
  return gain;
}

/// Haalt de barometerhoogtes uit het opgeslagen verloop (`baro`), of null als die er niet is.
List<double>? baroSeries(Map<String, dynamic>? streams) {
  final v = streams?['baro'];
  if (v is! List || v.length < 2) return null;
  return [for (final x in v) (x as num?)?.toDouble() ?? 0];
}
