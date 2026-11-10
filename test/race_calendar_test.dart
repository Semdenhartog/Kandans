import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/race_calendar.dart';

RaceListing race(String name, DateTime d, {double? lat, double? lon, String kind = 'loop'}) => RaceListing.fromRow({
      'key': name,
      'name': name,
      'race_date': '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      'kind': kind,
      'status': 'verleend',
      'source_url': 'u',
      'municipality': 'X',
      'lat': lat,
      'lon': lon,
    })!;

void main() {
  final today = DateTime(2026, 11, 10);
  const barneveld = (lat: 52.14, lon: 5.59);
  final all = [
    race('Ede', DateTime(2026, 12, 1), lat: 52.04, lon: 5.67), // ±12 km
    race('Groningen', DateTime(2026, 11, 20), lat: 53.22, lon: 6.57), // ±140 km
    race('Geweest', DateTime(2026, 11, 1), lat: 52.14, lon: 5.59),
    race('Zonder plek', DateTime(2026, 11, 15)),
    race('Apeldoorn trail', DateTime(2026, 11, 20), lat: 52.21, lon: 5.97, kind: 'trail'), // ±27 km
  ];

  test('afstand', () {
    final km = all.first.kmFrom(barneveld.lat, barneveld.lon)!;
    expect(km, closeTo(12.5, 2));
    expect(all[3].kmFrom(barneveld.lat, barneveld.lon), isNull);
  });

  test('in de buurt, op datum, zonder voorbije', () {
    final near = racesNear(all, lat: barneveld.lat, lon: barneveld.lon, maxKm: 50, today: today);
    expect(near.map((r) => r.name), ['Apeldoorn trail', 'Ede']);
    final nl = racesNear(all, today: today);
    expect(nl.length, 4); // zonder plek telt wél mee bij heel Nederland
    expect(nl.first.name, 'Zonder plek');
    expect(nl.last.name, 'Ede');
  });

  test('alleen één soort', () {
    expect(racesNear(all, kinds: {RaceKind.trail}, today: today).map((r) => r.name), ['Apeldoorn trail']);
  });

  test('gebruikelijke afstand en rij', () {
    expect(race('M', today, kind: 'marathon').typicalMeters, 42195);
    expect(race('H', today, kind: 'halve').typicalMeters, 21097.5);
    expect(race('L', today, kind: 'onbekend').kind, RaceKind.loop);
    final r = race('Ede', DateTime(2026, 12, 1), lat: 52.04, lon: 5.67);
    expect(RaceListing.fromRow(r.toRow())!.date, DateTime(2026, 12, 1));
  });

  test('luchtfototegel', () {
    final t = webMercatorTile(52.14, 5.59, 16);
    expect(t.x, 33785);
    expect(t.y, inInclusiveRange(21600, 21700));
    expect(t.fx, inInclusiveRange(0, 1));
  });
}
