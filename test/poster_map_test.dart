import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/poster_map.dart';

void main() {
  const track = [LatLng(52.14, 5.58), LatLng(52.15, 5.60), LatLng(52.16, 5.59)];

  test('kader rond de route is ruimer en ongeveer zo breed als het kaartvlak', () {
    final b = posterMapBounds(track);
    expect(b.s, lessThan(52.14));
    expect(b.n, greaterThan(52.16));
    expect(b.w, lessThan(5.58));
    expect(b.e, greaterThan(5.60));
    final h = distanceMeters(LatLng(b.s, b.w), LatLng(b.n, b.w));
    final w = distanceMeters(LatLng(b.s, b.w), LatLng(b.s, b.e));
    expect(w / h, closeTo(1.25, 0.05));
  });

  test('klein gebied: ook paden; groot gebied: alleen grote wegen', () {
    expect(posterMapQuery(track), contains('footway'));
    const big = [LatLng(52.0, 5.4), LatLng(52.3, 5.9)];
    expect(posterMapQuery(big), isNot(contains('residential')));
    expect(posterMapQuery(big), contains('primary'));
  });

  test('antwoord lezen, sorteren en compact bewaren', () {
    const body = '{"elements":['
        '{"type":"way","tags":{"highway":"primary"},"geometry":[{"lat":52.1,"lon":5.1},{"lat":52.2,"lon":5.2}]},'
        '{"type":"way","tags":{"natural":"water"},"geometry":[{"lat":52.1,"lon":5.1},{"lat":52.11,"lon":5.12},{"lat":52.1,"lon":5.1}]},'
        '{"type":"way","tags":{"highway":"footway"},"geometry":[{"lat":52.1,"lon":5.1},{"lat":52.12,"lon":5.13}]},'
        '{"type":"way","tags":{"building":"yes"},"geometry":[{"lat":52.1,"lon":5.1},{"lat":52.12,"lon":5.13}]},'
        '{"type":"way","tags":{"highway":"residential"},"geometry":[{"lat":52.1,"lon":5.1}]}'
        ']}';
    final lines = parsePosterMap(body);
    expect(lines.map((l) => l.kind), [MapLineKind.waterArea, MapLineKind.path, MapLineKind.major]);
    final back = decodePosterMap(encodePosterMap(lines));
    expect(back.map((l) => l.kind), lines.map((l) => l.kind));
    expect(back.last.points.last.lat, closeTo(52.2, 1e-5));
    expect(back.last.points.last.lon, closeTo(5.2, 1e-5));
  });
}
