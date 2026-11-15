import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bouwregel: bestanden zijn hoogstens 300 regels. Oude, grotere bestanden staan in `file_size_baseline.txt`
/// en mogen niet groeien; een nieuw bestand boven 300 regels laat deze test falen.
const _max = 300;

void main() {
  test('bestanden groeien niet voorbij de grens', () {
    final base = <String, int>{};
    for (final l in File('test/file_size_baseline.txt').readAsLinesSync()) {
      if (l.startsWith('#') || l.trim().isEmpty) continue;
      final i = l.lastIndexOf(' ');
      base[l.substring(0, i)] = int.parse(l.substring(i + 1));
    }
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll('\\', '/');
      if (!p.endsWith('.dart') || p.endsWith('i18n_strings.dart') || p.endsWith('privacy_text.dart')) continue;
      final n = f.readAsLinesSync().length;
      if (n <= _max) continue;
      final allowed = base[p];
      if (allowed == null) {
        bad.add('$p heeft $n regels (max $_max)');
      } else if (n > allowed) {
        bad.add('$p groeide van $allowed naar $n regels');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
