import '../data/models/models.dart';
import 'best_efforts.dart';
import 'weekly_load.dart';

/// Jouw jaar in runs.
class YearRecap {
  const YearRecap({
    required this.year,
    required this.runs,
    required this.km,
    required this.seconds,
    required this.elevation,
    required this.daysRun,
    this.longest,
    required this.bestMonth,
    required this.bestMonthKm,
    required this.favouriteWeekday,
    required this.favouritePartOfDay,
    required this.longestStreakWeeks,
    required this.fastest,
    required this.perMonthKm,
  });

  final int year;
  final int runs;
  final double km;
  final int seconds;
  final double elevation;
  final int daysRun;
  final Activity? longest;

  /// 1..12
  final int bestMonth;
  final double bestMonthKm;

  /// 1 = maandag
  final int favouriteWeekday;
  final String favouritePartOfDay;
  final int longestStreakWeeks;

  /// Snelste stukken dit jaar: meters -> seconden.
  final Map<int, double> fastest;
  final List<double> perMonthKm;
}

YearRecap? yearRecap(List<Activity> all, int year) {
  final runs = all.where((a) => a.startedAt.toLocal().year == year).toList();
  if (runs.isEmpty) return null;
  final perMonth = List<double>.filled(12, 0);
  final perWeekday = List<int>.filled(7, 0);
  final parts = <String, int>{'ochtend': 0, 'middag': 0, 'avond': 0};
  final days = <String>{};
  var km = 0.0, secs = 0, ele = 0.0;
  Activity? longest;
  for (final a in runs) {
    final t = a.startedAt.toLocal();
    km += a.distanceMeters / 1000;
    secs += a.movingTimeSeconds;
    ele += a.elevationGainMeters ?? 0;
    perMonth[t.month - 1] += a.distanceMeters / 1000;
    perWeekday[t.weekday - 1]++;
    final part = t.hour < 12 ? 'ochtend' : (t.hour < 18 ? 'middag' : 'avond');
    parts[part] = parts[part]! + 1;
    days.add('${t.month}-${t.day}');
    if (longest == null || a.distanceMeters > longest.distanceMeters) longest = a;
  }
  var bestMonth = 0;
  for (var m = 1; m < 12; m++) {
    if (perMonth[m] > perMonth[bestMonth]) bestMonth = m;
  }
  var favDay = 0;
  for (var d = 1; d < 7; d++) {
    if (perWeekday[d] > perWeekday[favDay]) favDay = d;
  }
  final favPart = parts.entries.reduce((a, b) => b.value > a.value ? b : a).key;

  // Langste reeks weken met minstens één run.
  final weeks = runs.map((a) => weekStart(a.startedAt)).toSet().toList()..sort();
  var streak = 0, best = 0;
  DateTime? prev;
  for (final w in weeks) {
    streak = prev != null && (w.difference(prev).inHours / 24).round() == 7 ? streak + 1 : 1;
    if (streak > best) best = streak;
    prev = w;
  }

  final overall = bestOverall([
    for (final a in runs)
      if (a.id != null && a.bestEfforts != null) (id: a.id!, efforts: a.bestEfforts!),
  ]);

  return YearRecap(
    year: year,
    runs: runs.length,
    km: km,
    seconds: secs,
    elevation: ele,
    daysRun: days.length,
    longest: longest,
    bestMonth: bestMonth + 1,
    bestMonthKm: perMonth[bestMonth],
    favouriteWeekday: favDay + 1,
    favouritePartOfDay: favPart,
    longestStreakWeeks: best,
    fastest: {for (final e in overall.entries) e.key: e.value.seconds},
    perMonthKm: perMonth,
  );
}
