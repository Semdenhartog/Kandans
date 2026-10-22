import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/data/services/pending_runs.dart';
import 'package:runwise/domain/geo.dart';

class _FakeUploader implements PendingRunUploader {
  _FakeUploader({this.failAfter = 999});
  final int failAfter;
  final uploaded = <String>[];
  final extras = <String>[];

  @override
  Future<String> upload(PendingRun run) async {
    if (uploaded.length >= failAfter) throw const SocketException('geen internet');
    uploaded.add(run.localId);
    return 'db-${run.localId}';
  }

  @override
  Future<void> afterUpload(String id, PendingRun run) async => extras.add(id);

  @override
  Future<Activity?> withWeather(PendingRun run) async => null;
}

PendingRun _run(String id, DateTime created, {double? temp}) => PendingRun(
      localId: id,
      createdAt: created,
      activity: Activity(
        startedAt: DateTime.utc(2026, 10, 22, 17, 30),
        distanceMeters: 5012.4,
        movingTimeSeconds: 1680,
        source: 'runwise',
        averageHeartRate: 151,
        temperatureCelsius: temp,
        trackPolyline: encodePolyline(const [LatLng(52.15, 5.59), LatLng(52.16, 5.60)]),
      ),
      streams: const {'t': [0, 1], 'd': [0, 3]},
      bestEfforts: const {'1000': 301.5},
    );

void main() {
  group('runs die wachten op internet', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('pending_runs_test');
      PendingRunStore.testDir = dir;
    });

    tearDown(() async {
      PendingRunStore.testDir = null;
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('heen en terug naar tekst zonder verlies', () {
      final r = _run('rw1', DateTime.utc(2026, 10, 22, 18));
      final back = PendingRun.fromJson(r.toJson())!;
      expect(back.localId, 'rw1');
      expect(back.activity.distanceMeters, 5012.4);
      expect(back.activity.movingTimeSeconds, 1680);
      expect(back.activity.source, 'runwise');
      expect(back.activity.averageHeartRate, 151);
      expect(back.activity.startedAt.toUtc(), DateTime.utc(2026, 10, 22, 17, 30));
      expect(back.streams!['d'], [0, 3]);
      expect(back.bestEfforts!['1000'], 301.5);
      expect(back.needsWeather, isTrue);
      expect(back.startPoint!.lat, closeTo(52.15, 0.0001));
      expect(r.toJson()['activity'], isNot(contains('user_id')));
    });

    test('met weer of zonder spoor is geen weer meer nodig', () {
      expect(_run('a', DateTime.now(), temp: 12).needsWeather, isFalse);
    });

    test('kapotte bestanden geven null in plaats van een crash', () {
      expect(PendingRun.fromJson('onzin'), isNull);
      expect(PendingRun.fromJson({'local_id': 'x'}), isNull);
    });

    test('sleutels zijn uniek en bruikbaar als bestandsnaam', () {
      final ids = {for (var i = 0; i < 200; i++) PendingRun.newLocalId()};
      expect(ids.length, 200);
      expect(ids.every((id) => RegExp(r'^rw[0-9a-z]+$').hasMatch(id)), isTrue);
    });

    test('versturen: oudste eerst, stopt bij geen internet en bewaart de rest', () async {
      await PendingRunStore.add(_run('nieuw', DateTime.utc(2026, 10, 22, 19)));
      await PendingRunStore.add(_run('oud', DateTime.utc(2026, 10, 22, 18)));
      expect(PendingRunStore.count.value, 2);

      final offline = _FakeUploader(failAfter: 1);
      expect(await PendingRunStore.flush(offline), 1);
      expect(offline.uploaded, ['oud']);
      expect(offline.extras, ['db-oud']);
      expect(PendingRunStore.count.value, 1);

      final online = _FakeUploader();
      expect(await PendingRunStore.flush(online), 1);
      expect(online.uploaded, ['nieuw']);
      expect(PendingRunStore.count.value, 0);
      expect(await PendingRunStore.flush(online), 0);
    });
  });
}
