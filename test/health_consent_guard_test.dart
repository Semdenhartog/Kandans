import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Privacyregel: gezondheidsgegevens vragen mag pas na `HealthConsent.ensure(context)`.
/// Een scherm dat Health Connect koppelt (`connectHealth`/`connectSteps`) moet die controle dus zelf doen.
void main() {
  test('schermen die Health Connect koppelen vragen eerst toestemming', () {
    final bad = <String>[];
    final call = RegExp(r'\.(connectHealth|connectSteps)\(');
    for (final f in Directory('lib/features').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      if (call.hasMatch(s) && !s.contains('HealthConsent.ensure')) bad.add(f.path);
    }
    expect(bad, isEmpty, reason: 'Geen HealthConsent.ensure in: ${bad.join(', ')}');
  });
}
