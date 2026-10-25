import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/challenges.dart';

Activity _run(DateTime t, {double km = 5, int sec = 1800, double? climb}) =>
    Activity(startedAt: t, distanceMeters: km * 1000, movingTimeSeconds: sec, elevationGainMeters: climb);

Challenge _c(ChallengeKind kind, double target, DateTime start, DateTime end, {double dailyMin = 1}) =>
    Challenge(key: 'k', title: 't', description: 'd', kind: kind, target: target, start: start, end: end, dailyMinKm: dailyMin);

void main() {
  final nov = DateTime(2026, 11), dec = DateTime(2026, 12);

  test('kilometers in de maand; runs erbuiten tellen niet', () {
    final c = _c(ChallengeKind.distance, 20, nov, dec);
    final p = challengeProgress(c, [
      _run(DateTime(2026, 10, 31, 20), km: 10),
      _run(DateTime(2026, 11, 3), km: 8),
      _run(DateTime(2026, 11, 10), km: 7),
      _run(DateTime(2026, 11, 20), km: 6),
    ]);
    expect(p.value, closeTo(21, 1e-9));
    expect(p.completedAt, DateTime(2026, 11, 20));
    expect(remainingText(p), 'Gehaald!');
    final half = challengeProgress(c, [_run(DateTime(2026, 11, 3), km: 12.5)]);
    expect(remainingText(half), 'nog 7,5 km');
    expect(half.fraction, closeTo(0.625, 1e-9));
  });

  test('hoogtemeters, uren, runs en één lange run', () {
    final runs = [
      _run(DateTime(2026, 11, 2), km: 21.2, sec: 7200, climb: 300),
      _run(DateTime(2026, 11, 5), km: 5, sec: 1800, climb: 50),
    ];
    expect(challengeProgress(_c(ChallengeKind.elevation, 1000, nov, dec), runs).value, 350);
    expect(challengeProgress(_c(ChallengeKind.hours, 10, nov, dec), runs).value, closeTo(2.5, 1e-9));
    expect(challengeProgress(_c(ChallengeKind.runs, 2, nov, dec), runs).completedAt, DateTime(2026, 11, 5));
    final long = challengeProgress(_c(ChallengeKind.longRun, 21.1, nov, dec), runs);
    expect(long.completedAt, DateTime(2026, 11, 2));
  });

  test('elke dag: gemiste dag stopt de telling', () {
    final c = _c(ChallengeKind.everyDay, 5, DateTime(2026, 12, 1), DateTime(2026, 12, 6), dailyMin: 1);
    final all = [for (var d = 1; d <= 5; d++) _run(DateTime(2026, 12, d, 7), km: d == 3 ? 0.6 : 2)];
    final p = challengeProgress(c, all, now: DateTime(2026, 12, 5, 12));
    expect(p.value, 2); // dag 3 maar 0,6 km
    expect(p.completed, isFalse);
    expect(p.stillPossible(DateTime(2026, 12, 5, 12)), isFalse);
    // Twee runs op één dag tellen samen.
    final fixed = [...all, _run(DateTime(2026, 12, 3, 19), km: 0.5)];
    final q = challengeProgress(c, fixed, now: DateTime(2026, 12, 5, 12));
    expect(q.completedAt, DateTime(2026, 12, 5, 7));
    expect(q.todayDone, isTrue);
    expect(c.goal, 5);
  });

  test('elke week 3 runs, 2 weken', () {
    final start = DateTime(2026, 11, 2); // maandag
    final c = _c(ChallengeKind.weekly, 3, start, DateTime(2026, 11, 16));
    final runs = [
      for (final d in [2, 4, 6]) _run(DateTime(2026, 11, d)),
      for (final d in [9, 12]) _run(DateTime(2026, 11, d)),
    ];
    expect(challengeProgress(c, runs).value, 1);
    final done = challengeProgress(c, [...runs, _run(DateTime(2026, 11, 15))]);
    expect(done.completedAt, DateTime(2026, 11, 15));
    expect(c.goal, 2);
  });

  test('aanbod: maand, seizoen en vaste sleutels', () {
    final list = availableChallenges(DateTime(2026, 11, 14), suggestedMonthKm: 90);
    final keys = list.map((c) => c.key).toList();
    expect(keys, contains('km125-2026-11')); // 90 × 1,15 = 103,5 → 125
    expect(keys, contains('advent-2026'));
    expect(list.firstWhere((c) => c.key == 'advent-2026').start, DateTime(2026, 12, 1));
    expect(keys.toSet().length, keys.length);
    expect(availableChallenges(DateTime(2026, 7, 1)).any((c) => c.key == 'summer-2026'), isTrue);
    expect(availableChallenges(DateTime(2026, 3, 1)).any((c) => c.key.startsWith('advent')), isFalse);
    final back = Challenge.fromJson(list.first.toJson())!;
    expect(back.key, list.first.key);
    expect(back.kind, list.first.kind);
    expect(back.end, list.first.end);
  });
}
