import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/barometer.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/record_layout.dart';
import 'package:runwise/domain/run_markers.dart';
import 'package:runwise/domain/run_recorder.dart';
import 'package:runwise/domain/run_streams.dart';
import 'package:runwise/domain/run_trim.dart';
import 'package:runwise/domain/stride_sensor.dart';

void main() {
  group('barometer', () {
    test('luchtdruk naar hoogte: zeeniveau 0 m, ~12 Pa per meter', () {
      expect(pressureToAltitude(1013.25), closeTo(0, 0.01));
      expect(pressureToAltitude(1013.25) - pressureToAltitude(1012.05), closeTo(-10, 0.6));
    });

    test('ruis onder 3 m telt niet, een echte klim wel', () {
      final flat = [for (var i = 0; i < 200; i++) 10.0 + (i.isEven ? 1.4 : -1.4)];
      expect(barometricGain(flat), 0);
      final climb = [for (var i = 0; i <= 30; i++) 10.0 + i]; // 30 m omhoog
      expect(barometricGain(climb), 30);
      final hill = [...climb, for (var i = 30; i >= 0; i--) 10.0 + i, ...climb];
      expect(barometricGain(hill), 60);
    });

    test('afvlakking dempt een uitschieter', () {
      final a = BarometricAltimeter()..add(1013.25);
      a.add(1003.25); // sensorhapering van ~80 m
      expect(a.altitude!, lessThan(30));
      a.add(5000); // onzin wordt genegeerd
      expect(a.altitude!, lessThan(30));
    });
  });

  group('loopsensor (RSC)', () {
    test('snelheid, cadans, paslengte en afstand', () {
      // flags: paslengte + totale afstand + rennen; 3,5 m/s; 88 rpm; 1,20 m; 1234,5 m
      final speed = (3.5 * 256).round();
      final d = [0x07, speed & 0xFF, speed >> 8, 88, 120, 0, 0x39, 0x30, 0, 0];
      final s = parseRunningSpeedCadence(d)!;
      expect(s.speed, closeTo(3.5, 0.01));
      expect(s.cadence, 176); // omwentelingen → stappen per minuut
      expect(s.strideLength, closeTo(1.2, 0.001));
      expect(s.totalDistance, closeTo(1234.5, 0.01));
      expect(s.running, isTrue);
    });

    test('cadans al in stappen per minuut blijft gelijk; wandelen niet verdubbelen', () {
      expect(normalizeCadence(172, speed: 3.2), 172);
      expect(normalizeCadence(100, speed: 1.2), 100);
      expect(normalizeCadence(0), isNull);
      expect(parseRunningSpeedCadence([0, 1]), isNull);
    });
  });

  group('tussentijden per afstand', () {
    final t = [for (var i = 0; i <= 600; i++) i * 1.0];
    final d = [for (var i = 0; i <= 600; i++) i * 4.0]; // 4 m/s, 2,4 km
    final s = RunStreams(time: t, distance: d, cadence: [for (var i = 0; i <= 600; i++) 170.0]);

    test('per 400 m: 6 stukken van 100 s', () {
      final sp = splitsOf(s, every: 400);
      expect(sp.length, 6);
      expect(sp.first.seconds, closeTo(100, 0.5));
      expect(sp.first.partial, isFalse);
      expect(sp.first.cadence, closeTo(170, 0.1));
    });

    test('per km blijft zoals het was', () {
      final sp = splitsOf(s);
      expect(sp.length, 3);
      expect(sp.last.partial, isTrue);
      expect(sp.first.paceSecPerKm, closeTo(250, 0.5));
    });

    test('labels', () {
      expect(splitDistanceLabel(400), '400 m');
      expect(splitDistanceLabel(1609.344), '1 mijl');
    });
  });

  group('opnamescherm-indeling', () {
    test('bewaren en teruglezen', () {
      const l = RecordLayout(name: 'Test', style: RecStyle.big, main: RecField.time, fields: [RecField.cadence], columns: 2);
      final back = RecordLayout.decodeAll(RecordLayout.encodeAll([l])).single;
      expect(back.name, 'Test');
      expect(back.style, RecStyle.big);
      expect(back.main, RecField.time);
      expect(back.fields, [RecField.cadence]);
      expect(back.columns, 2);
    });

    test('kapot of leeg = standaardindelingen; eerste is het oude scherm', () {
      expect(RecordLayout.decodeAll('{kapot').length, RecordLayout.presets.length);
      final std = RecordLayout.decodeAll(null).first;
      expect(std.main, RecField.distance);
      expect(std.fields, [RecField.time, RecField.currentPace, RecField.averagePace]);
    });

    test('maximaal 6 kleine cijfers', () {
      final l = const RecordLayout(name: 'x').copyWith(fields: RecField.values);
      expect(l.fields.length, RecordLayout.maxFields);
    });
  });

  group('markeringen', () {
    test('json heen en terug, lokale foto alleen als gevraagd', () {
      const m = RunMarker(seconds: 61, meters: 250, point: LatLng(52.1, 5.6), kind: MarkerKind.view, localPhoto: '/x.jpg');
      expect(m.toJson().containsKey('lp'), isFalse);
      final back = RunMarker.fromJson(m.toJson(includeLocal: true))!;
      expect(back.kind, MarkerKind.view);
      expect(back.localPhoto, '/x.jpg');
      expect(back.title, 'Mooi uitzicht');
    });

    test('bijsnijden verschuift en filtert markeringen', () {
      final streams = <String, dynamic>{
        't': [0, 100, 200, 300],
        'd': [0, 300, 600, 900],
        'marks': [
          const RunMarker(seconds: 50, meters: 150, point: LatLng(0, 0)).toJson(),
          const RunMarker(seconds: 250, meters: 750, point: LatLng(0, 0)).toJson(),
        ],
      };
      final r = trimRun(streams, 1, 3)!;
      final marks = markersOf(r.streams);
      expect(marks.length, 1);
      expect(marks.single.meters, closeTo(450, 0.1));
      expect(marks.single.seconds, closeTo(150, 0.1));
    });

    test('opname bewaart markeringen, cadans en barometer in het verloop', () {
      final rec = RunRecording(autoPause: false)..start(DateTime(2026, 1, 1));
      var t = DateTime(2026, 1, 1);
      for (var i = 0; i < 40; i++) {
        rec.cadence = 168;
        rec.baroAltitude = 10.0 + i * 0.5; // 20 m klim
        rec.add(GpsFix(LatLng(52.0 + i * 0.0001, 5.6), t, accuracy: 5));
        t = t.add(const Duration(seconds: 3));
      }
      rec.markers.add(const RunMarker(seconds: 10, meters: 30, point: LatLng(52, 5.6), kind: MarkerKind.water));
      final j = rec.streamsJson()!;
      expect((j['cad'] as List).first, 168);
      expect(j['baro'], isA<List<dynamic>>());
      expect(rec.baroGain, closeTo(18, 3.1));
      expect(markersOf(j).single.kind, MarkerKind.water);
      final back = RunRecording.fromSnapshot(rec.toSnapshot())!;
      expect(back.markers.single.kind, MarkerKind.water);
      expect(back.samples.last.cad, 168);
    });
  });
}
