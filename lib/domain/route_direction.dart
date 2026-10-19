import 'dart:math' as math;

import 'geo.dart';
import 'start_time_scoring.dart';

/// Advies welke kant je een rondje op moet lopen.
class DirectionAdvice {
  const DirectionAdvice({
    required this.reverse,
    required this.bestLabel,
    required this.endHeadwind,
    required this.otherEndHeadwind,
  });

  /// true = loop het rondje andersom dan zoals het is opgeslagen.
  final bool reverse;

  /// "linksom" of "rechtsom".
  final String bestLabel;

  /// Gemiddelde tegenwind (km/u) in de tweede helft bij de beste richting.
  final double endHeadwind;

  /// Hetzelfde bij de andere richting.
  final double otherEndHeadwind;

  String get text {
    final tail = endHeadwind < 1;
    return 'Loop $bestLabel (${bestLabel == 'linksom' ? 'tegen de klok in' : 'met de klok mee'}): '
        '${tail ? 'dan heb je op de tweede helft de wind in je rug' : 'dan heb je op de tweede helft minder tegenwind'} '
        '(${endHeadwind.round()} in plaats van ${otherEndHeadwind.round()} km/u tegenwind).';
  }
}

/// Totale lengte van een spoor in meters.
double trackLength(List<LatLng> track) {
  var d = 0.0;
  for (var i = 1; i < track.length; i++) {
    d += distanceMeters(track[i - 1], track[i]);
  }
  return d;
}

/// Is dit een rondje (start en eind dicht bij elkaar)?
bool isLoop(List<LatLng> track) {
  if (track.length < 4) return false;
  final length = trackLength(track);
  if (length < 500) return false;
  return distanceMeters(track.first, track.last) <= math.max(300.0, length * 0.05);
}

/// Oppervlakte met teken (m²): positief = tegen de klok in (linksom).
double signedArea(List<LatLng> track) {
  if (track.length < 3) return 0;
  final lat0 = track.first.lat * math.pi / 180;
  const r = 6371000.0;
  double x(LatLng p) => p.lon * math.pi / 180 * r * math.cos(lat0);
  double y(LatLng p) => p.lat * math.pi / 180 * r;
  var a = 0.0;
  for (var i = 0; i < track.length; i++) {
    final p = track[i];
    final q = track[(i + 1) % track.length];
    a += x(p) * y(q) - x(q) * y(p);
  }
  return a / 2;
}

/// Geeft advies over de looprichting, of null als het niet uitmaakt of niet kan
/// (geen rondje, heen-en-terug, of te weinig wind).
DirectionAdvice? adviseDirection(List<LatLng> track, double windSpeed, double? windFromDegrees) {
  if (windFromDegrees == null || windSpeed < 8 || !isLoop(track)) return null;
  final length = trackLength(track);
  final area = signedArea(track).abs();
  // Bijna geen oppervlakte = heen-en-terug over hetzelfde pad: omdraaien verandert niets.
  if (4 * math.pi * area / (length * length) < 0.03) return null;

  final forward = routeWind(trackSegments(track), windSpeed, windFromDegrees);
  final backward = routeWind(trackSegments(track.reversed.toList()), windSpeed, windFromDegrees);
  final diff = forward.secondHalfHead - backward.secondHalfHead;
  if (diff.abs() < 2) return null;

  final reverse = diff > 0;
  final storedIsCounterClockwise = signedArea(track) > 0;
  final bestIsCounterClockwise = reverse ? !storedIsCounterClockwise : storedIsCounterClockwise;
  return DirectionAdvice(
    reverse: reverse,
    bestLabel: bestIsCounterClockwise ? 'linksom' : 'rechtsom',
    endHeadwind: reverse ? backward.secondHalfHead : forward.secondHalfHead,
    otherEndHeadwind: reverse ? forward.secondHalfHead : backward.secondHalfHead,
  );
}
