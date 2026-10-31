import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/age_grading.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/gps_art.dart';
import 'package:runwise/domain/hindsight.dart';
import 'package:runwise/domain/hrr.dart';
import 'package:runwise/domain/pain_log.dart';
import 'package:runwise/domain/route_drawing.dart';

Activity _run(DateTime t, double km, {String? note, String? shoe, int? secs}) => Activity(
      startedAt: t,
      distanceMeters: km * 1000,
      movingTimeSeconds: secs ?? (km * 330).round(),
      source: 'runwise',
      note: note,
      shoeId: shoe,
    );

void main() {
  group('GPS-kunst', () {
    const c = LatLng(52.15, 5.59);

    test('elke vorm: gesloten, binnen 25 punten, ongeveer de gevraagde lengte', () {
      for (final s in ArtShape.values) {
        final pts = artWaypoints(s, c, 8000);
        expect(pts.length, inInclusiveRange(4, 25), reason: s.name);
        expect(distanceMeters(pts.first, pts.last), lessThan(30), reason: s.name);
        expect(straightLength(pts) * artRoadFactor, closeTo(8000, 400), reason: s.name);
      }
    });

    test('route precies over de vorm = 100%, ver ernaast = 0%', () {
      final shape = artWaypoints(ArtShape.heart, c, 6000);
      expect(artFidelity(shape, shape), 100);
      final far = [for (final p in shape) LatLng(p.lat + 0.05, p.lon)];
      expect(artFidelity(far, shape), 0);
    });
  });

  group('leeftijdsniveau', () {
    test('wereldrecord-tijd op topleeftijd ≈ 100%', () {
      expect(ageGradePercent(sex: Sex.male, age: 27, meters: 5000, seconds: 769), closeTo(100, 0.1));
    });

    test('ouder = zelfde tijd scoort hoger', () {
      final at30 = ageGradePercent(sex: Sex.male, age: 30, meters: 10000, seconds: 50 * 60)!;
      final at55 = ageGradePercent(sex: Sex.male, age: 55, meters: 10000, seconds: 50 * 60)!;
      expect(at55, greaterThan(at30));
      expect(at30, inInclusiveRange(50, 56));
      expect(ageGradeLevel(at30), 'Goede recreant');
    });

    test('factoren lopen af met de leeftijd; vrouwen eigen norm', () {
      expect(ageFactor(Sex.male, 25), 1.0);
      expect(ageFactor(Sex.female, 60), lessThan(ageFactor(Sex.female, 50)));
      expect(ageGradePercent(sex: Sex.female, age: 30, meters: 5000, seconds: 846), closeTo(100, 0.1));
      expect(openStandard(Sex.male, 1500), isNull);
    });
  });

  group('pijntjes', () {
    final now = DateTime(2026, 11, 1, 12);

    test('notitie heen en terug', () {
      final n = 'Lekker ritme, ${painNote(PainSpot.shin, 5)}';
      expect(parsePain(n), [(PainSpot.shin, 5)]);
      expect(parsePain('Pijntje'), isEmpty);
      expect(parsePain(null), isEmpty);
    });

    test('2× scheen na lange runs = patroon met oorzaak', () {
      final runs = [
        for (var i = 1; i <= 10; i++) _run(now.subtract(Duration(days: i * 3)), 6),
        _run(now.subtract(const Duration(days: 2)), 14, note: painNote(PainSpot.shin, 3)),
        _run(now.subtract(const Duration(days: 9)), 15, note: painNote(PainSpot.shin, 4)),
      ];
      final p = painPatterns(runs, now: now).single;
      expect(p.spot, PainSpot.shin);
      expect(p.count, 2);
      expect(p.reasons, contains('na langere runs'));
      expect(p.seeProfessional, isFalse);
    });

    test('één keer erg = meteen advies naar de fysio; één keer licht = niets', () {
      expect(painPatterns([_run(now.subtract(const Duration(days: 1)), 8, note: painNote(PainSpot.achilles, 7))], now: now).single.seeProfessional, isTrue);
      expect(painPatterns([_run(now.subtract(const Duration(days: 1)), 8, note: painNote(PainSpot.knee, 2))], now: now), isEmpty);
    });
  });

  group('hartslagherstel', () {
    HrrResult r(int d, int day) => HrrResult(at: DateTime(2026, 10, day), startBpm: 160, endBpm: 160 - d);

    test('niveau en trend', () {
      expect(hrrLevel(30), 'Goed herstel');
      expect(hrrLevel(8), 'Traag herstel');
      expect(hrrTrend([r(28, 1), r(30, 2)]), isNull);
      expect(hrrTrend([r(28, 1), r(30, 2), r(29, 3), r(15, 4)]), contains('minder snel'));
      expect(HrrResult.fromJson(r(20, 5).toJson())!.drop, 20);
    });
  });

  group('terugblik telt ontweken regen en hitte', () {
    HourWeather h(int hour, {double rain = 0, double t = 22}) =>
        HourWeather(time: DateTime(2026, 7, 1, hour), temperature: t, feelsLike: t, precipitation: rain, windSpeed: 10);

    test('ochtendrun op een hete dag met avondbui', () {
      final day = [for (var i = 0; i < 24; i++) h(i, rain: i == 18 ? 4 : 0, t: i < 9 ? 16 : 29)];
      final r = hindsight(day, DateTime(2026, 7, 1, 7), 45)!;
      expect(r.rainAvoided, greaterThan(2));
      expect(r.heatAvoided, closeTo(13, 0.5));
    });
  });
}
