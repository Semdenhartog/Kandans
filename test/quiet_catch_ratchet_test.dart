import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Geen lege `catch (_) {}` meer: gebruik `ErrorReporter.quiet(e, st, 'waar')` of een echte afhandeling.
void main() {
  test('geen lege catch-blokken in lib/', () {
    final bad = <String>[];
    final re = RegExp(r'catch \(_\) \{\s*\}');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final n = re.allMatches(f.readAsStringSync()).length;
      if (n > 0) bad.add('${f.path}: $n');
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
