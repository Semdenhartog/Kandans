import 'dart:math' as math;

import '../data/models/models.dart';

/// Eerste dag van de maand van [d] (lokale tijd).
DateTime monthStart(DateTime d) {
  final l = d.toLocal();
  return DateTime(l.year, l.month);
}

int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

/// Kilometers in de maand van [month].
double kmInMonth(List<Activity> activities, DateTime month) {
  final start = monthStart(month);
  final end = DateTime(start.year, start.month + 1);
  var m = 0.0;
  for (final a in activities) {
    final t = a.startedAt.toLocal();
    if (!t.isBefore(start) && t.isBefore(end)) m += a.distanceMeters;
  }
  return m / 1000;
}

/// Voorstel voor een maanddoel: je gemiddelde van de afgelopen 3 maanden + 10%,
/// afgerond op 5 km naar boven. Minimaal 20 km.
int suggestedGoalKm(List<Activity> activities, DateTime now) {
  final m = monthStart(now);
  final past = [for (var i = 1; i <= 3; i++) kmInMonth(activities, DateTime(m.year, m.month - i))];
  final active = past.where((k) => k > 0).toList();
  if (active.isEmpty) return 30;
  final avg = active.reduce((a, b) => a + b) / active.length;
  return math.max(20, ((avg * 1.1) / 5).ceil() * 5);
}

/// Voortgang van je maanduitdaging.
class GoalProgress {
  const GoalProgress({required this.targetKm, required this.doneKm, required this.now});

  final double targetKm;
  final double doneKm;
  final DateTime now;

  DateTime get month => monthStart(now);
  int get totalDays => daysInMonth(month);
  int get dayOfMonth => now.toLocal().day;

  /// Dagen over, vandaag meegeteld.
  int get daysLeft => totalDays - dayOfMonth + 1;

  double get fraction => targetKm <= 0 ? 0 : (doneKm / targetKm).clamp(0.0, 1.0);
  bool get achieved => doneKm >= targetKm;
  double get remainingKm => math.max(0, targetKm - doneKm);

  /// Wat je volgens schema nu had moeten hebben (tot en met gisteren).
  double get expectedKm => targetKm * (dayOfMonth - 1) / totalDays;

  /// Positief = voor op schema.
  double get aheadKm => doneKm - expectedKm;

  /// Kilometers per week die je nog nodig hebt.
  double get neededPerWeek => daysLeft <= 0 ? remainingKm : remainingKm / daysLeft * 7;

  String get statusText {
    if (achieved) {
      final extra = doneKm - targetKm;
      return extra >= 1 ? 'Gehaald, en ${extra.round()} km extra!' : 'Gehaald!';
    }
    final left = remainingKm.toStringAsFixed(remainingKm < 10 ? 1 : 0).replaceAll('.', ',');
    final days = daysLeft == 1 ? 'vandaag' : 'in $daysLeft dagen';
    if (daysLeft <= 7) return 'Nog $left km $days.';
    final perWeek = neededPerWeek.round();
    if (aheadKm >= 2) return 'Je ligt ${aheadKm.round()} km voor op schema. Nog $left km $days.';
    if (aheadKm <= -2) return 'Je loopt ${(-aheadKm).round()} km achter. Nog $left km $days, zo\'n $perWeek km per week.';
    return 'Precies op schema. Nog $left km $days, zo\'n $perWeek km per week.';
  }
}
