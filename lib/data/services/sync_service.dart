import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/supabase.dart';
import '../../domain/geo.dart';
import '../../domain/gpx_parser.dart' show buildRoute;
import '../../domain/readiness.dart';
import '../../domain/run_matcher.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';
import 'pending_runs.dart';
import 'weather_service.dart';

/// Status van de Strava-koppeling (rij in external_connections).
class StravaConnection {
  StravaConnection({this.athleteName, this.lastSyncedAt, this.lastError});
  final String? athleteName;
  final DateTime? lastSyncedAt;
  final String? lastError;
}

enum HealthStatus { unavailable, needsInstall, notConnected, connected }

/// Resultaat van één stap "oude runs ophalen".
class StravaHistoryPage {
  const StravaHistoryPage({required this.imported, required this.done, this.nextBefore, this.oldest, this.rateLimited = false});
  final int imported;
  final bool done;

  /// Waar de volgende stap verdergaat (epoch-seconden).
  final int? nextBefore;

  /// Oudste activiteit in deze stap (om de voortgang te tonen).
  final DateTime? oldest;

  /// Strava is even te druk; later verder.
  final bool rateLimited;
}

/// Een route in Strava (uit de lijst; de volledige lijn komt bij het importeren).
class StravaRouteSummary {
  const StravaRouteSummary({
    required this.id,
    required this.name,
    required this.distanceMeters,
    required this.summaryPolyline,
    this.elevationGainMeters,
    this.isPrivate = false,
    this.starred = false,
  });
  final String id;
  final String name;
  final double distanceMeters;
  final double? elevationGainMeters;
  final bool isPrivate;
  final bool starred;
  final String summaryPolyline;
}

class StravaRouteList {
  const StravaRouteList({required this.routes, required this.canSeePrivate, this.cyclingSkipped = 0});
  final List<StravaRouteSummary> routes;

  /// Mag Kadans je privéroutes zien? (Nee bij een koppeling van vóór deze versie: opnieuw koppelen.)
  final bool canSeePrivate;
  final int cyclingSkipped;
}

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

  Future<Map<String, dynamic>> _strava(String action, [Map<String, dynamic> extra = const {}]) async {
    try {
      final res = await _db.functions.invoke('strava', body: {'action': action, ...extra});
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

  static const _autoUploadKey = 'strava_auto_upload';

  /// Eigen Kadans-runs automatisch naar Strava sturen?
  Future<bool> stravaAutoUpload() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_autoUploadKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setStravaAutoUpload(bool on) async => (await SharedPreferences.getInstance()).setBool(_autoUploadKey, on);

  /// Eén eigen run naar Strava sturen. Gooit een fout met uitleg (bijv. "Koppel Strava opnieuw").
  Future<void> uploadToStrava(String activityId) => _strava('upload', {'activity_id': activityId});

  /// Na het opslaan van een run: naar Strava als dat aan staat. Fouten zijn stil (de run staat al in Kadans).
  Future<void> maybeAutoUploadToStrava(String activityId) async {
    if (!await stravaAutoUpload()) return;
    try {
      await uploadToStrava(activityId);
    } catch (_) {}
  }

  /// Eén stap van "oude runs ophalen": 200 Strava-activiteiten ouder dan [before] (epoch-seconden).
  /// Strava te druk? Dan [StravaHistoryPage.rateLimited] in plaats van een fout, zodat je later verder kunt.
  Future<StravaHistoryPage> stravaHistoryPage({int? before}) async {
    try {
      final res = await _db.functions.invoke('strava', body: {'action': 'history', if (before != null) 'before': before});
      final m = (res.data as Map).cast<String, dynamic>();
      return StravaHistoryPage(
        imported: (m['imported'] as num?)?.toInt() ?? 0,
        done: m['done'] == true,
        nextBefore: (m['next_before'] as num?)?.toInt(),
        oldest: m['oldest'] == null ? null : DateTime.tryParse(m['oldest'] as String),
      );
    } on FunctionException catch (e) {
      if (e.status == 429) return const StravaHistoryPage(imported: 0, done: false, rateLimited: true);
      final details = e.details is Map ? (e.details as Map).cast<String, dynamic>() : <String, dynamic>{};
      throw Exception(details['error'] ?? 'Oude runs ophalen is niet gelukt. Probeer het later opnieuw.');
    }
  }

  /// Je hardlooproutes in Strava.
  Future<StravaRouteList> stravaRoutes() async {
    final m = await _strava('routes');
    return StravaRouteList(
      routes: [
        for (final r in (m['routes'] as List? ?? const []).cast<Map>())
          StravaRouteSummary(
            id: r['id'].toString(),
            name: (r['name'] as String?) ?? 'Route uit Strava',
            distanceMeters: (r['distance_m'] as num?)?.toDouble() ?? 0,
            elevationGainMeters: (r['elevation_gain_m'] as num?)?.toDouble(),
            isPrivate: r['private'] == true,
            starred: r['starred'] == true,
            summaryPolyline: (r['summary_polyline'] as String?) ?? '',
          ),
      ],
      canSeePrivate: m['can_see_private'] == true,
      cyclingSkipped: (m['cycling_skipped'] as num?)?.toInt() ?? 0,
    );
  }

  /// Haalt één Strava-route met de volledige lijn op en bewaart hem als Kadans-route.
  Future<String> importStravaRoute(StravaRouteSummary r) async {
    final m = await _strava('route', {'route_id': r.id});
    final pts = decodePolyline(m['polyline'] as String);
    final route = buildRoute(pts, name: (m['name'] as String?) ?? r.name, source: 'strava_import')
        .copyWith(stravaRouteId: r.id, elevationGainMeters: (m['elevation_gain_m'] as num?)?.toDouble());
    final id = await _ref.read(repositoryProvider).addRoute(route);
    return id;
  }

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

  // ---------- Slaap, rusthartslag en HRV (voor je klaar-score) ----------

  static const _bodyTypes = [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
  ];
  static const _bodyKey = 'health_body_signals';

  Future<bool> bodySignalsEnabled() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_bodyKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Vraagt toestemming om slaap, rusthartslag en HRV te lezen (van je horloge of ring).
  Future<bool> connectBody() async {
    if (!Platform.isAndroid) return false;
    try {
      await _configureHealth();
      final ok = await _health.requestAuthorization(
        _bodyTypes,
        permissions: _bodyTypes.map((_) => HealthDataAccess.READ).toList(),
      );
      final p = await SharedPreferences.getInstance();
      await p.setBool(_bodyKey, ok);
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Afgelopen nacht en je normaal (gemiddelde van de 14 dagen ervoor). Null als niets gekoppeld is.
  Future<BodySignals?> bodySignals() async {
    if (!Platform.isAndroid || !await bodySignalsEnabled()) return null;
    try {
      await _configureHealth();
      final now = DateTime.now();
      final points = await _health.getHealthDataFromTypes(
        types: _bodyTypes,
        startTime: now.subtract(const Duration(days: 15)),
        endTime: now,
      );
      // Slaap per nacht (de dag waarop je wakker werd).
      final sleepPerDay = <DateTime, double>{};
      final rhrPerDay = <DateTime, List<double>>{};
      final hrvPerDay = <DateTime, List<double>>{};
      for (final p in points) {
        final d = DateTime(p.dateTo.year, p.dateTo.month, p.dateTo.day);
        if (p.type == HealthDataType.SLEEP_SESSION) {
          final h = p.dateTo.difference(p.dateFrom).inMinutes / 60;
          if (h > 0 && h < 16) sleepPerDay[d] = (sleepPerDay[d] ?? 0) + h;
        } else if (p.value is NumericHealthValue) {
          final v = (p.value as NumericHealthValue).numericValue.toDouble();
          if (p.type == HealthDataType.RESTING_HEART_RATE && v > 25 && v < 120) (rhrPerDay[d] ??= []).add(v);
          if (p.type == HealthDataType.HEART_RATE_VARIABILITY_RMSSD && v > 3 && v < 300) (hrvPerDay[d] ??= []).add(v);
        }
      }
      final today = DateTime(now.year, now.month, now.day);
      double avg(Iterable<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
      double? latest(Map<DateTime, double> m) {
        final yesterday = today.subtract(const Duration(days: 1));
        return m[today] ?? m[yesterday];
      }

      double? baseline(Map<DateTime, double> m) {
        final older = [for (final e in m.entries) if (e.key.isBefore(today.subtract(const Duration(days: 1)))) e.value];
        return older.length < 3 ? null : avg(older);
      }

      final rhr = {for (final e in rhrPerDay.entries) e.key: avg(e.value)};
      final hrv = {for (final e in hrvPerDay.entries) e.key: avg(e.value)};
      final s = BodySignals(
        sleepHours: latest(sleepPerDay),
        sleepAvgHours: baseline(sleepPerDay),
        restingHr: latest(rhr),
        restingHrBaseline: baseline(rhr),
        hrv: latest(hrv),
        hrvBaseline: baseline(hrv),
      );
      return s;
    } catch (_) {
      return null;
    }
  }

  // ---------- Runs naar Health Connect (Samsung Health, Google Fit) ----------

  static const _writeKey = 'health_write_runs';

  Future<bool> healthWriteEnabled() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_writeKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Zet het schrijven aan (vraagt dan toestemming) of uit.
  Future<bool> setHealthWrite(bool on) async {
    if (on) {
      if (!Platform.isAndroid) return false;
      await _configureHealth();
      final ok = await _health.requestAuthorization(
        const [HealthDataType.WORKOUT],
        permissions: const [HealthDataAccess.READ_WRITE],
      );
      if (!ok) return false;
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool(_writeKey, on);
    return true;
  }

  /// Zet een opgenomen run in Health Connect, zodat hij ook in Samsung Health staat.
  Future<bool> writeRunToHealth(Activity a) async {
    if (!Platform.isAndroid || !await healthWriteEnabled()) return false;
    try {
      await _configureHealth();
      final end = a.startedAt.add(Duration(seconds: a.movingTimeSeconds));
      return await _health.writeWorkoutData(
        activityType: HealthWorkoutActivityType.RUNNING,
        start: a.startedAt,
        end: end,
        totalDistance: a.distanceMeters.round(),
        totalDistanceUnit: HealthDataUnit.METER,
        title: 'Hardlopen (Kadans)',
      );
    } catch (_) {
      return false;
    }
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
      final origin = healthRunOrigin(p.sourceId);
      // Runs die Kadans zelf naar Health Connect schreef, staan er al.
      if (origin == HealthRunOrigin.runwise) continue;
      final externalId = healthExternalId(p.uuid, origin);
      if (known.contains(externalId)) continue;
      if (known.contains(p.uuid)) {
        // Eerder binnengekomen zonder herkenning: alsnog markeren als Strava-run (niet naar de coach).
        if (externalId != p.uuid) {
          try {
            await _db
                .from('activities')
                .update({'external_id': externalId})
                .eq('user_id', uid)
                .eq('source', 'health_connect')
                .eq('external_id', p.uuid);
          } catch (_) {
            // Volgende keer opnieuw.
          }
        }
        continue;
      }
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
        {...activity.toInsert(uid), 'external_id': externalId},
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

  /// Runs die zonder internet zijn opgenomen alsnog versturen.
  Future<int> flushPendingRuns() async {
    if (_db.auth.currentUser == null) return 0;
    final sent = await PendingRunStore.flush(_PendingUploader(_ref));
    if (sent > 0) _ref.invalidate(activitiesProvider);
    return sent;
  }

  Future<int> syncAll({bool force = false}) async {
    // De wachtrij altijd eerst, ook binnen de 30 minuten: dat is je eigen run.
    await flushPendingRuns().catchError((Object _) => 0);
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

class _PendingUploader implements PendingRunUploader {
  _PendingUploader(this._ref);
  final Ref _ref;

  @override
  Future<String> upload(PendingRun run) =>
      _ref.read(repositoryProvider).addRecordedRun(run.activity, run.localId);

  @override
  Future<void> afterUpload(String id, PendingRun run) async {
    final repo = _ref.read(repositoryProvider);
    final streams = run.streams;
    if (streams == null) return;
    await repo.setActivityStreams(id, streams, bestEfforts: run.bestEfforts);
    if (run.activity.hasTrack) repo.improveElevation(id, streams).ignore();
    maybeAutoUploadToStrava(id).ignore();
  }

  @override
  Future<Activity?> withWeather(PendingRun run) async {
    final p = run.startPoint;
    if (p == null) return null;
    final w = await _ref
        .read(weatherServiceProvider)
        .historical(p.lat, p.lon, run.activity.startedAt)
        .timeout(const Duration(seconds: 8), onTimeout: () => null);
    if (w == null) return null;
    final row = {...run.activity.toInsert('')}
      ..addAll({
        'temperature_celsius': w.temperature,
        'feels_like_celsius': w.feelsLike,
        'wind_speed_kmh': w.windSpeed,
        'wind_direction_degrees': w.windDirection,
        'humidity_pct': w.humidity,
      });
    return Activity.fromJson(row);
  }
}

/// Van welke app een Health Connect-run komt.
enum HealthRunOrigin { runwise, strava, other }

/// Pakketnaam van Kadans zelf (zie `flutter create --org nl.runwise` in build.yml).
const runwisePackage = 'nl.runwise.runwise';

/// Pakketnaam van de Strava-app.
const stravaPackage = 'com.strava';

HealthRunOrigin healthRunOrigin(String? sourceId) => switch (sourceId) {
      runwisePackage => HealthRunOrigin.runwise,
      stravaPackage => HealthRunOrigin.strava,
      _ => HealthRunOrigin.other,
    };

/// external_id voor een Health Connect-run: runs van de Strava-app krijgen een herkenbaar begin,
/// zodat ze (net als Strava-runs) niet naar de AI-coach gaan.
String healthExternalId(String uuid, HealthRunOrigin origin) =>
    origin == HealthRunOrigin.strava ? '${Activity.viaStravaPrefix}$uuid' : uuid;

final syncServiceProvider = Provider<SyncService>((ref) => SyncService(ref));

final stravaConnectionProvider = FutureProvider<StravaConnection?>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(syncServiceProvider).stravaConnection();
});

final healthStatusProvider = FutureProvider<HealthStatus>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(syncServiceProvider).healthStatus();
});

/// Slaap, rusthartslag en HRV uit Health Connect (null als niet gekoppeld).
final bodySignalsProvider = FutureProvider<BodySignals?>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(syncServiceProvider).bodySignals();
});
