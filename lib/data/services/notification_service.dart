import 'dart:io';

import 'package:flutter/material.dart' show Color, ValueNotifier;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/format.dart';
import '../../domain/availability.dart';
import '../../domain/geo.dart';
import '../../domain/performance_model.dart';
import '../../domain/extras.dart' show weekendLongRun, weekendText;
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

  /// Hetzelfde nummer als de melding van de GPS-dienst, zodat we die bijwerken in plaats van een tweede te tonen.
  static const _runId = 75415;

  /// Knoppen in de run-melding: 'pause', 'resume' of 'stop' (met een volgnummer zodat elke tik telt).
  final runAction = ValueNotifier<({String id, int n})?>(null);
  int _actions = 0;

  /// Live stand tijdens een run (op je vergrendelscherm en in de meldingenbalk).
  /// Met [movingSeconds] en niet gepauzeerd telt de klok in de melding zelf door (Android-chronometer).
  Future<void> showRunProgress(String title, String body, {double? movingSeconds, bool paused = false}) async {
    if (!_ready) return;
    try {
      final ticking = movingSeconds != null && !paused;
      await _plugin.show(
        _runId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'geolocator_channel_01',
            'Run opnemen',
            channelDescription: 'Je afstand, tijd en tempo terwijl je loopt',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            onlyAlertOnce: true,
            showWhen: ticking,
            usesChronometer: ticking,
            when: ticking ? DateTime.now().millisecondsSinceEpoch - (movingSeconds * 1000).round() : null,
            silent: true,
            playSound: false,
            enableVibration: false,
            visibility: NotificationVisibility.public,
            color: const Color(0xFFFD8A26),
            colorized: true,
            actions: [
              paused
                  ? const AndroidNotificationAction('resume', 'Verder', showsUserInterface: true, cancelNotification: false)
                  : const AndroidNotificationAction('pause', 'Pauze', showsUserInterface: true, cancelNotification: false),
              const AndroidNotificationAction('stop', 'Stop', showsUserInterface: true, cancelNotification: false),
            ],
          ),
        ),
      );
    } catch (_) {}
  }

  /// Mag RunWise meldingen tonen? (Android 13+ vraagt hier apart om.)
  Future<bool> allowed() async {
    await init();
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Vraagt toestemming voor meldingen. Geeft true als het mag.
  Future<bool> requestPermission() async {
    await init();
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  static const _turnId = 75416;

  /// Afslag-melding tijdens het volgen van een route. Gewone (niet vaste) meldingen komen
  /// ook op een gekoppeld horloge (Wear OS, Galaxy Watch, Garmin), zodat dat trilt bij een afslag.
  Future<void> showTurn(String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        _turnId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'afslagen',
            'Afslagen tijdens een run',
            channelDescription: 'Links- of rechtsaf terwijl je een route volgt (ook op je horloge)',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.navigation,
            timeoutAfter: 25000,
            autoCancel: true,
            onlyAlertOnce: false,
            playSound: false,
            visibility: NotificationVisibility.public,
            color: Color(0xFFFD8A26),
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> cancelTurn() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_turnId);
    } catch (_) {}
  }

  Future<void> cancelRunProgress() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_runId);
    } catch (_) {}
  }

  Future<void> init() async {
    if (_ready || !Platform.isAndroid) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) {
        final id = r.actionId;
        if (id == 'pause' || id == 'resume' || id == 'stop') runAction.value = (id: id!, n: ++_actions);
      },
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
      for (final id in [..._ids, _soonId]) {
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
    await _plugin.cancel(_soonId);
    // Seintje 30 minuten voor het beste moment van vandaag (alleen als het een goed moment is).
    try {
      final until = DateTime(now.year, now.month, now.day, 22);
      if (until.isAfter(now)) {
        final best = planner.bestPrecise(type, from: now, horizon: until.difference(now));
        final at = best?.start.subtract(const Duration(minutes: 30));
        if (best != null && best.score >= 70 && at != null && at.isAfter(now.add(const Duration(minutes: 2)))) {
          final w = best.weather;
          await _plugin.zonedSchedule(
            _soonId,
            'Over 30 minuten: je beste loopmoment',
            'Om ${Fmt.time(best.start)} · ${Fmt.temp(w.feelsLike ?? w.temperature)} gevoel, wind ${w.windSpeed.round()} km/u'
                '${(w.precipitationProbability ?? 0) < 20 ? ', droog' : ''} · score ${best.score}. Schoenen aan!',
            tz.TZDateTime.from(at.toUtc(), tz.UTC),
            _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    } catch (_) {}
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
    await scheduleWeeklyReport();
    await _scheduleWeekend(forecast, profile, track);
  }

  static const _weekendId = 105;

  /// Vrijdag om 19:00: wanneer je in het weekend het best je lange duurloop kunt doen.
  Future<void> _scheduleWeekend(Forecast forecast, PerformanceInsights profile, List<LatLng> track) async {
    try {
      await _plugin.cancel(_weekendId);
      final now = DateTime.now();
      if (now.weekday != DateTime.thursday && now.weekday != DateTime.friday) return;
      final at = DateTime(now.year, now.month, now.day + (DateTime.friday - now.weekday), 19);
      if (!at.isAfter(now.add(const Duration(minutes: 2)))) return;
      final planner = StartTimePlanner(forecast: forecast, profile: profile, track: track, durationMinutes: 90);
      final text = weekendText(weekendLongRun(planner, now), Fmt.time);
      if (text == null) return;
      await _plugin.zonedSchedule(
        _weekendId,
        'Je weekend in RunWise',
        text,
        tz.TZDateTime.from(at.toUtc(), tz.UTC),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }

  static const _weeklyId = 103;
  static const _soonId = 104;

  /// Elke maandag om 8:00 een seintje dat je weekoverzicht klaarstaat (alleen als meldingen aan staan).
  Future<void> scheduleWeeklyReport() async {
    if (!Platform.isAndroid) return;
    try {
      final s = await settings();
      await init();
      await _plugin.cancel(_weeklyId);
      if (!s.enabled) return;
      final now = DateTime.now();
      var at = DateTime(now.year, now.month, now.day, 8);
      while (at.weekday != DateTime.monday || !at.isAfter(now)) {
        at = DateTime(at.year, at.month, at.day + 1, 8);
      }
      await _plugin.zonedSchedule(
        _weeklyId,
        'Je week in RunWise',
        'Je weekoverzicht staat klaar: kilometers, schema en tips voor deze week.',
        tz.TZDateTime.from(at.toUtc(), tz.UTC),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'weekoverzicht',
            'Weekoverzicht',
            channelDescription: 'Elke maandag je week in het kort',
            importance: Importance.defaultImportance,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }
}
