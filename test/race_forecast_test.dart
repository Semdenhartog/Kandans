import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/performance_model.dart';
import 'package:runwise/domain/race_forecast.dart';

const _profile = PerformanceInsights(sampleSize: 10, optimalMin: 6, optimalMax: 14);

final _now = DateTime(2026, 11, 17, 12);

Activity _run(int daysAgo, double m, int seconds) => Activity(
      startedAt: _now.subtract(Duration(days: daysAgo)),
      distanceMeters: m,
      movingTimeSeconds: seconds,
    );

RaceEvent _race(double m, int goal) => RaceEvent(
      name: 'Test',
      raceDate: _now.add(const Duration(days: 60)),
      distanceMeters: m,
      goalTimeSeconds: goal,
    );

void main() {
  test('zonder recente runs geldt de doeltijd', () {
    final a = adviseRace(race: _race(10000, 3000), activities: const [], profile: _profile, now: _now);
    expect(a.baseFinishSeconds, 3000);
    expect(a.basedOn, contains('doeltijd'));
  });

  test('te oude of te korte runs tellen niet mee', () {
    final a = adviseRace(
      race: _race(10000, 3000),
      activities: [_run(200, 10000, 2800), _run(5, 2000, 500)],
      profile: _profile,
      now: _now,
    );
    expect(a.baseFinishSeconds, 3000);
  });

  test('dezelfde afstand: tijd van de run, met Riegel bij een andere afstand', () {
    final same = adviseRace(race: _race(10000, 3300), activities: [_run(10, 10000, 3000)], profile: _profile, now: _now);
    expect(same.baseFinishSeconds, 3000);
    final fromFive = adviseRace(race: _race(10000, 3300), activities: [_run(10, 5000, 1500)], profile: _profile, now: _now);
    expect(fromFive.baseFinishSeconds, closeTo(3171, 3));
    expect(fromFive.basedOn, contains('5,0 km'));
  });

  test('zonder weersverwachting geen weerinvloed en een wachttekst voor kleding', () {
    final a = adviseRace(race: _race(10000, 3000), activities: const [], profile: _profile, now: _now);
    expect(a.weather, isNull);
    expect(a.temperatureImpactSeconds, 0);
    expect(a.windImpactSeconds, 0);
    expect(a.predictedFinishSeconds, a.baseFinishSeconds);
    expect(a.clothing, contains('weersverwachting'));
  });

  test('doeltempo staat in het advies en drinkadvies hangt van de afstand af', () {
    final tien = adviseRace(race: _race(10000, 3000), activities: const [], profile: _profile, now: _now);
    expect(tien.pacing, contains('5:00'));
    final marathon = adviseRace(race: _race(42195, 14400), activities: const [], profile: _profile, now: _now);
    expect(marathon.hydration, isNot(tien.hydration));
    expect(marathon.hydration, contains('gel'));
  });
}
