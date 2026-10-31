import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/commute.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/hydration.dart';
import 'package:runwise/domain/plan_swap.dart';
import 'package:runwise/domain/record_weather.dart';
import 'package:runwise/domain/roster.dart';
import 'package:runwise/domain/run_warnings.dart';
import 'package:runwise/domain/training_plan.dart';

PlanSession _s(DateTime d, SessionKind k) => PlanSession(date: d, kind: k, title: k.label, description: '');

void main() {
  final now = DateTime(2026, 11, 2, 7); // maandag

  group('weerslim schema', () {
    // ma rustig, wo lang (regen), do rustig, za tempo
    final plan = [
      _s(DateTime(2026, 11, 2), SessionKind.easy),
      _s(DateTime(2026, 11, 4), SessionKind.long),
      _s(DateTime(2026, 11, 5), SessionKind.easy),
      _s(DateTime(2026, 11, 7), SessionKind.tempo),
    ];

    test('lange duurloop gaat van natte woensdag naar droge dinsdag', () {
      int score(DateTime d, SessionKind k) => d.day == 4 ? 40 : (d.day == 3 ? 85 : 60);
      final s = weatherSwaps(plan, score, now: now);
      expect(s.length, 1);
      expect(s.single.session.kind, SessionKind.long);
      expect(s.single.toDay, DateTime(2026, 11, 3));
      expect(s.single.gain, 45);
      final after = applySwap(plan, s.single);
      expect(after.firstWhere((x) => x.kind == SessionKind.long).date, DateTime(2026, 11, 3));
    });

    test('nooit naast een andere zware training en nooit naar het verleden', () {
      // Vrijdag is beter voor de lange duurloop? Nee: zaterdag staat tempo (vrijdag ligt ernaast).
      int score(DateTime d, SessionKind k) => d.day == 6 ? 95 : (d.day == 1 ? 99 : 50);
      final s = weatherSwaps(plan, score, now: now);
      expect(s.any((x) => x.toDay.day == 6 && x.session.kind == SessionKind.long), isFalse);
      expect(s.any((x) => x.toDay.isBefore(DateTime(2026, 11, 2))), isFalse);
    });

    test('rustige dag die er staat schuift mee terug', () {
      int score(DateTime d, SessionKind k) => d.day == 5 ? 90 : 50;
      final s = weatherSwaps([plan[1], plan[2]], score, now: now).single;
      expect(s.displaced?.kind, SessionKind.easy);
      final after = applySwap([plan[1], plan[2]], s);
      expect(after.firstWhere((x) => x.kind == SessionKind.easy).date, DateTime(2026, 11, 4));
    });

    test('klein verschil = geen voorstel', () {
      expect(weatherSwaps(plan, (d, k) => d.day == 3 ? 55 : 50, now: now), isEmpty);
    });
  });

  group('vocht', () {
    test('warmer en sneller = meer zweet', () {
      final cool = sweatRateLph(feelsLike: 8, speedKmh: 10);
      final warm = sweatRateLph(feelsLike: 26, humidity: 80, speedKmh: 12);
      expect(warm, greaterThan(cool * 2));
      expect(cool, inInclusiveRange(0.2, 0.6));
    });

    test('advies na een uur bij 24 °C', () {
      final h = hydrationAfter(minutes: 60, meters: 10000, feelsLike: 24, humidity: 70)!;
      expect(h.lossLiters, inInclusiveRange(0.7, 1.4));
      expect(h.drinkLiters, closeTo(h.lossLiters * 1.25, 0.001));
      expect(h.text, contains('L'));
      expect(hydrationAfter(minutes: 10, meters: 1500, feelsLike: 20), isNull);
    });

    test('drinken mee alleen bij lang en warm', () {
      expect(carryMl(minutes: 45, feelsLike: 25), isNull);
      expect(carryMl(minutes: 90, feelsLike: 10), isNull);
      expect(carryMl(minutes: 90, feelsLike: 24)! % 50, 0);
    });
  });

  group('recordweer', () {
    HourWeather w({double t = 8, double wind = 8, double rain = 0, double prob = 5}) =>
        HourWeather(time: now, temperature: t, feelsLike: t, windSpeed: wind, precipitation: rain, precipitationProbability: prob);

    test('koel, windstil en droog', () {
      expect(isRecordWeather(w()), isTrue);
      expect(isRecordWeather(w(t: 18)), isFalse);
      expect(isRecordWeather(w(wind: 25)), isFalse);
      expect(isRecordWeather(w(prob: 60)), isFalse);
    });

    test('5 km eerst, anders 10 km', () {
      expect(recordTarget({10000: 3000, 5000: 1400})!.label, '5 km');
      expect(recordTarget({10000: 3000})!.label, '10 km');
      expect(recordTarget({}), isNull);
    });
  });

  group('rennend naar je werk', () {
    final home = const LatLng(52.1500, 5.5900);
    final work = const LatLng(52.1500, 5.6900); // ± 6,8 km hemelsbreed
    final shifts = [
      BusyBlock(DateTime(2026, 11, 3, 8), DateTime(2026, 11, 3, 16)),
      BusyBlock(DateTime(2026, 11, 4, 22), DateTime(2026, 11, 5, 7)), // nacht
    ];
    Forecast fc({double rain = 0}) => Forecast(latitude: 52.15, longitude: 5.6, hours: [
          for (var h = 0; h < 96; h++)
            HourWeather(
              time: DateTime(2026, 11, 2).add(Duration(hours: h)),
              temperature: 9,
              feelsLike: 9,
              windSpeed: 15,
              windDirection: 270, // westenwind: waait naar het oosten
              precipitation: rain,
              precipitationProbability: rain > 0 ? 80 : 5,
            ),
        ]);

    test('afstand en ritten heen en terug; na nachtdienst niet naar huis', () {
      final c = CommuteSettings(home: home, work: work, maxKm: 12);
      expect(c.km, inInclusiveRange(8, 10));
      final runs = commuteRuns(c, shifts, fc(), paceSecPerKm: 360, now: now);
      expect(runs.where((r) => r.toWork).length, 2);
      expect(runs.where((r) => !r.toWork).length, 1); // alleen na de dagdienst
      final first = runs.first;
      expect(first.good, isTrue);
      expect(first.start.isBefore(DateTime(2026, 11, 3, 8)), isTrue);
      expect(first.text, contains('wind mee')); // oostwaarts met westenwind
    });

    test('regen = geen fijne rit; te ver = niets', () {
      final c = CommuteSettings(home: home, work: work, maxKm: 12);
      expect(commuteRuns(c, shifts, fc(rain: 1), now: now).every((r) => !r.good), isTrue);
      expect(commuteRuns(c.copyWith(maxKm: 5), shifts, fc(), now: now), isEmpty);
      expect(CommuteSettings.fromJson(c.toJson()).km, closeTo(c.km, 0.01));
    });
  });

  group('hond', () {
    final t0 = DateTime.utc(2026, 7, 1, 12);
    Forecast fc(double temp) => Forecast(latitude: 52, longitude: 5, hours: [
          for (var h = -2; h < 6; h++)
            HourWeather(time: t0.add(Duration(hours: h)), temperature: temp, feelsLike: temp, windSpeed: 8, weatherCode: 0, uvIndex: 7),
        ]);

    test('heet asfalt bij zon en 24 °C', () {
      final list = runWarnings(fc(24), t0, 45, dog: true);
      expect(list.any((w) => w.kind == 'dog' && w.level == WarningLevel.danger), isTrue);
    });

    test('zonder hond geen hondenwaarschuwing', () {
      expect(runWarnings(fc(24), t0, 45).any((w) => w.kind == 'dog'), isFalse);
    });

    test('drinken mee bij lange warme run', () {
      expect(runWarnings(fc(22), t0, 90).any((w) => w.kind == 'water'), isTrue);
    });
  });
}
