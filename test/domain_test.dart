import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/core/format.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/data/services/rain_service.dart';
import 'package:runwise/data/services/route_generator_service.dart';
import 'package:runwise/domain/clothing.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/route_direction.dart';
import 'package:runwise/domain/route_geometry.dart';
import 'package:runwise/domain/gpx_parser.dart';
import 'package:runwise/domain/performance_model.dart';
import 'package:runwise/domain/poi.dart';
import 'package:runwise/domain/records.dart';
import 'package:runwise/domain/start_time_scoring.dart';
import 'package:runwise/domain/weather_correction.dart';

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

  group('op de minuut', () {
    test('afronden naar boven op 5 minuten', () {
      expect(StartTimePlanner.roundUp(DateTime(2030, 6, 1, 14, 2), 5), DateTime(2030, 6, 1, 14, 5));
      expect(StartTimePlanner.roundUp(DateTime(2030, 6, 1, 14, 5), 5), DateTime(2030, 6, 1, 14, 5));
      expect(StartTimePlanner.roundUp(DateTime(2030, 6, 1, 14, 58), 5), DateTime(2030, 6, 1, 15, 0));
    });

    test('kwartierweer wordt tussen twee kwartieren geschat', () {
      final t0 = DateTime(2030, 6, 1, 18);
      final f = Forecast(
        latitude: 52,
        longitude: 5,
        hours: [hour(t0, temp: 10)],
        quarters: [
          hour(t0, temp: 10, wind: 20),
          hour(t0.add(const Duration(minutes: 15)), temp: 12, wind: 10),
        ],
      );
      final w = f.precise(t0.add(const Duration(minutes: 5)))!;
      expect(w.temperature, closeTo(10.67, 0.05));
      expect(w.windSpeed, closeTo(16.67, 0.05));
    });

    test('Buienradar-tekst lezen, ook over middernacht', () {
      final now = DateTime(2030, 6, 1, 23, 52);
      final rc = RainService.parse('000|23:55\n077|00:00\n109|00:05\n000|00:10', now);
      expect(rc.points.length, 4);
      expect(rc.points[1].time, DateTime(2030, 6, 2, 0, 0));
      expect(rc.points[0].mmPerHour, 0);
      expect(rc.points[2].mmPerHour, closeTo(1.0, 0.01));
      expect(rc.firstRain, DateTime(2030, 6, 2, 0, 0));
    });

    test('wacht tot de bui voorbij is, op 5 minuten nauwkeurig', () {
      final now = DateTime(2030, 6, 1, 14, 0);
      final hours = [
        for (var i = 0; i < 4; i++) hour(now.add(Duration(hours: i)), temp: 12, wind: 5),
      ];
      // Regen tot 14:35, daarna droog.
      final points = [
        for (var m = 0; m <= 120; m += 5)
          (time: now.add(Duration(minutes: m)), mmPerHour: m < 35 ? 3.0 : 0.0),
      ];
      final planner = StartTimePlanner(
        forecast: Forecast(latitude: 52, longitude: 5, hours: hours),
        profile: PerformanceInsights.defaults,
        durationMinutes: 30,
        rain: RainNowcast(points: points, fetchedAt: now),
      );
      final best = planner.bestPrecise(TrainingType.easy, from: now, horizon: const Duration(hours: 2))!;
      expect(best.start, DateTime(2030, 6, 1, 14, 35));
    });
  });

  group('kledingadvies', () {
    test('koud: lange tight, jack en handschoenen', () {
      final a = clothingFor(hour(DateTime(2030, 1, 10, 8), temp: -2, wind: 10), TrainingType.easy);
      expect(a.items.join(' ').toLowerCase(), contains('handschoenen'));
      expect(a.items.join(' '), contains('tight'));
    });
    test('warm: korte broek, en drinken bij een lange run', () {
      final a = clothingFor(hour(DateTime(2030, 7, 10, 18), temp: 24), TrainingType.long, durationMinutes: 100);
      expect(a.items, contains('Korte broek'));
      expect(a.extras.join(' '), contains('drinken'));
    });
    test('donker en regen geven extra tips', () {
      final a = clothingFor(hour(DateTime(2030, 11, 10, 19), temp: 8, rain: 80, day: false), TrainingType.easy);
      expect(a.extras.join(' '), contains('Regenjack'));
      expect(a.extras.join(' '), contains('lampje'));
    });
  });

  group('looprichting', () {
    // Driehoek: A -> 2 km oost -> 2 km noord -> terug naar A (linksom).
    const a = LatLng(52.0, 5.0);
    const b = LatLng(52.0, 5.0292);
    const c = LatLng(52.018, 5.0292);
    final loop = [a, b, c, a];

    test('rondje herkennen en richting bepalen', () {
      expect(isLoop(loop), isTrue);
      expect(signedArea(loop) > 0, isTrue); // tegen de klok in
      expect(isLoop([a, b]), isFalse);
    });

    test('wind uit het zuidwesten: rechtsom geeft minder tegenwind op het eind', () {
      final adv = adviseDirection(loop, 20, 225)!;
      expect(adv.reverse, isTrue);
      expect(adv.bestLabel, 'rechtsom');
      expect(adv.endHeadwind, lessThan(adv.otherEndHeadwind));
    });

    test('geen advies bij weinig wind of heen-en-terug', () {
      expect(adviseDirection(loop, 4, 0), isNull);
      expect(adviseDirection([a, b, a], 20, 90), isNull);
    });
  });

  group('route maken', () {
    test('PDOK-adres lezen', () {
      const body = '{"response":{"docs":[{"weergavenaam":"Stationsweg 1, 3771VE Barneveld","centroide_ll":"POINT(5.5869 52.1419)","type":"adres"}]}}';
      final p = RouteGeneratorService.parsePdok(body);
      expect(p.single.label, startsWith('Stationsweg 1'));
      expect(p.single.lat, closeTo(52.1419, 1e-6));
      expect(p.single.lon, closeTo(5.5869, 1e-6));
    });

    test('rondje uit punten bouwen', () {
      const a = LatLng(52.0, 5.0, 10);
      const b = LatLng(52.0, 5.0292, 12);
      const c = LatLng(52.018, 5.0292, 15);
      final pts = <LatLng>[];
      for (final (p, q) in [(a, b), (b, c), (c, a)]) {
        for (var i = 0; i < 20; i++) {
          final f = i / 20;
          pts.add(LatLng(p.lat + (q.lat - p.lat) * f, p.lon + (q.lon - p.lon) * f, p.ele));
        }
      }
      pts.add(a);
      final r = buildRoute(pts, name: 'Test', source: 'generated', estimatedPaceSecPerKm: 360);
      expect(r.source, 'generated');
      expect(r.distanceMeters, closeTo(6830, 120));
      expect(r.points.length, greaterThanOrEqualTo(7));
      expect(r.estimatedDurationSeconds, closeTo(6.83 * 360, 60));
    });
  });

  group('route op de kaart', () {
    // Recht naar het oosten (2 km) en weer terug naar het westen.
    final east = [for (var i = 0; i <= 20; i++) LatLng(52.0, 5.0 + 0.0292 * i / 20, 10.0 + i)];
    final outAndBack = [...east, ...east.reversed.skip(1)];

    test('punt en richting op afstand', () {
      final t = RouteTrack(east);
      expect(t.length, closeTo(2000, 30));
      expect(t.at(t.length / 2).lon, closeTo(5.0146, 1e-3));
      expect(t.bearingAt(500), closeTo(90, 1));
      expect(t.reversed().bearingAt(500), closeTo(270, 1));
    });

    test('westenwind: heen wind mee, terug tegenwind', () {
      final segs = windSegments(RouteTrack(outAndBack), windSpeedKmh: 20, windFromDegrees: 270);
      expect(segs.map((s) => s.windClass).toList(), [WindClass.tail, WindClass.head]);
      // De stukken sluiten op elkaar aan.
      expect(segs[0].points.last.lon, closeTo(segs[1].points.first.lon, 1e-9));
    });

    test('zijwind en weinig wind', () {
      expect(classifyWind(90, 20, 0), WindClass.side);
      expect(classifyWind(90, 4, 90), WindClass.calm);
      final segs = windSegments(RouteTrack(east), windSpeedKmh: 5, windFromDegrees: 90);
      expect(segs.single.windClass, WindClass.calm);
    });

    test('pijltjes en kilometerbordjes', () {
      final t = RouteTrack(outAndBack);
      final arrows = arrowPositions(t, 400);
      expect(arrows.length, 10);
      expect(arrows.first.bearing, closeTo(90, 2));
      expect(arrows.last.bearing, closeTo(270, 2));
      expect(kmPositions(t).map((k) => k.km).toList(), [1, 2, 3]);
      expect(markerDensity(25000).kmEvery, 2);
      expect(markerDensity(5000, compact: true).kmEvery, 0);
    });

    test('hoogteprofiel', () {
      final prof = sampleElevation(east);
      expect(prof.first.meters, 0);
      expect(prof.last.meters, closeTo(2000, 30));
      expect(prof.length, inInclusiveRange(41, 42));
      final range = elevationRange(prof);
      expect(range.max, greaterThan(range.min));
      expect(elevationAt(prof, 1000), closeTo(20, 1.5));
      // Zonder hoogtes geen profiel.
      expect(sampleElevation([for (final p in east) LatLng(p.lat, p.lon)]), isEmpty);
      // Opslaan en teruglezen.
      final back = ElevationSample.listFromJson([for (final e in prof) e.toJson()]);
      expect(back.length, prof.length);
      expect(back[10].ele, closeTo(prof[10].ele, 0.06));
      // Omgekeerd lopen: begint hoog, eindigt laag.
      final rev = reverseProfile(prof);
      expect(rev.first.meters, 0);
      expect(rev.first.ele, closeTo(prof.last.ele, 1e-9));
      expect(profileAscent(prof), closeTo(prof.last.ele - prof.first.ele, 1.5));
      expect(profileAscent(rev), lessThan(1));
    });

    test('route krijgt een hoogteprofiel', () {
      final r = buildRoute(east, name: 'Oost', source: 'generated');
      expect(r.elevationProfile.length, greaterThan(30));
      expect(r.toInsert('u')['elevation_profile'], isA<List>());
      expect(r.profileOrKmPoints, isNotEmpty);
    });
  });

  group('records en weercorrectie', () {
    Activity run(String id, double km, int seconds, {double? wind, double? feels, String? route, int daysAgo = 0}) => Activity(
          id: id,
          startedAt: DateTime(2026, 10, 1).subtract(Duration(days: daysAgo)),
          distanceMeters: km * 1000,
          movingTimeSeconds: seconds,
          windSpeedKmh: wind,
          temperatureCelsius: feels,
          feelsLikeCelsius: feels,
          routeId: route,
        );

    test('wind en warmte kosten tijd, windstil en koel niet', () {
      expect(netWindSecPerKm(20), closeTo(3, 0.01));
      final storm = weatherCost(run('a', 10, 3000, wind: 30, feels: 10));
      expect(storm.windSeconds, closeTo(67.5, 0.1));
      expect(storm.heatSeconds, 0);
      final hot = weatherCost(run('b', 10, 3000, wind: 0, feels: 25));
      expect(hot.heatSeconds, closeTo(3000 * 0.035 / 1.035, 0.5));
      expect(weatherCost(run('c', 10, 3000, wind: 3, feels: 10)).matters, isFalse);
      expect(correctedSeconds(run('d', 10, 3000, wind: 30, feels: 10)), 2933);
    });

    test('records per afstand, met weer-record', () {
      final calm = run('calm', 10.0, 2900, wind: 0, feels: 10);
      final storm = run('storm', 10.1, 2950, wind: 40, feels: 10);
      final five = run('five', 5.05, 1400, wind: 10, feels: 12);
      final r = computeRecords([calm, storm, five, run('kort', 0.5, 200)]);
      final ten = r.distances.firstWhere((d) => d.distance.meters == 10000);
      expect(ten.best.id, 'calm');
      expect(ten.bestSeconds, 2900);
      expect(ten.bestWeather.id, 'storm');
      expect(ten.weatherRecordDiffers, isTrue);
      expect(r.badgesFor(storm), ['Weer-PR 10 km', 'Langste run']);
      expect(r.badgesFor(calm), ['PR 10 km']);
      expect(r.distances.map((d) => d.distance.label), ['5 km', '10 km']);
      expect(scaledSeconds(1400, 5050, 5000), 1386);
    });

    test('runs op een vaste route met trend', () {
      final runs = [
        for (var i = 0; i < 6; i++) run('r$i', 8, 2880 - i * 30, wind: 10, feels: 10, route: 'x', daysAgo: 60 - i * 10),
        run('ander', 8, 2000, route: 'y'),
      ];
      final h = routeHistory(runs, 'x');
      expect(h.runs.length, 6);
      expect(h.runs.first.activity.id, 'r5');
      expect(h.fastest!.activity.id, 'r5');
      expect(h.trendSecPerKm, lessThan(-5));
    });
  });

  group('water en toilet langs de route', () {
    final east = [for (var i = 0; i <= 20; i++) LatLng(52.0, 5.0 + 0.0292 * i / 20)];

    test('Overpass lezen en privé overslaan', () {
      const body = '{"elements":['
          '{"type":"node","lat":52.0005,"lon":5.0146,"tags":{"amenity":"drinking_water"}},'
          '{"type":"node","lat":52.0003,"lon":5.0147,"tags":{"amenity":"drinking_water"}},'
          '{"type":"node","lat":52.0,"lon":5.02,"tags":{"amenity":"toilets","fee":"yes","name":"Bezoekerscentrum"}},'
          '{"type":"node","lat":52.0,"lon":5.01,"tags":{"amenity":"toilets","access":"private"}},'
          '{"type":"node","lat":52.01,"lon":5.01,"tags":{"amenity":"drinking_water"}}'
          ']}';
      final raw = parseOverpass(body);
      expect(raw.length, 4);
      final along = poisAlongRoute(raw, RouteTrack(east));
      // Dubbele kraan samengevoegd, punt 1 km van de route valt af.
      expect(along.length, 2);
      expect(along.first.kind, PoiKind.water);
      expect(along.first.alongMeters, closeTo(1000, 30));
      expect(along.first.offsetMeters, closeTo(55, 10));
      expect(along.last.label, 'Toilet (betaald)');
      expect(along.last.name, 'Bezoekerscentrum');
    });

    test('zoekopdracht bevat het gebied', () {
      final q = overpassQuery(east);
      expect(q, contains('drinking_water'));
      expect(q, contains('51.99700,4.99700,52.00300,5.03220'));
    });
  });
}
