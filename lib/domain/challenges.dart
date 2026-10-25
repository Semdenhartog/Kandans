import 'dart:math' as math;

import '../data/models/models.dart';

/// Wat een uitdaging meet.
enum ChallengeKind {
  /// Totaal aantal kilometers in de periode.
  distance,

  /// Aantal runs in de periode.
  runs,

  /// Elke dag van de periode minstens [Challenge.dailyMinKm] km.
  everyDay,

  /// Elke week van de periode minstens [Challenge.target] runs.
  weekly,

  /// Totaal aantal hoogtemeters.
  elevation,

  /// Totale looptijd in uren.
  hours,

  /// Eén run van minstens [Challenge.target] km.
  longRun,
}

/// Een uitdaging met een vaste begin- en einddatum (zelf gekozen of uit de lijst).
class Challenge {
  const Challenge({
    required this.key,
    required this.title,
    required this.description,
    required this.kind,
    required this.target,
    required this.start,
    required this.end,
    this.icon = 'flag',
    this.dailyMinKm = 1,
  });

  /// Uniek per uitdaging én periode (bijv. "km100-2026-11"), ook gebruikt voor de ranglijst.
  final String key;
  final String title;
  final String description;
  final ChallengeKind kind;
  final double target;

  /// Begin (inclusief) en eind (exclusief), lokale tijd, hele dagen.
  final DateTime start;
  final DateTime end;
  final String icon;
  final double dailyMinKm;

  int get totalDays => end.difference(start).inDays;

  bool isRunning(DateTime now) => !now.isBefore(start) && now.isBefore(end);

  /// "8,4 van 100 km"-achtige eenheid.
  String get unit => switch (kind) {
        ChallengeKind.distance || ChallengeKind.longRun => 'km',
        ChallengeKind.runs => 'runs',
        ChallengeKind.everyDay => 'dagen',
        ChallengeKind.weekly => 'weken',
        ChallengeKind.elevation => 'm',
        ChallengeKind.hours => 'uur',
      };

  /// Doel in de eenheid van [unit] (bij elke dag/week: het aantal dagen/weken).
  double get goal => switch (kind) {
        ChallengeKind.everyDay => totalDays.toDouble(),
        ChallengeKind.weekly => (totalDays / 7).ceilToDouble(),
        _ => target,
      };

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'description': description,
        'kind': kind.name,
        'target': target,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'icon': icon,
        'daily_min_km': dailyMinKm,
      };

  static Challenge? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      return Challenge(
        key: raw['key'] as String,
        title: raw['title'] as String,
        description: raw['description'] as String,
        kind: ChallengeKind.values.byName(raw['kind'] as String),
        target: (raw['target'] as num).toDouble(),
        start: DateTime.parse(raw['start'] as String),
        end: DateTime.parse(raw['end'] as String),
        icon: (raw['icon'] as String?) ?? 'flag',
        dailyMinKm: (raw['daily_min_km'] as num?)?.toDouble() ?? 1,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Hoe je ervoor staat.
class ChallengeProgress {
  const ChallengeProgress({required this.challenge, required this.value, this.completedAt, this.todayDone = false});

  final Challenge challenge;

  /// Stand in de eenheid van [Challenge.unit].
  final double value;
  final DateTime? completedAt;

  /// Elke dag: heb je vandaag je km al?
  final bool todayDone;

  bool get completed => completedAt != null;
  double get fraction => challenge.goal <= 0 ? 0 : (value / challenge.goal).clamp(0.0, 1.0);
  double get remaining => math.max(0, challenge.goal - value);

  /// Mag je nog kunnen halen? (Bij elke dag: geen dag gemist.)
  bool stillPossible(DateTime now) {
    if (completed) return true;
    if (!now.isBefore(challenge.end)) return false;
    if (challenge.kind == ChallengeKind.everyDay) {
      final day = DateTime(now.year, now.month, now.day);
      final passed = day.difference(challenge.start).inDays; // volle dagen vóór vandaag
      return value >= passed;
    }
    return true;
  }
}

DateTime _day(DateTime d) {
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Voortgang van [c] met deze runs (alleen runs binnen de periode tellen).
ChallengeProgress challengeProgress(Challenge c, List<Activity> runs, {DateTime? now}) {
  final inPeriod = [
    for (final a in runs)
      if (!a.startedAt.toLocal().isBefore(c.start) && a.startedAt.toLocal().isBefore(c.end)) a,
  ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  switch (c.kind) {
    case ChallengeKind.distance:
    case ChallengeKind.runs:
    case ChallengeKind.elevation:
    case ChallengeKind.hours:
      var sum = 0.0;
      DateTime? done;
      for (final a in inPeriod) {
        sum += switch (c.kind) {
          ChallengeKind.distance => a.distanceMeters / 1000,
          ChallengeKind.runs => 1,
          ChallengeKind.elevation => a.elevationGainMeters ?? 0,
          _ => a.movingTimeSeconds / 3600,
        };
        if (done == null && sum >= c.target - 1e-9) done = a.startedAt;
      }
      return ChallengeProgress(challenge: c, value: sum, completedAt: done);
    case ChallengeKind.longRun:
      var best = 0.0;
      DateTime? done;
      for (final a in inPeriod) {
        best = math.max(best, a.distanceMeters / 1000);
        if (done == null && best >= c.target - 1e-9) done = a.startedAt;
      }
      return ChallengeProgress(challenge: c, value: best, completedAt: done);
    case ChallengeKind.everyDay:
      final perDay = <DateTime, double>{};
      for (final a in inPeriod) {
        final d = _day(a.startedAt);
        perDay[d] = (perDay[d] ?? 0) + a.distanceMeters / 1000;
      }
      // Dagen op rij vanaf de start (een gemiste dag stopt de telling).
      var days = 0;
      DateTime? done;
      for (var d = c.start; d.isBefore(c.end); d = DateTime(d.year, d.month, d.day + 1)) {
        if ((perDay[d] ?? 0) < c.dailyMinKm - 1e-9) break;
        days++;
        if (days == c.totalDays) {
          done = inPeriod.lastWhere((a) => _day(a.startedAt) == d).startedAt;
        }
      }
      final today = _day(now ?? DateTime.now());
      return ChallengeProgress(
        challenge: c,
        value: days.toDouble(),
        completedAt: done,
        todayDone: (perDay[today] ?? 0) >= c.dailyMinKm - 1e-9,
      );
    case ChallengeKind.weekly:
      var weeks = 0;
      DateTime? done;
      final total = c.goal.toInt();
      for (var w = 0; w < total; w++) {
        final ws = DateTime(c.start.year, c.start.month, c.start.day + 7 * w);
        final we = DateTime(ws.year, ws.month, ws.day + 7);
        final inWeek = inPeriod.where((a) => !a.startedAt.toLocal().isBefore(ws) && a.startedAt.toLocal().isBefore(we)).toList();
        if (inWeek.length < c.target) break;
        weeks++;
        if (weeks == total) done = inWeek[c.target.toInt() - 1].startedAt;
      }
      return ChallengeProgress(challenge: c, value: weeks.toDouble(), completedAt: done);
  }
}

String _monthName(int m) =>
    const ['januari', 'februari', 'maart', 'april', 'mei', 'juni', 'juli', 'augustus', 'september', 'oktober', 'november', 'december'][m - 1];

/// Uitdagingen die je nu kunt kiezen: voor deze maand, en in december/zomer iets extra's.
List<Challenge> availableChallenges(DateTime now, {double suggestedMonthKm = 50}) {
  final m = DateTime(now.year, now.month);
  final next = DateTime(now.year, now.month + 1);
  final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
  final name = _monthName(m.month);
  // Maandafstand: een stapje boven je normale maand, afgerond op 25 km (minimaal 50).
  final stretch = math.max(50, ((suggestedMonthKm * 1.15) / 25).ceil() * 25).toDouble();
  final weekStart = DateTime(now.year, now.month, now.day - (now.weekday - 1));

  final list = <Challenge>[
    Challenge(
      key: 'km${stretch.round()}-$ym',
      title: '${stretch.round()} km in $name',
      description: 'Loop deze maand samen ${stretch.round()} kilometer.',
      kind: ChallengeKind.distance,
      target: stretch,
      start: m,
      end: next,
      icon: 'route',
    ),
    Challenge(
      key: 'runs12-$ym',
      title: '12 runs in $name',
      description: 'Twaalf keer lopen deze maand, hoe kort ook.',
      kind: ChallengeKind.runs,
      target: 12,
      start: m,
      end: next,
      icon: 'directions_run',
    ),
    Challenge(
      key: 'hours10-$ym',
      title: '10 uur lopen in $name',
      description: 'Samen tien uur hardlopen deze maand.',
      kind: ChallengeKind.hours,
      target: 10,
      start: m,
      end: next,
      icon: 'timer',
    ),
    Challenge(
      key: 'climb1000-$ym',
      title: '1000 hoogtemeters',
      description: 'Klim deze maand samen 1000 meter. Tip: bruggen, duinen en de Veluwe.',
      kind: ChallengeKind.elevation,
      target: 1000,
      start: m,
      end: next,
      icon: 'terrain',
    ),
    Challenge(
      key: 'half-$ym',
      title: 'Halve marathon in $name',
      description: 'Eén run van 21,1 km deze maand.',
      kind: ChallengeKind.longRun,
      target: 21.1,
      start: m,
      end: next,
      icon: 'military_tech',
    ),
    Challenge(
      key: 'week3x4-${weekStart.year}-${weekStart.month}-${weekStart.day}',
      title: '4 weken, 3× per week',
      description: 'Vier weken lang elke week drie runs, vanaf deze maandag.',
      kind: ChallengeKind.weekly,
      target: 3,
      start: weekStart,
      end: DateTime(weekStart.year, weekStart.month, weekStart.day + 28),
      icon: 'event_repeat',
    ),
  ];
  // Seizoensuitdagingen.
  if (now.month == 11 || (now.month == 12 && now.day <= 24)) {
    final y = now.year;
    list.add(Challenge(
      key: 'advent-$y',
      title: 'Adventsloop',
      description: 'Van 1 tot en met 24 december elke dag minstens 1 km.',
      kind: ChallengeKind.everyDay,
      target: 24,
      start: DateTime(y, 12, 1),
      end: DateTime(y, 12, 25),
      icon: 'park',
    ));
  }
  if (now.month == 1) {
    list.add(Challenge(
      key: 'january-${now.year}',
      title: 'Goed begin',
      description: 'Elke dag van januari minstens 2 km.',
      kind: ChallengeKind.everyDay,
      target: 31,
      start: DateTime(now.year, 1, 1),
      end: DateTime(now.year, 2, 1),
      icon: 'celebration',
      dailyMinKm: 2,
    ));
  }
  if (now.month >= 6 && now.month <= 8) {
    list.add(Challenge(
      key: 'summer-${now.year}',
      title: 'Zomer van 300 km',
      description: 'Loop van juni tot en met augustus samen 300 kilometer.',
      kind: ChallengeKind.distance,
      target: 300,
      start: DateTime(now.year, 6, 1),
      end: DateTime(now.year, 9, 1),
      icon: 'wb_sunny',
    ));
  }
  return list;
}

/// Hoeveel nog te gaan, in gewone woorden (voor op het opnamescherm en in de stem).
String remainingText(ChallengeProgress p) {
  final c = p.challenge;
  if (p.completed) return 'Gehaald!';
  final r = p.remaining;
  String km(double v) => v.toStringAsFixed(v < 10 ? 1 : 0).replaceAll('.', ',');
  return switch (c.kind) {
    ChallengeKind.distance => 'nog ${km(r)} km',
    ChallengeKind.longRun => 'nog ${km(r)} km in één run',
    ChallengeKind.runs => 'nog ${r.round()} ${r.round() == 1 ? 'run' : 'runs'}',
    ChallengeKind.elevation => 'nog ${r.round()} hoogtemeters',
    ChallengeKind.hours => 'nog ${km(r)} uur',
    ChallengeKind.everyDay => p.todayDone ? 'vandaag gehaald' : 'vandaag nog ${km(c.dailyMinKm)} km',
    ChallengeKind.weekly => 'nog ${r.round()} ${r.round() == 1 ? 'week' : 'weken'}',
  };
}
