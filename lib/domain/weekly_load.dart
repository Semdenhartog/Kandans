import '../data/models/models.dart';

/// Maandag 00:00 van de week van [d] (lokale tijd).
DateTime weekStart(DateTime d) {
  final l = d.toLocal();
  final day = DateTime(l.year, l.month, l.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

class WeekTotal {
  const WeekTotal(this.start, this.km, this.runs, this.seconds);
  final DateTime start;
  final double km;
  final int runs;
  final int seconds;
}

/// Kilometers per week, de oudste eerst, de huidige week als laatste.
List<WeekTotal> weeklyTotals(List<Activity> runs, DateTime now, {int weeks = 8}) {
  final current = weekStart(now);
  return [
    for (var i = weeks - 1; i >= 0; i--)
      () {
        final from = current.subtract(Duration(days: 7 * i));
        final to = from.add(const Duration(days: 7));
        var m = 0.0, n = 0, s = 0;
        for (final a in runs) {
          final t = a.startedAt.toLocal();
          if (!t.isBefore(from) && t.isBefore(to)) {
            m += a.distanceMeters;
            n++;
            s += a.movingTimeSeconds;
          }
        }
        return WeekTotal(from, m / 1000, n, s);
      }(),
  ];
}

/// Opbouw: de afgelopen 7 dagen vergeleken met het weekgemiddelde van de 4 weken daarvoor.
class LoadCheck {
  const LoadCheck({required this.last7Km, required this.previousAvgKm});
  final double last7Km;
  final double previousAvgKm;

  /// Verhouding (1,0 = gelijk). Null als er te weinig geschiedenis is.
  double? get ratio => previousAvgKm < 5 ? null : last7Km / previousAvgKm;

  /// Meer dan 30% erbij in één week: grotere kans op blessures.
  bool get tooFast => (ratio ?? 0) > 1.3 && last7Km - previousAvgKm >= 5;

  /// Duidelijk minder dan normaal (bijv. na ziekte of vakantie).
  bool get muchLess => (ratio ?? 1) < 0.5;

  String? get message {
    final r = ratio;
    if (r == null) return null;
    final pct = ((r - 1) * 100).round();
    if (tooFast) {
      return 'Je liep de afgelopen 7 dagen $pct% meer dan je gemiddelde (${previousAvgKm.round()} km per week). '
          'Bouw liever met hooguit 10 tot 20% per week op, dat verkleint de kans op blessures.';
    }
    if (muchLess) {
      return 'Rustigere week dan normaal. Bouw na een pauze weer rustig op, niet meteen terug naar ${previousAvgKm.round()} km.';
    }
    return null;
  }
}

LoadCheck loadCheck(List<Activity> runs, DateTime now) {
  final end = now;
  final start7 = end.subtract(const Duration(days: 7));
  final start35 = end.subtract(const Duration(days: 35));
  var last7 = 0.0, prev = 0.0;
  for (final a in runs) {
    final t = a.startedAt;
    if (t.isAfter(start7) && !t.isAfter(end)) {
      last7 += a.distanceMeters;
    } else if (t.isAfter(start35) && !t.isAfter(start7)) {
      prev += a.distanceMeters;
    }
  }
  return LoadCheck(last7Km: last7 / 1000, previousAvgKm: prev / 1000 / 4);
}

/// Aantal weken op rij met minstens één run. Loop je deze week nog niet, dan telt
/// de reeks tot en met vorige week (je hebt nog tot zondag).
int weekStreak(List<Activity> runs, DateTime now) {
  final weeks = <DateTime>{for (final a in runs) weekStart(a.startedAt)};
  var w = weekStart(now);
  if (!weeks.contains(w)) w = w.subtract(const Duration(days: 7));
  var n = 0;
  while (weeks.contains(w)) {
    n++;
    w = w.subtract(const Duration(days: 7));
  }
  return n;
}
