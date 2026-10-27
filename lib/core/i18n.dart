import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n_strings.dart';

/// Talen in Kadans. Nederlands is de brontaal: elke tekst in de code is Nederlands en wordt via [tr] vertaald.
enum AppLanguage {
  nl('Nederlands', 'nl', 'NL'),
  en('English', 'en', 'GB'),
  de('Deutsch', 'de', 'DE'),
  fr('Français', 'fr', 'FR'),
  es('Español', 'es', 'ES');

  const AppLanguage(this.label, this.code, this.country);
  final String label;
  final String code;
  final String country;

  Locale get locale => Locale(code, country);
  String get intlLocale => '${code}_$country';
}

/// Bewaart de gekozen taal (standaard: de taal van de telefoon als die er is, anders Nederlands).
class LanguageController extends ChangeNotifier {
  LanguageController._();
  static final instance = LanguageController._();
  static const _key = 'app_language';

  AppLanguage _lang = AppLanguage.nl;
  AppLanguage get lang => _lang;

  /// Heeft de gebruiker zelf gekozen? (Anders volgen we de telefoon.)
  bool _chosen = false;
  bool get chosen => _chosen;

  Future<void> load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_key);
      final match = AppLanguage.values.where((l) => l.code == v);
      if (match.isNotEmpty) {
        _lang = match.first;
        _chosen = true;
        return;
      }
    } catch (_) {}
    final phone = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    _lang = AppLanguage.values.where((l) => l.code == phone).firstOrNull ?? AppLanguage.nl;
  }

  Future<void> set(AppLanguage l) async {
    _lang = l;
    _chosen = true;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_key, l.code);
    } catch (_) {}
  }
}

/// Vertaalt een Nederlandse tekst naar de gekozen taal. Nog niet vertaald? Dan blijft het Nederlands.
String tr(String nl) {
  final l = LanguageController.instance.lang;
  if (l == AppLanguage.nl) return nl;
  return kTranslations[nl]?[l.index - 1] ?? nl;
}

/// Zoals [tr], met invulplekken: tr2('Hallo {naam}', {'naam': 'Sem'}).
String trf(String nl, Map<String, Object?> values) {
  var s = tr(nl);
  values.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  return s;
}
