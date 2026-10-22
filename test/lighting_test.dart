import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/lighting.dart';
import 'package:runwise/domain/route_geometry.dart';

void main() {
  test('verlichting langs de route', () {
    // Route 1 km naar het oosten. De eerste 600 m verlicht, daarna een onverlicht pad.
    final route = RouteTrack([for (var i = 0; i <= 10; i++) LatLng(52.0, 5.0 + i * 100 / 68540)]);
    final body = '{"elements":['
        '{"type":"way","tags":{"highway":"residential","lit":"yes"},"geometry":[{"lat":52.0,"lon":5.0},{"lat":52.0,"lon":${5.0 + 600 / 68540}}]},'
        '{"type":"way","tags":{"highway":"path","lit":"no"},"geometry":[{"lat":52.0,"lon":${5.0 + 600 / 68540}},{"lat":52.0,"lon":${5.0 + 1000 / 68540}}]},'
        '{"type":"way","tags":{"highway":"service"},"geometry":[{"lat":52.01,"lon":5.0},{"lat":52.01,"lon":5.01}]}'
        ']}';
    final ways = parseLitWays(body);
    expect(ways.length, 3);
    expect(ways[2].lit, isNull);
    final l = lightingAlong(route, ways);
    expect(l.lit, closeTo(600, 45));
    expect(l.unlit, closeTo(400, 45));
    expect(l.unknown, lessThan(5));
    expect(sampleTrack(route).length, inInclusiveRange(12, 14));
    expect(litQuery(sampleTrack(route)), startsWith('[out:json][timeout:25];way["highway"](around:25,52.00000,5.00000'));
  });
}
