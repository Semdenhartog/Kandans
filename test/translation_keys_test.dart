import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Elke tekst die via `tr('…')`/`trf('…')` loopt moet in `i18n_strings.dart` staan, anders blijft hij
/// in andere talen gewoon Nederlands. De paar bekende uitzonderingen (samengestelde teksten) staan in `_baseline`;
/// het aantal mag alleen dalen. Nieuwe tekst? `tools/vertalingen.py` aanvullen en `python3 tools/maak_vertalingen.py`.
const _baseline = 7;

void main() {
  test('tr()-teksten hebben een vertaling', () {
    final src = File('lib/core/i18n_strings.dart').readAsStringSync();
    final keys = RegExp(r"^\s*'((?:[^'\\]|\\.)*)':\s*\[", multiLine: true).allMatches(src).map((m) => m.group(1)!).toSet();
    final use = RegExp(r"\btrf?\('((?:[^'\\]|\\.)*)'");
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('i18n_strings.dart')) continue;
      for (final m in use.allMatches(f.readAsStringSync())) {
        final k = m.group(1)!;
        if (!keys.contains(k)) missing.add(k);
      }
    }
    expect(missing.length, lessThanOrEqualTo(_baseline),
        reason: 'Zonder vertaling (${missing.length}, max $_baseline):\n${missing.take(20).join('\n')}');
  });
}
