import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/badges.dart';
import 'package:runwise/domain/run_pause.dart';
import 'package:runwise/domain/weekly_load.dart';

Activity _run(DateTime t) => Activity(startedAt: t, distanceMeters: 5000, movingTimeSeconds: 1800);

void main() {
  // Maandag 5 okt 2026 t/m zondag 1 nov 2026: vier weken.
  final w1 = DateTime(2026, 10, 5);
  final w2 = DateTime(2026, 10, 12);
  final w3 = DateTime(2026, 10, 19);
  final w4 = DateTime(2026, 10, 26);

  test('pauze: actief op de juiste dagen, ook zonder einddatum', () {
    final p = PausePeriod(reason: PauseReason.injury, start: DateTime(2026, 10, 12, 9), end: DateTime(2026, 10, 18));
    expect(p.activeOn(DateTime(2026, 10, 11, 23)), isFalse);
    expect(p.activeOn(DateTime(2026, 10, 12, 0, 5)), isTrue);
    expect(p.activeOn(DateTime(2026, 10, 18, 22)), isTrue);
    expect(p.activeOn(DateTime(2026, 10, 19, 6)), isFalse);
    final open = PausePeriod(reason: PauseReason.holiday, start: DateTime(2026, 10, 12));
    expect(open.activeOn(DateTime(2027, 1, 1)), isTrue);
    expect(currentPause([p, open], DateTime(2026, 10, 30))?.reason, PauseReason.holiday);
  });

  test('pauzeweek telt pas bij minstens 4 dagen', () {
    final kort = PausePeriod(reason: PauseReason.sick, start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 14)); // 3 dagen
    final lang = PausePeriod(reason: PauseReason.sick, start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 15)); // 4 dagen
    expect(kort.coversWeek(w2), isFalse);
    expect(lang.coversWeek(w2), isTrue);
    expect(pausedWeeks([lang], DateTime(2026, 10, 30)), {w2});
  });

  test('reeks breekt niet door een pauzeweek, maar die week telt niet mee', () {
    final runs = [_run(w1.add(const Duration(days: 1))), _run(w3.add(const Duration(days: 2))), _run(w4.add(const Duration(days: 1)))];
    final now = DateTime(2026, 10, 30, 12);
    expect(weekStreak(runs, now), 2); // w4 + w3, w2 leeg breekt
    final paused = pausedWeeks([PausePeriod(reason: PauseReason.injury, start: w2, end: w2.add(const Duration(days: 6)))], now);
    expect(weekStreak(runs, now, paused: paused), 3); // w4 + w3 + (pauze) + w1
  });

  test('badge "4 weken op rij" springt over pauzeweken heen', () {
    final weeks = [for (var i = 0; i < 6; i++) DateTime(2026, 9, 7 + 7 * i)]; // 7 sep .. 12 okt
    final runs = [for (final w in weeks) if (w != weeks[2]) _run(w.add(const Duration(days: 2)))];
    final now = DateTime(2026, 10, 20);
    bool has4(Set<DateTime> paused) => computeBadges(runs, now: now, pausedWeeks: paused).firstWhere((b) => b.id == 'streak4').earned;
    expect(has4(const {}), isFalse); // 2 + 3 weken, met een gat
    expect(has4({weeks[2]}), isTrue); // gat is een pauzeweek: 5 weken lopen
  });

  test('opslaan en teruglezen', () {
    final p = PausePeriod(reason: PauseReason.holiday, start: DateTime(2026, 10, 30, 15), end: DateTime(2026, 11, 5));
    final back = PausePeriod.fromJson(p.toJson())!;
    expect(back.reason, PauseReason.holiday);
    expect(back.start, DateTime(2026, 10, 30));
    expect(back.end, DateTime(2026, 11, 5));
    expect(PausePeriod.fromJson({'start': 'onzin'}), isNull);
    expect(PauseReason.of('bestaat-niet'), PauseReason.rest);
  });
}
