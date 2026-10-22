import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/route_heads_up.dart';
import 'package:runwise/domain/run_coach.dart';
import 'package:runwise/domain/run_recorder.dart';

void main() {
  final t0 = DateTime(2026, 10, 22, 8);

  /// Loopt [km] kilometer met per kilometer een eigen snelheid (m/s) en verzamelt de stem.
  List<String> runWith(CueScheduler cues, List<double> speeds, {double? routeMeters}) {
    final r = RunRecording()..start(t0);
    final said = <String>[];
    var d = 0.0;
    var s = 0;
    for (var k = 0; k < speeds.length; k++) {
      final v = speeds[k];
      // Per kilometer (gemeten zoals de app meet) een eigen snelheid.
      while (r.distance < (k + 1) * 1000 + 2) {
        d += v;
        s++;
        r.add(GpsFix(LatLng(52.0, 5.0 + d / 68540), t0.add(Duration(seconds: s)), accuracy: 5));
        final rem = routeMeters == null ? null : routeMeters - r.distance;
        if (cues.update(r, remainingMeters: rem) case final c?) said.add(c);
      }
    }
    return said;
  }

  group('stemcoach', () {
    test('vergelijkt met het vorige stuk', () {
      final said = runWith(CueScheduler(const CueSettings()), [3.0, 3.3, 3.3]);
      expect(said.length, 3);
      expect(said[0], isNot(contains('vorige')));
      expect(said[1], contains('seconden sneller dan het vorige stuk.'));
      expect(said[2], contains('Even snel als het vorige stuk.'));
    });

    test('verwachte eindtijd bij een route', () {
      final said = runWith(CueScheduler(const CueSettings()), [3.0, 3.0], routeMeters: 5000);
      // Na 1 km in ~5:33 per km: klaar na ongeveer 27 minuten 47.
      expect(said.first, contains('Met dit tempo ben je klaar na 27 minuten'));
    });

    test('korte stem: alleen afstand en tempo', () {
      final said = runWith(CueScheduler(const CueSettings(style: CoachStyle.short)), [3.0]);
      expect(said.single, startsWith('1 kilometer. 5 minuten'));
      expect(said.single, isNot(contains('Gemiddeld')));
      expect(said.single, isNot(contains('Totale tijd')));
    });

    test('motiverende stem moedigt aan', () {
      final said = runWith(CueScheduler(const CueSettings(style: CoachStyle.motivating)), [3.0, 3.0]);
      expect(said[0], endsWith(motivatingLines[0]));
      expect(said[1], endsWith(motivatingLines[1]));
    });

    test('nieuwe instellingen worden bewaard', () {
      const c = CueSettings(style: CoachStyle.short, compare: false, finish: false);
      final back = CueSettings.fromJson(c.toJson());
      expect(back.style, CoachStyle.short);
      expect(back.compare, isFalse);
      expect(back.finish, isFalse);
      expect(CueSettings.fromJson({'e': 'km'}).style, CoachStyle.calm);
    });
  });

  group('recordjacht', () {
    test('seintje, record en langste run', () {
      final h = RecordHunt(bests: {5000: 1500, 1000: 280}, longestBefore: 4000, labels: {5000: '5 km', 1000: '1 km'});
      final said = <String>[];
      // 5:00 per km: 1 km in 300 s (geen record), 5 km in 1500 - iets.
      for (var m = 0.0; m <= 5200; m += 10) {
        final t = m * 0.296; // net iets sneller dan 5:00 per km
        if (h.update(m, t, 296) case final c?) said.add(c);
      }
      expect(said.length, 3);
      expect(said[0], startsWith('Houd dit tempo vast en je loopt een nieuw 5 km-record: rond 24 minuten'));
      expect(said[1], startsWith('Dit is nu je langste run ooit'));
      expect(said[2], startsWith('Nieuw record op de 5 km!'));
      expect(said.any((c) => c.contains('1 km')), isFalse);
    });

    test('geen seintje als het niet gaat lukken', () {
      final h = RecordHunt(bests: {5000: 1200});
      for (var m = 0.0; m <= 5000; m += 10) {
        expect(h.update(m, m * 0.33, 330), isNull);
      }
    });
  });

  test('heen en terug: één minuut vooraf en halverwege', () {
    final t = Turnaround(40 * 60);
    final said = <String>[];
    for (var s = 0; s <= 2400; s++) {
      if (t.update(s.toDouble()) case final c?) said.add(c);
    }
    expect(said, ['Over een minuut ben je halverwege.', 'Halverwege! Draai nu om, dan ben je na 40 minuten weer terug.']);
  });

  test('briefing bij de start', () {
    expect(
      startBriefing(temperature: 11.6, feelsLike: 8.4, windKmh: 18, windFrom: 225, firstHalfHead: 12, secondHalfHead: -10),
      'Het is 12 graden, het voelt als 8. Wind 18 kilometer per uur uit het zuidwesten. '
      'De eerste helft heb je tegenwind, op de terugweg helpt de wind je.',
    );
    expect(startBriefing(temperature: 20, windKmh: 3, rainChance: 70),
        'Het is 20 graden. Er staat bijna geen wind. Kans op regen: 70 procent.');
    expect(windFromWords(0), 'uit het noorden');
  });

  test('bezienswaardigheden onderweg, niet te vaak', () {
    final h = RouteHeadsUp.build(landmarks: [
      (meters: 1000, name: 'Kasteel De Schaffelaar'),
      (meters: 1200, name: 'Te dichtbij'),
      (meters: 2500, name: 'Oude Kerk'),
    ]);
    final said = <String>[];
    for (var m = 0.0; m < 3000; m += 10) {
      if (h.update(m) case final c?) said.add(c);
    }
    expect(said, ['Over 150 meter kom je langs Kasteel De Schaffelaar.', 'Over 150 meter kom je langs Oude Kerk.']);
  });
}
