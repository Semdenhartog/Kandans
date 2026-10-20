import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/geo.dart';
import '../../core/format.dart';
import '../../domain/intervals.dart';
import '../../domain/route_geometry.dart';
import '../../domain/run_coach.dart';
import '../../domain/run_streams.dart';
import '../../domain/run_recorder.dart';
import 'heart_rate_service.dart';
import 'live_share_service.dart';
import 'notification_service.dart';
import 'recording_store.dart';

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
    this.heartRate,
    this.hrStatus = HrStatus.off,
    this.indoor = false,
    this.followRoute = const [],
    this.routeRemaining,
    this.offRoute = false,
    this.ghostDelta,
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

  /// Live hartslag van je band (null = geen band of geen signaal).
  final int? heartRate;
  final HrStatus hrStatus;

  /// Loopband (geen GPS).
  final bool indoor;

  /// Route die je volgt (leeg = geen), wat er nog over is en of je ervan af bent.
  final List<LatLng> followRoute;
  final double? routeRemaining;
  final bool offRoute;

  /// Tegen je record op deze route: seconden achter (+) of voor (-). Null = geen record-race.
  final double? ghostDelta;

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

  /// Trillen bij elke kilometer en bij intervalwissels (handig zonder oortjes).
  bool haptics = true;
  IntervalTracker? _intervals;
  LatLng? _position;
  CueScheduler? _cues;
  PaceCoach? _coach;
  RouteFollower? _follower;
  GhostRace? _ghost;
  FuelReminder? _fuel;
  int _ticks = 0;

  /// Doeltempo van de huidige run (s/km), of null.
  double? targetPace;

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
    // Onthouden hartslagband alvast verbinden.
    HeartRateService.instance.autoConnect().catchError((Object _) {});
  }

  void _listen({bool indoor = false}) {
    // Binnen (loopband) hebben we geen nauwkeurige GPS nodig; de dienst houdt de app wel wakker.
    final LocationSettings settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: indoor ? LocationAccuracy.lowest : LocationAccuracy.bestForNavigation,
            distanceFilter: indoor ? 500 : 0,
            intervalDuration: Duration(seconds: indoor ? 30 : 1),
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
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    final r = _rec;
    if (r != null && r.indoor) {
      r.tick(1);
      if (r.isActive) _sayCue(r);
    }
    _checkIntervals();
    view.value = _snapshot();
    if (r == null || !isRecording || r.status == RecorderStatus.idle) return;
    _ticks++;
    if (_ticks % 5 == 0) _updateNotification(r);
    if (_ticks % 15 == 0) RecordingStore.save(r).ignore();
  }

  void _updateNotification(RunRecording r) {
    final v = view.value;
    final paused = r.status == RecorderStatus.paused || r.status == RecorderStatus.autoPaused;
    final title = r.indoor
        ? 'Loopband · ${Fmt.duration(v.movingSeconds)}'
        : '${Fmt.km(r.distance, decimals: 2)} · ${Fmt.duration(v.movingSeconds)}';
    final body = paused
        ? 'Gepauzeerd'
        : [
            if (!r.indoor && r.currentPace > 0) 'Tempo ${Fmt.pace(r.currentPace)}',
            if (!r.indoor && r.averagePace > 0) 'gem. ${Fmt.pace(r.averagePace)}',
            if (v.heartRate != null) '♥ ${v.heartRate}',
            if (v.step != null) '${v.step!.kind.label}: nog ${v.step!.byDistance ? '${v.stepRemaining.round()} m' : Fmt.duration(v.stepRemaining)}',
          ].join(' · ');
    NotificationService.instance.showRunProgress(title, body.isEmpty ? 'RunWise neemt je run op' : body).ignore();
  }

  void _sayCue(RunRecording r) {
    final f = _fuel?.update(r.movingSeconds);
    if (f != null) {
      _say(f);
      _buzz(const [0, 200, 120, 200]);
    }
    if (_intervals != null && !_intervals!.finished) return;
    final c = _cues?.update(r, heartRate: HeartRateService.instance.bpm.value);
    if (c != null) _say(c);
  }

  Future<void> start({
    bool voice = true,
    bool shareLive = false,
    String name = '',
    IntervalPlan? intervals,
    bool haptics = true,
    bool indoor = false,
    CueSettings cues = const CueSettings(),
    double? targetPace,
    List<LatLng> followRoute = const [],
    RunStreams? ghost,
  }) async {
    this.haptics = haptics;
    this.voice = voice || intervals != null || targetPace != null;
    this.shareLive = shareLive && !indoor;
    this.targetPace = targetPace;
    _ticks = 0;
    if (indoor) {
      // Geen GPS-opname: de klok telt. Als de GPS al zocht, die stoppen.
      await _sub?.cancel();
      _sub = null;
      _rec = RunRecording(indoor: true);
      try {
        await _ensurePermission();
        _listen(indoor: true);
      } catch (_) {
        _tick?.cancel();
        _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
      }
      HeartRateService.instance.autoConnect().catchError((Object _) {});
    } else {
      if (_sub == null) await warmUp();
      _rec ??= RunRecording();
    }
    // Op de loopband melden we op tijd (afstand weten we niet).
    _cues = CueScheduler(indoor && cues.every.meters != null ? cues.copyWith(every: CueEvery.fiveMin) : cues);
    _fuel = cues.fuel ? FuelReminder() : null;
    _coach = targetPace == null || indoor ? null : PaceCoach(targetPace);
    _follower = indoor || followRoute.length < 2 ? null : RouteFollower(RouteTrack(followRoute));
    _ghost = _follower == null || ghost == null || ghost.totalDistance < 500 ? null : GhostRace(ghost);
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
    final r = _rec;
    r?.pause();
    _say('Gepauzeerd.');
    view.value = _snapshot();
    if (r != null) {
      RecordingStore.save(r).ignore();
      _updateNotification(r);
    }
  }

  void resume() {
    final r = _rec;
    r?.resume();
    _say('We gaan weer.');
    view.value = _snapshot();
    if (r != null) _updateNotification(r);
  }

  void _onPosition(Position p) {
    final r = _rec;
    if (r == null || r.indoor) return;
    _lastFixAt = DateTime.now();
    final before = r.status;
    r.heartRate = HeartRateService.instance.bpm.value;
    final km = r.add(GpsFix(LatLng(p.latitude, p.longitude), p.timestamp,
        accuracy: p.accuracy, speed: p.speed >= 0 ? p.speed : null, altitude: p.altitude == 0 ? null : p.altitude));
    if (before == RecorderStatus.running && r.status == RecorderStatus.autoPaused) _say('Automatisch gepauzeerd.');
    if (before == RecorderStatus.autoPaused && r.status == RecorderStatus.running) _say('Verder.');
    if (km != null) _buzz(const [0, 180, 140, 180]);
    final follower = _follower;
    if (follower != null && r.isActive) {
      final c = follower.update(LatLng(p.latitude, p.longitude));
      if (c != null) {
        _say(c);
        _buzz(follower.offRoute ? const [0, 500, 200, 500] : const [0, 150]);
      }
      final g = _ghost;
      if (g != null && !follower.offRoute) {
        final gc = g.update(follower.progress, r.movingSeconds);
        if (gc != null) _say(gc);
      }
    }
    if (r.status == RecorderStatus.running) {
      _sayCue(r);
      final coach = _coach;
      if (coach != null && (_intervals == null || _intervals!.finished)) {
        final c = coach.update(r.movingSeconds, r.currentPace);
        if (c != null) {
          _say(c);
          _buzz(const [0, 90, 90, 90]);
        }
      }
    }
    _position = LatLng(p.latitude, p.longitude);
    _checkIntervals();
    if (shareLive && r.isActive) LiveShareService.instance.feed(p);
    view.value = _snapshot(accuracy: p.accuracy);
  }

  void _checkIntervals() {
    final it = _intervals, r = _rec;
    if (it == null || r == null || !r.isActive || it.finished) return;
    final cue = it.update(_movingNow(), r.distance);
    if (cue != null) {
      _say(cue.text);
      _buzzFor(cue, it);
    }
  }

  void _buzzFor(IntervalCue cue, IntervalTracker it) {
    if (!cue.stepChanged) {
      _buzz(const [0, 120]);
    } else if (cue.finished) {
      _buzz(const [0, 300, 150, 300, 150, 600]);
    } else if (it.current?.kind == StepKind.work) {
      _buzz(const [0, 400, 120, 400, 120, 400]);
    } else {
      _buzz(const [0, 700]);
    }
  }

  void _buzz(List<int> pattern) {
    if (!haptics) return;
    Vibration.vibrate(pattern: pattern).catchError((_) {});
  }

  /// Sla de huidige intervalstap over (bijv. als je eerder klaar bent met inlopen).
  void skipStep() {
    final it = _intervals, r = _rec;
    if (it == null || r == null) return;
    final cue = it.skip(_movingNow(), r.distance);
    if (cue != null) {
      _say(cue.text);
      _buzzFor(cue, it);
    }
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
      heartRate: HeartRateService.instance.bpm.value,
      hrStatus: HeartRateService.instance.status.value,
      indoor: r.indoor,
      followRoute: _follower?.track.points ?? const [],
      routeRemaining: _follower?.remaining,
      offRoute: _follower?.offRoute ?? false,
      ghostDelta: _ghost == null || _follower == null ? null : _ghost!.delta(_follower!.progress, moving),
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
    HeartRateService.instance.disconnect().catchError((Object _) {});
    RecordingStore.clear().ignore();
    NotificationService.instance.cancelRunProgress().ignore();
    _cues = null;
    _coach = null;
    _follower = null;
    _ghost = null;
    _fuel = null;
    _rec = null;
    _intervals = null;
    _position = null;
    return r;
  }

  /// Een onderbroken run terugzetten (op pauze), zodat je verder kunt lopen of hem kunt opslaan.
  Future<void> restore(RunRecording r, {bool voice = true}) async {
    await _sub?.cancel();
    _sub = null;
    _rec = r;
    this.voice = voice;
    _cues = CueScheduler(const CueSettings());
    try {
      await _ensurePermission();
      _listen(indoor: r.indoor);
    } catch (_) {
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    }
    if (voice) {
      _tts ??= FlutterTts();
      try {
        await _tts!.setLanguage('nl-NL');
        await _tts!.setQueueMode(1);
        await _tts!.setAudioAttributesForNavigation();
      } catch (_) {}
    }
    view.value = _snapshot();
  }

  /// Annuleert zonder op te slaan.
  Future<void> discard() async {
    await stop();
    view.value = const RecorderView();
  }
}
