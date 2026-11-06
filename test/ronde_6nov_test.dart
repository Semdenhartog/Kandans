import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/run_streams.dart';
import 'package:runwise/domain/start_time_scoring.dart';
import 'package:runwise/domain/verdict.dart';

StartTimeScore _score(int s, List<String> reasons, DateTime t) => StartTimeScore(
      start: t,
      score: s,
      weather: HourWeather(time: t, temperature: 10, windSpeed: 10),
      reasons: reasons,
    );

void main() {
  test('typische looptijd = mediaan van recente runs, afgerond op 5 min', () {
    expect(typicalRunMinutes([3000, 2700, 2400]), 45);
    expect(typicalRunMinutes([3000, 2700]), isNull); // te weinig runs
    expect(typicalRunMinutes([300, 400, 500]), isNull); // te korte runs tellen niet
  });

  test('waarom niet nu: noemt alleen wat het beste moment niet heeft', () {
    final t = DateTime(2026, 11, 6, 17);
    final now = _score(50, ['Kans op regen (70%)', 'Wind (25 km/u)'], t);
    final best = _score(80, ['Wind (25 km/u)'], t.add(const Duration(hours: 2)));
    final v = runVerdict(now, best);
    expect(whyNotNow(v), 'Nu: kans op regen (70%)');
    // Bijna even goed: geen reden nodig.
    expect(whyNotNow(runVerdict(_score(78, ['Wind (25 km/u)'], t), best)), isNull);
  });

  test('kaartstukken op tempo en schaal tussen 10e en 90e percentiel', () {
    final s = RunStreams(
      time: [for (var i = 0; i <= 40; i++) i * 30.0],
      distance: [for (var i = 0; i <= 40; i++) i * 100.0],
      positions: [for (var i = 0; i <= 40; i++) LatLng(52 + i * 0.0009, 5.6)],
    );
    final segs = valueSegments(s);
    expect(segs, isNotEmpty);
    expect(segs.first.value, closeTo(300, 1)); // 100 m in 30 s = 5:00 /km
    expect(valueSegments(s, heartRate: true), isEmpty); // geen hartslag
    final scale = relativeScale([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(scale(1), 0);
    expect(scale(10), 1);
  });
}
