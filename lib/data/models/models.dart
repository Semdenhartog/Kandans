/// Datamodellen die overeenkomen met de Supabase-tabellen.
library;

import '../../domain/route_geometry.dart';

export '../../domain/route_geometry.dart' show ElevationSample;

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
    this.isPremium = false,
    this.coachFreeQuestionsUsed = 0,
  });

  final String id;
  final bool isPremium;
  final int coachFreeQuestionsUsed;
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
        isPremium: (j['is_premium'] as bool?) ?? false,
        coachFreeQuestionsUsed: _in(j['coach_free_questions_used']) ?? 0,
      );
}

/// Eén bericht in het gesprek met de AI-coach.
class CoachMessage {
  CoachMessage({required this.role, required this.content, required this.createdAt, this.id});

  final String? id;
  final String role; // 'user' of 'assistant'
  final String content;
  final DateTime createdAt;

  bool get isUser => role == 'user';

  factory CoachMessage.fromJson(Map<String, dynamic> j) => CoachMessage(
        id: j['id'] as String?,
        role: j['role'] as String,
        content: j['content'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
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
    this.trackPolyline,
    this.routeLinkLocked = false,
    this.shoeId,
    this.feel,
    this.note,
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

  /// GPS-spoor van de run (Google-polyline, uit Strava). Leeg of null = geen spoor.
  final String? trackPolyline;

  /// De gebruiker heeft zelf de route gekozen of losgemaakt: niet automatisch koppelen.
  final bool routeLinkLocked;

  bool get hasTrack => (trackPolyline ?? '').isNotEmpty;

  /// Schoen waarop je liep (null = je standaardschoen, als je die hebt).
  final String? shoeId;

  /// Hoe voelde het: 1 = zwaar, 2 = oké, 3 = top.
  final int? feel;
  final String? note;

  /// Automatisch aan de route gekoppeld (niet door de gebruiker gekozen).
  bool get autoLinked => routeId != null && !routeLinkLocked && source != 'manual';

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
        trackPolyline: j['track_polyline'] as String?,
        routeLinkLocked: (j['route_link_locked'] as bool?) ?? false,
        shoeId: j['shoe_id'] as String?,
        feel: _in(j['feel']),
        note: j['note'] as String?,
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
    this.elevationProfile = const [],
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

  /// Hoogte elke ~50 m (leeg bij oudere of getekende routes).
  final List<ElevationSample> elevationProfile;

  /// Hoogteprofiel, of anders de hoogtes per kilometer als die er zijn.
  List<ElevationSample> get profileOrKmPoints {
    if (elevationProfile.length >= 3) return elevationProfile;
    final km = [
      for (final p in points)
        if (p.elevation != null) ElevationSample(p.kmMarker * 1000, p.elevation!),
    ];
    return km.length >= 3 ? km : const [];
  }

  String get sourceLabel => switch (source) {
        'gpx_upload' => 'GPX',
        'strava_import' => 'Strava',
        'generated' => 'RunWise',
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
        elevationProfile: elevationProfile,
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
        elevationProfile: ElevationSample.listFromJson(j['elevation_profile']),
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
        if (elevationProfile.isNotEmpty) 'elevation_profile': [for (final e in elevationProfile) e.toJson()],
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
  Forecast({
    required this.latitude,
    required this.longitude,
    required this.hours,
    this.quarters = const [],
  });

  final double latitude;
  final double longitude;
  final List<HourWeather> hours;

  /// Weer per kwartier (komende dagen). Leeg als het niet beschikbaar is.
  final List<HourWeather> quarters;

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

  /// Weer op precies [t]: tussen twee kwartieren in geschat (geïnterpoleerd).
  /// Zonder kwartierdata valt het terug op het dichtstbijzijnde uur.
  HourWeather? precise(DateTime t) {
    final hourly = at(t);
    HourWeather? before;
    HourWeather? after;
    for (final q in quarters) {
      if (!q.time.isAfter(t)) {
        before = q;
      } else {
        after = q;
        break;
      }
    }
    if (before == null) return hourly;
    if (after == null || t.difference(before.time).inMinutes > 30) {
      return t.difference(before.time).inMinutes <= 15 ? _withHourly(before, hourly, t) : hourly;
    }
    final span = after.time.difference(before.time).inSeconds;
    final f = span <= 0 ? 0.0 : t.difference(before.time).inSeconds / span;
    double lerp(double a, double b) => a + (b - a) * f;
    double? lerpN(double? a, double? b) => (a == null || b == null) ? (a ?? b) : lerp(a, b);
    final near = f < 0.5 ? before : after;
    return HourWeather(
      time: t,
      temperature: lerp(before.temperature, after.temperature),
      feelsLike: lerpN(before.feelsLike, after.feelsLike),
      humidity: hourly?.humidity,
      precipitationProbability: hourly?.precipitationProbability,
      precipitation: lerpN(before.precipitation, after.precipitation),
      windSpeed: lerp(before.windSpeed, after.windSpeed),
      windDirection: near.windDirection,
      windGusts: lerpN(before.windGusts, after.windGusts),
      uvIndex: hourly?.uvIndex,
      weatherCode: hourly?.weatherCode,
      isDay: near.isDay,
    );
  }

  HourWeather _withHourly(HourWeather q, HourWeather? h, DateTime t) => HourWeather(
        time: t,
        temperature: q.temperature,
        feelsLike: q.feelsLike,
        humidity: h?.humidity,
        precipitationProbability: h?.precipitationProbability,
        precipitation: q.precipitation,
        windSpeed: q.windSpeed,
        windDirection: q.windDirection,
        windGusts: q.windGusts,
        uvIndex: h?.uvIndex,
        weatherCode: h?.weatherCode,
        isDay: q.isDay,
      );
}

/// Buienverwachting per 5 minuten voor de komende 2 uur (Buienradar).
class RainNowcast {
  RainNowcast({required this.points, required this.fetchedAt});

  /// Tijdstip en neerslag in mm per uur, oplopend in tijd.
  final List<({DateTime time, double mmPerHour})> points;
  final DateTime fetchedAt;

  bool covers(DateTime t) =>
      points.isNotEmpty && !t.isBefore(points.first.time) && !t.isAfter(points.last.time.add(const Duration(minutes: 5)));

  /// Neerslag op [t] (mm/u), of null als [t] buiten de 2 uur valt.
  double? at(DateTime t) {
    if (!covers(t)) return null;
    var value = points.first.mmPerHour;
    for (final p in points) {
      if (p.time.isAfter(t)) break;
      value = p.mmPerHour;
    }
    return value;
  }

  /// Eerste moment met regen (>= 0,1 mm/u), of null als het droog blijft.
  DateTime? get firstRain => points.where((p) => p.mmPerHour >= 0.1).map((p) => p.time).firstOrNull;

  /// Eerste droge moment na regen, of null.
  DateTime? get firstDry => points.where((p) => p.mmPerHour < 0.1).map((p) => p.time).firstOrNull;

  bool get rainingNow => points.isNotEmpty && points.first.mmPerHour >= 0.1;
}

/// Een paar hardloopschoenen.
class Shoe {
  Shoe({
    this.id,
    required this.name,
    this.startKm = 0,
    this.limitKm = 700,
    this.isDefault = false,
    this.retired = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String? id;
  final String name;

  /// Kilometers die er al op zaten toen je de schoen toevoegde.
  final double startKm;

  /// Na hoeveel km je een seintje wilt (meestal 600 tot 800).
  final int limitKm;
  final bool isDefault;
  final bool retired;
  final DateTime createdAt;

  factory Shoe.fromJson(Map<String, dynamic> j) => Shoe(
        id: j['id'] as String?,
        name: j['name'] as String,
        startKm: _d(j['start_km']),
        limitKm: _in(j['limit_km']) ?? 700,
        isDefault: (j['is_default'] as bool?) ?? false,
        retired: (j['retired'] as bool?) ?? false,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  Map<String, dynamic> toInsert() => {
        'name': name,
        'start_km': startKm,
        'limit_km': limitKm,
        'is_default': isDefault,
      };
}
