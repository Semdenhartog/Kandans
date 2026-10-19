import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';

enum LiveStatus { idle, starting, active, paused, stopping }

/// Huidige stand van live delen.
@immutable
class LiveShareState {
  const LiveShareState({
    this.status = LiveStatus.idle,
    this.shareId,
    this.token,
    this.startedAt,
    this.expiresAt,
    this.lastSentAt,
    this.updates = 0,
    this.error,
  });

  final LiveStatus status;
  final String? shareId;
  final String? token;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final DateTime? lastSentAt;
  final int updates;
  final String? error;

  String? get url => token == null ? null : '${AppConfig.siteUrl}/live.html?t=$token';
  bool get isOn => status == LiveStatus.active || status == LiveStatus.starting;

  LiveShareState copyWith({
    LiveStatus? status,
    DateTime? lastSentAt,
    int? updates,
    String? error,
    bool clearError = false,
  }) =>
      LiveShareState(
        status: status ?? this.status,
        shareId: shareId,
        token: token,
        startedAt: startedAt,
        expiresAt: expiresAt,
        lastSentAt: lastSentAt ?? this.lastSentAt,
        updates: updates ?? this.updates,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Willekeurig, niet te raden token voor de link (32 tekens, ~190 bits).
String newLiveToken([math.Random? random]) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final r = random ?? math.Random.secure();
  return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Moet deze positie verstuurd worden? Elke [minInterval], of eerder als je
/// [minMeters] verder bent. Zo blijft de batterij gespaard.
bool shouldSend({
  required DateTime now,
  DateTime? lastAt,
  double? movedMeters,
  Duration minInterval = const Duration(seconds: 15),
  double minMeters = 60,
}) {
  if (lastAt == null) return true;
  final elapsed = now.difference(lastAt);
  if (elapsed >= minInterval) return true;
  return (movedMeters ?? 0) >= minMeters && elapsed >= const Duration(seconds: 5);
}

/// Deelt je locatie tijdens een run via een geheime link.
/// Blijft actief als je de app wegklikt (Android-melding "RunWise deelt je locatie").
class LiveShareService {
  LiveShareService._();
  static final instance = LiveShareService._();

  final state = ValueNotifier(const LiveShareState());
  StreamSubscription<Position>? _sub;
  Timer? _expiryTimer;
  Position? _lastSent;
  bool _sending = false;

  SupabaseClient get _db => Supabase.instance.client;

  /// Kijkt of er nog een gedeelde run openstaat (bijv. na herstart van de app).
  Future<void> restore() async {
    if (state.value.status != LiveStatus.idle) return;
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await _db
          .from('live_shares')
          .select('id, token, started_at, expires_at')
          .eq('user_id', uid)
          .isFilter('ended_at', null)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return;
      state.value = LiveShareState(
        status: LiveStatus.paused,
        shareId: row['id'] as String,
        token: row['token'] as String,
        startedAt: DateTime.parse(row['started_at'] as String),
        expiresAt: DateTime.parse(row['expires_at'] as String),
      );
    } catch (_) {}
  }

  Future<void> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Zet locatie aan op je telefoon om je live locatie te delen.');
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      throw Exception('RunWise mag je locatie niet gebruiken. Zet dit aan in de instellingen van je telefoon.');
    }
  }

  /// Start delen en geeft de link terug. Met [ownStream] = false levert iemand anders
  /// (de run-opname) de posities aan via [feed], zodat er maar één GPS-stroom loopt.
  Future<String> start({required String name, required Duration duration, bool ownStream = true}) async {
    if (state.value.isOn) return state.value.url!;
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw Exception('Je bent niet ingelogd.');
    await _ensurePermission();
    state.value = const LiveShareState(status: LiveStatus.starting);
    try {
      final token = newLiveToken();
      final now = DateTime.now().toUtc();
      final expires = now.add(duration);
      final row = await _db
          .from('live_shares')
          .insert({
            'user_id': uid,
            'token': token,
            'display_name': name.trim().isEmpty ? null : name.trim().substring(0, math.min(40, name.trim().length)),
            'started_at': now.toIso8601String(),
            'expires_at': expires.toIso8601String(),
          })
          .select('id')
          .single();
      state.value = LiveShareState(
        status: LiveStatus.starting,
        shareId: row['id'] as String,
        token: token,
        startedAt: now,
        expiresAt: expires,
      );
      if (ownStream) {
        _beginStream();
      } else {
        _startExpiryTimer();
      }
      return state.value.url!;
    } catch (e) {
      state.value = const LiveShareState();
      rethrow;
    }
  }

  /// Verder delen met een gedeelde run die nog openstond.
  Future<void> resume() async {
    if (state.value.status != LiveStatus.paused) return;
    await _ensurePermission();
    state.value = state.value.copyWith(status: LiveStatus.starting, clearError: true);
    _beginStream();
  }

  void _beginStream() {
    _sub?.cancel();
    _lastSent = null;
    final LocationSettings settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            intervalDuration: const Duration(seconds: 10),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'RunWise deelt je locatie',
              notificationText: 'Je live locatie is zichtbaar via je link. Open RunWise om te stoppen.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPosition,
      onError: (Object e) {
        state.value = state.value.copyWith(error: 'Locatie kon niet worden bepaald. Staat GPS aan?');
      },
    );
    _startExpiryTimer();
  }

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    final expires = state.value.expiresAt;
    if (expires != null) {
      final left = expires.difference(DateTime.now().toUtc());
      _expiryTimer = Timer(left.isNegative ? Duration.zero : left, () => stop());
    }
  }

  /// Positie van buitenaf (de run-opname).
  void feed(Position p) {
    if (_sub == null && state.value.shareId != null) _onPosition(p);
  }

  Future<void> _onPosition(Position p) async {
    final s = state.value;
    if (s.shareId == null || _sending) return;
    final now = DateTime.now();
    final moved = _lastSent == null
        ? null
        : Geolocator.distanceBetween(_lastSent!.latitude, _lastSent!.longitude, p.latitude, p.longitude);
    if (!shouldSend(now: now, lastAt: s.lastSentAt, movedMeters: moved)) return;
    if (p.accuracy > 100) return; // te onnauwkeurig (bijv. binnen of net gestart)
    _sending = true;
    try {
      final at = now.toUtc().toIso8601String();
      await _db.from('live_shares').update({
        'last_lat': p.latitude,
        'last_lon': p.longitude,
        'last_accuracy': p.accuracy,
        'last_at': at,
      }).eq('id', s.shareId!);
      await _db.from('live_share_points').insert({
        'share_id': s.shareId,
        'lat': p.latitude,
        'lon': p.longitude,
        'recorded_at': at,
      });
      _lastSent = p;
      state.value = state.value.copyWith(
        status: LiveStatus.active,
        lastSentAt: now,
        updates: state.value.updates + 1,
        clearError: true,
      );
    } catch (_) {
      state.value = state.value.copyWith(error: 'Geen internet: we proberen het zo opnieuw.');
    } finally {
      _sending = false;
    }
  }

  /// Stopt delen. Je route en locatie worden direct van de server gewist.
  Future<void> stop() async {
    final s = state.value;
    _expiryTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    if (s.shareId == null) {
      state.value = const LiveShareState();
      return;
    }
    state.value = s.copyWith(status: LiveStatus.stopping);
    try {
      await _db.from('live_shares').update({
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'last_lat': null,
        'last_lon': null,
        'last_accuracy': null,
      }).eq('id', s.shareId!);
      await _db.from('live_share_points').delete().eq('share_id', s.shareId!);
    } catch (_) {
      // Ook als dit mislukt verloopt de link vanzelf.
    }
    state.value = const LiveShareState();
  }
}
