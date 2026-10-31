import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/bingo.dart';
import 'package:runwise/domain/forecast_confidence.dart';

Activity _run(DateTime t, {double km = 5, int min = 30, double? wind, double? feels, String? id, String? route}) => Activity(
      id: id,
      startedAt: t,
      distanceMeters: km * 1000,
      movingTimeSeconds: min * 60,
      source: 'runwise',
      windSpeedKmh: wind,
      feelsLikeCelsius: feels,
      routeId: route,
    );

void main() {
  group('Hoe zeker is dit moment', () {
    final start = DateTime(2026, 11, 2, 16);
    List<EnsembleHour> hours(double Function(int m) rain) => [
          for (var h = 14; h <= 19; h++)
            EnsembleHour(DateTime(2026, 11, 2, h), [for (var m = 0; m < 20; m++) rain(m)], [for (var m = 0; m < 20; m++) 8.0 + m * 0.1]),
        ];

    test('alle varianten droog = zeker droog', () {
      final c = confidenceFor(hours((_) => 0), start, 45, now: DateTime(2026, 11, 2, 10))!;
      expect(c.level, ConfidenceLevel.sure);
      expect(c.mostlyDry, isTrue);
      expect(c.recheckAt, isNull);
      expect(c.members, 20);
    });

    test('de helft nat = twijfel, met een moment om nog te kijken', () {
      final c = confidenceFor(hours((m) => m.isEven ? 0.6 : 0), start, 45, now: DateTime(2026, 11, 2, 10))!;
      expect(c.level, ConfidenceLevel.shaky);
      expect(c.wetShare, closeTo(0.5, 0.01));
      expect(c.recheckAt, DateTime(2026, 11, 2, 14, 30));
    });

    test('vlak voor de start geen "kijk later nog even"', () {
      final c = confidenceFor(hours((m) => m.isEven ? 0.6 : 0), start, 45, now: DateTime(2026, 11, 2, 15))!;
      expect(c.recheckAt, isNull);
    });

    test('ensemble-antwoord van Open-Meteo lezen', () {
      final h = parseEnsemble({
        'hourly': {
          'time': ['2026-11-02T16:00', '2026-11-02T17:00'],
          'precipitation': [0.0, 0.1],
          'precipitation_member01': [0.3, null],
          'temperature_2m': [8.0, 7.5],
          'temperature_2m_member01': [8.4, 7.9],
        },
      });
      expect(h.length, 2);
      expect(h.first.precip, [0.0, 0.3]);
      expect(h.last.precip, [0.1]);
      expect(h.first.temp, [8.0, 8.4]);
    });
  });

  group('Klopte de voorspelling', () {
    final s = ForecastSnapshot(time: DateTime(2026, 11, 1, 17), lat: 52, lon: 5, temp: 10, rainChance: 10, rainMm: 0, wind: 15);

    test('droog voorspeld, droog geweest, temperatuur dichtbij', () {
      expect(forecastWasRight(s, actualTemp: 11.5, actualMm: 0), isTrue);
      expect(forecastWasRight(s, actualTemp: 14, actualMm: 0), isFalse);
      expect(forecastWasRight(s, actualTemp: 10, actualMm: 1.2), isFalse);
    });

    test('score over 30 dagen, ongecontroleerde tellen niet mee', () {
      final now = DateTime(2026, 11, 30);
      final all = [
        s.withResult(true),
        ForecastSnapshot(time: DateTime(2026, 11, 3, 8), lat: 52, lon: 5, temp: 5, rainChance: 80, rainMm: 2, wind: 10).withResult(false),
        ForecastSnapshot(time: DateTime(2026, 11, 4, 8), lat: 52, lon: 5, temp: 5, rainChance: 0, rainMm: 0, wind: 10),
        ForecastSnapshot(time: DateTime(2026, 9, 4, 8), lat: 52, lon: 5, temp: 5, rainChance: 0, rainMm: 0, wind: 10).withResult(true),
      ];
      expect(forecastScore(all, now: now), (1, 2));
      final back = ForecastSnapshot.fromJson(all.first.toJson())!;
      expect(back.ok, isTrue);
      expect(back.time, all.first.time);
    });
  });

  group('Loop-bingo', () {
    test('elke maand acht opdrachten, vast per maand, midden gratis', () {
      final a = bingoTasksFor(DateTime(2026, 11));
      final b = bingoTasksFor(DateTime(2026, 11));
      expect(a.length, 8);
      expect(a.map((t) => t.id), b.map((t) => t.id));
      expect(a.map((t) => t.id).toSet().length, 8);
      expect(a.any((t) => t.id == 'warm'), isFalse, reason: 'geen 20 graden in november');
      final card = bingoFor(DateTime(2026, 11, 15), const []);
      expect(card.cells[4].free, isTrue);
      expect(card.lines, 0);
      expect(card.doneCount, 0);
    });

    test('runs vullen vakjes, alleen in deze maand', () {
      final runs = [
        for (var d = 2; d <= 4; d++) _run(DateTime(2026, 11, d, 6, 30), km: 11, min: 60, wind: 30, feels: 2),
        _run(DateTime(2026, 10, 31, 21), km: 3), // vorige maand
      ];
      final card = bingoFor(DateTime(2026, 11, 20), runs);
      final done = {for (final c in card.cells) if (c.task != null && c.done) c.task!.id};
      final ids = {for (final c in card.cells) if (c.task != null) c.task!.id};
      for (final id in ['ten', 'long', 'wind', 'cold', 'early', 'week3', 'twoDays']) {
        if (ids.contains(id)) expect(done, contains(id), reason: id);
      }
      if (ids.contains('short')) expect(done, isNot(contains('short')));
      if (ids.contains('evening')) expect(done, isNot(contains('evening')));
    });

    test('drie op een rij is bingo', () {
      const t = BingoTask('x', 'x', 'x');
      final d = DateTime(2026, 11, 2);
      final card = BingoCard(DateTime(2026, 11), [
        BingoCell(t, doneAt: d), const BingoCell(t), const BingoCell(t),
        const BingoCell(t), const BingoCell(null), const BingoCell(t),
        const BingoCell(t), const BingoCell(t), BingoCell(t, doneAt: d),
      ]);
      expect(card.lines, 1); // diagonaal via het gratis midden
      expect(card.winning, {0, 4, 8});
    });
  });
}
