import 'weekly_load.dart';

/// Waarom je even niet loopt.
enum PauseReason {
  injury('Blessure', 'herstelt van een blessure'),
  sick('Ziek', 'is ziek'),
  holiday('Vakantie', 'is op vakantie'),
  rest('Even rust', 'neemt bewust even rust');

  const PauseReason(this.label, this.coachText);
  final String label;

  /// Voor de coach: "De loper [coachText]".
  final String coachText;

  static PauseReason of(String? name) => values.firstWhere((r) => r.name == name, orElse: () => rest);
}

/// Een periode waarin je niet loopt (blessure, ziek, vakantie). Tijdens een pauze:
/// geen loopherinneringen, je reeks breekt niet en de coach geeft geen trainingsdruk.
class PausePeriod {
  const PausePeriod({required this.reason, required this.start, this.end});

  final PauseReason reason;

  /// Eerste dag van de pauze (alleen de datum telt).
  final DateTime start;

  /// Laatste dag van de pauze, of null = "tot ik weer begin".
  final DateTime? end;

  static DateTime _day(DateTime t) {
    final l = t.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  /// Valt [t] in deze pauze?
  bool activeOn(DateTime t) {
    final d = _day(t);
    if (d.isBefore(_day(start))) return false;
    return end == null || !d.isAfter(_day(end!));
  }

  /// Telt de week vanaf [monday] als pauzeweek? Ja als minstens 4 van de 7 dagen in de pauze vallen.
  bool coversWeek(DateTime monday) {
    var n = 0;
    for (var i = 0; i < 7; i++) {
      if (activeOn(DateTime(monday.year, monday.month, monday.day + i, 12))) n++;
    }
    return n >= 4;
  }

  PausePeriod endedOn(DateTime day) => PausePeriod(reason: reason, start: start, end: _day(day));

  Map<String, dynamic> toJson() => {
        'reason': reason.name,
        'start': _day(start).toIso8601String(),
        if (end != null) 'end': _day(end!).toIso8601String(),
      };

  static PausePeriod? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = DateTime.tryParse('${j['start']}');
    if (s == null) return null;
    return PausePeriod(
      reason: PauseReason.of(j['reason'] as String?),
      start: s,
      end: j['end'] == null ? null : DateTime.tryParse('${j['end']}'),
    );
  }
}

/// De pauze die nu loopt (of null).
PausePeriod? currentPause(List<PausePeriod> pauses, DateTime now) {
  for (final p in pauses.reversed) {
    if (p.activeOn(now)) return p;
  }
  return null;
}

/// Maandagen van alle weken die (grotendeels) in een pauze vielen, tot en met [now].
Set<DateTime> pausedWeeks(List<PausePeriod> pauses, DateTime now) {
  final out = <DateTime>{};
  for (final p in pauses) {
    var w = weekStart(p.start);
    final last = weekStart(p.end == null || p.end!.isAfter(now) ? now : p.end!);
    while (!w.isAfter(last)) {
      if (p.coversWeek(w)) out.add(w);
      w = DateTime(w.year, w.month, w.day + 7);
    }
  }
  return out;
}
