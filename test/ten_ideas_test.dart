import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/data/services/together_service.dart';
import 'package:runwise/domain/fall_detector.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/lighting.dart';
import 'package:runwise/domain/pain_log.dart';
import 'package:runwise/domain/pain_routine.dart';
import 'package:runwise/domain/run_title.dart';
import 'package:runwise/domain/segments.dart';

Activity _run(DateTime t, {double km = 5, double? wind, double? feels, String source = 'manual', String? poly, String? note, String? ext}) => Activity(
      startedAt: t,
      distanceMeters: km * 1000,
      movingTimeSeconds: (km * 330).round(),
      source: source,
      windSpeedKmh: wind,
      feelsLikeCelsius: feels,
      temperatureCelsius: feels,
      trackPolyline: poly,
      note: note,
      externalId: ext,
    );

/// Een rechte lijn van [len] meter naar het oosten, punt om de 10 m, tempo 5 min/km.
SegTrack _line(String id, DateTime d, {double startLon = 5.6, double len = 3000, double secPerM = 0.3}) {
  final pts = <LatLng>[], t = <double>[], dist = <double>[];
  for (var m = 0.0; m <= len; m += 10) {
    pts.add(LatLng(52.1, startLon + m / (111320 * math.cos(52.1 * math.pi / 180))));
    t.add(m * secPerM);
    dist.add(m);
  }
  return SegTrack(id, d, pts, t, dist);
}

void main() {
  group('Valdetectie', () {
    test('val en stil liggen: melding', () {
      final f = FallDetector();
      var fired = false;
      var t = 0.0;
      // Lopen: telefoon rechtop, kleine schokken.
      for (; t < 5; t += 0.02) {
        fired |= f.add(t, 0.5, 9.8 + math.sin(t * 20) * 1.5, 0.5);
      }
      // Klap.
      fired |= f.add(t, 25, 20, 10);
      t += 0.02;
      // Liggen: telefoon plat (zwaartekracht op z), stil.
      for (; t < 25; t += 0.02) {
        fired |= f.add(t, 0.2, 0.3, 9.8);
      }
      expect(fired, isTrue);
    });

    test('hard neerkomen en doorlopen: geen melding', () {
      final f = FallDetector();
      var fired = false;
      for (var t = 0.0; t < 30; t += 0.02) {
        final peak = (t * 3 % 1) < 0.02 ? 32.0 : 9.8 + math.sin(t * 20) * 4;
        fired |= f.add(t, 0.5, peak, 0.5);
      }
      expect(fired, isFalse);
    });

    test('klap en dan stilstaan bij een stoplicht (rechtop): geen melding', () {
      final f = FallDetector();
      var fired = f.add(0, 5, 31, 3);
      for (var t = 0.02; t < 25; t += 0.02) {
        fired |= f.add(t, 0.3, 9.79, 0.3);
      }
      expect(fired, isFalse);
    });
  });

  test('donker-route: best verlicht eerst', () {
    expect(litShare((lit: 800, unlit: 200, unknown: 0)), closeTo(0.8, 0.001));
    final list = [(lit: 0.4, score: 90), (lit: 0.92, score: 70), (lit: 0.95, score: 80)]..sort(compareForDark);
    expect(list.first.score, 80);
    expect(list.last.lit, 0.4);
  });

  test('krachtroutine op maat', () {
    final now = DateTime(2026, 11, 10);
    final runs = [
      _run(DateTime(2026, 11, 8), note: 'Pijntje: kuit 5'),
      _run(DateTime(2026, 11, 6), note: 'Pijntje: knie 2'),
      _run(DateTime(2026, 10, 1), note: 'Pijntje: rug 7'),
    ];
    final spots = recentPainSpots(painEntries(runs), now: now);
    expect(spots, [PainSpot.calf, PainSpot.knee]);
    final r = routineForPains(spots)!;
    expect(r.exercises.first.name, 'Langzaam kuitheffen op één been');
    expect(r.exercises.map((e) => e.name), contains('Squat met pauze'));
    expect(r.exercises.length, lessThanOrEqualTo(7));
    expect(routineForPains(const []), isNull);
  });

  test('eigen segmenten: herkennen en tijd per stuk', () {
    final runs = [
      for (var i = 0; i < 3; i++) _line('r$i', DateTime(2026, 10, 1 + i), secPerM: 0.3 - i * 0.01),
      _line('ander', DateTime(2026, 10, 9), startLon: 6.2),
    ];
    final segs = findSegments(runs);
    expect(segs, isNotEmpty);
    expect(segs.first.length, inInclusiveRange(600, 2500));
    final t0 = effortTime(runs[0], segs.first)!;
    final t2 = effortTime(runs[2], segs.first)!;
    expect(t2, lessThan(t0), reason: 'de snelste run heeft de kortste tijd');
    expect(effortTime(runs[3], segs.first), isNull);
    final back = Segment.fromJson(segs.first.toJson())!;
    expect(back.id, segs.first.id);
  });

  group('Automatische runtitel', () {
    test('weer en moment', () {
      expect(smartTitle(_run(DateTime(2026, 11, 3, 18), wind: 45)), 'Stormrondje');
      expect(smartTitle(_run(DateTime(2026, 11, 3, 9, 30), feels: 1)), 'Koude ochtendrun');
      expect(smartTitle(_run(DateTime(2026, 11, 3, 14), feels: 12)), 'Middagrun');
      expect(smartTitle(_run(DateTime(2026, 11, 3, 14), feels: 12), routeName: 'Rondje bos'), 'Rondje bos');
      expect(smartTitle(_run(DateTime(2026, 11, 3, 14), wind: 30, feels: 12), routeName: 'Rondje bos'), 'Rondje bos met wind');
      expect(smartTitle(_run(DateTime(2026, 12, 31, 11), feels: 12)), 'Oudejaarsrun');
      expect(smartTitle(_run(DateTime(2026, 11, 3, 9), km: 21.3, feels: 10)), 'Halve marathon');
      expect(smartTitle(_run(DateTime(2026, 11, 3, 9), source: 'runwise')), 'Loopbandrun');
    });
  });

  test('loopmaatje: tempo en momenten uit eigen runs, zonder Strava', () {
    final runs = [
      for (var i = 0; i < 6; i++) _run(DateTime(2026, 11, 2 + i, 7), km: 8),
      _run(DateTime(2026, 11, 1, 19), km: 8, source: 'strava'),
      _run(DateTime(2026, 11, 1, 19), km: 8, ext: 'viastrava-1'),
    ];
    final s = buddyStats(runs);
    expect(s.pace, 330);
    expect(s.times, contains('ochtend'));
    expect(s.times, isNot(contains('avond')));
  });
}
