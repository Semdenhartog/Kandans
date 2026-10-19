import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/format.dart';
import '../../domain/availability.dart';
import '../../domain/geo.dart';
import '../../domain/performance_model.dart';
import '../../domain/start_time_scoring.dart';
import '../models/models.dart';

/// Instellingen voor de dagelijkse melding.
class DailyReminderSettings {
  const DailyReminderSettings({required this.enabled, required this.hour, required this.minute});
  final bool enabled;
  final int hour;
  final int minute;

  String get timeLabel => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Dagelijkse melding "beste moment vandaag".
///
/// De meldingen worden ingepland op de telefoon zelf, telkens als RunWise de
/// weersverwachting ophaalt (bij openen of vernieuwen). De verwachting gaat
/// 2 dagen vooruit, dus vandaag en morgen staan altijd klaar.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _kEnabled = 'reminder_enabled';
  static const _kHour = 'reminder_hour';
  static const _kMinute = 'reminder_minute';
  static const _kType = 'last_training_type';
  static const _ids = [101, 102];

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'beste_moment',
      'Beste moment vandaag',
      channelDescription: 'Elke dag je beste vertrektijd voor een run',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  Future<void> init() async {
    if (_ready || !Platform.isAndroid) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    _ready = true;
  }

  Future<DailyReminderSettings> settings() async {
    final p = await SharedPreferences.getInstance();
    return DailyReminderSettings(
      enabled: p.getBool(_kEnabled) ?? false,
      hour: p.getInt(_kHour) ?? 7,
      minute: p.getInt(_kMinute) ?? 30,
    );
  }

  /// Zet de melding aan of uit. Geeft false als de gebruiker geen toestemming gaf.
  Future<bool> setEnabled(bool enabled) async {
    await init();
    if (enabled) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? true;
      if (!granted) return false;
    } else {
      for (final id in _ids) {
        await _plugin.cancel(id);
      }
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, enabled);
    return true;
  }

  Future<void> setTime(int hour, int minute) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kHour, hour);
    await p.setInt(_kMinute, minute);
  }

  Future<void> rememberTrainingType(TrainingType type) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kType, type.index);
  }

  Future<TrainingType> lastTrainingType() async {
    final p = await SharedPreferences.getInstance();
    final i = p.getInt(_kType) ?? 0;
    return TrainingType.values[i.clamp(0, TrainingType.values.length - 1)];
  }

  /// Plant de meldingen voor vandaag en morgen opnieuw in met de nieuwste verwachting.
  Future<void> reschedule({
    required Forecast forecast,
    required PerformanceInsights profile,
    List<LatLng> track = const [],
    int durationMinutes = 45,
    RainNowcast? rain,
    Availability availability = Availability.always,
  }) async {
    if (!Platform.isAndroid) return;
    final s = await settings();
    if (!s.enabled) return;
    await init();
    final type = await lastTrainingType();
    final planner = StartTimePlanner(
      forecast: forecast,
      profile: profile,
      track: track,
      durationMinutes: durationMinutes,
      rain: rain,
      availability: availability,
    );

    final now = DateTime.now();
    for (var day = 0; day < _ids.length; day++) {
      final id = _ids[day];
      await _plugin.cancel(id);
      final date = DateTime(now.year, now.month, now.day + day);
      final notifyAt = DateTime(date.year, date.month, date.day, s.hour, s.minute);
      if (notifyAt.isBefore(now.add(const Duration(minutes: 1)))) continue;

      // Alleen vertrektijden na het meldmoment en vóór 22:00 die dag.
      final from = notifyAt.isAfter(DateTime(date.year, date.month, date.day, 5)) ? notifyAt : DateTime(date.year, date.month, date.day, 5);
      final until = DateTime(date.year, date.month, date.day, 22, 0);
      if (!until.isAfter(from)) continue;
      final best = planner.bestPrecise(type, from: from, horizon: until.difference(from));
      if (best == null) continue;

      final w = best.weather;
      final body = 'Vertrek om ${Fmt.time(best.start)} (${best.verdict.toLowerCase()}, score ${best.score}) · '
          '${Fmt.temp(w.feelsLike ?? w.temperature)} gevoel, wind ${w.windSpeed.round()} km/u. '
          'Training: ${type.label.toLowerCase()}.';
      await _plugin.zonedSchedule(
        id,
        'Je beste moment vandaag',
        body,
        tz.TZDateTime.from(notifyAt.toUtc(), tz.UTC),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
