import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/data/services/sync_service.dart';

Activity _a(String source, {String? externalId}) => Activity.fromJson({
      'started_at': '2026-10-22T17:30:00Z',
      'distance_meters': 5000,
      'moving_time_seconds': 1500,
      'source': source,
      'external_id': externalId,
    });

void main() {
  group('Strava-data niet naar de coach', () {
    test('herkomst van een Health Connect-run', () {
      expect(healthRunOrigin('nl.runwise.runwise'), HealthRunOrigin.runwise);
      expect(healthRunOrigin('com.strava'), HealthRunOrigin.strava);
      expect(healthRunOrigin('com.garmin.android.apps.connectmobile'), HealthRunOrigin.other);
      expect(healthRunOrigin(null), HealthRunOrigin.other);
    });

    test('runs van de Strava-app krijgen een herkenbaar id', () {
      expect(healthExternalId('abc', HealthRunOrigin.strava), 'viastrava-abc');
      expect(healthExternalId('abc', HealthRunOrigin.other), 'abc');
    });

    test('viaStrava: direct, via Health Connect, en gewone runs', () {
      expect(_a('strava', externalId: '123').viaStrava, isTrue);
      expect(_a('health_connect', externalId: 'viastrava-abc').viaStrava, isTrue);
      expect(_a('health_connect', externalId: 'abc').viaStrava, isFalse);
      expect(_a('runwise').viaStrava, isFalse);
      expect(_a('manual').viaStrava, isFalse);
    });
  });
}
