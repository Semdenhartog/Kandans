import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/custom_plan.dart';
import 'package:runwise/features/planner/custom_plan_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF van een marathonschema is geldig en heeft meerdere pagina\'s', () async {
    final w = PlanWishes(
      goal: PlanGoal.marathon,
      raceDate: DateTime(2027, 4, 18),
      raceName: 'Marathon Rotterdam',
      weeklyKm: 35,
      longestKm: 18,
      runDays: const [2, 4, 6, 7],
      strengthPerWeek: 2,
      cross: true,
      goalTimeSeconds: 4 * 3600,
      skipWeeks: const {6},
    );
    final plan = buildCustomPlan(w, start: DateTime(2026, 11, 16), thresholdPace: 320);
    final bytes = await buildCustomPlanPdf(plan);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(20000));
  });
}
