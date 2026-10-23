import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/run_recorder.dart';
import 'package:runwise/domain/run_streams.dart';

void main() {
  final t0 = DateTime(2026, 10, 23, 18);
  GpsFix at(int sec, double meters, {double acc = 5}) =>
      GpsFix(LatLng(52.0, 5.0 + meters / 68540), t0.add(Duration(seconds: sec)), accuracy: acc);

  group('GPS-kwaliteit per run', () {
    test('schone run', () {
      final r = RunRecording()..start(t0);
      for (var s = 0; s <= 120; s++) {
        r.add(at(s, s * 3.0));
      }
      expect(r.gps.isClean, isTrue);
      expect(r.gps.text, 'GPS: goed, geen storingen.');
    });

    test('onnauwkeurig, sprong en een tunnel van 40 s', () {
      final r = RunRecording()..start(t0);
      for (var s = 0; s <= 60; s++) {
        r.add(at(s, s * 3.0));
      }
      r.add(at(61, 183, acc: 60)); // onnauwkeurig
      r.add(at(62, 900)); // sprong
      for (var s = 63; s <= 70; s++) {
        r.add(at(s, s * 3.0));
      }
      // Tunnel: 40 s niets, daarna verder (120 m verder, 3 m/s: geen sprong).
      final before = r.distance;
      r.add(at(110, 330));
      expect(r.distance, closeTo(before + 120, 1), reason: 'rechte lijn telt mee');
      expect(r.gps.inaccurate, 1);
      expect(r.gps.jumps, 1);
      expect(r.gps.gaps, 1);
      expect(r.gps.gapSeconds, 40);
      expect(r.gps.text, contains('1× even geen GPS (samen 40 s'));
      expect(r.gps.text, startsWith('GPS: goed.'));

      // Gaat mee in het verloop en in het herstelbestand.
      final streams = RunStreams.fromJson(r.streamsJson())!;
      expect(GpsQuality.fromJson(streams.gpsQuality)!.jumps, 1);
      expect(RunRecording.fromSnapshot(r.toSnapshot())!.gps.gaps, 1);
    });

    test('pauze is geen GPS-gat', () {
      final r = RunRecording(autoPause: false)..start(t0);
      for (var s = 0; s <= 30; s++) {
        r.add(at(s, s * 3.0));
      }
      r.pause();
      r.resume();
      for (var s = 120; s <= 140; s++) {
        r.add(at(s, 90 + (s - 120) * 3.0));
      }
      expect(r.gps.gaps, 0);
    });
  });
}
