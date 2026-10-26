import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/route_share.dart';

void main() {
  final pts = [for (var i = 0; i <= 1000; i++) LatLng(52.15 + i * 0.00001, 5.59 + i * 0.00002)];

  test('link heen en terug', () {
    final r = SharedRoute('Rondje bos & heide', pts);
    final uri = Uri.parse(r.appLink);
    expect(uri.path, '/route-delen');
    final back = SharedRoute.fromParams(uri.queryParameters)!;
    expect(back.name, 'Rondje bos & heide');
    expect(back.points.length, SharedRoute.maxPoints);
    expect(back.points.first.lat, closeTo(52.15, 1e-5));
    expect(back.points.last.lat, closeTo(pts.last.lat, 1e-5));
  });

  test('webpagina-link met hash', () {
    final link = SharedRoute('A', pts.take(3).toList()).webLink('https://x.github.io/Runwise');
    expect(link, startsWith('https://x.github.io/Runwise/route.html#n=A&p='));
  });

  test('ongeldige link', () {
    expect(SharedRoute.fromParams({}), isNull);
    expect(SharedRoute.fromParams({'p': '?'}), isNull);
  });
}
