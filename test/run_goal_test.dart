import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/run_goal.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    runGoalNotifier.value = null;
  });

  test('zonder bewaard doel: null', () async {
    expect(await savedRunGoal(), isNull);
  });

  test('doel bewaren en weer inlezen; scherm wordt meteen bijgewerkt', () async {
    await saveRunGoal(RunGoal.race);
    expect(runGoalNotifier.value, RunGoal.race);
    runGoalNotifier.value = null;
    await loadRunGoal();
    expect(runGoalNotifier.value, RunGoal.race);
  });

  test('onbekende waarde in de opslag wordt genegeerd', () async {
    SharedPreferences.setMockInitialValues({'run_goal_v1': 'bestaat_niet', 'coach_length_v1': 'ook_niet'});
    expect(await savedRunGoal(), isNull);
    expect(await savedCoachStyle(), CoachLength.normal);
  });

  test('antwoordlengte van de coach: standaard normaal, daarna de keuze', () async {
    expect(await savedCoachStyle(), CoachLength.normal);
    await saveCoachStyle(CoachLength.short);
    expect(await savedCoachStyle(), CoachLength.short);
  });

  test('elk doel heeft een label en uitleg', () {
    for (final g in RunGoal.values) {
      expect(g.label, isNotEmpty);
      expect(g.explanation, isNotEmpty);
    }
  });
}
