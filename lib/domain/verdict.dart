import 'start_time_scoring.dart';

enum VerdictKind { goNow, later, tough }

/// Eén duidelijk oordeel bovenaan Vandaag: nu lopen, later lopen of vandaag lastig.
class RunVerdict {
  const RunVerdict({required this.kind, required this.title, required this.detail, required this.best, required this.now});
  final VerdictKind kind;
  final String title;
  final String detail;
  final StartTimeScore best;
  final StartTimeScore now;
}

/// [nowAllowed]: valt "nu" binnen je looptijden.
RunVerdict runVerdict(StartTimeScore now, StartTimeScore best, {bool nowAllowed = true, String Function(DateTime)? time}) {
  String t(DateTime d) => time?.call(d) ?? '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final why = best.reasons.isEmpty ? '' : best.reasons.first;
  if (best.score < 40) {
    return RunVerdict(
      kind: VerdictKind.tough,
      title: 'Vandaag lastig',
      detail: 'Beste kans om ${t(best.start)}${why.isEmpty ? '' : ': ${_lower(why)}'}',
      best: best,
      now: now,
    );
  }
  final gain = best.score - now.score;
  final soon = best.start.difference(now.start).inMinutes.abs() <= 15;
  if (nowAllowed && now.score >= 55 && (soon || gain <= 5)) {
    return RunVerdict(
      kind: VerdictKind.goNow,
      title: 'Nu lopen',
      detail: gain <= 0 || soon ? 'Dit is het beste moment van de komende uren.' : 'Bijna net zo goed als om ${t(best.start)}.',
      best: best,
      now: now,
    );
  }
  return RunVerdict(
    kind: VerdictKind.later,
    title: 'Later lopen: ${t(best.start)}',
    detail: gain > 0 ? '$gain punten beter dan nu${why.isEmpty ? '' : '. ${_cap(why)}'}' : (why.isEmpty ? 'Het beste moment binnen je looptijden.' : _cap(why)),
    best: best,
    now: now,
  );
}

String _lower(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Alleen de goede uren (Runcast-stijl filter).
List<StartTimeScore> goodHoursOnly(List<StartTimeScore> all, {int minScore = 70}) =>
    all.where((s) => s.score >= minScore).toList();
