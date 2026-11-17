import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/fit_parser.dart';

void main() {
  test('leeg of te kort bestand geeft een nette fout, geen crash', () {
    expect(() => parseFit(Uint8List(0)), throwsA(isA<FitFormatException>()));
    expect(() => parseFit(Uint8List(10)), throwsA(isA<FitFormatException>()));
  });

  test('bestand zonder .FIT-kop wordt geweigerd', () {
    final b = Uint8List(40)..[0] = 14;
    expect(() => parseFit(b), throwsA(isA<FitFormatException>()));
  });

  test('kop zonder gegevens geeft nul punten', () {
    final b = Uint8List(16);
    b[0] = 14;
    b.setRange(8, 12, '.FIT'.codeUnits);
    final r = parseFit(b);
    expect(r.points, isEmpty);
    expect(r.isRunning, isTrue);
  });

  test('afgekapt of beschadigd gegevensdeel crasht niet', () {
    final b = Uint8List(40);
    b[0] = 14;
    b.setRange(8, 12, '.FIT'.codeUnits);
    b[4] = 200; // meer gegevens aangekondigd dan er zijn
    for (var i = 14; i < 40; i++) {
      b[i] = (i * 37) & 0xff;
    }
    try {
      parseFit(b);
    } on FitFormatException {
      // netjes geweigerd is ook goed
    }
  });
}
