import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/core/error_reporter.dart';
import 'package:runwise/core/format.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/data/services/live_share_service.dart';
import 'package:runwise/data/services/rain_service.dart';
import 'package:runwise/data/services/route_generator_service.dart';
import 'package:runwise/domain/availability.dart';
import 'package:runwise/domain/clothing.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/route_direction.dart';
import 'package:runwise/domain/route_geometry.dart';
import 'package:runwise/domain/gpx_parser.dart';
import 'package:runwise/domain/monthly_goal.dart';
import 'package:runwise/domain/performance_model.dart';
import 'package:runwise/domain/poi.dart';
import 'package:runwise/domain/records.dart';
import 'package:runwise/domain/run_matcher.dart';
import 'package:runwise/domain/run_recorder.dart';
import 'package:runwise/domain/run_streams.dart';
import 'package:runwise/domain/run_warnings.dart';
import 'package:runwise/data/services/air_quality_service.dart';
import 'package:runwise/domain/start_time_scoring.dart';
import 'package:runwise/domain/weather_correction.dart';
import 'package:runwise/domain/weekly_load.dart';
import 'package:runwise/domain/verdict.dart';
import 'package:runwise/domain/dashboard_layout.dart';
import 'package:runwise/domain/run_filter.dart';
import 'package:runwise/domain/intervals.dart';
import 'package:runwise/domain/run_export.dart';
import 'package:runwise/domain/route_drawing.dart';
import 'package:runwise/domain/route_photos.dart';
import 'package:runwise/domain/best_efforts.dart';
import 'package:runwise/domain/heart_rate.dart';
import 'package:runwise/domain/run_coach.dart';
import 'package:runwise/domain/run_file_import.dart';
import 'package:runwise/domain/training_load.dart';

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

  group('maanduitdaging', () {
    Activity on(DateTime d, double km) => Activity(startedAt: d, distanceMeters: km * 1000, movingTimeSeconds: (km * 330).round());

    test('voorstel uit vorige maanden', () {
      final runs = [
        on(DateTime(2026, 9, 3), 40),
        on(DateTime(2026, 8, 3), 50),
        on(DateTime(2026, 7, 3), 60),
        on(DateTime(2026, 6, 3), 500), // te lang geleden
      ];
      expect(suggestedGoalKm(runs, DateTime(2026, 10, 17)), 55);
      expect(suggestedGoalKm(const [], DateTime(2026, 10, 17)), 30);
      expect(kmInMonth(runs, DateTime(2026, 9, 30)), 40);
    });

    test('voortgang en schema', () {
      final p = GoalProgress(targetKm: 62, doneKm: 20, now: DateTime(2026, 10, 17, 12));
      expect(p.totalDays, 31);
      expect(p.daysLeft, 15);
      expect(p.expectedKm, closeTo(32, 0.01));
      expect(p.aheadKm, closeTo(-12, 0.01));
      expect(p.statusText, contains('achter'));
      expect(p.neededPerWeek, closeTo(42 / 15 * 7, 0.01));
      final done = GoalProgress(targetKm: 50, doneKm: 53.4, now: DateTime(2026, 10, 30));
      expect(done.achieved, isTrue);
      expect(done.fraction, 1);
      expect(done.statusText, 'Gehaald, en 3 km extra!');
    });
  });

  group('live delen', () {
    test('token is lang en zonder rare tekens', () {
      final a = newLiveToken(), b = newLiveToken();
      expect(a.length, 32);
      expect(RegExp(r'^[A-Za-z0-9]{32}$').hasMatch(a), isTrue);
      expect(a, isNot(b));
    });

    test('niet te vaak versturen', () {
      final t0 = DateTime(2026, 10, 19, 10);
      expect(shouldSend(now: t0), isTrue);
      expect(shouldSend(now: t0.add(const Duration(seconds: 8)), lastAt: t0, movedMeters: 20), isFalse);
      expect(shouldSend(now: t0.add(const Duration(seconds: 8)), lastAt: t0, movedMeters: 80), isTrue);
      expect(shouldSend(now: t0.add(const Duration(seconds: 16)), lastAt: t0, movedMeters: 0), isTrue);
    });
  });

  group('runs automatisch aan routes koppelen', () {
    // Vierkant rondje van ~4 km rond (52.0, 5.0), punten om de ~50 m.
    List<LatLng> square(double lat0, double lon0, {double sideDeg = 0.009}) {
      final lonSide = sideDeg / 0.6157; // even lang in meters
      final corners = [
        LatLng(lat0, lon0),
        LatLng(lat0, lon0 + lonSide),
        LatLng(lat0 + sideDeg, lon0 + lonSide),
        LatLng(lat0 + sideDeg, lon0),
        LatLng(lat0, lon0),
      ];
      final pts = <LatLng>[];
      for (var c = 0; c < 4; c++) {
        for (var i = 0; i < 20; i++) {
          final f = i / 20;
          final a = corners[c], b = corners[c + 1];
          pts.add(LatLng(a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f));
        }
      }
      return pts..add(corners.first);
    }

    final home = square(52.0, 5.0);
    final other = square(52.03, 5.05);
    final routes = [MatchableRoute('thuis', home), MatchableRoute('ander', other)];

    test('zelfde rondje, andersom en elders gestart, met GPS-ruis', () {
      // Start halverwege, loop andersom, en schuif alles ~20 m op.
      final shifted = [for (final p in home) LatLng(p.lat + 0.00018, p.lon)];
      final run = [...shifted.sublist(30), ...shifted.sublist(1, 31)].reversed.toList();
      final m = matchRun(run, routes);
      expect(m, isNotNull);
      expect(m!.routeId, 'thuis');
      expect(m.score, greaterThan(0.95));
    });

    test('ander rondje of maar een stukje: geen koppeling', () {
      expect(matchRun(square(52.1, 5.2), routes), isNull);
      expect(matchRun(home.sublist(0, 40), routes), isNull);
      // Groter rondje dat de route deels volgt.
      expect(matchRun(square(52.0, 5.0, sideDeg: 0.013), routes), isNull);
    });

    test('Strava-polyline (alleen hoekpunten) wordt ook herkend', () {
      final sparse = [home[0], home[20], home[40], home[60], home[80]];
      expect(matchRun(sparse, routes)?.routeId, 'thuis');
    });
  });

  group('foutmeldingen', () {
    test('zelfde fout herkennen en lange teksten inkorten', () {
      final st = StackTrace.fromString('#0      foo (package:runwise/a.dart:10)\n#1      bar (package:runwise/b.dart:2)');
      final a = ErrorReporter.fingerprint(StateError('kapot'), st);
      final b = ErrorReporter.fingerprint(StateError('kapot'), st);
      expect(a, b);
      expect(a, isNot(ErrorReporter.fingerprint(StateError('anders'), st)));
      expect(ErrorReporter.clip('x' * 3000, 2000).length, 2000);
      expect(ErrorReporter.clip('kort', 2000), 'kort');
    });
  });

  group('privacyzone', () {
    test('begin en eind worden verborgen', () {
      final east = [for (var i = 0; i <= 20; i++) LatLng(52.0, 5.0 + 0.0292 * i / 20)]; // 2 km
      final trimmed = trimPrivacyZone(east, radius: 300);
      expect(distanceMeters(trimmed.first, east.first), greaterThanOrEqualTo(300));
      expect(distanceMeters(trimmed.last, east.last), greaterThanOrEqualTo(300));
      expect(trimmed.length, lessThan(east.length));
      // Rondje: start en finish op dezelfde plek, beide kanten weg.
      final loop = [...east, ...east.reversed.skip(1)];
      final t2 = trimPrivacyZone(loop, radius: 300);
      expect(distanceMeters(t2.first, loop.first), greaterThanOrEqualTo(300));
      expect(distanceMeters(t2.last, loop.first), greaterThanOrEqualTo(300));
      // Te kort: niets over.
      expect(trimPrivacyZone(east.sublist(0, 4), radius: 300), isEmpty);
      expect(trimPrivacyZone(east, radius: 0), east);
    });
  });

  group('route naar horloge', () {
    test('GPX maken en weer inlezen', () {
      final pts = [for (var i = 0; i <= 20; i++) LatLng(52.0, 5.0 + 0.0292 * i / 20)];
      final prof = [const ElevationSample(0, 10), const ElevationSample(2000, 30)];
      final gpx = buildGpx('Rondje & <test>', pts, profile: prof);
      expect(gpx, contains('Rondje &amp; &lt;test&gt;'));
      expect(RegExp('<trkpt').allMatches(gpx).length, 21);
      expect(gpx, contains('<ele>10.0</ele>'));
      final back = parseGpx(gpx, fallbackName: 'x');
      expect(back.distanceMeters, closeTo(2000, 30));
      expect(back.name, 'Rondje & <test>');
    });
  });

  group('waarschuwingen', () {
    final t0 = DateTime(2026, 10, 20, 17, 0);
    Forecast fc(HourWeather Function(DateTime t) make) => Forecast(
          latitude: 52,
          longitude: 5.6,
          hours: [for (var h = -1; h < 6; h++) make(t0.add(Duration(hours: h)))],
          quarters: [for (var q = -4; q < 24; q++) make(t0.add(Duration(minutes: 15 * q)))],
        );
    HourWeather w(DateTime t, {double temp = 12, double gust = 20, int code = 2, bool day = true, double rain = 0}) =>
        HourWeather(time: t, temperature: temp, feelsLike: temp, windSpeed: 10, windGusts: gust, weatherCode: code, isDay: day, precipitation: rain);

    test('rustig weer: geen waarschuwingen', () {
      expect(runWarnings(fc((t) => w(t)), t0, 60), isEmpty);
    });

    test('onweer, windstoten en hitte', () {
      final list = runWarnings(fc((t) => w(t, temp: 31, gust: 65, code: 95)), t0, 60);
      expect(list.map((x) => x.kind), containsAll(['thunder', 'gusts', 'heat']));
      expect(list.first.level, WarningLevel.danger);
      expect(list.firstWhere((x) => x.kind == 'heat').text, contains('s/km'));
    });

    test('glad en donker', () {
      final ice = runWarnings(fc((t) => w(t, temp: 0.5, rain: 0.4, code: 61)), t0, 45);
      expect(ice.single.kind, 'ice');
      expect(ice.single.level, WarningLevel.danger);
      // Na 17:45 wordt het donker; een run van 60 minuten eindigt in het donker.
      final dark = runWarnings(fc((t) => w(t, day: t.isBefore(t0.add(const Duration(minutes: 45))))), t0, 60);
      expect(dark.single.kind, 'dark');
      expect(dark.single.text, contains('17:45'));
    });

    test('luchtkwaliteit en pollen', () {
      final json = {
        'hourly': {
          'time': ['2026-10-20T17:00'],
          'european_aqi': [72],
          'grass_pollen': [80],
          'birch_pollen': [12],
        }
      };
      final aq = AirQualityService.parse(json);
      final at = airAt(aq, t0.add(const Duration(minutes: 20)));
      expect(at?.europeanAqi, 72);
      final list = runWarnings(fc((t) => w(t)), t0, 30, air: at);
      expect(list.map((x) => x.kind), containsAll(['air', 'pollen']));
      expect(list.firstWhere((x) => x.kind == 'pollen').title, 'Veel graspollen');
    });
  });

  group('tijden per km', () {
    // 3,05 km: eerste km in 300 s, tweede in 330 s, derde in 280 s, laatste 50 m bij de derde.
    final t = <double>[], d = <double>[], alt = <double>[], hr = <double>[];
    for (var m = 0.0; m <= 3050; m += 10) {
      final sec = m <= 1000 ? m * 0.3 : m <= 2000 ? 300 + (m - 1000) * 0.33 : 630 + (m - 2000) * 0.28;
      t.add(sec);
      d.add(m);
      alt.add(m < 1500 ? m / 100 : 15 - (m - 1500) / 200);
      hr.add(m < 1000 ? 140 : 155);
    }
    final json = {'t': t, 'd': d, 'alt': alt, 'hr': hr};

    test('splits met tempo, hartslag en hoogte', () {
      final s = RunStreams.fromJson(json)!;
      final sp = splitsOf(s);
      expect(sp.length, 3);
      expect(sp[0].paceSecPerKm, closeTo(300, 1));
      expect(sp[1].paceSecPerKm, closeTo(330, 1));
      expect(sp[2].meters, closeTo(1050, 1));
      expect(sp[0].heartRate, closeTo(140, 1));
      expect(sp[0].elevationGain, closeTo(10, 0.5));
      final ex = extremes(sp);
      expect(ex.fastest?.index, 3);
      expect(ex.slowest?.index, 2);
    });

    test('tempo-lijn en onvolledige gegevens', () {
      final s = RunStreams.fromJson(json)!;
      final p = paceSeries(s);
      expect(p, isNotEmpty);
      expect(p.first.pace, closeTo(300, 5));
      expect(RunStreams.fromJson({'t': [0], 'd': [0]}), isNull);
      expect(RunStreams.fromJson(null), isNull);
    });
  });

  group('weekoverzicht', () {
    final now = DateTime(2026, 10, 22, 12); // woensdag
    Activity r(DateTime t, double km) => Activity(startedAt: t, distanceMeters: km * 1000, movingTimeSeconds: (km * 330).round());

    test('weken, reeks en opbouw', () {
      final runs = [
        r(DateTime(2026, 10, 21), 14), r(DateTime(2026, 10, 19, 8), 12), // deze week en 20 okt
        r(DateTime(2026, 10, 14), 8), // vorige week
        r(DateTime(2026, 10, 7), 8),
        r(DateTime(2026, 9, 30), 8),
        r(DateTime(2026, 9, 23), 8),
      ];
      final w = weeklyTotals(runs, now);
      expect(w.length, 8);
      expect(w.last.start, DateTime(2026, 10, 19));
      expect(w.last.km, 26);
      expect(w.last.runs, 2);
      expect(weekStreak(runs, now), 5);
      final c = loadCheck(runs, now);
      expect(c.last7Km, 26);
      expect(c.previousAvgKm, 8);
      expect(c.tooFast, isTrue);
      expect(c.message, contains('%'));
    });

    test('reeks loopt door als je deze week nog niet liep', () {
      final runs = [r(DateTime(2026, 10, 14), 5), r(DateTime(2026, 10, 8), 5)];
      expect(weekStreak(runs, now), 2);
      expect(weekStreak(const [], now), 0);
      expect(loadCheck(runs, now).message, isNull);
    });
  });

  group('looptijden', () {
    test('alleen binnen je tijden, hele run moet passen', () {
      final a = Availability.preset('werk');
      final mon = DateTime(2026, 10, 19); // maandag
      expect(a.allows(mon.add(const Duration(hours: 17)), 60), isTrue);
      expect(a.allows(mon.add(const Duration(hours: 21)), 45), isFalse); // eindigt na 21:30
      expect(a.allows(mon.add(const Duration(hours: 12)), 30), isFalse);
      expect(a.allows(DateTime(2026, 10, 25, 9), 90), isTrue); // zondag
      expect(a.firstAllowedInHour(mon.add(const Duration(hours: 16)), 30), isNull);
      final half = Availability({1: const [TimeWindow(17 * 60 + 30, 19 * 60)]});
      expect(half.firstAllowedInHour(mon.add(const Duration(hours: 17)), 30), mon.add(const Duration(hours: 17, minutes: 30)));
      expect(Availability.always.allows(mon.add(const Duration(hours: 3)), 30), isTrue);
      final back = Availability.fromJson(a.toJson());
      expect(back.allows(mon.add(const Duration(hours: 17)), 60), isTrue);
      expect(back.days.length, 7);
    });

    test('planner kiest alleen tijden binnen je looptijden', () {
      final start = DateTime(2026, 10, 19, 6);
      final f = Forecast(latitude: 52, longitude: 5, hours: [for (var h = 0; h < 18; h++) hour(start.add(Duration(hours: h)))]);
      final planner = StartTimePlanner(
        forecast: f,
        profile: PerformanceInsights.defaults,
        durationMinutes: 45,
        availability: Availability({1: const [TimeWindow(18 * 60, 20 * 60)]}),
      );
      final all = planner.scoreAll(TrainingType.easy, from: start, horizon: const Duration(hours: 16));
      expect(all, isNotEmpty);
      expect(all.every((s) => s.start.hour >= 18 && s.start.hour < 20), isTrue);
      final best = planner.bestPrecise(TrainingType.easy, from: start, horizon: const Duration(hours: 16));
      expect(best!.start.hour, inInclusiveRange(18, 19));
    });
  });

  group('run opnemen', () {
    // Loop naar het oosten met 3 m/s (5:33/km), één meting per seconde.
    final t0 = DateTime(2026, 10, 20, 18);
    GpsFix at(int sec, double meters, {double acc = 5, double? speed}) =>
        GpsFix(LatLng(52.0, 5.0 + meters / 68540), t0.add(Duration(seconds: sec)), accuracy: acc, speed: speed);

    test('afstand, tijd en kilometers', () {
      final r = RunRecording()..start(t0);
      final kms = <int>[];
      for (var s = 0; s <= 700; s++) {
        final km = r.add(at(s, s * 3.0));
        if (km != null) kms.add(km);
      }
      expect(r.distance, closeTo(2100, 15));
      expect(r.movingSeconds, closeTo(700, 1));
      expect(kms, [1, 2]);
      expect(r.kmTimes.first, closeTo(333, 3));
      expect(r.averagePace, closeTo(333, 3));
      expect(r.currentPace, closeTo(333, 5));
      expect(kmAnnouncement(r, 2), contains('Kilometer 2.'));
      expect(r.simplifiedTrack().length, inInclusiveRange(70, 120));
    });

    test('automatisch pauzeren bij stilstaan en GPS-sprongen negeren', () {
      final r = RunRecording()..start(t0);
      var s = 0;
      for (; s <= 60; s++) {
        r.add(at(s, s * 3.0));
      }
      // 30 seconden stil bij een stoplicht.
      for (var i = 1; i <= 30; i++) {
        r.add(at(s + i, 180, speed: 0));
      }
      expect(r.status, RecorderStatus.autoPaused);
      final movingBefore = r.movingSeconds;
      expect(movingBefore, lessThan(75));
      // Weer lopen.
      for (var i = 1; i <= 20; i++) {
        r.add(at(s + 30 + i, 180 + i * 3.0, speed: 3));
      }
      expect(r.status, RecorderStatus.running);
      // Onnauwkeurig en een sprong van 500 m: niet meetellen.
      final d = r.distance;
      r.add(at(s + 51, 300, acc: 80));
      r.add(at(s + 52, 800));
      expect(r.distance, closeTo(d, 0.01));
    });

    test('stem: tijden uitspreken', () {
      expect(spokenPace(332), '5 minuten 32');
      expect(spokenPace(300), '5 minuten');
      expect(spokenDuration(3725), '1 uur 2 minuten');
      expect(spokenDuration(1420), '23 minuten 40');
    });
  });

  group('oordeel bovenaan', () {
    StartTimeScore sc(DateTime t, int score, [List<String> r = const ['Weinig wind']]) =>
        StartTimeScore(start: t, score: score, weather: hour(t), reasons: r);
    final t = DateTime(2026, 10, 20, 17);
    test('nu lopen als nu bijna net zo goed is', () {
      final v = runVerdict(sc(t, 78), sc(t.add(const Duration(hours: 2)), 81));
      expect(v.kind, VerdictKind.goNow);
    });
    test('later lopen als wachten duidelijk beter is', () {
      final v = runVerdict(sc(t, 50), sc(t.add(const Duration(hours: 2)), 80));
      expect(v.kind, VerdictKind.later);
      expect(v.title, 'Later lopen: 19:00');
      expect(v.detail, startsWith('30 punten beter dan nu'));
    });
    test('vandaag lastig', () {
      expect(runVerdict(sc(t, 20), sc(t, 35)).kind, VerdictKind.tough);
    });
    test('nu valt buiten je looptijden', () {
      expect(runVerdict(sc(t, 80), sc(t, 80), nowAllowed: false).kind, VerdictKind.later);
    });
    test('alleen goede uren', () {
      expect(goodHoursOnly([sc(t, 40), sc(t, 75), sc(t, 90)]).length, 2);
    });
  });

  group('indeling Vandaag', () {
    test('opslaan, lezen en nieuwe kaarten achteraan', () {
      final l = DashLayout.standard.move(DashCard.values.indexOf(DashCard.month), 0).toggle(DashCard.rain);
      final back = DashLayout.decode(l.encode());
      expect(back.order.first, DashCard.month);
      expect(back.hidden, {DashCard.rain});
      expect(back.visible, isNot(contains(DashCard.rain)));
      final old = DashLayout.decode('month,-rain,onbekend');
      expect(old.order.length, DashCard.values.length);
      expect(old.order.first, DashCard.month);
    });
  });

  group('runs filteren en per periode', () {
    Activity run(DateTime t, double km, {String source = 'runwise', double? wind, String? note}) =>
        Activity(startedAt: t, distanceMeters: km * 1000, movingTimeSeconds: (km * 330).round(), source: source, windSpeedKmh: wind, note: note);
    final now = DateTime(2026, 10, 21, 12); // woensdag
    final runs = [
      run(DateTime(2026, 10, 19, 8), 5),
      run(DateTime(2026, 10, 21, 7), 12, source: 'strava', wind: 25),
      run(DateTime(2026, 9, 3, 7), 8, note: 'zwaar'),
      run(DateTime(2025, 6, 1, 7), 21.2),
    ];
    test('maand en jaar', () {
      final m = periodTotals(runs, now, Period.month, count: 3);
      expect(m.last.km, closeTo(17, 0.01));
      expect(m[1].km, closeTo(8, 0.01));
      final y = periodTotals(runs, now, Period.year, count: 2);
      expect(y.first.km, closeTo(21.2, 0.01));
      expect(y.last.runs, 3);
    });
    test('weekstrook', () {
      final s = weekStrip(runs, now);
      expect(s.length, 7);
      expect(s[0].km, closeTo(5, 0.01));
      expect(s[2].isToday, isTrue);
      expect(s[3].isFuture, isTrue);
    });
    test('filters', () {
      expect(const RunFilter(band: DistanceBand.mid).apply(runs).length, 2);
      expect(const RunFilter(source: 'strava').apply(runs).length, 1);
      expect(const RunFilter(windyOnly: true).apply(runs).length, 1);
      expect(const RunFilter(withNote: true).apply(runs).length, 1);
      expect(const RunFilter().isEmpty, isTrue);
      expect(const RunFilter(band: DistanceBand.long, windyOnly: true).activeCount, 2);
    });
    test('export', () {
      final csv = runsCsv(runs);
      expect(csv.split('\n').where((l) => l.isNotEmpty).length, 6);
      expect(csv, contains('2025-06-01;07:00;21.20'));
      final gpx = runsGpx([
        Activity(startedAt: now, distanceMeters: 1000, movingTimeSeconds: 300,
            trackPolyline: encodePolyline(const [LatLng(52, 5), LatLng(52.001, 5), LatLng(52.002, 5)])),
      ]);
      expect('<trk>'.allMatches(gpx).length, 1);
      expect('<trkpt'.allMatches(gpx).length, 3);
    });
  });

  group('intervallen', () {
    test('schema bouwen', () {
      final p = IntervalPlan.build(reps: 6, workMeters: 400, restSeconds: 90);
      expect(p.name, '6 × 400 m');
      expect(p.reps, 6);
      expect(p.steps.length, 1 + 6 + 5 + 1);
      final back = IntervalPlan.fromJson(p.toJson())!;
      expect(back.steps.length, p.steps.length);
      expect(IntervalPlan.build(reps: 4, workMeters: 1000, restSeconds: 60).name, '4 × 1 km');
      expect(IntervalPlan.presets.length, greaterThanOrEqualTo(4));
    });
    test('stappen doorlopen op tijd en afstand', () {
      final p = IntervalPlan.build(warmupMin: 1, reps: 2, workMeters: 400, restSeconds: 60, cooldownMin: 0);
      final tr = IntervalTracker(p);
      expect(tr.start(0, 0).text, startsWith('Inlopen'));
      final cues = <String>[];
      // 3 m/s, één update per seconde.
      for (var s = 1; s <= 600 && !tr.finished; s++) {
        final c = tr.update(s.toDouble(), s * 3.0);
        if (c != null) cues.add(c.text);
      }
      expect(tr.finished, isTrue);
      expect(cues.where((c) => c.startsWith('Snel!')).length, 2);
      expect(cues.first, startsWith('Nog 10 seconden'));
      expect(cues, contains(startsWith('Nog 100 meter')));
      expect(cues.last, startsWith('Intervallen klaar'));
    });
  });

  group('route tekenen', () {
    const a = LatLng(52, 5), b = LatLng(52.01, 5), c = LatLng(52.01, 5.01);
    test('vormen', () {
      expect(drawWaypoints([a, b, c], DrawShape.open).length, 3);
      expect(drawWaypoints([a, b, c], DrawShape.loop).last, a);
      expect(drawWaypoints([a, b, c], DrawShape.outAndBack), [a, b, c, b, a]);
      expect(straightLength([a, b]), closeTo(1112, 5));
    });
  });

  group('GPS-ruis', () {
    test('stilstaan zonder autopauze telt geen afstand', () {
      final t0 = DateTime(2026, 10, 20, 18);
      final r = RunRecording(autoPause: false)..start(t0);
      for (var s = 0; s <= 60; s++) {
        // Ruis van ±1,5 m rond hetzelfde punt, nauwkeurigheid 10 m.
        final jitter = (s % 2 == 0 ? 1 : -1) * 1.5 / 68540;
        r.add(GpsFix(LatLng(52.0, 5.0 + jitter), t0.add(Duration(seconds: s)), accuracy: 10));
      }
      expect(r.distance, lessThan(5));
      expect(r.movingSeconds, greaterThan(40));
    });
  });

  group('foto\'s langs de route', () {
    // Route van 3 km naar het oosten.
    final t = RouteTrack([for (var i = 0; i <= 30; i++) LatLng(52.0, 5.0 + i * 100 / 68540)]);
    test('punten gelijkmatig verdeeld met looprichting', () {
      final s = photoSamples(t, every: 500);
      expect(s.length, 6);
      expect(s.first.meters, closeTo(250, 5));
      expect(s.first.bearing, closeTo(90, 2));
      expect(photoSamples(t, max: 3).length, 3);
    });
    test('straatfoto\'s van de server', () {
      final s = photoSamples(t, every: 500);
      final photos = parseStreetPhotos({
        'photos': [
          {'index': 2, 'id': 'b', 'url': 'https://x/b.jpg', 'lat': 52.0, 'lon': 5.02, 'captured_at': 1700000000000, 'creator': 'piet'},
          {'index': 0, 'id': 'a', 'url': 'https://x/a.jpg', 'lat': 52.0, 'lon': 5.004},
          {'index': 99, 'id': 'z', 'url': 'https://x/z.jpg', 'lat': 52.0, 'lon': 5.0},
        ],
      }, s);
      expect(photos.length, 2);
      expect(photos.first.url, 'https://x/a.jpg');
      expect(photos.last.credit, contains('piet'));
      expect(photos.last.link, contains('pKey=b'));
    });
    test('bezienswaardigheden dicht bij de route', () {
      final body = '{"query":{"pages":['
          '{"title":"Molen De Hoop","coordinates":[{"lat":52.0005,"lon":5.0146}],"thumbnail":{"source":"https://w/m.jpg"},"description":"molen"},'
          '{"title":"Ver weg","coordinates":[{"lat":52.02,"lon":5.01}],"thumbnail":{"source":"https://w/v.jpg"}},'
          '{"title":"Zonder foto","coordinates":[{"lat":52.0,"lon":5.01}]}'
          ']}}';
      final l = parseWikipediaLandmarks(body, t);
      expect(l.length, 1);
      expect(l.first.title, 'Molen De Hoop');
      expect(l.first.meters, closeTo(1000, 30));
      expect(l.first.link, contains('Molen_De_Hoop'));
      final merged = mergeRoutePhotos([
        RoutePhoto(source: PhotoSource.street, url: 'a', thumb: 'a', point: t.at(950), meters: 950),
        RoutePhoto(source: PhotoSource.street, url: 'b', thumb: 'b', point: t.at(2000), meters: 2000),
      ], l);
      expect(merged.length, 2);
      expect(merged.first.source, PhotoSource.landmark);
    });
    test('vakje om de route', () {
      final b = routeBounds(t.points, marginM: 200);
      expect(b.south, lessThan(52.0));
      expect(b.east, greaterThan(5.0438));
    });
  });

  group('snelste stukken en verloop van eigen opnames', () {
    test('snelste km midden in een run', () {
      // 3 km: eerste en laatste km in 6:00, middelste in 4:30.
      final t = <double>[], d = <double>[];
      for (var m = 0; m <= 3000; m += 10) {
        d.add(m.toDouble());
        final sec = m <= 1000 ? m * 0.36 : (m <= 2000 ? 360 + (m - 1000) * 0.27 : 630 + (m - 2000) * 0.36);
        t.add(sec);
      }
      final s = RunStreams(time: t, distance: d);
      final b = bestEfforts(s);
      final km = b.firstWhere((e) => e.meters == 1000);
      expect(km.seconds, closeTo(270, 1));
      expect(km.startMeters, closeTo(1000, 15));
      expect(b.any((e) => e.meters == 5000), isFalse);
      final json = bestEffortsToJson(b);
      expect(json['1000'], closeTo(270, 1));
      final overall = bestOverall([(id: 'a', efforts: {'1000': 280.0}), (id: 'b', efforts: json)]);
      expect(overall[1000]!.activityId, 'b');
      expect(bestEffortLabel(5000), '5 km');
    });

    test('opname bewaart verloop met hoogte en hartslag', () {
      final t0 = DateTime(2026, 10, 20, 18);
      final r = RunRecording()..start(t0);
      for (var s = 0; s <= 400; s++) {
        r.heartRate = 140 + (s ~/ 100);
        r.add(GpsFix(LatLng(52.0, 5.0 + s * 3.0 / 68540), t0.add(Duration(seconds: s)),
            accuracy: 5, altitude: 10 + (s % 7).toDouble()));
      }
      final j = r.streamsJson()!;
      final parsed = RunStreams.fromJson(j)!;
      expect(parsed.length, greaterThan(100));
      expect(parsed.altitude, isNotNull);
      expect(parsed.heartRate, isNotNull);
      expect(parsed.totalDistance, closeTo(1200, 15));
      expect(splitsOf(parsed).first.paceSecPerKm, closeTo(333, 5));
      expect(r.averageHeartRate, inInclusiveRange(140, 144));
    });
  });

  group('hartslagband', () {
    test('meting lezen (8 en 16 bits)', () {
      expect(parseHeartRateMeasurement([0x00, 142]), 142);
      expect(parseHeartRateMeasurement([0x01, 0x2C, 0x01]), 300);
      expect(parseHeartRateMeasurement([0x16, 75, 0x10, 0x03]), 75);
      expect(parseHeartRateMeasurement([0x01, 5]), isNull);
    });
    test('zones', () {
      expect(heartRateZone(110, 190), 1);
      expect(heartRateZone(125, 190), 2);
      expect(heartRateZone(150, 190), 3);
      expect(heartRateZone(160, 190), 4);
      expect(heartRateZone(180, 190), 5);
    });
  });

  group('ronde 2: opname veilig, coach, belasting, import', () {
    final t0 = DateTime(2026, 10, 20, 18);
    RunRecording sampleRun(int seconds) {
      final r = RunRecording()..start(t0);
      for (var s = 0; s <= seconds; s++) {
        r.add(GpsFix(LatLng(52.0, 5.0 + s * 3.0 / 68540), t0.add(Duration(seconds: s)), accuracy: 5, altitude: 10));
      }
      return r;
    }

    test('onderbroken run terughalen', () {
      final r = sampleRun(400);
      final back = RunRecording.fromSnapshot(r.toSnapshot())!;
      expect(back.distance, closeTo(r.distance, 0.01));
      expect(back.movingSeconds, closeTo(r.movingSeconds, 0.01));
      expect(back.samples.length, r.samples.length);
      expect(back.track.length, r.track.length);
      expect(back.status, RecorderStatus.paused);
      expect(back.startedAt, t0);
      expect(RunRecording.fromSnapshot({'v': 9}), isNull);
    });

    test('loopband: klok zonder GPS', () {
      final r = RunRecording(indoor: true)..start(t0);
      for (var i = 0; i < 600; i++) {
        r.tick(1);
      }
      r.pause();
      r.tick(100);
      r.setIndoorDistance(1800);
      expect(r.movingSeconds, 600);
      expect(r.averagePace, closeTo(333, 1));
    });

    test('stemmeldingen op afstand en op tijd', () {
      final r = RunRecording()..start(t0);
      final km = CueScheduler(const CueSettings());
      final min5 = CueScheduler(const CueSettings(every: CueEvery.fiveMin));
      final kmCues = <String>[], timeCues = <String>[];
      for (var s = 0; s <= 700; s++) {
        r.add(GpsFix(LatLng(52.0, 5.0 + s * 3.0 / 68540), t0.add(Duration(seconds: s)), accuracy: 5));
        if (km.update(r, heartRate: 150) case final c?) kmCues.add(c);
        if (min5.update(r) case final c?) timeCues.add(c);
      }
      expect(kmCues.length, 2);
      expect(kmCues.first, startsWith('1 kilometer.'));
      expect(kmCues.first, contains('Hartslag 150.'));
      expect(timeCues.length, 2);
      expect(timeCues.first, startsWith('5 minuten.'));
      expect(const CueSettings(every: CueEvery.twoKm).toJson()['e'], 'twoKm');
      expect(CueSettings.fromJson({'e': 'halfKm', 'h': false}).heartRate, isFalse);
    });

    test('doeltempo-coach', () {
      final c = PaceCoach(330);
      final said = <String>[];
      // 60 s te langzaam (6:00), dan op tempo.
      for (var t = 0; t < 60; t++) {
        if (c.update(t.toDouble(), 360) case final s?) said.add(s);
      }
      for (var t = 60; t < 90; t++) {
        if (c.update(t.toDouble(), 332) case final s?) said.add(s);
      }
      expect(said.first, startsWith('Iets sneller'));
      expect(said.where((s) => s.startsWith('Iets sneller')).length, 1);
      expect(said.last, startsWith('Mooi'));
      expect(PaceCoach(330).update(30, 290), isNull);
    });

    test('fitheid en vorm', () {
      final now = DateTime(2026, 10, 20);
      final runs = [
        for (var i = 1; i <= 60; i++)
          if (i % 2 == 0)
            Activity(startedAt: now.subtract(Duration(days: i)), distanceMeters: 8000, movingTimeSeconds: 8 * 330),
      ];
      final series = fitnessSeries(runs, now, days: 30);
      expect(series.length, 30);
      expect(series.last.fitness, greaterThan(10));
      expect(estimateThresholdPace(runs), closeTo(340, 5));
      final hard = [...runs, for (var i = 0; i < 6; i++) Activity(startedAt: now.subtract(Duration(days: i)), distanceMeters: 15000, movingTimeSeconds: 15 * 300)];
      expect(fitnessSeries(hard, now, days: 10).last.form, lessThan(series.last.form));
      expect(formAdvice(FitnessDay(now, 0, 2, 1)).title, 'Opbouwen');
      final withHr = Activity(startedAt: now, distanceMeters: 10000, movingTimeSeconds: 3600, averageHeartRate: 165);
      expect(runLoad(withHr, thresholdPace: 330, maxHr: 190), inInclusiveRange(60, 140));
    });

    test('run uit GPX en TCX importeren', () {
      final gpx = StringBuffer('<?xml version="1.0"?><gpx xmlns="http://www.topografix.com/GPX/1/1" '
          'xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"><trk><name>Ochtendrun</name><trkseg>');
      for (var s = 0; s <= 400; s += 2) {
        final time = t0.toUtc().add(Duration(seconds: s)).toIso8601String();
        gpx.write('<trkpt lat="52.0" lon="${5.0 + s * 3.0 / 68540}"><ele>${10 + s % 5}</ele><time>$time</time>'
            '<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>${140 + s % 10}</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions></trkpt>');
      }
      gpx.write('</trkseg></trk></gpx>');
      final r = parseRunFile(gpx.toString());
      expect(r.distanceMeters, closeTo(1200, 15));
      expect(r.movingSeconds, closeTo(400, 3));
      expect(r.averageHeartRate, inInclusiveRange(140, 150));
      expect(r.name, 'Ochtendrun');
      expect(RunStreams.fromJson(r.streams)!.heartRate, isNotNull);

      final tcx = StringBuffer('<?xml version="1.0"?><TrainingCenterDatabase><Activities><Activity Sport="Running"><Lap><Track>');
      for (var s = 0; s <= 400; s += 5) {
        tcx.write('<Trackpoint><Time>${t0.toUtc().add(Duration(seconds: s)).toIso8601String()}</Time>'
            '<DistanceMeters>${s * 3}</DistanceMeters><HeartRateBpm><Value>150</Value></HeartRateBpm></Trackpoint>');
      }
      tcx.write('</Track></Lap></Activity></Activities></TrainingCenterDatabase>');
      final r2 = parseRunFile(tcx.toString());
      expect(r2.distanceMeters, closeTo(1200, 1));
      expect(r2.track, isEmpty);
      expect(r2.averageHeartRate, 150);
      expect(() => parseRunFile('<foo/>'), throwsA(isA<RunFileException>()));
    });
  });
}
