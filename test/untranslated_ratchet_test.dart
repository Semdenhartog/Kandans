import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Houdt het aantal onvertaalde teksten (`Text('Nederlands')` zonder `tr()`) in de gaten.
/// Het aantal mag alleen dalen: bij een nieuwe tekst gebruik je `tr()` (zie tools/tr_codemod.py).
/// Is het aantal gedaald? Zet BASELINE dan lager.
const _baseline = 550;

void main() {
  test('aantal onvertaalde teksten stijgt niet', () {
    final re = RegExp(r"""(?:Text\(|(?:label|title|tooltip|hintText|labelText): )'[A-Z][a-z]""");
    var n = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final p = f.path;
      if (!p.endsWith('.dart') || p.endsWith('i18n_strings.dart') || p.endsWith('privacy_text.dart')) continue;
      for (final line in f.readAsLinesSync()) {
        if (re.hasMatch(line) && !line.contains('tr(')) n++;
      }
    }
    expect(n, lessThanOrEqualTo(_baseline), reason: 'Onvertaalde teksten: $n (maximaal $_baseline). Gebruik tr().');
  });
}
