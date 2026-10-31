import 'training_plan.dart';

/// Voorstel om een training naar een dag met beter loopweer te schuiven ("weerslim schema").
class SwapSuggestion {
  const SwapSuggestion({
    required this.session,
    required this.toDay,
    required this.fromScore,
    required this.toScore,
    this.displaced,
  });

  final PlanSession session;
  final DateTime toDay;
  final int fromScore;
  final int toScore;

  /// Rustige duurloop die op [toDay] stond; die schuift naar de oude dag.
  final PlanSession? displaced;

  int get gain => toScore - fromScore;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Zoekt voor zware trainingen in de komende [lookahead] dagen een dag (±2) met duidelijk beter weer.
/// [scoreOn] geeft de beste score van die dag voor die soort training (null = geen verwachting).
/// Regels: nooit naar het verleden, een wedstrijd verschuift niet, en geen twee zware dagen achter elkaar.
List<SwapSuggestion> weatherSwaps(
  List<PlanSession> plan,
  int? Function(DateTime day, SessionKind kind) scoreOn, {
  DateTime? now,
  int lookahead = 6,
  int minGain = 12,
  int maxSuggestions = 2,
}) {
  final today = _day(now ?? DateTime.now());
  final byDay = <DateTime, PlanSession>{for (final s in plan) _day(s.date): s};
  final out = <SwapSuggestion>[];
  final used = <DateTime>{};
  for (final s in plan) {
    final d = _day(s.date);
    if (!s.isKey || s.kind == SessionKind.race) continue;
    if (d.isBefore(today) || d.difference(today).inDays > lookahead) continue;
    final from = scoreOn(d, s.kind);
    if (from == null) continue;
    SwapSuggestion? best;
    for (final offset in const [-2, -1, 1, 2]) {
      final t = DateTime(d.year, d.month, d.day + offset);
      if (t.isBefore(today) || used.contains(t) || used.contains(d)) continue;
      final there = byDay[t];
      if (there != null && there.isKey) continue;
      // Geen zware dag ernaast (behalve de dag waar hij vandaan komt).
      bool keyOn(DateTime x) => x != d && (byDay[x]?.isKey ?? false);
      if (keyOn(DateTime(t.year, t.month, t.day - 1)) || keyOn(DateTime(t.year, t.month, t.day + 1))) continue;
      final to = scoreOn(t, s.kind);
      if (to == null || to - from < minGain) continue;
      if (best == null || to > best.toScore) {
        best = SwapSuggestion(session: s, toDay: t, fromScore: from, toScore: to, displaced: there);
      }
    }
    if (best != null) {
      out.add(best);
      used
        ..add(d)
        ..add(best.toDay);
    }
  }
  out.sort((a, b) => b.gain.compareTo(a.gain));
  return out.take(maxSuggestions).toList();
}

/// Het schema na het verschuiven.
List<PlanSession> applySwap(List<PlanSession> plan, SwapSuggestion s) => [
      for (final x in plan)
        if (identical(x, s.session) || (_day(x.date) == _day(s.session.date) && x.kind == s.session.kind))
          x.copyWith(date: s.toDay)
        else if (s.displaced != null && _day(x.date) == s.toDay)
          x.copyWith(date: _day(s.session.date))
        else
          x,
    ];
