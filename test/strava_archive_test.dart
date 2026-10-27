import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/run_file_import.dart';
import 'package:runwise/domain/strava_archive.dart';
import 'package:runwise/domain/zip_reader.dart';

// Testbestanden: python3 tools/maak_strava_testarchief.py
void main() {
  test('soorten hardlopen in meerdere talen', () {
    for (final t in ['Run', 'Trail Run', 'Virtual Run', 'Hardlopen', 'Lauf', 'Course à pied', 'Carrera']) {
      expect(isStravaRunType(t), isTrue, reason: t);
    }
    for (final t in ['Ride', 'Walk', 'Wandelen', 'Swim', 'Nordic Ski', 'Langlauf', 'Wheelchair', '']) {
      expect(isStravaRunType(t), isFalse, reason: t);
    }
  });

  test('csv met komma, aanhalingstekens en regeleinde in een veld', () {
    final rows = parseCsv('a,b\n1,"x, ""y""\nz"\n');
    expect(rows.length, 2);
    expect(rows[1][1], 'x, "y"\nz');
  });

  for (final name in ['strava_export.zip', 'strava_export_zip64.zip']) {
    group(name, () {
      late ZipReader zip;
      setUp(() async => zip = await ZipReader.open('test/fixtures/$name'));
      tearDown(() => zip.close());

      test('inhoud en activiteitenlijst', () async {
        expect(zip.entries.length, 6);
        final csv = zip.find('activities.csv')!;
        final items = parseStravaActivitiesCsv(String.fromCharCodes(await zip.read(csv)));
        expect(items.map((i) => i.id), ['111', '222', '333', '444', '555']);
        expect(items.first.name, 'Ochtendloop');
        expect(items.first.file, 'activities/111.fit.gz');
        expect(items.where((i) => i.isRun && i.hasFile).map((i) => i.id), ['111', '222', '333']);
        expect(zip.find('ACTIVITIES/111.FIT.GZ'), isNotNull);
      });

      test('FIT (ingepakt, met compacte tijdstempels en ontwikkelaarsveld)', () async {
        final e = zip.find('activities/111.fit.gz')!;
        final run = parseStravaArchiveFile(e.name, await zip.read(e), name: 'Ochtendloop');
        expect(run.start, DateTime.utc(2024, 5, 4, 7, 30));
        expect(run.distanceMeters, closeTo(357, 1));
        expect(run.movingSeconds, 119);
        expect((run.streams['t'] as List).last, 119);
        expect(run.averageHeartRate, inInclusiveRange(130, 140));
        expect(run.elevationGain, greaterThan(3));
        expect(run.track.first.lat, closeTo(52.15, 1e-5));
        expect(run.track.first.lon, closeTo(5.60, 1e-5));
        expect(run.name, 'Ochtendloop');
      });

      test('GPX en TCX (met spaties voor de XML-kop)', () async {
        final g = zip.find('activities/222.gpx')!;
        final gpx = parseStravaArchiveFile(g.name, await zip.read(g), name: 'Avondloop');
        expect(gpx.distanceMeters, closeTo(594, 3));
        expect(gpx.name, 'Avondloop');
        final t = zip.find('activities/333.tcx.gz')!;
        final tcx = parseStravaArchiveFile(t.name, await zip.read(t));
        expect(tcx.distanceMeters, closeTo(495, 1));
        expect(tcx.averageHeartRate, inInclusiveRange(130, 140));
      });
    });
  }

  test('FIT van een andere sport wordt geweigerd', () {
    final bytes = File('test/fixtures/fietsrit.fit').readAsBytesSync();
    expect(
      () => parseFitRun(bytes),
      throwsA(isA<RunFileException>().having((e) => e.message, 'melding', contains('geen hardloop'))),
    );
  });

  test('kapotte bestanden geven een nette melding', () {
    expect(() => parseStravaArchiveFile('x.fit', Uint8List.fromList([1, 2, 3])), throwsA(isA<RunFileException>()));
    expect(() => parseStravaArchiveFile('x.fit.gz', Uint8List.fromList([1, 2, 3])), throwsA(isA<RunFileException>()));
    expect(() => parseStravaArchiveFile('x.doc', Uint8List(0)), throwsA(isA<RunFileException>()));
  });

  test('geen zip', () async {
    expect(ZipReader.open('test/fixtures/fietsrit.fit'), throwsA(isA<ZipFormatException>()));
  });
}
