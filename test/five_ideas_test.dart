import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/availability.dart';
import 'package:runwise/domain/decoupling.dart';
import 'package:runwise/domain/hindsight.dart';
import 'package:runwise/domain/roster.dart';
import 'package:runwise/domain/run_streams.dart';
import 'package:runwise/domain/sun_position.dart';

const _ics = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
DTSTART;TZID=Europe/Amsterdam:20261102T070000
DTEND;TZID=Europe/Amsterdam:20261102T153000
SUMMARY:Vroege dienst
END:VEVENT
BEGIN:VEVENT
DTSTART:20261103T220000
DTEND:20261104T070000
SUMMARY:Nachtdienst meldkamer
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20261105
DTEND;VALUE=DATE:20261106
SUMMARY:Verjaardag
END:VEVENT
BEGIN:VEVENT
DTSTART:20261106T080000
DTEND:20261106T160000
SUMMARY:Vrij
END:VEVENT
BEGIN:VEVENT
DTSTART:20261020T080000
DTEND:20261020T160000
SUMMARY:Oude dienst
END:VEVENT
END:VCALENDAR''';

void main() {
  final now = DateTime(2026, 11, 1, 12);

  group('rooster', () {
    test('diensten lezen; hele dag, vrij en voorbij tellen niet', () {
      final shifts = parseIcs(_ics, now: now);
      expect(shifts.length, 2);
      expect(shifts.first.start, DateTime(2026, 11, 2, 7));
      expect(shifts.first.label, 'Vroege dienst');
      expect(isNightShift(shifts.last), isTrue);
      expect(isNightShift(shifts.first), isFalse);
    });

    test('regels die doorlopen (folding) en UTC-tijden', () {
      const ics = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:20261102T060000Z\r\nDTEND:20261102T14\r\n 3000Z\r\nSUMMARY:La\r\n te dienst\r\nEND:VEVENT\r\nEND:VCALENDAR';
      final s = parseIcs(ics, now: now).single;
      expect(s.label, 'Late dienst');
      expect(s.start, DateTime.utc(2026, 11, 2, 6).toLocal());
      expect(s.end, DateTime.utc(2026, 11, 2, 14, 30).toLocal());
    });

    test('reistijd en slapen na een nachtdienst blokkeren loopmomenten', () {
      final blocks = blockedTimes(parseIcs(_ics, now: now));
      final a = Availability.always.withBusy(blocks);
      expect(a.unrestricted, isFalse);
      expect(a.isAlways, isTrue); // geen eigen weektijden
      expect(a.allows(DateTime(2026, 11, 2, 6, 15), 45), isFalse); // reistijd vóór de vroege dienst
      expect(a.allows(DateTime(2026, 11, 2, 16, 30), 45), isTrue); // na dienst + reistijd
      expect(a.allows(DateTime(2026, 11, 4, 9), 45), isFalse); // slapen na nachtdienst
      expect(a.allows(DateTime(2026, 11, 4, 14), 45), isTrue);
    });
  });

  group('zon', () {
    test('midzomer in Amsterdam: hoog in het zuiden', () {
      final p = sunPosition(DateTime.utc(2026, 6, 21, 11, 40), 52.37, 4.9);
      expect(p.elevation, inInclusiveRange(58, 63));
      expect(p.azimuth, inInclusiveRange(170, 200));
    });

    test('winteravond: laag in het zuidwesten', () {
      final p = sunPosition(DateTime.utc(2026, 12, 21, 15, 0), 52.37, 4.9);
      expect(isLowSun(p.elevation), isTrue);
      expect(p.azimuth, inInclusiveRange(215, 240));
    });

    test('deel van de route tegen de zon in', () {
      final route = [(bearing: 225.0, meters: 600.0, startKm: 0.0), (bearing: 45.0, meters: 400.0, startKm: 0.6)];
      expect(fractionTowardSun(route, 230), closeTo(0.6, 0.001));
      expect(angleBetween(350, 10), 20);
    });
  });

  group('terugblik', () {
    HourWeather h(int hour, {double rain = 0, double t = 10, double wind = 10}) =>
        HourWeather(time: DateTime(2026, 11, 1, hour), temperature: t, feelsLike: t, precipitation: rain, windSpeed: wind);

    test('droog gebleven terwijl het later regende', () {
      final day = [for (var i = 0; i < 24; i++) h(i, rain: i >= 15 && i <= 17 ? 3 : 0)];
      final r = hindsight(day, DateTime(2026, 11, 1, 10), 60)!;
      expect(r.good, isTrue);
      expect(r.title, 'Droog gebleven');
      expect(r.rainAvoided, greaterThan(2));
    });

    test('nat geworden terwijl het kort ervoor droog was', () {
      final day = [for (var i = 0; i < 24; i++) h(i, rain: i == 12 ? 2 : 0)];
      final r = hindsight(day, DateTime(2026, 11, 1, 12), 60)!;
      expect(r.good, isFalse);
    });

    test('heel weinig data = geen oordeel', () {
      expect(hindsight([h(10)], DateTime(2026, 11, 1, 10), 60), isNull);
    });
  });

  group('hartslagdrift', () {
    RunStreams run(double hrRise) {
      final n = 600; // 50 min, elke 5 s
      return RunStreams(
        time: [for (var i = 0; i <= n; i++) i * 5.0],
        distance: [for (var i = 0; i <= n; i++) i * 5 * 3.0], // 3 m/s, 9 km
        heartRate: [for (var i = 0; i <= n; i++) 140 + hrRise * i / n],
      );
    }

    test('stabiele hartslag = weinig drift', () {
      expect(decouplingOf(run(2))!.percent, lessThan(2));
    });

    test('oplopende hartslag = flinke drift', () {
      final d = decouplingOf(run(20))!;
      expect(d.percent, greaterThan(5));
      expect(d.secondHr, greaterThan(d.firstHr));
    });

    test('te kort = geen uitkomst', () {
      final s = RunStreams(time: [0, 600], distance: [0, 2000], heartRate: [140, 150]);
      expect(decouplingOf(s), isNull);
    });
  });
}
