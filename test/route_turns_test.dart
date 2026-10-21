import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/fit_course.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/gpx_parser.dart';
import 'package:runwise/domain/route_geometry.dart';
import 'package:runwise/domain/route_turns.dart';

/// Route uit stukken (kompasrichting, meters), een punt per 10 m.
List<LatLng> path(List<(double, double)> moves, {double step = 10}) {
  final pts = [const LatLng(52.0, 5.6)];
  for (final (bearing, meters) in moves) {
    final n = (meters / step).round();
    for (var k = 0; k < n; k++) {
      final p = pts.last;
      final dn = step * math.cos(bearing * math.pi / 180);
      final de = step * math.sin(bearing * math.pi / 180);
      pts.add(LatLng(p.lat + dn / 111320, p.lon + de / (111320 * math.cos(p.lat * math.pi / 180))));
    }
  }
  return pts;
}

List<RouteTurn> turnsOf(List<(double, double)> moves) => detectTurns(RouteTrack(path(moves)));

void main() {
  group('afslagen herkennen', () {
    test('rechtsaf en linksaf', () {
      final r = turnsOf([(0, 500), (90, 500)]);
      expect(r, hasLength(1));
      expect(r.single.kind, TurnKind.right);
      expect(r.single.meters, closeTo(500, 20));
      final l = turnsOf([(0, 500), (270, 500)]);
      expect(l.single.kind, TurnKind.left);
    });

    test('rechtdoor en een flauwe bocht in de weg geven geen afslag', () {
      expect(turnsOf([(0, 1000)]), isEmpty);
      final pts = path([(0, 300)]);
      final o = pts.last;
      for (var d = 2; d <= 90; d += 2) {
        final th = d * math.pi / 180;
        pts.add(LatLng(o.lat + 300 * math.sin(th) / 111320,
            o.lon + (300 - 300 * math.cos(th)) / (111320 * math.cos(o.lat * math.pi / 180))));
      }
      expect(detectTurns(RouteTrack(pts)), isEmpty);
    });

    test('keerpunt, scherpe en flauwe afslag', () {
      expect(turnsOf([(0, 500), (180, 500)]).single.kind, TurnKind.uTurn);
      expect(turnsOf([(0, 400), (135, 400)]).single.kind, TurnKind.sharpRight);
      expect(turnsOf([(0, 500), (45, 500)]).single.kind, TurnKind.slightRight);
    });

    test('even oversteken (links-rechts binnen 20 m) is geen afslag', () {
      expect(turnsOf([(0, 500), (90, 20), (0, 500)]), isEmpty);
    });

    test('vierkant rondje: drie keer rechtsaf', () {
      final t = turnsOf([(0, 300), (90, 300), (180, 300), (270, 300)]);
      expect(t.map((e) => e.kind), everyElement(TurnKind.right));
      expect(t, hasLength(3));
    });

    test('GPS-ruis geeft geen nep-afslagen', () {
      final rnd = math.Random(7);
      double g() => (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 1.5) * 2 * 3; // ~3 m
      final noisy = [
        for (final p in path([(0, 500), (90, 500), (180, 400)], step: 8))
          LatLng(p.lat + g() / 111320, p.lon + g() / 68700)
      ];
      final t = detectTurns(RouteTrack(noisy));
      expect(t, hasLength(2));
      expect(t.map((e) => e.kind), everyElement(TurnKind.right));
    });
  });

  group('aanwijzingen tijdens het lopen', () {
    test('vooraankondiging en nu', () {
      final guide = TurnGuide(turnsOf([(0, 500), (90, 500)]));
      final said = <String>[];
      for (var m = 0.0; m < 1000; m += 5) {
        final c = guide.update(m);
        if (c != null) said.add(c.text);
      }
      expect(said, hasLength(2));
      expect(said.first, startsWith('Over '));
      expect(said.first, endsWith('rechtsaf'));
      expect(said.last, 'Rechtsaf');
      expect(guide.next, isNull);
    });

    test('afslag die je voorbij bent wordt overgeslagen', () {
      final guide = TurnGuide(turnsOf([(0, 300), (90, 300), (180, 300)]));
      expect(guide.update(450), isNull); // Eerste afslag gemist (afgesneden).
      expect(guide.next!.meters, greaterThan(450));
    });

    test('teksten', () {
      const t = RouteTurn(meters: 100, point: LatLng(0, 0), kind: TurnKind.slightLeft, angle: -40);
      expect(turnSpeech(t, inMeters: 118), 'Over 120 meter links aanhouden');
      expect(turnSpeech(t, inMeters: 230), 'Over 250 meter links aanhouden');
      expect(turnSpeech(t), 'Houd links');
      expect(classifyTurn(-170), TurnKind.uTurn);
      expect(headingChange(350, 10), closeTo(20, 1e-9));
      expect(headingChange(10, 350), closeTo(-20, 1e-9));
    });
  });

  group('bestanden voor je horloge', () {
    final pts = path([(0, 600), (90, 400), (180, 600)]);
    final turns = detectTurns(RouteTrack(pts));

    test('FIT-koers: kop, lengte en controlegetal kloppen', () {
      final fit = buildFitCourse('Rondje Barneveld', pts, turns: turns, paceSecondsPerKm: 330, start: DateTime.utc(2026, 10, 21, 8));
      expect(fit[0], 14);
      expect(String.fromCharCodes(fit.sublist(8, 12)), '.FIT');
      final dataSize = fit[4] | fit[5] << 8 | fit[6] << 16 | fit[7] << 24;
      expect(fit.length, 14 + dataSize + 2);
      expect(fitCrc(fit.sublist(0, 14)), 0, reason: 'kop-controlegetal');
      expect(fitCrc(fit), 0, reason: 'controlegetal van het hele bestand');
      // Voor de controle met de officiële Garmin-lezer in de cloudbuild.
      Directory('build').createSync(recursive: true);
      File('build/test_course.fit').writeAsBytesSync(fit);
      File('build/test_course_turns.txt').writeAsStringSync(turns.map((t) => fitCoursePointType(t.kind)).join(','));
    });

    test('GPX met afslagen als waypoints, en nog steeds in te lezen', () {
      final gpx = buildGpx('Rondje', pts, turns: turns);
      expect('<wpt'.allMatches(gpx).length, turns.length);
      expect(gpx, contains('<sym>Right</sym>'));
      final back = parseGpx(gpx);
      expect(back.distanceMeters, closeTo(RouteTrack(pts).length, 5));
    });
  });
}
