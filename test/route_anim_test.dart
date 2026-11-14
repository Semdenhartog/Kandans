import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/route_anim.dart';

List<LatLng> _rondje() => [
      for (var i = 0; i <= 120; i++) LatLng(52.0 + 0.004 * (i / 120), 5.0 + 0.006 * (i % 40) / 40),
    ];

void main() {
  test('tijd en afstand opmaken', () {
    expect(formatAnimTime(2878), '47:58');
    expect(formatAnimTime(3912), '1:05:12');
    expect(formatAnimKm(10230), '10,2 km');
  });

  test('voortgang loopt van 0 naar 1 en lussen blijven op 1', () {
    for (final s in RouteAnimStyle.values) {
      expect(routeProgress(s, 0), 0 + (s == RouteAnimStyle.comet || s == RouteAnimStyle.echo ? 1 : 0));
      expect(routeProgress(s, s.seconds), 1);
      expect(s.frames, (s.seconds * routeAnimFps).round());
    }
  });

  test('lijn past in het vak en heeft lengte', () {
    const box = Rect.fromLTWH(80, 520, 920, 700);
    final p = RoutePath.fit(_rondje(), box)!;
    expect(p.length, greaterThan(100));
    for (final o in p.points) {
      expect(o.dx, inInclusiveRange(box.left - 1, box.right + 1));
      expect(o.dy, inInclusiveRange(box.top - 1, box.bottom + 1));
    }
    final half = p.slice(0, p.length / 2);
    expect(half.length, lessThan(p.points.length));
  });

  test('te korte lijn geeft null', () {
    expect(RoutePath.fit([LatLng(52, 5), LatLng(52, 5)], const Rect.fromLTWH(0, 0, 100, 100)), isNull);
  });

  test('pad per stuk en vaste videosnelheid', () {
    const box = Rect.fromLTWH(80, 520, 920, 700);
    final p = RoutePath.fit(_rondje(), box)!;
    final part = p.slicePath(p.length * 0.2, p.length * 0.6).computeMetrics().first.length;
    expect(part, closeTo(p.length * 0.4, p.length * 0.02));
    expect(p.slicePath(10, 5).computeMetrics().isEmpty, isTrue);
    expect(routeAnimFps, 30);
  });

  test('onderdelen verslepen blijft binnen beeld en bewaart netjes', () {
    const base = Rect.fromLTWH(90, 1390, 900, 180);
    var l = RouteAnimLayout.none;
    expect(l.isDefault, isTrue);
    l = l.moved(RouteAnimPart.stats, const Offset(-500, 900), base);
    expect(l.stats.dx, -90);
    expect(l.stats.dy, 1920 - base.bottom);
    expect(l.label, Offset.zero);
    final back = RouteAnimLayout.fromJson(l.toJson());
    expect(back, l);
    expect(RouteAnimLayout.fromJson('kapot').isDefault, isTrue);
    expect(RouteAnimLayout.fromJson(null).isDefault, isTrue);
  });
}
