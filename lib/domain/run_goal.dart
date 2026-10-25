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
  try {
    await (await SharedPreferences.getInstance()).setString(_goalKey, g.name);
  } catch (_) {}
}
