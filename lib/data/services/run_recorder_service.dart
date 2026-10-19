import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/geo.dart';
import '../../domain/run_recorder.dart';
import 'live_share_service.dart';

/// Wat het opnamescherm laat zien.
@immutable
class RecorderView {
  const RecorderView({
    this.status = RecorderStatus.idle,
    this.distance = 0,
    this.movingSeconds = 0,
    this.currentPace = 0,
    this.averagePace = 0,
    this.km = 0,
    this.gpsAccuracy,
    this.error,
  });

  final RecorderStatus status;
  final double distance;
  final double movingSeconds;
  final double currentPace;
  final double averagePace;
  final int km;
  final double? gpsAccuracy;
  final String? error;

  bool get gpsReady => gpsAccuracy != null && gpsAccuracy! <= RunRecording.maxAccuracy;
}

/// Neemt een run op met GPS. Blijft doorlopen met het scherm uit (Android-melding).
class RunRecorderService {
  RunRecorderService._();
  static final instance = RunRecorderService._();

  final view = ValueNotifier(const RecorderView());
  RunRecording? _rec;
  StreamSubscription<Position>? _sub;
  Timer? _tick;
  DateTime? _lastFixAt;
  FlutterTts? _tts;
  bool voice = true;
  bool shareLive = false;

  RunRecording? get recording => _rec;
  bool get isRecording => _rec != null && _rec!.status != RecorderStatus.finished;

  Future<void> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Zet locatie (GPS) aan op je telefoon om je run op te nemen.');
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      throw Exception('RunWise mag je locatie niet gebruiken. Zet dit aan in de instellingen van je telefoon.');
    }
  }

  /// Begint met GPS zoeken (zonder te starten), zodat de start meteen nauwkeurig is.
  Future<void> warmUp() async {
    if (_sub != null) return;
    await _ensurePermission();
    _rec = RunRecording();
    _listen();
  }

  void _listen() {
    final LocationSettings settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 1),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'RunWise neemt je run op',
              notificationText: 'Tik om je run te zien of te stoppen.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(_onPosition, onError: (Object _) {
      view.value = _snapshot(error: 'GPS-signaal kwijt. We proberen het opnieuw.');
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => view.value = _snapshot());
  }

  Future<void> start({bool voice = true, bool shareLive = false, String name = ''}) async {
    this.voice = voice;
    this.shareLive = shareLive;
    if (_sub == null) await warmUp();
    _rec ??= RunRecording();
    _rec!.start(DateTime.now());
    if (voice) {
      _tts ??= FlutterTts();
      try {
        await _tts!.setLanguage('nl-NL');
        await _tts!.setSpeechRate(0.5);
      } catch (_) {}
      _say('Run gestart. Succes!');
    }
    if (shareLive) {
      try {
        await LiveShareService.instance.start(name: name, duration: const Duration(hours: 4), ownStream: false);
      } catch (_) {
        // Delen is een extraatje; de opname gaat gewoon door.
      }
    }
    view.value = _snapshot();
  }

  void pause() {
    _rec?.pause();
    _say('Gepauzeerd.');
    view.value = _snapshot();
  }

  void resume() {
    _rec?.resume();
    _say('We gaan weer.');
    view.value = _snapshot();
  }

  void _onPosition(Position p) {
    final r = _rec;
    if (r == null) return;
    _lastFixAt = DateTime.now();
    final before = r.status;
    final km = r.add(GpsFix(LatLng(p.latitude, p.longitude), p.timestamp, accuracy: p.accuracy, speed: p.speed >= 0 ? p.speed : null));
    if (before == RecorderStatus.running && r.status == RecorderStatus.autoPaused) _say('Automatisch gepauzeerd.');
    if (before == RecorderStatus.autoPaused && r.status == RecorderStatus.running) _say('Verder.');
    if (km != null) _say(kmAnnouncement(r, km));
    if (shareLive && r.isActive) LiveShareService.instance.feed(p);
    view.value = _snapshot(accuracy: p.accuracy);
  }

  void _say(String text) {
    if (!voice || _tts == null) return;
    _tts!.speak(text).catchError((_) => 0);
  }

  RecorderView _snapshot({double? accuracy, String? error}) {
    final r = _rec;
    if (r == null) return const RecorderView();
    // Tussen twee GPS-metingen de klok laten doorlopen (hooguit 5 s).
    var moving = r.movingSeconds;
    if (r.status == RecorderStatus.running && _lastFixAt != null) {
      final since = DateTime.now().difference(_lastFixAt!).inMilliseconds / 1000;
      if (since < 5) moving += since;
    }
    return RecorderView(
      status: r.status,
      distance: r.distance,
      movingSeconds: moving,
      currentPace: r.currentPace,
      averagePace: r.averagePace,
      km: r.kmTimes.length,
      gpsAccuracy: accuracy ?? view.value.gpsAccuracy,
      error: error,
    );
  }

  /// Stopt de opname en geeft de run terug om op te slaan (of null als er niets is).
  Future<RunRecording?> stop() async {
    final r = _rec;
    await _sub?.cancel();
    _sub = null;
    _tick?.cancel();
    _tick = null;
    r?.finish();
    if (shareLive) await LiveShareService.instance.stop();
    if (r != null && r.distance > 0) _say('Run gestopt. ${(r.distance / 1000).toStringAsFixed(2).replaceAll('.', ',')} kilometer.');
    view.value = const RecorderView(status: RecorderStatus.finished);
    _rec = null;
    return r;
  }

  /// Annuleert zonder op te slaan.
  Future<void> discard() async {
    await stop();
    view.value = const RecorderView();
  }
}
