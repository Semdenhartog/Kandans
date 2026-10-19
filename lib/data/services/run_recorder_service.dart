import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/geo.dart';
import '../../domain/intervals.dart';
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
    this.track = const [],
    this.position,
    this.step,
    this.nextStep,
    this.stepRemaining = 0,
    this.stepProgress = 0,
    this.workNumber = 0,
    this.reps = 0,
    this.intervalsDone = false,
  });

  final RecorderStatus status;
  final double distance;
  final double movingSeconds;
  final double currentPace;
  final double averagePace;
  final int km;
  final double? gpsAccuracy;
  final String? error;

  /// Gelopen spoor (voor de kaart tijdens het lopen).
  final List<LatLng> track;
  final LatLng? position;

  /// Intervallen: huidige en volgende stap, wat er nog over is (s of m) en voortgang 0..1.
  final IntervalStep? step;
  final IntervalStep? nextStep;
  final double stepRemaining;
  final double stepProgress;
  final int workNumber;
  final int reps;
  final bool intervalsDone;

  bool get hasIntervals => step != null || intervalsDone;

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
  IntervalTracker? _intervals;
  LatLng? _position;

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
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkIntervals();
      view.value = _snapshot();
    });
  }

  Future<void> start({bool voice = true, bool shareLive = false, String name = '', IntervalPlan? intervals}) async {
    this.voice = voice || intervals != null;
    this.shareLive = shareLive;
    if (_sub == null) await warmUp();
    _rec ??= RunRecording();
    _rec!.start(DateTime.now());
    if (this.voice) {
      _tts ??= FlutterTts();
      try {
        await _tts!.setLanguage('nl-NL');
        await _tts!.setSpeechRate(0.5);
        // Achter elkaar uitspreken in plaats van elkaar af te kappen, en muziek even zachter zetten.
        await _tts!.setQueueMode(1);
        await _tts!.setAudioAttributesForNavigation();
      } catch (_) {}
      _say(intervals == null ? 'Run gestart. Succes!' : 'Run gestart: ${intervals.name}.');
    }
    _intervals = intervals == null ? null : IntervalTracker(intervals);
    final first = _intervals?.start(0, 0);
    if (first != null) _say(first.text);
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
    // Tijdens intervallen geen lange kilometer-melding, die zit de aanwijzingen in de weg.
    if (km != null && _intervals == null) _say(kmAnnouncement(r, km));
    _position = LatLng(p.latitude, p.longitude);
    _checkIntervals();
    if (shareLive && r.isActive) LiveShareService.instance.feed(p);
    view.value = _snapshot(accuracy: p.accuracy);
  }

  void _checkIntervals() {
    final it = _intervals, r = _rec;
    if (it == null || r == null || !r.isActive || it.finished) return;
    final cue = it.update(_movingNow(), r.distance);
    if (cue != null) _say(cue.text);
  }

  /// Sla de huidige intervalstap over (bijv. als je eerder klaar bent met inlopen).
  void skipStep() {
    final it = _intervals, r = _rec;
    if (it == null || r == null) return;
    final cue = it.skip(_movingNow(), r.distance);
    if (cue != null) _say(cue.text);
    view.value = _snapshot();
  }

  void _say(String text) {
    if (!voice || _tts == null) return;
    _tts!.speak(text, focus: true).catchError((_) => 0);
  }

  /// Bewegende tijd inclusief de seconden sinds de laatste GPS-meting (hooguit 5 s).
  double _movingNow() {
    final r = _rec;
    if (r == null) return 0;
    var moving = r.movingSeconds;
    if (r.status == RecorderStatus.running && _lastFixAt != null) {
      final since = DateTime.now().difference(_lastFixAt!).inMilliseconds / 1000;
      if (since < 5) moving += since;
    }
    return moving;
  }

  RecorderView _snapshot({double? accuracy, String? error}) {
    final r = _rec;
    if (r == null) return const RecorderView();
    // Tussen twee GPS-metingen de klok laten doorlopen (hooguit 5 s).
    final moving = _movingNow();
    final it = _intervals;
    return RecorderView(
      status: r.status,
      distance: r.distance,
      movingSeconds: moving,
      currentPace: r.currentPace,
      averagePace: r.averagePace,
      km: r.kmTimes.length,
      gpsAccuracy: accuracy ?? view.value.gpsAccuracy,
      error: error,
      track: r.track,
      position: _position,
      step: it?.current,
      nextStep: it?.next,
      stepRemaining: it == null ? 0 : it.remaining(moving, r.distance),
      stepProgress: it == null ? 0 : it.progress(moving, r.distance),
      workNumber: it?.workNumber ?? 0,
      reps: it?.plan.reps ?? 0,
      intervalsDone: it?.finished ?? false,
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
    _intervals = null;
    _position = null;
    return r;
  }

  /// Annuleert zonder op te slaan.
  Future<void> discard() async {
    await stop();
    view.value = const RecorderView();
  }
}
