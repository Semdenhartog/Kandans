import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Vaste `Color(0x…)`-waarden buiten het thema mogen niet méér worden: gebruik `RwColors`/`RwPalette`
/// (die volgen licht én donker). Kunst, posters, PDF's en de thema-bestanden zijn uitgezonderd.
/// Is het aantal gedaald? Zet `_baseline` dan lager.
const _baseline = 328;

void main() {
  test('aantal vaste kleuren stijgt niet', () {
    final re = RegExp(r'Color\(0x');
    var n = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll('\\', '/');
      if (!p.endsWith('.dart')) continue;
      if (p.contains('/shared/art/') || p.endsWith('core/theme.dart') || p.contains('poster') || p.contains('_pdf')) continue;
      n += re.allMatches(f.readAsStringSync()).length;
    }
    expect(n, lessThanOrEqualTo(_baseline), reason: 'Vaste kleuren: $n (maximaal $_baseline). Gebruik RwColors.');
  });
}
