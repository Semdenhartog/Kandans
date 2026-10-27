import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/core/i18n.dart';
import 'package:runwise/core/i18n_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => LanguageController.instance.set(AppLanguage.nl));

  test('vertalen en terugvallen op Nederlands', () async {
    await LanguageController.instance.set(AppLanguage.en);
    expect(tr('Vandaag'), 'Today');
    expect(tr('Iets dat nog niet vertaald is'), 'Iets dat nog niet vertaald is');
    await LanguageController.instance.set(AppLanguage.de);
    expect(tr('Vandaag'), 'Heute');
    await LanguageController.instance.set(AppLanguage.nl);
    expect(tr('Vandaag'), 'Vandaag');
  });

  test('elke vertaling heeft 4 talen en is niet leeg', () {
    for (final e in kTranslations.entries) {
      expect(e.value.length, 4, reason: e.key);
      expect(e.value.every((t) => t.trim().isNotEmpty), isTrue, reason: e.key);
    }
  });

  test('invullen met trf', () async {
    await LanguageController.instance.set(AppLanguage.nl);
    expect(trf('Hallo {naam}', {'naam': 'Sem'}), 'Hallo Sem');
  });
}
