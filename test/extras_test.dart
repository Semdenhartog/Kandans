import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/extras.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/start_time_scoring.dart';

void main() {
  Activity run(DateTime d, double km, {String? route, int? sec}) =>
      Activity(startedAt: d, distanceMeters: km * 1000, movingTimeSeconds: sec ?? (km * 330).round(), routeId: route);
  RunRoute route(String id) => RunRoute(
      id: id, name: 'Rondje $id', source: 'drawn', distanceMeters: 5000, startLatitude: 52, startLongitude: 5.6, polyline: '');

  group('nog een keer', () {
    test('laatste route die nog bestaat, met aantal keer', () {
      final runs = [
        run(DateTime(2026, 10, 1), 5, route: 'a'),
        run(DateTime(2026, 10, 10), 8, route: 'weg'),
        run(DateTime(2026, 10, 5), 5, route: 'a'),
        run(DateTime(2026, 10, 12), 4),
      ];
      final r = lastRouteAgain(runs, [route('a'), route('b')]);
      expect(r!.route.id, 'a');
      expect(r.run.startedAt, DateTime(2026, 10, 5));
      expect(r.times, 2);
      expect(lastRouteAgain([run(DateTime(2026, 1, 1), 5)], [route('a')]), isNull);
    });

    test('dagen in woorden', () {
      expect(daysAgoWords(0), 'vandaag');
      expect(daysAgoWords(1), 'gisteren');
      expect(daysAgoWords(5), '5 dagen geleden');
      expect(daysAgoWords(21), '3 weken geleden');
      expect(daysAgoWords(90), '3 maanden geleden');
      expect(calendarDaysBetween(DateTime(2026, 10, 1, 23), DateTime(2026, 10, 2, 1)), 1);
    });
  });

  test('op deze dag: langste run per jaar, nieuwste eerst', () {
    final now = DateTime(2026, 10, 22, 9);
    final list = onThisDay([
      run(DateTime(2025, 10, 22, 7), 5),
      run(DateTime(2025, 10, 22, 18), 10),
      run(DateTime(2023, 10, 22), 3),
      run(DateTime(2025, 10, 21), 21),
      run(DateTime(2026, 10, 22, 7), 6),
    ], now);
    expect(list.map((e) => e.yearsAgo), [1, 3]);
    expect(list.first.run.distanceMeters, 10000);
  });

  test('gouden uur: eerstvolgende, vandaag of morgen', () {
    // Barneveld, eind oktober: zon onder rond 18:20 (zomertijd).
    final g = nextGoldenHour(DateTime(2026, 10, 22, 12), 52.14, 5.58)!;
    expect(g.evening, isTrue);
    expect(g.end.difference(g.start).inMinutes, 60);
    final night = nextGoldenHour(DateTime(2026, 10, 22, 22), 52.14, 5.58)!;
    expect(night.evening, isFalse);
    expect(night.start.day, 23);
  });

  test('jaardoel: voorspelling en nodig per week', () {
    final p = YearGoalProgress(targetKm: 1000, doneKm: 500, now: DateTime(2026, 7, 2));
    expect(p.dayOfYear, 183);
    expect(p.daysInYear, 365);
    expect(p.projectedKm, closeTo(997, 1));
    expect(p.onTrack, isFalse);
    expect(p.neededPerWeek, closeTo(500 / 183 * 7, 0.2));
    expect(kmInYear([run(DateTime(2026, 1, 3), 10), run(DateTime(2025, 12, 31), 10)], DateTime(2026, 5, 1)), 10);
  });

  test('hoogtemeters vergelijken', () {
    expect(climbComparison(0), 'Nog geen hoogtemeters.');
    expect(climbComparison(35), 'Dat is 51% van de Amerongse Berg.');
    expect(climbComparison(138), 'Dat is 1,2× de Domtoren.');
    expect(climbComparison(100), 'Dat is 1,4× de Amerongse Berg.');
    expect(climbComparison(250), 'Dat is 1,4× de Euromast.');
    expect(climbComparison(9000), 'Dat is 1,0× de Mount Everest.');
    expect(climbComparison(3300), 'Dat is 10× de Vaalserberg, het hoogste punt van Nederland.');
  });

  test('hersteltip hangt af van duur, hartslag en warmte', () {
    expect(recoveryTip(movingSeconds: 1800).title, 'Herstel: gewoon eten is genoeg');
    expect(recoveryTip(movingSeconds: 3000).title, 'Herstel');
    expect(recoveryTip(movingSeconds: 5400).title, 'Herstel na een stevige run');
    expect(recoveryTip(movingSeconds: 1800, avgHeartRate: 175, maxHeartRate: 190).title, 'Herstel na een stevige run');
    expect(recoveryTip(movingSeconds: 1800, temperature: 26).text, contains('zouts'));
  });

  test('nieuwe wegen', () {
    // Oude run: 1 km naar het oosten. Nieuwe run: dezelfde km en dan 500 m naar het noorden.
    final old = [for (var i = 0; i <= 10; i++) LatLng(52.0, 5.0 + i * 100 / 68540)];
    final now = [
      ...old,
      for (var i = 1; i <= 5; i++) LatLng(52.0 + i * 100 / 111200, 5.0 + 1000 / 68540),
    ];
    final m = newRoadMeters(now, [old]);
    expect(m, inInclusiveRange(350, 520));
    expect(newRoadMeters(old, [old]), 0);
    expect(newRoadMeters(old, const []), closeTo(1000, 10));
  });

  group('weekend', () {
    test('alleen van donderdag tot en met zaterdag', () {
      expect(weekendPreviewDay(DateTime(2026, 10, 21)), isFalse); // woensdag
      expect(weekendPreviewDay(DateTime(2026, 10, 22)), isTrue); // donderdag
      expect(weekendPreviewDay(DateTime(2026, 10, 24)), isTrue); // zaterdag
      expect(weekendPreviewDay(DateTime(2026, 10, 25)), isFalse); // zondag
    });

    test('tekst noemt de beste dag eerst', () {
      StartTimeScore sc(DateTime t, int score) => StartTimeScore(
          start: t, score: score, weather: HourWeather(time: t, temperature: 11, windSpeed: 10), reasons: const []);
      String time(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
      final text = weekendText((saturday: sc(DateTime(2026, 10, 24, 9, 15), 70), sunday: sc(DateTime(2026, 10, 25, 10, 30), 84)), time);
      expect(text, 'Zondag 10:30 is je beste moment voor een lange duurloop (goed, score 84, 11°). Op zaterdag is 9:15 het best (score 70).');
      expect(weekendText((saturday: null, sunday: null), time), isNull);
    });
  });
}
