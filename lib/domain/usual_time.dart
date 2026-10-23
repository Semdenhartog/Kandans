import 'start_time_scoring.dart';

/// Het tijdstip waarop je meestal gaat lopen.
class UsualTime {
  const UsualTime({required this.hour, required this.minute, required this.runs, required this.share});
  final int hour;
  final int minute;

  /// Aantal runs rond dit tijdstip.
  final int runs;

  /// Deel van al je runs dat rond dit tijdstip begint (0–1).
  final double share;

  /// Dit tijdstip op dag [day].
  DateTime on(DateTime day) => DateTime(day.year, day.month, day.day, hour, minute);

  String get label => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Wanneer je meestal loopt, uit de starttijden van je runs van de afgelopen [window].
///
/// Zoekt het drukste blok van 2 uur. Pas als daar minstens [minRuns] runs in vallen en dat
/// minstens [minShare] van al je runs is, noemen we het "je gewone tijd". Anders null:
/// dan loop je op wisselende tijden (bijv. door diensten) en is er geen gewone tijd.
UsualTime? usualStartTime(
  Iterable<DateTime> starts, {
  required DateTime now,
  Duration window = const Duration(days: 60),
  int minRuns = 4,
  double minShare = 0.4,
}) {
  final from = now.subtract(window);
  final minutes = <int>[
    for (final s in starts)
      if (s.isAfter(from) && !s.isAfter(now)) s.toLocal().hour * 60 + s.toLocal().minute,
  ]..sort();
  if (minutes.length < minRuns) return null;

  var bestStart = 0, bestEnd = -1;
  for (var i = 0, j = 0; i < minutes.length; i++) {
    while (j + 1 < minutes.length && minutes[j + 1] - minutes[i] <= 120) {
      j++;
    }
    if (j - i > bestEnd - bestStart) {
      bestStart = i;
      bestEnd = j;
    }
  }
  final group = minutes.sublist(bestStart, bestEnd + 1);
  final share = group.length / minutes.length;
  if (group.length < minRuns || share < minShare) return null;

  // Mediaan van het blok, afgerond op 5 minuten.
  final median = group[group.length ~/ 2];
  final rounded = ((median + 2) ~/ 5) * 5;
  return UsualTime(hour: (rounded ~/ 60) % 24, minute: rounded % 60, runs: group.length, share: share);
}

/// Uitkomst: wel of geen ochtendmelding, en zo ja met welke extra zin.
class ReminderDecision {
  const ReminderDecision({required this.send, this.note});
  final bool send;

  /// Extra uitleg in de melding (bijv. "12 punten beter dan je gewone tijd").
  final String? note;
}

/// Is de ochtendmelding de moeite waard?
///
/// Zonder gewone looptijd, of als je die dag op je gewone tijd niet kunt (diensten), altijd sturen.
/// Met een gewone tijd alleen als een ander moment duidelijk beter is ([minGain] punten),
/// of als je gewone tijd die dag slecht uitkomt (score onder [badBelow]).
ReminderDecision reminderDecision({
  required StartTimeScore best,
  UsualTime? usual,
  StartTimeScore? atUsual,
  bool usualAllowed = true,
  int minGain = 8,
  int badBelow = 55,
}) {
  if (usual == null || atUsual == null || !usualAllowed) return const ReminderDecision(send: true);
  final gain = best.score - atUsual.score;
  final nearUsual = best.start.difference(atUsual.start).inMinutes.abs() <= 30;
  if (!nearUsual && gain >= minGain) {
    return ReminderDecision(send: true, note: '$gain punten beter dan je gewone tijd (${usual.label}).');
  }
  if (atUsual.score < badBelow) {
    return ReminderDecision(send: true, note: 'Om je gewone tijd (${usual.label}) is het vandaag lastig.');
  }
  return const ReminderDecision(send: false);
}
