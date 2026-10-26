import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Vraagt één keer om een beoordeling in de Play Store, na de [afterRuns]e eigen run.
///
/// Google bepaalt zelf of het venster echt verschijnt (en hoe vaak). Buiten de Play Store
/// (bijv. een APK uit GitHub) gebeurt er niets.
class ReviewService {
  ReviewService._();

  static const afterRuns = 5;
  static const _key = 'review_asked';

  /// Moet er na deze run om een beoordeling worden gevraagd?
  /// Na een record ([happy]) mag het al vanaf de 3e run: dan is iemand het meest tevreden.
  static bool shouldAsk({required int ownRuns, required bool askedBefore, bool happy = false}) =>
      !askedBefore && (ownRuns >= afterRuns || (happy && ownRuns >= 3));

  /// Na het opslaan van een eigen run aanroepen met het aantal eigen runs (inclusief deze).
  static Future<void> maybeAsk(int ownRuns, {bool happy = false}) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!shouldAsk(ownRuns: ownRuns, askedBefore: p.getBool(_key) ?? false, happy: happy)) return;
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      await p.setBool(_key, true);
      await review.requestReview();
    } catch (_) {
      // Niet belangrijk genoeg om iets te melden.
    }
  }
}
