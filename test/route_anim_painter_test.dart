import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/route_anim.dart';
import 'package:runwise/features/activities/route_anim_painter.dart';

RouteAnimData _data({ui.Image? bg, RouteAnimLayout layout = RouteAnimLayout.none}) {
  final track = [for (var i = 0; i <= 120; i++) LatLng(52.0 + 0.004 * (i / 120), 5.0 + 0.006 * (i % 40) / 40)];
  return RouteAnimData(
    path: RoutePath.fit(track, RouteAnimPainter.routeBox)!,
    label: 'Rondje test',
    meters: 8200,
    seconds: 2878,
    pathMeters: 8200,
    background: bg,
    layout: layout,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('elke stijl tekent op elk moment zonder fouten', () {
    final d = _data();
    for (final s in RouteAnimStyle.values) {
      for (final t in [0.0, 0.2, s.seconds / 2, s.seconds - 0.1]) {
        final rec = ui.PictureRecorder();
        RouteAnimPainter(style: s, data: d, t: t).paint(Canvas(rec), const Size(360, 640));
        rec.endRecording().dispose();
      }
    }
  });

  test('tekenen met foto, verplaatste tekst en hulplijn', () async {
    final rec0 = ui.PictureRecorder();
    Canvas(rec0).drawRect(const Rect.fromLTWH(0, 0, 40, 30), Paint()..color = Colors.green);
    final pic = rec0.endRecording();
    final img = await pic.toImage(40, 30);
    final d = _data(bg: img, layout: const RouteAnimLayout(label: Offset(0, 300), stats: Offset(-40, -200), brand: Offset(100, 0))).copyWith(photoZoom: 2, photoPan: const Offset(0.5, 0));
    final rec = ui.PictureRecorder();
    RouteAnimPainter(style: RouteAnimStyle.draw, data: d, t: 3, highlight: RouteAnimPart.label).paint(Canvas(rec), const Size(360, 640));
    rec.endRecording().dispose();
    pic.dispose();
    img.dispose();
  });
}
