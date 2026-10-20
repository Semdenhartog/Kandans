import 'readiness.dart';
import 'training_plan.dart';

enum PlanFix {
  /// Vorige week herhalen en de rest een week opschuiven (alleen zonder vaste wedstrijddatum).
  repeatWeek,

  /// De trainingen die deze week nog komen lichter maken.
  lighterWeek,
}

/// Uitkomst van de check: hoe je schema loopt (zoals Runna's Mileage Insights).
class PlanCheck {
  const PlanCheck({required this.title, required this.text, this.fix, this.warning = false, required this.plannedKm, required this.actualKm});
  final String title;
  final String text;
  final PlanFix? fix;
  final bool warning;
  final double plannedKm;
  final double actualKm;
}

typedef DoneRun = ({DateTime start, double meters, int seconds});

/// Kijkt naar de afgelopen 7 dagen: gemiste trainingen en veel meer kilometers dan gepland.
/// [fixedEnd]: het schema eindigt op een wedstrijd (dan niet opschuiven).
PlanCheck? checkPlan(List<PlanSession> plan, List<DoneRun> runs, DateTime now, {required bool fixedEnd}) {
  if (plan.isEmpty) return null;
  final today = DateTime(now.year, now.month, now.day);
  final from = today.subtract(const Duration(days: 7));
  final past = plan.where((s) => !s.date.isBefore(from) && s.date.isBefore(today) && s.kind != SessionKind.race).toList();
  if (past.isEmpty || plan.last.date.isBefore(today)) return null;
  final missed = past.where((s) => !sessionDone(s, runs)).length;
  final planned = past.fold<double>(0, (a, s) => a + (s.distanceMeters ?? 0) / 1000);
  final actual = runs
      .where((r) {
        final t = r.start.toLocal();
        return !t.isBefore(from) && t.isBefore(today);
      })
      .fold<double>(0, (a, r) => a + r.meters / 1000);

  if (planned >= 8 && actual > planned * 1.3 && actual - planned >= 5) {
    final pct = ((actual / planned - 1) * 100).round();
    return PlanCheck(
      title: 'Je loopt meer dan gepland',
      text: 'De afgelopen week ${_km(actual)} km, gepland was ${_km(planned)} km (+$pct%). '
          'Meer is niet altijd beter: houd de komende trainingen rustig, dan voorkom je blessures.',
      fix: PlanFix.lighterWeek,
      warning: true,
      plannedKm: planned,
      actualKm: actual,
    );
  }
  if (missed >= 2) {
    return PlanCheck(
      title: '$missed trainingen gemist',
      text: fixedEnd
          ? 'Geen probleem. Je wedstrijddatum staat vast, dus inhalen hoeft niet: maak deze week wat lichter en pak daarna de draad op.'
          : 'Geen probleem. Herhaal vorige week, dan schuift de rest een week op. Zo bouw je veilig verder.',
      fix: fixedEnd ? PlanFix.lighterWeek : PlanFix.repeatWeek,
      plannedKm: planned,
      actualKm: actual,
    );
  }
  if (missed == 0 && past.length >= 2) {
    return PlanCheck(
      title: 'Je ligt op schema',
      text: 'Alle ${past.length} trainingen van de afgelopen week gedaan${planned > 0 ? ' (${_km(actual)} van ${_km(planned)} km)' : ''}. Mooi zo.',
      plannedKm: planned,
      actualKm: actual,
    );
  }
  return null;
}

String _km(double km) => km.toStringAsFixed(1).replaceAll('.', ',');

/// Vorige week herhalen: alles vanaf vandaag een week later, en de trainingen van de afgelopen 7 dagen nog eens.
List<PlanSession> repeatLastWeek(List<PlanSession> plan, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final from = today.subtract(const Duration(days: 7));
  PlanSession moved(PlanSession s, int days, {int weekShift = 0}) => PlanSession(
        date: DateTime(s.date.year, s.date.month, s.date.day + days),
        kind: s.kind,
        title: s.title,
        description: s.description,
        distanceMeters: s.distanceMeters,
        targetPace: s.targetPace,
        intervals: s.intervals,
        week: s.week + weekShift,
      );
  return [
    for (final s in plan)
      if (s.date.isBefore(today)) s,
    for (final s in plan)
      if (!s.date.isBefore(from) && s.date.isBefore(today)) moved(s, 7, weekShift: 1),
    for (final s in plan)
      if (!s.date.isBefore(today)) moved(s, 7, weekShift: 1),
  ]..sort((a, b) => a.date.compareTo(b.date));
}

/// De trainingen van vandaag tot en met zondag lichter maken (wedstrijd blijft staan).
List<PlanSession> lighterThisWeek(List<PlanSession> plan, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final end = today.add(Duration(days: 8 - today.weekday));
  return [
    for (final s in plan)
      if (!s.date.isBefore(today) && s.date.isBefore(end) && s.kind != SessionKind.race && !s.title.contains('(aangepast)'))
        easierSession(s)
      else
        s,
  ];
}
