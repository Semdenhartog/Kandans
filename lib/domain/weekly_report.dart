import '../data/models/models.dart';
import 'training_load.dart';
import 'training_plan.dart';
import 'weekly_load.dart';

/// Je vorige week in het kort (zoals de weekoverzichten van Garmin en Strava).
class WeeklyReport {
  const WeeklyReport({
    required this.weekStart,
    required this.km,
    required this.runs,
    required this.seconds,
    required this.avgKmBefore,
    this.planDone,
    this.planTotal,
    this.longest,
    required this.easyShare,
  });

  final DateTime weekStart;
  final double km;
  final int runs;
  final int seconds;

  /// Gemiddeld per week in de 4 weken daarvoor.
  final double avgKmBefore;
  final int? planDone;
  final int? planTotal;
  final Activity? longest;

  /// Aandeel rustige tijd (0..1), of null als er niets te zeggen valt.
  final double? easyShare;

  String get headline {
    if (runs == 0) return 'Vorige week niet gelopen. Deze week weer een rondje?';
    final diff = avgKmBefore <= 0 ? 0 : (km - avgKmBefore) / avgKmBefore;
    if (diff > 0.3) return 'Flink meer gelopen dan normaal. Bouw rustig verder.';
    if (diff < -0.3) return 'Rustigere week dan normaal.';
    return 'Een mooie, regelmatige week.';
  }
}

WeeklyReport weeklyReport(List<Activity> runs, DateTime now, {List<PlanSession> plan = const [], int? maxHr}) {
  final thisWeek = weekStart(now);
  final start = DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7);
  bool inWeek(DateTime t, DateTime s) {
    final l = t.toLocal();
    return !l.isBefore(s) && l.isBefore(DateTime(s.year, s.month, s.day + 7));
  }

  final last = runs.where((a) => inWeek(a.startedAt, start)).toList();
  final before = [
    for (var w = 1; w <= 4; w++)
      runs
          .where((a) => inWeek(a.startedAt, DateTime(start.year, start.month, start.day - 7 * w)))
          .fold<double>(0, (s, a) => s + a.distanceMeters / 1000),
  ];
  final planned = plan.where((s) => !s.date.isBefore(start) && s.date.isBefore(thisWeek)).toList();
  final done = [for (final a in runs) (start: a.startedAt, meters: a.distanceMeters, seconds: a.movingTimeSeconds)];
  Activity? longest;
  for (final a in last) {
    if (longest == null || a.distanceMeters > longest.distanceMeters) longest = a;
  }
  final balance = intensityBalance(runs, now: thisWeek, days: 7, maxHr: maxHr);
  return WeeklyReport(
    weekStart: start,
    km: last.fold(0, (s, a) => s + a.distanceMeters / 1000),
    runs: last.length,
    seconds: last.fold(0, (s, a) => s + a.movingTimeSeconds),
    avgKmBefore: before.fold<double>(0, (a, b) => a + b) / 4,
    planDone: planned.isEmpty ? null : planned.where((s) => sessionDone(s, done)).length,
    planTotal: planned.isEmpty ? null : planned.length,
    longest: longest,
    easyShare: balance?.easyShare,
  );
}
