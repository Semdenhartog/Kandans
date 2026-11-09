import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/club_calendar.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/run_paths.dart';

const _ics = '''BEGIN:VCALENDAR\r
VERSION:2.0\r
X-WR-CALNAME:SSS Barneveld\\, agenda\r
BEGIN:VEVENT\r
DTSTART;TZID=Europe/Amsterdam:20261110T193000\r
DTEND;TZID=Europe/Amsterdam:20261110T203000\r
SUMMARY:Rondje SSS <-> Koewei\r
LOCATION:Sportpark Norschoten\\, Barneveld\r
URL:https://sss.example/agenda/1\r
DESCRIPTION:Rustig tempo\\nIedereen welkom\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART;VALUE=DATE:20261212\r
SUMMARY:Veluweloop\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART:20261101T090000Z\r
SUMMARY:Al geweest\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART:20261115T090000Z\r
SUMMARY:Afgelast\r
STATUS:CANCELLED\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART:20261120T080000Z\r
SUMMARY:Lange titel die over\r
 twee regels loopt\r
END:VEVENT\r
END:VCALENDAR\r
''';

void main() {
  final now = DateTime(2026, 11, 9, 23);

  group('clubagenda', () {
    test('naam van de agenda', () => expect(icsCalendarName(_ics), 'SSS Barneveld, agenda'));

    test('leest komende evenementen, ook hele dag; slaat voorbije en afgelaste over', () {
      final e = parseClubIcs(_ics, from: 'SSS', now: now);
      expect(e.map((x) => x.title), ['Rondje SSS <-> Koewei', 'Lange titel die overtwee regels loopt', 'Veluweloop']);
      final first = e.first;
      expect(first.start, DateTime(2026, 11, 10, 19, 30));
      expect(first.location, 'Sportpark Norschoten, Barneveld');
      expect(first.description, 'Rustig tempo\nIedereen welkom');
      expect(first.url, 'https://sss.example/agenda/1');
      expect(first.allDay, isFalse);
      final day = e.last;
      expect(day.allDay, isTrue);
      expect(day.start, DateTime(2026, 12, 12));
    });

    test('alleen binnen het venster', () {
      expect(parseClubIcs(_ics, from: 'SSS', now: now, days: 5).map((x) => x.title), ['Rondje SSS <-> Koewei']);
    });

    test('opslaan en teruglezen', () {
      final e = parseClubIcs(_ics, from: 'SSS', now: now).first;
      final back = ClubEvent.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>)!;
      expect(back.title, e.title);
      expect(back.start, e.start);
      expect(back.location, e.location);
      expect(back.from, 'SSS');
    });

    test('samenvoegen: gesorteerd, zonder dubbel en zonder voorbije', () {
      ClubEvent ev(String t, DateTime s) => ClubEvent(title: t, start: s, source: ClubEventSource.calendar, from: 'x');
      final merged = mergeClubEvents([
        [ev('B', DateTime(2026, 11, 12)), ev('Oud', DateTime(2026, 11, 1))],
        [ev('A', DateTime(2026, 11, 10, 8)), ev('b', DateTime(2026, 11, 12))],
      ], now: now);
      expect(merged.map((x) => x.title), ['A', 'B']);
    });

    test('links', () {
      expect(normalizeCalendarUrl('webcal://club.nl/agenda.ics').toString(), 'https://club.nl/agenda.ics');
      expect(normalizeCalendarUrl(' https://a.nl/x.ics ')?.host, 'a.nl');
      expect(normalizeCalendarUrl('geen link'), isNull);
      expect(normalizeCalendarUrl('ftp://a.nl/x'), isNull);
    });
  });

  group('looppaden', () {
    test('soort pad', () {
      expect(runPathKind({'highway': 'footway'}), RunPathKind.foot);
      expect(runPathKind({'highway': 'cycleway'}), RunPathKind.cycle);
      expect(runPathKind({'highway': 'track'}), RunPathKind.trail);
      expect(runPathKind({'highway': 'path'}), RunPathKind.trail);
      expect(runPathKind({'highway': 'path', 'surface': 'paved'}), RunPathKind.foot);
      expect(runPathKind({'highway': 'cycleway', 'surface': 'sand'}), RunPathKind.trail);
      expect(runPathKind({'highway': 'residential'}), isNull);
    });

    test('vakken: dichtbij = zelfde vak, de vraag dekt het vak met rand', () {
      const a = LatLng(52.145, 5.585), b = LatLng(52.149, 5.589);
      expect(runPathCellKey(a), runPathCellKey(b));
      expect(runPathCellKey(const LatLng(52.20, 5.585)), isNot(runPathCellKey(a)));
      final q = runPathsQuery(a);
      expect(q, contains('footway'));
      expect(q, contains('"footway"!="sidewalk"'));
    });

    test('lezen, inkorten en compact bewaren', () {
      final body = jsonEncode({
        'elements': [
          {
            'type': 'way',
            'tags': {'highway': 'footway'},
            'geometry': [
              {'lat': 52.1, 'lon': 5.5},
              {'lat': 52.101, 'lon': 5.5},
            ],
          },
          {
            'type': 'way',
            'tags': {'highway': 'track'},
            'geometry': [
              {'lat': 52.1, 'lon': 5.5},
              {'lat': 52.11, 'lon': 5.5},
            ],
          },
          {
            'type': 'way',
            'tags': {'highway': 'primary'},
            'geometry': [
              {'lat': 52.1, 'lon': 5.5},
              {'lat': 52.2, 'lon': 5.5},
            ],
          },
        ],
      });
      final all = parseRunPaths(body);
      expect(all.length, 2);
      final longest = parseRunPaths(body, max: 1);
      expect(longest.single.kind, RunPathKind.trail);
      final back = decodeRunPaths(encodeRunPaths(all));
      expect(back.length, 2);
      expect(back.first.points.last.lat, closeTo(52.101, 1e-5));
    });
  });
}
