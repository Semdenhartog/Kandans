import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/badges.dart';
import 'package:runwise/domain/geo.dart';

Activity _run(DateTime t, {double km = 5, int sec = 1800, Map<String, double>? efforts, String? track, String? routeId, double? feels}) => Activity(
      startedAt: t,
      distanceMeters: km * 1000,
      movingTimeSeconds: sec,
      bestEfforts: efforts,
      trackPolyline: track,
      routeId: routeId,
      feelsLikeCelsius: feels,
    );

String _at(double lat, double lon) => encodePolyline([LatLng(lat, lon), LatLng(lat + 0.01, lon + 0.01)]);

void main() {
  Map<String, Badge> badges(List<Activity> runs, {DateTime? now}) => {for (final b in computeBadges(runs, now: now)) b.id: b};

  test('snelheid: snelste stuk telt, een lange run wordt niet omgerekend', () {
    final b = badges([
      _run(DateTime(2026, 3, 1), km: 12, sec: 3700, efforts: {'5000': 1440, '10000': 2950}),
    ]);
    expect(b['5k_25']!.earned, isTrue);
    expect(b['5k_20']!.earned, isFalse);
    expect(b['10k_50']!.earned, isTrue);
    // Zonder snelste stukken: 12 km in 61 min is géén 5 km onder 25 min.
    final c = badges([_run(DateTime(2026, 3, 1), km: 12, sec: 3660)]);
    expect(c['5k_25']!.earned, isFalse);
    expect(effortSeconds(_run(DateTime(2026, 3, 1), km: 5.1, sec: 1530), 5000), closeTo(1500, 0.5));
  });

  test('volhouden: dagen en maanden op rij', () {
    final days = [for (var i = 0; i < 7; i++) _run(DateTime(2026, 5, 1 + i, 7))];
    final b = badges(days);
    expect(b['days7']!.earnedAt, DateTime(2026, 5, 7, 7));
    final gap = badges([...days.take(3), ...days.skip(4)]);
    expect(gap['days7']!.earned, isFalse);
    expect(gap['days7']!.progress, closeTo(3 / 7, 0.001));

    final months = [for (var m = 0; m < 12; m++) _run(DateTime(2025, 11 + m, 10))];
    expect(badges(months)['months12']!.earned, isTrue);
    expect(badges(months.take(11).toList())['months12']!.progress, closeTo(11 / 12, 0.001));
  });

  test('een jaar loper', () {
    final b = badges([_run(DateTime(2025, 1, 1)), _run(DateTime(2026, 1, 2))], now: DateTime(2026, 2, 1));
    expect(b['year1']!.earned, isTrue);
    final c = badges([_run(DateTime(2025, 10, 1))], now: DateTime(2026, 1, 1));
    expect(c['year1']!.earned, isFalse);
    expect(c['year1']!.progress, closeTo(92 / 365, 0.01));
  });

  test('weer en seizoen', () {
    final b = badges([
      _run(DateTime(2026, 1, 10)),
      _run(DateTime(2026, 4, 10)),
      _run(DateTime(2026, 7, 10), feels: 31),
      _run(DateTime(2026, 10, 10)),
      _run(DateTime(2026, 12, 25, 10)),
      _run(DateTime(2026, 12, 31, 11)),
    ]);
    expect(b['seasons']!.earnedAt, DateTime(2026, 10, 10));
    expect(b['tropical']!.earned, isTrue);
    expect(b['xmas']!.earned, isTrue);
    expect(b['nye']!.earned, isTrue);
    expect(b['midsummer']!.earned, isFalse);
    expect(b['seasons']!.category, BadgeCategory.weather);
  });

  test('ontdekken: routes, plekken en op reis', () {
    final home = [for (var i = 0; i < 4; i++) _run(DateTime(2026, 2, 1 + i), track: _at(52.15, 5.59), routeId: 'r$i')];
    final away = [
      _run(DateTime(2026, 3, 1), track: _at(52.37, 4.90)), // Amsterdam
      _run(DateTime(2026, 3, 2), track: _at(51.92, 4.48)), // Rotterdam
      _run(DateTime(2026, 3, 3), track: _at(51.44, 5.47)), // Eindhoven
      _run(DateTime(2026, 3, 4), track: _at(53.22, 6.57), routeId: 'r9'), // Groningen
    ];
    final b = badges([...home, ...away]);
    expect(b['explorer']!.earned, isTrue);
    expect(b['routes10']!.progress, closeTo(0.5, 0.001));
    expect(b['places5']!.earnedAt, DateTime(2026, 3, 4));
    expect(b['far']!.earnedAt, DateTime(2026, 3, 1));
  });

  test('eerste punt van een polyline zonder alles te ontcijferen', () {
    final enc = encodePolyline(const [LatLng(52.15123, 5.59456), LatLng(52.2, 5.6), LatLng(52.3, 5.7)]);
    final p = firstPolylinePoint(enc)!;
    final full = decodePolyline(enc).first;
    expect(p.lat, closeTo(full.lat, 1e-9));
    expect(p.lon, closeTo(full.lon, 1e-9));
    expect(firstPolylinePoint(''), isNull);
    expect(firstPolylinePoint('?'), isNull);
  });

  test('bestaande badges houden hun id', () {
    final ids = computeBadges(const []).map((b) => b.id).toSet();
    for (final old in ['first', '5k', '10k', 'half', 'full', 'runs10', 'runs50', 'runs100', 'km100', 'km500', 'km1000', 'streak4', 'streak12',
      'early', 'night', 'climb', 'explorer', 'wind', 'storm', 'heat', 'frost', 'humid']) {
      expect(ids, contains(old));
    }
    expect(ids.length, 50);
  });
}
