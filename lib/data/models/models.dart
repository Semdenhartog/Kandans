/// Datamodellen die overeenkomen met de Supabase-tabellen.
library;

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
double? _dn(dynamic v) => v == null ? null : (v as num).toDouble();
int? _in(dynamic v) => v == null ? null : (v as num).round();

class Profile {
  Profile({
    required this.id,
    this.fullName,
    this.firstName,
    this.username,
    this.homeLatitude,
    this.homeLongitude,
  });

  final String id;
  final String? fullName;
  final String? firstName;
  final String? username;
  final double? homeLatitude;
  final double? homeLongitude;

  String get displayName {
    final first = firstName?.trim();
    if (first != null && first.isNotEmpty) return first;
    final full = fullName?.trim();
    if (full != null && full.isNotEmpty) return full.split(' ').first;
    return username ?? 'loper';
  }

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        fullName: j['full_name'] as String?,
        firstName: j['first_name'] as String?,
        username: j['username'] as String?,
        homeLatitude: _dn(j['home_latitude']),
        homeLongitude: _dn(j['home_longitude']),
      );
}

class Activity {
  Activity({
    this.id,
    required this.startedAt,
    required this.distanceMeters,
    required this.movingTimeSeconds,
    this.source = 'manual',
    this.routeId,
    this.averageHeartRate,
    this.elevationGainMeters,
    this.temperatureCelsius,
    this.feelsLikeCelsius,
    this.windSpeedKmh,
    this.windDirectionDegrees,
    this.humidityPct,
  });

  final String? id;
  final DateTime startedAt;
  final double distanceMeters;
  final int movingTimeSeconds;
  final String source;
  final String? routeId;
  final int? averageHeartRate;
  final double? elevationGainMeters;
  final double? temperatureCelsius;
  final double? feelsLikeCelsius;
  final double? windSpeedKmh;
  final double? windDirectionDegrees;
  final double? humidityPct;

  double get paceSecondsPerKm =>
      distanceMeters <= 0 ? 0 : movingTimeSeconds / (distanceMeters / 1000);

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
        id: j['id'] as String?,
        startedAt: DateTime.parse(j['started_at'] as String),
        distanceMeters: _d(j['distance_meters']),
        movingTimeSeconds: _in(j['moving_time_seconds']) ?? 0,
        source: (j['source'] as String?) ?? 'manual',
        routeId: j['route_id'] as String?,
        averageHeartRate: _in(j['average_heart_rate']),
        elevationGainMeters: _dn(j['elevation_gain_meters']),
        temperatureCelsius: _dn(j['temperature_celsius']),
        feelsLikeCelsius: _dn(j['feels_like_celsius']),
        windSpeedKmh: _dn(j['wind_speed_kmh']),
        windDirectionDegrees: _dn(j['wind_direction_degrees']),
        humidityPct: _dn(j['humidity_pct']),
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'route_id': routeId,
        'source': source,
        'started_at': startedAt.toUtc().toIso8601String(),
        'distance_meters': distanceMeters,
        'moving_time_seconds': movingTimeSeconds,
        'average_pace_seconds_per_km': double.parse(paceSecondsPerKm.toStringAsFixed(2)),
        'average_heart_rate': averageHeartRate,
        'elevation_gain_meters': elevationGainMeters,
        'temperature_celsius': temperatureCelsius,
        'feels_like_celsius': feelsLikeCelsius,
        'wind_speed_kmh': windSpeedKmh,
        'wind_direction_degrees': windDirectionDegrees,
        'humidity_pct': humidityPct,
      };
}

class RoutePoint {
  RoutePoint({
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.kmMarker = 0,
    this.bearing,
  });

  final double latitude;
  final double longitude;
  final double? elevation;
  final double kmMarker;
  final double? bearing;

  factory RoutePoint.fromJson(Map<String, dynamic> j) => RoutePoint(
        latitude: _d(j['latitude']),
        longitude: _d(j['longitude']),
        elevation: _dn(j['elevation_meters']),
        kmMarker: _d(j['km_marker']),
        bearing: _dn(j['bearing_degrees']),
      );
}

class RunRoute {
  RunRoute({
    this.id,
    required this.name,
    required this.source,
    required this.distanceMeters,
    required this.startLatitude,
    required this.startLongitude,
    required this.polyline,
    this.elevationGainMeters,
    this.estimatedDurationSeconds,
    this.isFavorite = false,
    this.points = const [],
  });

  final String? id;
  final String name;
  final String source;
  final double distanceMeters;
  final double startLatitude;
  final double startLongitude;
  final String polyline;
  final double? elevationGainMeters;
  final int? estimatedDurationSeconds;
  final bool isFavorite;

  /// Punten per kilometer (met looprichting), alleen geladen in detailweergave.
  final List<RoutePoint> points;

  String get sourceLabel => switch (source) {
        'gpx_upload' => 'GPX',
        'strava_import' => 'Strava',
        _ => 'Getekend',
      };

  RunRoute copyWith({List<RoutePoint>? points, bool? isFavorite}) => RunRoute(
        id: id,
        name: name,
        source: source,
        distanceMeters: distanceMeters,
        startLatitude: startLatitude,
        startLongitude: startLongitude,
        polyline: polyline,
        elevationGainMeters: elevationGainMeters,
        estimatedDurationSeconds: estimatedDurationSeconds,
        isFavorite: isFavorite ?? this.isFavorite,
        points: points ?? this.points,
      );

  factory RunRoute.fromJson(Map<String, dynamic> j) => RunRoute(
        id: j['id'] as String?,
        name: j['name'] as String,
        source: j['source'] as String,
        distanceMeters: _d(j['distance_meters']),
        startLatitude: _d(j['start_latitude']),
        startLongitude: _d(j['start_longitude']),
        polyline: (j['polyline'] as String?) ?? '',
        elevationGainMeters: _dn(j['elevation_gain_meters']),
        estimatedDurationSeconds: _in(j['estimated_duration_seconds']),
        isFavorite: (j['is_favorite'] as bool?) ?? false,
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'name': name,
        'source': source,
        'distance_meters': distanceMeters,
        'elevation_gain_meters': elevationGainMeters,
        'estimated_duration_seconds': estimatedDurationSeconds,
        'start_latitude': startLatitude,
        'start_longitude': startLongitude,
        'polyline': polyline,
        'is_favorite': isFavorite,
      };
}

class RaceEvent {
  RaceEvent({
    this.id,
    required this.name,
    required this.raceDate,
    required this.distanceMeters,
    required this.goalTimeSeconds,
    this.startTime,
    this.startLatitude,
    this.startLongitude,
    this.routeId,
  });

  final String? id;
  final String name;
  final DateTime raceDate;
  final double distanceMeters;
  final int goalTimeSeconds;

  /// "HH:mm" of null.
  final String? startTime;
  final double? startLatitude;
  final double? startLongitude;
  final String? routeId;

  /// Starttijdstip als DateTime (standaard 10:00 als er geen tijd bekend is).
  DateTime get startDateTime {
    var h = 10, m = 0;
    final t = startTime;
    if (t != null) {
      final parts = t.split(':');
      h = int.tryParse(parts[0]) ?? 10;
      m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    }
    return DateTime(raceDate.year, raceDate.month, raceDate.day, h, m);
  }

  int get daysUntil {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(raceDate.year, raceDate.month, raceDate.day)
        .difference(today)
        .inDays;
  }

  factory RaceEvent.fromJson(Map<String, dynamic> j) => RaceEvent(
        id: j['id'] as String?,
        name: j['name'] as String,
        raceDate: DateTime.parse(j['race_date'] as String),
        distanceMeters: _d(j['distance_meters']),
        goalTimeSeconds: _in(j['goal_time_seconds']) ?? 0,
        startTime: (j['start_time'] as String?)?.substring(0, 5),
        startLatitude: _dn(j['start_latitude']),
        startLongitude: _dn(j['start_longitude']),
        routeId: j['route_id'] as String?,
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'name': name,
        'race_date':
            '${raceDate.year.toString().padLeft(4, '0')}-${raceDate.month.toString().padLeft(2, '0')}-${raceDate.day.toString().padLeft(2, '0')}',
        'distance_meters': distanceMeters,
        'goal_time_seconds': goalTimeSeconds,
        'start_time': startTime == null ? null : '$startTime:00',
        'start_latitude': startLatitude,
        'start_longitude': startLongitude,
        'route_id': routeId,
      };
}

/// Weer voor één uur.
class HourWeather {
  HourWeather({
    required this.time,
    required this.temperature,
    this.feelsLike,
    this.humidity,
    this.precipitationProbability,
    this.precipitation,
    required this.windSpeed,
    this.windDirection,
    this.windGusts,
    this.uvIndex,
    this.weatherCode,
    this.isDay = true,
  });

  final DateTime time;
  final double temperature;
  final double? feelsLike;
  final double? humidity;
  final double? precipitationProbability;
  final double? precipitation;
  final double windSpeed;
  final double? windDirection;
  final double? windGusts;
  final double? uvIndex;
  final int? weatherCode;
  final bool isDay;
}

class Forecast {
  Forecast({required this.latitude, required this.longitude, required this.hours});

  final double latitude;
  final double longitude;
  final List<HourWeather> hours;

  /// Het uur dat het dichtst bij [t] ligt.
  HourWeather? at(DateTime t) {
    if (hours.isEmpty) return null;
    HourWeather best = hours.first;
    var bestDiff = (best.time.difference(t)).inMinutes.abs();
    for (final h in hours) {
      final d = h.time.difference(t).inMinutes.abs();
      if (d < bestDiff) {
        best = h;
        bestDiff = d;
      }
    }
    return bestDiff <= 90 ? best : null;
  }
}
