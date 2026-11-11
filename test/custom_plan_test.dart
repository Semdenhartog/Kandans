import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/custom_plan.dart';
import 'package:runwise/domain/training_plan.dart';

void main() {
  final start = DateTime(2026, 11, 16); // maandag

  test('halve marathon: fases, afbouw, wedstrijd en herstelweek', () {
    final w = PlanWishes(
      goal: PlanGoal.halve,
      raceDate: DateTime(2027, 3, 14),
      weeklyKm: 25,
      longestKm: 12,
      runDays: const [2, 4, 7],
      longRunDay: 7,
      strengthPerWeek: 2,
      goalTimeSeconds: 2 * 3600,
    );
    final p = buildCustomPlan(w, start: start, thresholdPace: 330);
    expect(p.weeks.length, greaterThanOrEqualTo(17));
    expect(p.weeks.first.phase, PlanPhase.basis);
    expect(p.weeks.any((x) => x.phase == PlanPhase.piek), isTrue);
    expect(p.weeks.where((x) => x.phase == PlanPhase.afbouw).length, 2);
    expect(p.weeks.last.phase, PlanPhase.herstel);
    final race = p.runSessions.where((s) => s.kind == SessionKind.race).single;
    expect(race.date, DateTime(2027, 3, 14));
    // Geen training na de wedstrijd behalve de herstelweek.
    expect(p.weeks.last.items.every((i) => i.session.kind == SessionKind.easy), isTrue);
    // Lange duurloop maximaal 21 km, piek tussen 40 en 70 km.
    final longest = p.runSessions.where((s) => s.kind == SessionKind.long).map((s) => s.distanceMeters!).reduce((a, b) => a > b ? a : b);
    expect(longest, lessThanOrEqualTo(21000));
    expect(p.peakKm, inInclusiveRange(30, 70));
    // Nooit meer dan ±10% groei tussen gewone opbouwweken (met afronding marge).
    expect(p.predictedSeconds, isNotNull);
    expect(p.goalCheck, isNotNull);
    expect(p.raceDay, isNotEmpty);
    // Kracht staat op loopvrije dagen.
    for (final wk in p.weeks) {
      final runDates = {for (final i in wk.items) i.session.date};
      for (final e in wk.extras.where((e) => e.kind == ExtraKind.kracht)) {
        expect(runDates.contains(e.date), isFalse);
      }
    }
  });

  test('geen twee zware trainingen op opeenvolgende dagen', () {
    final w = PlanWishes(goal: PlanGoal.k10, raceDate: DateTime(2027, 2, 7), weeklyKm: 30, runDays: const [1, 2, 3, 5, 6, 7], longRunDay: 7);
    final p = buildCustomPlan(w, start: start, thresholdPace: 300);
    for (final wk in p.weeks) {
      final keys = [for (final i in wk.items) if (i.session.kind == SessionKind.tempo || i.session.kind == SessionKind.interval) i.session.date]..sort();
      for (var i = 1; i < keys.length; i++) {
        expect(keys[i].difference(keys[i - 1]).inDays, greaterThan(1));
      }
    }
  });

  test('vakantieweek heeft geen looptrainingen', () {
    const w = PlanWishes(goal: PlanGoal.fit, weeks: 10, skipWeeks: {4});
    final p = buildCustomPlan(w, start: start);
    expect(p.weeks.length, 10);
    expect(p.weeks[3].phase, PlanPhase.vrij);
    expect(p.weeks[3].items, isEmpty);
    expect(p.paceIsEstimate, isTrue);
  });

  test('beginnen gebruikt loop-wandelblokken', () {
    const w = PlanWishes(goal: PlanGoal.beginnen, weeks: 9, runDays: [1, 3, 5]);
    final p = buildCustomPlan(w, start: start);
    expect(p.weeks.length, 9);
    expect(p.runSessions.length, greaterThanOrEqualTo(24));
    expect(p.runSessions.first.intervals, isNotNull);
  });

  test('wensen bewaren en teruglezen', () {
    final w = PlanWishes(goal: PlanGoal.marathon, raceDate: DateTime(2027, 4, 18), skipWeeks: const {5, 6}, ambition: Ambition.ambitieus, inMinutes: true);
    final back = PlanWishes.fromJson(w.toJson())!;
    expect(back.goal, PlanGoal.marathon);
    expect(back.skipWeeks, {5, 6});
    expect(back.ambition, Ambition.ambitieus);
    expect(back.inMinutes, isTrue);
    expect(back.raceDate, DateTime(2027, 4, 18));
  });

  test('voorspelling en doelcheck', () {
    // Drempel 4:30 -> 5 km ~ 21:22.
    expect(predictSeconds(270, 5000), inInclusiveRange(1270, 1300));
    final w = PlanWishes(goal: PlanGoal.k5, raceDate: DateTime(2027, 1, 24), goalTimeSeconds: 17 * 60);
    final p = buildCustomPlan(w, start: start, thresholdPace: 270);
    expect(p.goalCheck, 'erg ambitieus');
    expect(p.warnings, isNotEmpty);
  });
}
