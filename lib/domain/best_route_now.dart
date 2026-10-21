import 'geo.dart';
import 'route_direction.dart';
import 'start_time_scoring.dart';

/// Een kandidaat-route: naam/id, het spoor en waar hij begint.
class RouteCandidate {
  const RouteCandidate({required this.id, required this.name, required this.track});
  final String id;
  final String name;
  final List<LatLng> track;
}

/// Uitkomst: welke route nu het lekkerst loopt met deze wind, en welke kant op.
class BestRouteNow {
  const BestRouteNow({
    required this.route,
    required this.wind,
    required this.reverse,
    required this.directionLabel,
    required this.score,
    required this.compared,
  });

  final RouteCandidate route;
  final RouteWind wind;

  /// Andersom lopen dan opgeslagen (alleen bij rondjes).
  final bool reverse;
  final String? directionLabel;

  /// Lager = beter (km/u "gevoelde" tegenwind, met extra gewicht op de terugweg).
  final double score;

  /// Met hoeveel routes vergeleken.
  final int compared;

  String get summary {
    final back = wind.secondHalfHead < 1 ? 'op de terugweg wind mee' : 'op de terugweg ${wind.secondHalfHead.round()} km/u tegenwind';
    return 'Gemiddeld ${wind.headwindAvg.round()} km/u tegenwind, $back.'
        '${directionLabel == null ? '' : ' Loop hem $directionLabel.'}';
  }
}

/// Kiest uit je routes (binnen [maxStartMeters] van waar je bent) de route met de minste last van de wind.
/// Null bij weinig wind (dan maakt het niet uit) of als er minder dan 2 routes in de buurt zijn.
BestRouteNow? bestRouteForWind(
  List<RouteCandidate> routes, {
  required double windSpeed,
  required double? windFromDegrees,
  LatLng? near,
  double maxStartMeters = 5000,
  double minWind = 12,
}) {
  final from = windFromDegrees;
  if (from == null || windSpeed < minWind) return null;
  final nearby = [
    for (final r in routes)
      if (r.track.length >= 2 && (near == null || distanceMeters(near, r.track.first) <= maxStartMeters)) r
  ];
  if (nearby.length < 2) return null;
  BestRouteNow? best;
  for (final r in nearby) {
    final advice = adviseDirection(r.track, windSpeed, from);
    final reverse = advice?.reverse ?? false;
    final track = reverse ? r.track.reversed.toList() : r.track;
    final w = routeWind(trackSegments(track), windSpeed, from);
    final score = w.effective + 0.5 * w.secondHalfHead;
    if (best == null || score < best.score) {
      best = BestRouteNow(
        route: r,
        wind: w,
        reverse: reverse,
        directionLabel: advice?.bestLabel,
        score: score,
        compared: nearby.length,
      );
    }
  }
  return best;
}
