import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/core/format.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/gpx_parser.dart';
import 'package:runwise/domain/performance_model.dart';
import 'package:runwise/domain/start_time_scoring.dart';

HourWeather hour(DateTime t,
        {double temp = 12, double wind = 5, double dir = 270, double rain = 0, bool day = true}) =>
    HourWeather(
      time: t,
      temperature: temp,
      feelsLike: temp,
      windSpeed: wind,
      windDirection: dir,
      precipitationProbability: rain,
      isDay: day,
    );

void main() {
  group('Fmt', () {
    test('pace en duur', () {
      expect(Fmt.pace(330), '5:30 /km');
      expect(Fmt.duration(3725), '1:02:05');
      expect(Fmt.duration(605), '10:05');
      expect(Fmt.parseMinSec('5:30'), 330);
      expect(Fmt.parseDuration('1:45:00'), 6300);
      expect(Fmt.parseDuration('45:00'), 2700);
      expect(Fmt.parseDuration('1:75:00'), isNull);
      expect(Fmt.parseDecimal('5,2'), 5.2);
      expect(Fmt.compass(0), 'N');
      expect(Fmt.compass(225), 'ZW');
    });
  });

  group('geo', () {
    test('polyline encode/decode (voorbeeld van Google)', () {
      const pts = [LatLng(38.5, -120.2), LatLng(40.7, -120.95), LatLng(43.252, -126.453)];
      final enc = encodePolyline(pts);
      expect(enc, '_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      final dec = decodePolyline(enc);
      expect(dec.length, 3);
      expect(dec[2].lat, closeTo(43.252, 1e-5));
      expect(dec[2].lon, closeTo(-126.453, 1e-5));
    });

    test('afstand en richting', () {
      const a = LatLng(52.0, 5.0);
      const b = LatLng(52.01, 5.0);
      expect(distanceMeters(a, b), closeTo(1112, 5));
      expect(bearingDegrees(a, b), closeTo(0, 0.5));
      expect(bearingDegrees(b, a), closeTo(180, 0.5));
    });
  });

  group('GPX', () {
    test('leest punten, afstand en km-punten', () {
      final buf = StringBuffer(
          '<?xml version="1.0"?><gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">'
          '<trk><name>Rondje test</name><trkseg>');
      // 3 km recht naar het noorden in stappen van ~111 m.
      for (var i = 0; i <= 27; i++) {
        buf.write('<trkpt lat="${52 + i * 0.001}" lon="5.0"><ele>${10 + i}</ele></trkpt>');
      }
      buf.write('</trkseg></trk></gpx>');
      final route = parseGpx(buf.toString());
      expect(route.name, 'Rondje test');
      expect(route.distanceMeters, closeTo(3002, 10));
      expect(route.points.length, greaterThanOrEqualTo(4));
      expect(route.points.first.bearing, closeTo(0, 1));
      expect(route.elevationGainMeters, greaterThan(20));
      expect(decodePolyline(route.polyline).length, greaterThan(10));
    });

    test('ongeldige invoer geeft nette fout', () {
      expect(() => parseGpx('geen xml'), throwsA(isA<GpxParseException>()));
    });
  });

  group('wind langs route', () {
    test('noordelijke wind is tegenwind als je naar het noorden loopt', () {
      final segs = [(bearing: 0.0, meters: 1000.0, startKm: 0.0)];
      final w = routeWind(segs, 20, 0);
      expect(w.headwindAvg, closeTo(20, 0.01));
      expect(w.tailwindAvg, closeTo(0, 0.01));
    });

    test('heen en terug: tegenwind op de terugweg', () {
      final segs = [
        (bearing: 0.0, meters: 2000.0, startKm: 0.0),
        (bearing: 180.0, meters: 2000.0, startKm: 2.0),
      ];
      final w = routeWind(segs, 20, 180); // wind uit het zuiden
      expect(w.firstHalfHead, closeTo(0, 0.01));
      expect(w.secondHalfHead, closeTo(20, 0.01));
    });
  });

  group('vertrektijd', () {
    test('kiest het koele, droge, windstille uur', () {
      final base = DateTime(2030, 6, 1, 6);
      final hours = [
        hour(base, temp: 14, wind: 6),
        hour(base.add(const Duration(hours: 1)), temp: 15, wind: 5),
        hour(base.add(const Duration(hours: 6)), temp: 28, wind: 10),
        hour(base.add(const Duration(hours: 8)), temp: 22, wind: 35, rain: 80),
      ];
      final planner = StartTimePlanner(
        forecast: Forecast(latitude: 52, longitude: 5, hours: hours),
        profile: PerformanceInsights.defaults,
      );
      final best = planner.best(TrainingType.quality, from: base)!;
      expect(best.start.hour, anyOf(6, 7));
      final hot = planner.scoreAt(base.add(const Duration(hours: 6)), TrainingType.quality);
      expect(hot.score, lessThan(best.score));
      expect(hot.reasons.first, contains('Warm'));
    });
  });

  group('prestatiemodel', () {
    test('vindt de snelste temperatuurgroep', () {
      final runs = <Activity>[];
      final start = DateTime(2030, 1, 1, 8);
      for (var i = 0; i < 12; i++) {
        final temp = i.isEven ? 10.0 : 26.0;
        final pace = temp < 20 ? 300 : 330; // sneller bij 10 graden
        runs.add(Activity(
          startedAt: start.add(Duration(days: i)),
          distanceMeters: 8000,
          movingTimeSeconds: pace * 8,
          temperatureCelsius: temp,
          windSpeedKmh: 10,
        ));
      }
      final p = PerformanceInsights.compute(runs);
      expect(p.isPersonal, isTrue);
      expect(p.optimalMin, lessThanOrEqualTo(10));
      expect(p.optimalMax, greaterThan(10));
      expect(p.optimalMax, lessThanOrEqualTo(16));
      expect(p.pctFasterInOptimal, closeTo(9.1, 0.5));
    });
  });
}
