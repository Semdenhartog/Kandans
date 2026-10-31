import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/age_grading.dart';

/// Geboortejaar en geslacht voor het leeftijdsniveau (alleen op dit toestel).
class AgeGradeSettings {
  const AgeGradeSettings({this.birthYear, this.sex});
  final int? birthYear;
  final Sex? sex;
  bool get ready => birthYear != null && sex != null;
  int ageAt(DateTime t) => t.year - birthYear!;
}

final ageGradeSettingsProvider = FutureProvider<AgeGradeSettings>((ref) async {
  try {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('ag_sex');
    return AgeGradeSettings(birthYear: p.getInt('ag_birth_year'), sex: Sex.values.where((x) => x.name == s).firstOrNull);
  } catch (_) {
    return const AgeGradeSettings();
  }
});

Future<void> saveAgeGradeSettings(WidgetRef ref, int birthYear, Sex sex) async {
  final p = await SharedPreferences.getInstance();
  await p.setInt('ag_birth_year', birthYear);
  await p.setString('ag_sex', sex.name);
  ref.invalidate(ageGradeSettingsProvider);
}
