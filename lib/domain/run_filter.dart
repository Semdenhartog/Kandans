import '../data/models/models.dart';
import 'weekly_load.dart';

enum Period { week, month, year }

class PeriodTotal {
  const PeriodTotal(this.start, this.km, this.runs, this.seconds);
  final DateTime start;
  final double km;
  final int runs;
  final int seconds;

  double get paceSecPerKm => km <= 0 ? 0 : seconds / km;
}

DateTime periodStart(DateTime d, Period p) {
  final l = d.toLocal();
  return switch (p) {
    Period.week => weekStart(l),
    Period.month => DateTime(l.year, l.month),
    Period.year => DateTime(l.year),
  };
}

DateTime _next(DateTime s, Period p) => switch (p) {
      Period.week => DateTime(s.year, s.month, s.day + 7),
      Period.month => DateTime(s.year, s.month + 1),
      Period.year => DateTime(s.year + 1),
    };

DateTime _prev(DateTime s, Period p) => switch (p) {
      Period.week => DateTime(s.year, s.month, s.day - 7),
      Period.month => DateTime(s.year, s.month - 1),
      Period.year => DateTime(s.year - 1),
    };

/// Totalen per week, maand of jaar; de oudste eerst, de huidige als laatste.
List<PeriodTotal> periodTotals(List<Activity> runs, DateTime now, Period p, {int count = 8}) {
  final starts = <DateTime>[periodStart(now, p)];
  while (starts.length < count) {
    starts.insert(0, _prev(starts.first, p));
  }
  return [
    for (final s in starts)
      () {
        final e = _next(s, p);
        var m = 0.0, n = 0, sec = 0;
        for (final a in runs) {
          final t = a.startedAt.toLocal();
          if (!t.isBefore(s) && t.isBefore(e)) {
            m += a.distanceMeters;
            n++;
            sec += a.movingTimeSeconds;
          }
        }
        return PeriodTotal(s, m / 1000, n, sec);
      }(),
  ];
}

/// Een dag in de weekstrook (maandag t/m zondag).
class StripDay {
  const StripDay(this.date, this.km, this.runs, {required this.isToday, required this.isFuture});
  final DateTime date;
  final double km;
  final int runs;
  final bool isToday;
  final bool isFuture;
}

List<StripDay> weekStrip(List<Activity> runs, DateTime now) {
  final start = weekStart(now);
  final today = DateTime(now.year, now.month, now.day);
  return [
    for (var i = 0; i < 7; i++)
      () {
        final d = DateTime(start.year, start.month, start.day + i);
        var m = 0.0, n = 0;
        for (final a in runs) {
          final t = a.startedAt.toLocal();
          if (t.year == d.year && t.month == d.month && t.day == d.day) {
            m += a.distanceMeters;
            n++;
          }
        }
        return StripDay(d, m / 1000, n, isToday: d == today, isFuture: d.isAfter(today));
      }(),
  ];
}

enum DistanceBand {
  all('Alle afstanden', 0, double.infinity),
  short('Tot 5 km', 0, 5000),
  mid('5 – 10 km', 5000, 10000),
  long('10 – 21 km', 10000, 21100),
  veryLong('Langer dan 21 km', 21100, double.infinity);

  const DistanceBand(this.label, this.min, this.max);
  final String label;
  final double min;
  final double max;

  bool contains(double m) => m >= min && m < max;
}

/// Filters voor de lijst met runs (zoals bij Strava).
class RunFilter {
  const RunFilter({this.band = DistanceBand.all, this.source, this.routeId, this.shoeId, this.windyOnly = false, this.withNote = false});

  final DistanceBand band;

  /// 'runwise', 'strava', 'health_connect', 'manual' of null voor alles.
  final String? source;
  final String? routeId;
  final String? shoeId;

  /// Alleen runs met veel wind (≥ 20 km/u).
  final bool windyOnly;
  final bool withNote;

  bool get isEmpty => band == DistanceBand.all && source == null && routeId == null && shoeId == null && !windyOnly && !withNote;

  int get activeCount =>
      (band != DistanceBand.all ? 1 : 0) +
      (source != null ? 1 : 0) +
      (routeId != null ? 1 : 0) +
      (shoeId != null ? 1 : 0) +
      (windyOnly ? 1 : 0) +
      (withNote ? 1 : 0);

  bool matches(Activity a) =>
      band.contains(a.distanceMeters) &&
      (source == null || a.source == source) &&
      (routeId == null || a.routeId == routeId) &&
      (shoeId == null || a.shoeId == shoeId) &&
      (!windyOnly || (a.windSpeedKmh ?? 0) >= 20) &&
      (!withNote || (a.note ?? '').trim().isNotEmpty || a.feel != null);

  List<Activity> apply(List<Activity> list) => [for (final a in list) if (matches(a)) a];

  RunFilter copyWith({
    DistanceBand? band,
    String? Function()? source,
    String? Function()? routeId,
    String? Function()? shoeId,
    bool? windyOnly,
    bool? withNote,
  }) =>
      RunFilter(
        band: band ?? this.band,
        source: source != null ? source() : this.source,
        routeId: routeId != null ? routeId() : this.routeId,
        shoeId: shoeId != null ? shoeId() : this.shoeId,
        windyOnly: windyOnly ?? this.windyOnly,
        withNote: withNote ?? this.withNote,
      );
}
