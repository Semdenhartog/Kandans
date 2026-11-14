import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/hr_alarm.dart';
import 'package:runwise/domain/run_recorder.dart';

void main() {
  group('Hartslagalarm', () {
    test('uit = nooit alarm', () {
      final a = HrAlarm();
      for (var i = 0; i < 100; i++) {
        expect(a.tick(190, 190), isFalse);
      }
    });

    test('alarm pas na 15 s boven de zone, dan 90 s stilte', () {
      final a = HrAlarm(limitZone: 2); // alarm vanaf zone 3: boven 70% van 190 = 133
      var fired = <int>[];
      for (var s = 1; s <= 200; s++) {
        if (a.tick(150, 190)) fired.add(s);
      }
      expect(fired.first, 15);
      expect(fired[1] - fired[0], greaterThanOrEqualTo(90));
    });

    test('een piekje of zonder band geeft geen alarm', () {
      final a = HrAlarm(limitZone: 2);
      for (var s = 0; s < 14; s++) {
        expect(a.tick(150, 190), isFalse);
      }
      expect(a.tick(120, 190), isFalse); // terug in zone 2: teller weer op nul
      for (var s = 0; s < 14; s++) {
        expect(a.tick(150, 190), isFalse);
      }
      for (var s = 0; s < 50; s++) {
        expect(a.tick(null, 190), isFalse);
      }
    });
  });

  group('Opnameflow met nepsensoren', () {
    final t0 = DateTime(2026, 11, 14, 9);
    GpsFix fix(int sec, double meters) => GpsFix(LatLng(52.0, 5.0 + meters / 68540), t0.add(Duration(seconds: sec)), accuracy: 5);

    test('lopen, pauzeren, hervatten en herstel na afsluiten geven dezelfde run', () {
      final r = RunRecording()..start(t0);
      for (var s = 0; s <= 300; s++) {
        r.heartRate = 140;
        r.add(fix(s, s * 3.0));
      }
      final before = r.distance;
      expect(before, greaterThan(850));
      expect(before, lessThan(950));
      r.pause();
      expect(r.status, RecorderStatus.paused);
      r.resume();

      // Telefoon "stort in": alleen de bewaarde momentopname blijft over.
      final saved = jsonDecode(jsonEncode(r.toSnapshot()));
      final back = RunRecording.fromSnapshot(saved);
      expect(back, isNotNull);
      expect(back!.distance, closeTo(before, 0.01));
      expect(back.movingSeconds, r.movingSeconds);
      expect(back.track.length, r.track.length);
    });

    test('kapotte momentopname geeft null in plaats van een crash', () {
      expect(RunRecording.fromSnapshot({'v': 99}), isNull);
      expect(RunRecording.fromSnapshot('rommel'), isNull);
    });
  });
}
