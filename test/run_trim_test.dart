import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/run_trim.dart';

/// Run van 101 meetpunten: elke 3 s 9 m, met hartslag, hoogte en posities.
Map<String, dynamic> _streams() => {
      't': [for (var i = 0; i <= 100; i++) i * 3.0],
      'd': [for (var i = 0; i <= 100; i++) i * 9.0],
      'hr': [for (var i = 0; i <= 100; i++) i < 50 ? 140.0 : 160.0],
      'alt': [for (var i = 0; i <= 100; i++) 10.0],
      'll': [for (var i = 0; i <= 100; i++) [52.0, 5.0 + i * 9 / 68540]],
      'src': 'runwise',
    };

void main() {
  group('run bijsnijden', () {
    test('begin en eind eraf, alles schuift naar 0', () {
      final r = trimRun(_streams(), 10, 60)!;
      expect(r.distanceMeters, 450);
      expect(r.movingSeconds, 150);
      expect(r.startOffsetSeconds, 30);
      expect((r.streams['t'] as List).first, 0);
      expect((r.streams['d'] as List).last, 450);
      expect((r.streams['hr'] as List).length, 51);
      expect((r.streams['ll'] as List).length, 51);
      expect(r.streams['src'], 'runwise');
      // Gemiddelde van 40× 140 en 11× 160.
      expect(r.averageHeartRate, ((40 * 140 + 11 * 160) / 51).round());
      expect(r.track.length, greaterThan(10));
    });

    test('grenzen buiten het bereik worden bijgesteld', () {
      final r = trimRun(_streams(), -5, 500)!;
      expect(r.distanceMeters, 900);
      expect(r.movingSeconds, 300);
    });

    test('te weinig over of kapotte data geeft null', () {
      expect(trimRun(_streams(), 40, 40), isNull);
      expect(trimRun({'t': [0, 1]}, 0, 1), isNull);
    });

    test('dichtstbijzijnde meetpunt bij een afstand', () {
      final d = [for (var i = 0; i <= 100; i++) i * 9.0];
      expect(indexAtDistance(d, 0), 0);
      expect(indexAtDistance(d, 452), 50);
      expect(indexAtDistance(d, 5000), 100);
    });
  });
}
