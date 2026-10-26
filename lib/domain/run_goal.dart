import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Waarvoor je loopt (gekozen in de rondleiding, op dit toestel bewaard).
enum RunGoal { start, fit, faster, race }

extension RunGoalInfo on RunGoal {
  String get label => switch (this) {
        RunGoal.start => 'Beginnen met lopen',
        RunGoal.fit => 'Fit blijven',
        RunGoal.faster => 'Sneller worden',
        RunGoal.race => 'Een wedstrijd lopen',
      };

  String get explanation => switch (this) {
        RunGoal.start => 'Rustig opbouwen, lopen en wandelen afwisselen mag',
        RunGoal.fit => 'Regelmatig lopen, gezond en ontspannen',
        RunGoal.faster => 'Tempo- en intervaltrainingen, je tijden omlaag',
        RunGoal.race => 'Toewerken naar een wedstrijd met schema en tempoplan',
      };
}

const _goalKey = 'run_goal_v1';

Future<RunGoal?> savedRunGoal() async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString(_goalKey);
    return RunGoal.values.where((g) => g.name == raw).firstOrNull;
  } catch (_) {
    return null;
  }
}

Future<void> saveRunGoal(RunGoal g) async {
  runGoalNotifier.value = g;
  try {
    await (await SharedPreferences.getInstance()).setString(_goalKey, g.name);
  } catch (_) {}
}

/// Hoe lang de antwoorden van de coach zijn (Coach → menu).
enum CoachLength {
  short('Kort', 'Een paar regels, alleen de kern'),
  normal('Normaal', 'Kern plus de belangrijkste uitleg'),
  long('Uitgebreid', 'Met meer uitleg en achtergrond');

  const CoachLength(this.label, this.explanation);
  final String label;
  final String explanation;
}

const _coachLengthKey = 'coach_length_v1';

Future<CoachLength> savedCoachStyle() async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString(_coachLengthKey);
    return CoachLength.values.where((c) => c.name == raw).firstOrNull ?? CoachLength.normal;
  } catch (_) {
    return CoachLength.normal;
  }
}

Future<void> saveCoachStyle(CoachLength c) async {
  try {
    await (await SharedPreferences.getInstance()).setString(_coachLengthKey, c.name);
  } catch (_) {}
}

/// Huidig doel, zodat schermen meteen bijwerken als je het wijzigt (null = nog niet gekozen).
final runGoalNotifier = ValueNotifier<RunGoal?>(null);

/// Eén keer bij het opstarten het bewaarde doel inlezen.
Future<void> loadRunGoal() async => runGoalNotifier.value = await savedRunGoal();
