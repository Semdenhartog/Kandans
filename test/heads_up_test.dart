import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/services/metronome_service.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/poi.dart';
import 'package:runwise/domain/route_geometry.dart';
import 'package:runwise/domain/route_heads_up.dart';

List<ElevationSample> profile(List<(double, double)> pts) => [for (final (m, e) in pts) ElevationSample(m, e)];

void main() {
  group('klimmetjes', () {
    test('herkent een klim en negeert vlak en kleine bultjes', () {
      final p = profile([(0, 10), (500, 10), (600, 14), (700, 20), (800, 28), (900, 30), (1500, 30), (1600, 32), (2000, 31)]);
      final c = detectClimbs(p);
      expect(c, hasLength(1));
      expect(c.single.startMeters, 500);
      expect(c.single.gainMeters, closeTo(20, 0.01));
      expect(c.single.grade, closeTo(5, 0.01));
    });

    test('lange flauwe helling telt niet', () {
      final p = profile([(0, 0), (1000, 10), (2000, 20)]);
      expect(detectClimbs(p), isEmpty); // 1 %
    });

    test('profiel op andere schaal wordt omgerekend naar de route', () {
      final p = profile([(0, 0), (100, 0), (200, 15), (300, 15)]);
      final c = detectClimbs(p, trackLength: 600);
      expect(c.single.startMeters, 200);
      expect(c.single.lengthMeters, 200);
    });
  });

  group('vooraankondigingen', () {
    test('klim en watertappunt op tijd, elk één keer', () {
      final h = RouteHeadsUp.build(
        climbs: const [RouteClimb(startMeters: 800, lengthMeters: 400, gainMeters: 20)],
        pois: const [
          RoutePoi(kind: PoiKind.water, point: LatLng(0, 0), alongMeters: 2000, offsetMeters: 10),
          RoutePoi(kind: PoiKind.water, point: LatLng(0, 0), alongMeters: 2300, offsetMeters: 10), // te kort erna
          RoutePoi(kind: PoiKind.toilet, point: LatLng(0, 0), alongMeters: 2500, offsetMeters: 300), // te ver weg
        ],
      );
      final said = <(double, String)>[];
      for (var m = 0.0; m < 3000; m += 5) {
        final t = h.update(m);
        if (t != null) said.add((m, t));
      }
      expect(said, hasLength(2));
      expect(said[0].$1, 650);
      expect(said[0].$2, contains('klim van 20 meter'));
      expect(said[1].$2, contains('watertappunt'));
    });

    test('daglicht-seintje één keer, 20 minuten vooraf', () {
      final sunset = DateTime(2026, 10, 21, 18, 40);
      final w = DaylightWarner(sunset);
      expect(w.update(DateTime(2026, 10, 21, 18, 0)), isNull);
      expect(w.update(DateTime(2026, 10, 21, 18, 21)), 'Nog 19 minuten daglicht. Zorg dat je gezien wordt.');
      expect(w.update(DateTime(2026, 10, 21, 18, 30)), isNull);
      expect(DaylightWarner(sunset).update(DateTime(2026, 10, 21, 19, 0)), isNull);
    });
  });

  test('cadans-tik: geldig WAV-bestand met de juiste lengte', () {
    final wav = metronomeWav(180, beats: 8, sampleRate: 22050);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    final samples = (wav.length - 44) ~/ 2;
    // 8 tikken op 180 per minuut = 2,67 s.
    expect(samples / 22050, closeTo(8 * 60 / 180, 0.01));
  });
}
