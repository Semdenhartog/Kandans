import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/supabase.dart';
import '../../domain/geo.dart';
import '../../domain/run_matcher.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';
import 'weather_service.dart';

/// Status van de Strava-koppeling (rij in external_connections).
class StravaConnection {
  StravaConnection({this.athleteName, this.lastSyncedAt, this.lastError});
  final String? athleteName;
  final DateTime? lastSyncedAt;
  final String? lastError;
}

enum HealthStatus { unavailable, needsInstall, notConnected, connected }

/// Haalt runs automatisch op uit Strava (via de server) en Health Connect (op de telefoon).
class SyncService {
  SyncService(this._ref);

  final Ref _ref;
  DateTime? _lastAutoSync;
  bool _busy = false;

  SupabaseClient get _db => _ref.read(supabaseProvider);
  final _health = Health();
  bool _healthConfigured = false;

  static const _healthTypes = [HealthDataType.WORKOUT, HealthDataType.HEART_RATE];
  static const _runTypes = {
    HealthWorkoutActivityType.RUNNING,
  };

  // ------------------------------------------------------------ Strava

  Future<StravaConnection?> stravaConnection() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _db
        .from('external_connections')
        .select('athlete_name, last_synced_at, last_error')
        .eq('user_id', uid)
        .eq('provider', 'strava')
        .maybeSingle();
    if (row == null) return null;
    return StravaConnection(
      athleteName: row['athlete_name'] as String?,
      lastSyncedAt: row['last_synced_at'] == null ? null : DateTime.parse(row['last_synced_at'] as String),
      lastError: row['last_error'] as String?,
    );
  }

  Future<Map<String, dynamic>> _strava(String action) async {
    try {
      final res = await _db.functions.invoke('strava', body: {'action': action});
      return (res.data as Map).cast<String, dynamic>();
    } on FunctionException catch (e) {
      final details = e.details is Map ? (e.details as Map).cast<String, dynamic>() : <String, dynamic>{};
      throw Exception(details['error'] ?? 'Strava is even niet bereikbaar. Probeer het later opnieuw.');
    }
  }

  /// Opent de Strava-toestemmingspagina. Daarna komt de gebruiker terug via runwise://app/strava-connected.
  Future<void> connectStrava() async {
    final data = await _strava('connect');
    final ok = await launchUrl(Uri.parse(data['url'] as String), mode: LaunchMode.externalApplication);
    if (!ok) throw Exception('Strava kon niet worden geopend.');
  }

  Future<int> syncStrava() async {
    final data = await _strava('sync');
    return (data['imported'] as num?)?.toInt() ?? 0;
  }

  Future<void> disconnectStrava() => _strava('disconnect');

  // ------------------------------------------------------------ Health Connect

  Future<void> _configureHealth() async {
    if (_healthConfigured) return;
    await _health.configure();
    _healthConfigured = true;
  }

  Future<HealthStatus> healthStatus() async {
    if (!Platform.isAndroid) return HealthStatus.unavailable;
    try {
      await _configureHealth();
      final sdk = await _health.getHealthConnectSdkStatus();
      if (sdk == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired) return HealthStatus.needsInstall;
      if (sdk != HealthConnectSdkStatus.sdkAvailable) return HealthStatus.needsInstall;
      final ok = await _health.hasPermissions(_healthTypes) ?? false;
      return ok ? HealthStatus.connected : HealthStatus.notConnected;
    } catch (_) {
      return HealthStatus.unavailable;
    }
  }

  Future<void> installHealthConnect() async {
    await _configureHealth();
    await _health.installHealthConnect();
  }

  /// Vraagt toestemming om trainingen en hartslag te lezen. Geeft true als dat is gegeven.
  Future<bool> connectHealth() async {
    await _configureHealth();
    return _health.requestAuthorization(
      _healthTypes,
      permissions: _healthTypes.map((_) => HealthDataAccess.READ).toList(),
    );
  }

  /// Leest hardloopsessies uit Health Connect en slaat nieuwe op (met het weer van dat moment).
  Future<int> syncHealth() async {
    if (await healthStatus() != HealthStatus.connected) return 0;
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return 0;

    // Vanaf de laatste Health Connect-run; de eerste keer de afgelopen 30 dagen
    // (verder terug mag Health Connect standaard niet).
    final now = DateTime.now();
    final last = await _db
        .from('activities')
        .select('started_at')
        .eq('user_id', uid)
        .eq('source', 'health_connect')
        .order('started_at', ascending: false)
        .limit(1)
        .maybeSingle();
    var since = last == null
        ? now.subtract(const Duration(days: 30))
        : DateTime.parse(last['started_at'] as String).toLocal().subtract(const Duration(hours: 1));
    final earliest = now.subtract(const Duration(days: 30));
    if (since.isBefore(earliest)) since = earliest;

    final points = await _health.getHealthDataFromTypes(
      types: const [HealthDataType.WORKOUT],
      startTime: since,
      endTime: now,
    );
    final runs = points.where((p) {
      final v = p.value;
      return v is WorkoutHealthValue && _runTypes.contains(v.workoutActivityType);
    }).toList();
    if (runs.isEmpty) return 0;

    // Bestaande runs rond hetzelfde tijdstip (handmatig of Strava) niet dubbel opslaan.
    final existing = await _db
        .from('activities')
        .select('started_at, source, external_id')
        .eq('user_id', uid)
        .gte('started_at', since.subtract(const Duration(days: 1)).toUtc().toIso8601String());
    final known = existing
        .where((e) => e['source'] == 'health_connect')
        .map((e) => e['external_id'] as String?)
        .toSet();
    final otherTimes = existing
        .where((e) => e['source'] != 'health_connect')
        .map((e) => DateTime.parse(e['started_at'] as String))
        .toList();

    final profile = await _ref.read(profileProvider.future);
    final lat = profile?.homeLatitude ?? AppConfig.fallbackLatitude;
    final lon = profile?.homeLongitude ?? AppConfig.fallbackLongitude;
    final weather = _ref.read(weatherServiceProvider);

    var imported = 0;
    for (final p in runs) {
      if (known.contains(p.uuid)) continue;
      if (otherTimes.any((t) => t.difference(p.dateFrom).inMinutes.abs() < 20)) continue;

      final v = p.value as WorkoutHealthValue;
      final meters = _meters(v.totalDistance, v.totalDistanceUnit);
      final seconds = p.dateTo.difference(p.dateFrom).inSeconds;
      if (meters < 500 || seconds <= 0) continue;

      final hr = await _averageHeartRate(p.dateFrom, p.dateTo);
      final w = await weather.historical(lat, lon, p.dateFrom);

      final activity = Activity(
        startedAt: p.dateFrom,
        distanceMeters: meters,
        movingTimeSeconds: seconds,
        source: 'health_connect',
        averageHeartRate: hr,
        temperatureCelsius: w?.temperature,
        feelsLikeCelsius: w?.feelsLike,
        windSpeedKmh: w?.windSpeed,
        windDirectionDegrees: w?.windDirection,
        humidityPct: w?.humidity,
      );
      await _db.from('activities').upsert(
        {...activity.toInsert(uid), 'external_id': p.uuid},
        onConflict: 'user_id,source,external_id',
        ignoreDuplicates: true,
      );
      imported++;
    }
    return imported;
  }

  double _meters(num? value, HealthDataUnit? unit) {
    if (value == null) return 0;
    return switch (unit) {
      HealthDataUnit.MILE => value * 1609.344,
      _ => value.toDouble(),
    };
  }

  Future<int?> _averageHeartRate(DateTime from, DateTime to) async {
    try {
      final hr = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.HEART_RATE],
        startTime: from,
        endTime: to,
      );
      final values = hr
          .map((p) => p.value)
          .whereType<NumericHealthValue>()
          .map((v) => v.numericValue.toDouble())
          .where((v) => v > 30 && v < 230)
          .toList();
      if (values.isEmpty) return null;
      return (values.reduce((a, b) => a + b) / values.length).round();
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ alles samen

  /// Haalt nieuwe runs op uit alle gekoppelde bronnen. Geeft het aantal nieuwe runs.
  /// Zonder [force] hooguit eens per 30 minuten (bij het openen van de app).
  // ------------------------------------------------------------ Runs aan routes koppelen

  /// Koppelt runs met een GPS-spoor (uit Strava) automatisch aan de route waarop
  /// je liep. Runs waarvan je zelf de route koppelde of losmaakte, blijven zoals ze zijn.
  /// Geeft het aantal nieuw gekoppelde runs terug.
  Future<int> autoLinkRuns() async {
    if (_db.auth.currentUser == null) return 0;
    final repo = _ref.read(repositoryProvider);
    final runs = await repo.activities();
    final todo = runs.where((a) => a.id != null && a.routeId == null && !a.routeLinkLocked && a.hasTrack).toList();
    if (todo.isEmpty) return 0;
    final routes = await repo.routes();
    if (routes.isEmpty) return 0;
    final matchable = [
      for (final r in routes)
        if (r.id != null) MatchableRoute(r.id!, decodePolyline(r.polyline)),
    ];
    var linked = 0;
    for (final a in todo) {
      final m = matchRun(decodePolyline(a.trackPolyline!), matchable);
      if (m == null) continue;
      try {
        await repo.autoLinkActivity(a.id!, m.routeId);
        linked++;
      } catch (_) {}
    }
    if (linked > 0) _ref.invalidate(activitiesProvider);
    return linked;
  }

  Future<int> syncAll({bool force = false}) async {
    if (_busy) return 0;
    if (!force && _lastAutoSync != null && DateTime.now().difference(_lastAutoSync!).inMinutes < 30) {
      return 0;
    }
    if (_db.auth.currentUser == null) return 0;
    _busy = true;
    _lastAutoSync = DateTime.now();
    var total = 0;
    try {
      try {
        if (await stravaConnection() != null) total += await syncStrava();
      } catch (e) {
        if (force) rethrow;
      }
      try {
        total += await syncHealth();
      } catch (e) {
        if (force) rethrow;
      }
      try {
        await autoLinkRuns();
      } catch (_) {}
    } finally {
      _busy = false;
    }
    if (total > 0) _ref.invalidate(activitiesProvider);
    return total;
  }
}

final syncServiceProvider = Provider<SyncService>((ref) => SyncService(ref));

final stravaConnectionProvider = FutureProvider<StravaConnection?>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(syncServiceProvider).stravaConnection();
});

final healthStatusProvider = FutureProvider<HealthStatus>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(syncServiceProvider).healthStatus();
});
