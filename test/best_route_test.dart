import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/best_route_now.dart';
import 'package:runwise/domain/geo.dart';

List<LatLng> path(List<(double, double)> moves) {
  final pts = [const LatLng(52.0, 5.6)];
  for (final (bearing, meters) in moves) {
    for (var k = 0; k < (meters / 20).round(); k++) {
      final p = pts.last;
      pts.add(LatLng(p.lat + 20 * math.cos(bearing * math.pi / 180) / 111320,
          p.lon + 20 * math.sin(bearing * math.pi / 180) / (111320 * math.cos(p.lat * math.pi / 180))));
    }
  }
  return pts;
}

void main() {
  final square = RouteCandidate(id: 'a', name: 'Vierkant', track: path([(0, 1000), (90, 1000), (180, 1000), (270, 1000)]));
  final eastWest = RouteCandidate(id: 'b', name: 'Oost-west', track: path([(90, 2000), (270, 2000)]));

  test('kiest de route met de minste tegenwind', () {
    final best = bestRouteForWind([square, eastWest], windSpeed: 25, windFromDegrees: 0);
    expect(best, isNotNull);
    expect(best!.route.id, 'b');
    expect(best.compared, 2);
    expect(best.summary, contains('tegenwind'));
  });

  test('bij weinig wind of één route geen advies', () {
    expect(bestRouteForWind([square, eastWest], windSpeed: 6, windFromDegrees: 0), isNull);
    expect(bestRouteForWind([square], windSpeed: 25, windFromDegrees: 0), isNull);
    expect(bestRouteForWind([square, eastWest], windSpeed: 25, windFromDegrees: null), isNull);
  });

  test('routes ver weg tellen niet mee', () {
    expect(bestRouteForWind([square, eastWest], windSpeed: 25, windFromDegrees: 0, near: const LatLng(53.0, 6.5)), isNull);
  });
}
