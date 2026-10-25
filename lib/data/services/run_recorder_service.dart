import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/geo.dart';
import '../../core/format.dart';
import '../../domain/intervals.dart';
import '../../domain/route_geometry.dart';
import '../../domain/guided_runs.dart';
import '../../domain/run_coach.dart';
import '../../domain/run_streams.dart';
import '../../domain/run_recorder.dart';
import '../../domain/route_turns.dart';
import '../../domain/route_heads_up.dart';
import '../../domain/poi.dart';
import 'heart_rate_service.dart';
import 'metronome_service.dart';
import 'live_share_service.dart';
import 'notification_service.dart';
import 'sound_service.dart';
import 'rain_service.dart';
import 'recording_store.dart';
import '../../domain/run_helpers.dart';

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
    this.approachingRoute = false,
    this.wayToRoute,
    this.ghostDelta,
    this.nextTurn,
    this.nextTurnIn,
    this.walkRun = false,
    this.treadmillKmh,
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

  /// Nog niet op de route (je loopt ernaartoe) en waar de route ligt.
  final bool approachingRoute;
  final WayToRoute? wayToRoute;

  /// Tegen je record op deze route: seconden achter (+) of voor (-). Null = geen record-race.
  final double? ghostDelta;

  /// Volgende afslag op je route en hoeveel meter je er nog van af bent.
  final RouteTurn? nextTurn;
  final double? nextTurnIn;

  /// Lopen/wandelen-schema: stappen heten "Hardlopen" en "Wandelen".
  final bool walkRun;

  /// Ingestelde loopbandsnelheid (km/u), of null.
  final double? treadmillKmh;

  bool get gpsReady => gpsAccuracy != null && gpsAccuracy! <= RunRecording.maxAccuracy;
}

/// Neemt een run op met GPS. Blijft doorlopen met het scherm uit (Android-melding).
class RunRecorderService {
  RunRecorderService._() {
    NotificationService.instance.runAction.addListener(_onNotificationAction);
  }

  /// Telt op als je in de melding op Stop tikt; het opnamescherm luistert en rondt de run netjes af.
  final stopRequested = ValueNotifier<int>(0);

  void _onNotificationAction() {
    final a = NotificationService.instance.runAction.value;
    if (a == null || !isRecording) return;
    switch (a.id) {
      case 'pause':
        pause();
      case 'resume':
        resume();
      case 'stop':
        stopRequested.value++;
    }
  }
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
  TurnGuide? _turns;
  RouteHeadsUp? _headsUp;
  List<RouteClimb> _climbs = const [];
  List<RoutePoi> _pois = const [];
  List<({double meters, String name})> _landmarks = const [];
  RecordHunt? _hunt;
  Turnaround? _turnaround;
  int _routeTimesBefore = 0;
  double? _targetMeters;
  bool _routeDoneSaid = false;
  DaylightWarner? _daylight;
  bool _daylightChecked = false;

  /// Afslagen aankondigen (stem, trillen en een melding die ook op je horloge komt).
  bool turnByTurn = true;

  /// Cadans-tik in stappen per minuut (null = uit).
  int? cadence;

  /// Spreektempo van de stem (0.4 = rustig, 0.5 = normaal, 0.6 = vlot).
  double speechRate = 0.5;

  /// Laat de stem iets zeggen met het gekozen tempo (om uit te proberen).
  Future<void> previewVoice(String text) async {
    await _ensureTts();
    try {
      await _tts!.setSpeechRate(speechRate);
      await _tts!.speak(text);
    } catch (_) {}
  }
  FuelReminder? _fuel;
  GuidedPlayer? _guided;
  int _ticks = 0;

  /// Doeltempo van de huidige run (s/km), of null.
  double? targetPace;

  RunRecording? get recording => _rec;
  bool get isRecording => _rec != null && _rec!.status != RecorderStatus.finished;

  /// Seconden op handmatige pauze / stilstaand op automatische pauze (voor de herinneringen).
  int _pausedSecs = 0;
  int _stillSecs = 0;

  /// Laatste regenwaarschuwing (niet steeds opnieuw).
  DateTime? _rainWarnedFor;
  final _rain = RainService();

  /// Iets laten uitspreken van buiten de service (bijv. "doelafstand bereikt").
  void say(String text, {bool buzz = false}) {
    if (buzz) _buzz(const [0, 200, 120, 200]);
    final wasVoice = voice;
    voice = true;
    _ensureTts().then((_) {
      _say(text);
      voice = wasVoice;
    }).ignore();
  }

  Future<void> _ensureTts() async {
    if (_tts != null) return;
    _tts = FlutterTts();
    await _configureTts();
  }

  /// Gekozen stem (naam + taal), of null = automatisch de beste Nederlandse stem.
  ({String name, String locale})? voiceChoice;

  /// Nederlandse stemmen op dit toestel, beste eerst (hoogste kwaliteit, en zonder internet vóór met internet).
  Future<List<({String name, String locale, bool network, int quality})>> dutchVoices() async {
    _tts ??= FlutterTts();
    try {
      final raw = await _tts!.getVoices;
      final list = <({String name, String locale, bool network, int quality})>[];
      for (final v in (raw as List? ?? const [])) {
        if (v is! Map) continue;
        final name = '${v['name'] ?? ''}';
        final locale = '${v['locale'] ?? ''}';
        if (!locale.toLowerCase().startsWith('nl')) continue;
        final network = '${v['network_required'] ?? ''}' == '1' || '${v['network_required']}' == 'true' || name.contains('network');
        final quality = int.tryParse('${v['quality'] ?? ''}') ?? (name.contains('network') ? 400 : 300);
        list.add((name: name, locale: locale, network: network, quality: quality));
      }
      list.sort((a, b) {
        final q = b.quality.compareTo(a.quality);
        if (q != 0) return q;
        if (a.network != b.network) return a.network ? 1 : -1;
        // België (nl-BE) na Nederland (nl-NL).
        return a.locale.compareTo(b.locale) * -1;
      });
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Taal, tempo, stem en audio-instellingen op de stem zetten.
  Future<void> _configureTts() async {
    final t = _tts;
    if (t == null) return;
    try {
      await t.setLanguage('nl-NL');
      await t.setSpeechRate(speechRate);
      await t.setPitch(1.0);
      final choice = voiceChoice ?? await _autoVoice();
      if (choice != null) await t.setVoice({'name': choice.name, 'locale': choice.locale});
      // Achter elkaar uitspreken in plaats van elkaar af te kappen, en muziek even zachter zetten.
      await t.setQueueMode(1);
      await t.setAudioAttributesForNavigation();
    } catch (_) {}
  }

  ({String name, String locale})? _auto;
  Future<({String name, String locale})?> _autoVoice() async {
    if (_auto != null) return _auto;
    final v = await dutchVoices();
    // Automatisch: de beste stem die zonder internet werkt (onderweg is er niet altijd bereik).
    final local = v.where((x) => !x.network).toList();
    final pick = local.isNotEmpty ? local.first : (v.isNotEmpty ? v.first : null);
    return _auto = pick == null ? null : (name: pick.name, locale: pick.locale);
  }

  /// Stem kiezen (null = automatisch) en meteen laten horen.
  Future<void> setVoice(({String name, String locale})? v, {String preview = ''}) async {
    voiceChoice = v;
    await _ensureTts();
    await _configureTts();
    if (preview.isNotEmpty) {
      try {
        await _tts!.speak(preview);
      } catch (_) {}
    }
  }

  /// Tik op je afstand: de stem leest afstand, tijd en tempo voor (en de weg terug als je ver van je start bent).
  void announceNow() {
    final r = _rec;
    if (r == null) return;
    final v = view.value;
    final km = (r.distance / 1000).toStringAsFixed(2).replaceAll('.', ',');
    final t = v.movingSeconds.round();
    final time = t >= 3600 ? '${t ~/ 3600} uur ${(t % 3600) ~/ 60} minuten' : '${t ~/ 60} minuten ${t % 60} seconden';
    final parts = <String>[r.indoor ? '' : '$km kilometer', time];
    if (!r.indoor && r.averagePace > 0) {
      final p = r.averagePace.round();
      parts.add('gemiddeld ${p ~/ 60} ${(p % 60).toString().padLeft(2, '0')} per kilometer');
    }
    if (v.heartRate != null) parts.add('hartslag ${v.heartRate}');
    final back = backToStart(r.track);
    if (back != null && back.meters > 300 && back.relative != null) {
      parts.add('je start ligt ${(back.meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} kilometer ${directionWords(back.relative!)}');
    }
    _buzz(const [0, 60]);
    say(parts.where((p) => p.isNotEmpty).join('. '));
  }

  /// Herinneringen tijdens pauze/stilstand en de regenwaarschuwing. Eén keer per seconde.
  void _watchdog(RunRecording r) {
    if (r.status == RecorderStatus.paused) {
      _pausedSecs++;
      if (_pausedSecs == 120 || _pausedSecs == 300 || _pausedSecs == 600) {
        _buzz(const [0, 300, 200, 300]);
        say('Je run staat nog op pauze. Tik op verder als je weer gaat lopen.');
        NotificationService.instance
            .showRunProgress(Fmt.km(r.distance, decimals: 2), 'Nog op pauze: tik om verder te gaan', movingSeconds: view.value.movingSeconds, paused: true)
            .ignore();
      }
    } else {
      _pausedSecs = 0;
    }
    if (r.status == RecorderStatus.autoPaused) {
      _stillSecs++;
      if (_stillSecs == 300 || (_stillSecs > 300 && _stillSecs % 600 == 300)) {
        _buzz(const [0, 500, 250, 500]);
        say('Sta je stil? Je run wordt nog opgenomen. Ben je klaar, stop hem dan.');
        NotificationService.instance
            .showRunProgress(Fmt.km(r.distance, decimals: 2), 'Nog aan het lopen? Al ${_stillSecs ~/ 60} minuten stil. Tik op Stop als je klaar bent.',
                movingSeconds: view.value.movingSeconds, paused: true)
            .ignore();
      }
    } else {
      _stillSecs = 0;
    }
    // Regen: elke 5 minuten de buienradar voor je huidige plek.
    if (!r.indoor && r.isActive && _ticks % 300 == 150 && _position != null) {
      _checkRain(_position!).ignore();
    }
  }

  Future<void> _checkRain(LatLng at) async {
    try {
      final n = await _rain.nowcast(at.lat, at.lon);
      final first = n.firstRain;
      if (first == null || n.rainingNow) return;
      final mins = first.difference(DateTime.now()).inMinutes;
      if (mins < 3 || mins > 20) return;
      if (_rainWarnedFor != null && first.difference(_rainWarnedFor!).inMinutes.abs() < 20) return;
      _rainWarnedFor = first;
      _buzz(const [0, 150, 100, 150]);
      say('Let op: over ongeveer $mins minuten begint het te regenen.');
    } catch (_) {
      // Geen netwerk onderweg: dan maar geen regenwaarschuwing.
    }
  }

  Future<void> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Zet locatie (GPS) aan op je telefoon om je run op te nemen.');
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      throw Exception('Kadans mag je locatie niet gebruiken. Zet dit aan in de instellingen van je telefoon.');
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
              notificationTitle: 'Kadans neemt je run op',
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
      final km = r.tick(1);
      if (km != null) {
        _buzz(const [0, 180, 140, 180]);
        SoundService.instance.play(RwSound.km).ignore();
      }
      if (r.isActive) _sayCue(r);
    }
    _checkIntervals();
    view.value = _snapshot();
    if (r == null || !isRecording || r.status == RecorderStatus.idle) return;
    _ticks++;
    _watchdog(r);
    if (_ticks % 5 == 0) _updateNotification(r);
    if (_ticks % 15 == 0) RecordingStore.save(r).ignore();
  }

  void _updateNotification(RunRecording r) {
    final v = view.value;
    final paused = r.status == RecorderStatus.paused || r.status == RecorderStatus.autoPaused;
    final body = paused
        ? 'Gepauzeerd'
        : [
            if (!r.indoor && r.currentPace > 0) 'Tempo ${Fmt.pace(r.currentPace)}',
            if (!r.indoor && r.averagePace > 0) 'gem. ${Fmt.pace(r.averagePace)}',
            if (v.heartRate != null) '♥ ${v.heartRate}',
            if (v.step != null) '${stepLabel(v.step!.kind, walkRun: v.walkRun)}: nog ${v.step!.byDistance ? '${v.stepRemaining.round()} m' : Fmt.duration(v.stepRemaining)}',
          ].join(' · ');
    // Volg je een route? Dan staat de volgende afslag bovenaan de melding: die zie je ook op je
    // Galaxy Watch, Pixel Watch of ander Wear OS-horloge en op je vergrendelscherm.
    final nav = paused ? null : _navLine(v);
    final title = r.indoor ? 'Loopband${r.treadmillKmh == null ? '' : ' · ${Fmt.km(r.distance, decimals: 2)}'}' : Fmt.km(r.distance, decimals: 2);
    NotificationService.instance
        .showRunProgress(nav ?? title,
            nav == null ? (body.isEmpty ? 'Kadans neemt je run op' : body) : '$title${body.isEmpty ? '' : ' · $body'}',
            movingSeconds: v.movingSeconds, paused: paused)
        .ignore();
  }

  String _wayLine(WayToRoute w) =>
      '↩ Route ${w.meters < 1000 ? '${(w.meters / 10).round() * 10} m' : Fmt.km(w.meters, decimals: 1)} ${w.words}';

  /// Horloge dat alleen basistekens toont (Garmin zonder routes): alleen ← en → in meldingen.
  bool _simpleArrows = false;
  String _arrow(TurnKind k) => _simpleArrows ? k.simpleArrow : k.arrow;

  /// Eén regel navigatie voor de melding: volgende afslag, of waar de route ligt.
  String? _navLine(RecorderView v) {
    if (v.routeRemaining == null) return null;
    final w = v.wayToRoute;
    if ((v.offRoute || v.approachingRoute) && w != null) {
      return _wayLine(w);
    }
    final t = v.nextTurn, d = v.nextTurnIn;
    if (t != null && d != null && d < 1500) {
      final m = d < 20 ? 'nu' : (d >= 150 ? '${(d / 50).round() * 50} m' : '${(d / 10).round() * 10} m');
      return '${_arrow(t.kind)} ${t.kind.label} · $m';
    }
    return '↑ Rechtdoor · nog ${Fmt.km(v.routeRemaining!, decimals: 1)}';
  }

  void _sayCue(RunRecording r) {
    final g = _guided?.update(r.movingSeconds);
    if (g != null) _say(g);
    final f = _fuel?.update(r.movingSeconds);
    if (f != null) {
      _say(f);
      _buzz(const [0, 200, 120, 200]);
    }
    final t = _turnaround?.update(r.movingSeconds);
    if (t != null) {
      _say(t);
      _buzz(const [0, 400, 150, 400]);
    }
    final h = _hunt?.update(r.distance, r.movingSeconds, r.currentPace > 0 ? r.currentPace : r.averagePace);
    if (h != null) {
      _say(h);
      if (h.startsWith('Nieuw record') || h.startsWith('Dit is nu')) {
        SoundService.instance.play(RwSound.finish).ignore();
        _buzz(const [0, 150, 80, 150, 80, 400]);
      }
    }
    if (_intervals != null && !_intervals!.finished) return;
    final f2 = _follower;
    final tm = _targetMeters;
    final remaining = f2 != null
        ? (!f2.approaching && !f2.offRoute ? f2.remaining : null)
        : (tm != null && tm > r.distance ? tm - r.distance : null);
    final c = _cues?.update(r, heartRate: HeartRateService.instance.bpm.value, remainingMeters: remaining);
    if (c != null) _say(c);
  }

  /// Bezienswaardigheden langs de route (komen binnen terwijl je al loopt): onderweg aankondigen.
  void setRouteLandmarks(List<({double meters, String name})> landmarks) {
    final f = _follower;
    if (f == null) return;
    final len = f.original.length;
    _landmarks = f.isLoop && f.joinedAt > 0
        ? [for (final l in landmarks) (meters: ((l.meters - f.joinedAt) % len + len) % len, name: l.name)]
        : landmarks;
    _headsUp = RouteHeadsUp.build(climbs: _climbs, pois: _pois, landmarks: _landmarks);
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
    List<ElevationSample> followProfile = const [],
    RunStreams? ghost,
    GuidedRun? guided,
    double? treadmillKmh,
    Map<int, double> bests = const {},
    Map<int, String> recordLabels = const {},
    double longestBefore = 0,
    double? turnaroundMinutes,
    int routeTimesBefore = 0,
    String? briefing,
    double? targetMeters,
  }) async {
    try {
      _simpleArrows = (await SharedPreferences.getInstance()).getBool('simple_turn_arrows') ?? false;
    } catch (_) {}
    this.haptics = haptics;
    this.voice = voice || intervals != null || targetPace != null;
    this.shareLive = shareLive && !indoor;
    this.targetPace = targetPace;
    _ticks = 0;
    if (indoor) {
      // Geen GPS-opname: de klok telt. Als de GPS al zocht, die stoppen.
      await _sub?.cancel();
      _sub = null;
      _rec = RunRecording(indoor: true)..treadmillKmh = treadmillKmh;
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
    _guided = guided == null ? null : GuidedPlayer(guided);
    if (guided != null) this.voice = true;
    _coach = targetPace == null || indoor ? null : PaceCoach(targetPace);
    _follower = indoor || followRoute.length < 2 ? null : RouteFollower(RouteTrack(followRoute));
    _ghost = _follower == null || ghost == null || ghost.totalDistance < 500 ? null : GhostRace(ghost);
    _turns = _follower == null ? null : TurnGuide(detectTurns(_follower!.track));
    _climbs = _follower == null ? const [] : detectClimbs(followProfile, trackLength: _follower!.track.length);
    _landmarks = const [];
    _headsUp = _follower == null ? null : RouteHeadsUp.build(climbs: _climbs, pois: _pois);
    _hunt = bests.isEmpty && longestBefore < 3000 ? null : RecordHunt(bests: bests, longestBefore: longestBefore, labels: recordLabels);
    _turnaround = turnaroundMinutes == null || turnaroundMinutes <= 0 || _follower != null ? null : Turnaround(turnaroundMinutes * 60);
    _routeTimesBefore = routeTimesBefore;
    _routeDoneSaid = false;
    _targetMeters = targetMeters;
    _daylightChecked = indoor;
    _rec!.start(DateTime.now());
    if (this.voice) {
      _tts ??= FlutterTts();
      await _configureTts();
      SoundService.instance.play(RwSound.start).ignore();
      if (_guided == null) _say(intervals == null ? 'Run gestart. Succes!' : 'Run gestart: ${intervals.name}.');
      if (briefing != null && briefing.isNotEmpty && _guided == null) _say(briefing);
      if (_turnaround != null) _say('Heen en terug: halverwege zeg ik wanneer je moet omdraaien.');
      final g0 = _guided?.update(0);
      if (g0 != null) _say(g0);
    }
    final spm = cadence;
    if (spm != null) MetronomeService.instance.start(spm).ignore();
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

  /// Water en toiletten langs de route (komen binnen terwijl je al loopt): dan ook aankondigen.
  void setRoutePois(List<RoutePoi> pois) {
    final f = _follower;
    _pois = f != null && f.isLoop && f.joinedAt > 0 ? _shiftPois(pois, f) : pois;
    if (_follower != null) _headsUp = RouteHeadsUp.build(climbs: _climbs, pois: _pois, landmarks: _landmarks);
  }

  /// Loopband: snelheid van de band doorgeven (km/u), dan telt de afstand live mee.
  void setTreadmillSpeed(double? kmh) {
    final r = _rec;
    if (r == null || !r.indoor) return;
    r.treadmillKmh = kmh == null || kmh <= 0 ? null : kmh;
    view.value = _snapshot();
    RecordingStore.save(r).ignore();
  }

  void pause() {
    final r = _rec;
    r?.pause();
    MetronomeService.instance.pause().ignore();
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
    MetronomeService.instance.resume().ignore();
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
    if (km != null) {
      _buzz(const [0, 180, 140, 180]);
      SoundService.instance.play(RwSound.km).ignore();
    }
    final follower = _follower;
    if (follower != null && r.isActive) {
      final wasOff = follower.offRoute || follower.approaching;
      final c = follower.update(LatLng(p.latitude, p.longitude), seconds: r.movingSeconds);
      if (follower.rebased) _rebaseRoute(follower);
      if (c != null) {
        _say(c);
        final nowOff = follower.offRoute || follower.approaching;
        // Eraf: lang-kort-lang. Nog steeds eraf: één middellange tik. Weer erop: één korte.
        _buzz(nowOff ? (wasOff ? const [0, 300] : const [0, 500, 200, 500]) : const [0, 150]);
        if (nowOff && follower.way != null) {
          NotificationService.instance
              .showTurn(_wayLine(follower.way!),
                  follower.approaching ? 'Loop naar je route, dan begint de begeleiding' : 'Je bent van je route af')
              .ignore();
        }
      }
      final tg = _turns;
      if (tg != null && turnByTurn && !follower.offRoute && !follower.approaching) {
        final cue = tg.update(follower.progress);
        if (cue != null) {
          _say(cue.text);
          // Links: twee korte tikken, rechts: één lange. Zo voel je de kant ook zonder oortjes.
          if (cue.atTurn) {
            _buzz(cue.turn.kind.isLeft ? const [0, 120, 100, 120] : const [0, 380]);
          } else {
            _buzz(const [0, 60]);
          }
          NotificationService.instance
              .showTurn('${_arrow(cue.turn.kind)} ${cue.atTurn ? 'Nu ${cue.turn.kind.label.toLowerCase()}' : cue.text}',
                  'Kadans-route · nog ${Fmt.km(follower.remaining, decimals: 1)}')
              .ignore();
        }
      }
      if (!_routeDoneSaid &&
          !follower.approaching &&
          follower.track.length > 800 &&
          follower.remaining < 30 &&
          follower.progress > follower.track.length * 0.9) {
        _routeDoneSaid = true;
        final n = _routeTimesBefore + 1;
        _say(n <= 1
            ? 'Route voltooid! Je eerste keer op deze route. Mooi gedaan.'
            : 'Route voltooid! Dit was je ${n}e keer op deze route.');
        SoundService.instance.play(RwSound.finish).ignore();
        _buzz(const [0, 150, 80, 150, 80, 500]);
      }
      final h = follower.offRoute ? null : _headsUp?.update(follower.progress);
      if (h != null) _say(h);
      final g = _ghost;
      if (g != null && !follower.offRoute) {
        final gc = g.update(follower.progress, r.movingSeconds);
        if (gc != null) _say(gc);
      }
    }
    if (!_daylightChecked) {
      _daylightChecked = true;
      _daylight = DaylightWarner(sunTimes(DateTime.now(), p.latitude, p.longitude).sunset);
    }
    if (r.status == RecorderStatus.running) {
      final dl = _daylight?.update(DateTime.now());
      if (dl != null) {
        _say(dl);
        _buzz(const [0, 200, 120, 200]);
      }
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
    SoundService.instance.play(cue.finished ? RwSound.finish : RwSound.interval).ignore();
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

  /// Rondje opgepakt halverwege: afslagen, klimmen en tappunten tellen vanaf het nieuwe begin.
  void _rebaseRoute(RouteFollower f) {
    f.rebased = false;
    final len = f.original.length;
    double shift(double m) => ((m - f.joinedAt) % len + len) % len;
    _turns = TurnGuide(detectTurns(f.track));
    _climbs = [
      for (final c in _climbs) RouteClimb(startMeters: shift(c.startMeters), lengthMeters: c.lengthMeters, gainMeters: c.gainMeters),
    ];
    _pois = _shiftPois(_pois, f);
    final len2 = f.original.length;
    _landmarks = [for (final l in _landmarks) (meters: ((l.meters - f.joinedAt) % len2 + len2) % len2, name: l.name)];
    _headsUp = RouteHeadsUp.build(climbs: _climbs, pois: _pois, landmarks: _landmarks);
    // Je record op deze route is vanaf het echte begin gemeten: dan klopt de vergelijking niet meer.
    _ghost = null;
  }

  List<RoutePoi> _shiftPois(List<RoutePoi> pois, RouteFollower f) {
    final len = f.original.length;
    double shift(double m) => ((m - f.joinedAt) % len + len) % len;
    return [
      for (final p in pois)
        RoutePoi(
            kind: p.kind,
            point: p.point,
            alongMeters: shift(p.alongMeters),
            offsetMeters: p.offsetMeters,
            name: p.name,
            fee: p.fee,
            seasonal: p.seasonal),
    ];
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
      approachingRoute: _follower?.approaching ?? false,
      wayToRoute: _follower?.way,
      walkRun: it?.plan.walkRun ?? false,
      treadmillKmh: r.treadmillKmh,
      ghostDelta: _ghost == null || _follower == null ? null : _ghost!.delta(_follower!.progress, moving),
      nextTurn: turnByTurn ? _turns?.next : null,
      nextTurnIn: turnByTurn && _follower != null ? _turns?.distanceTo(_follower!.progress) : null,
    );
  }

  /// Stopt de opname en geeft de run terug om op te slaan (of null als er niets is).
  Future<RunRecording?> stop() async {
    SoundService.instance.play(RwSound.finish).ignore();
    MetronomeService.instance.stop().ignore();
    final r = _rec;
    await _sub?.cancel();
    _sub = null;
    _tick?.cancel();
    _tick = null;
    r?.finish();
    if (shareLive) await LiveShareService.instance.stop();
    if (r != null && r.distance > 0 && !r.indoor) _say('Run gestopt. ${(r.distance / 1000).toStringAsFixed(2).replaceAll('.', ',')} kilometer.');
    if (r != null && r.indoor) _say('Training gestopt. Goed gedaan.');
    view.value = const RecorderView(status: RecorderStatus.finished);
    HeartRateService.instance.disconnect().catchError((Object _) {});
    RecordingStore.clear().ignore();
    NotificationService.instance.cancelRunProgress().ignore();
    _cues = null;
    _coach = null;
    _follower = null;
    _ghost = null;
    _turns = null;
    _headsUp = null;
    _climbs = const [];
    _pois = const [];
    _daylight = null;
    _daylightChecked = false;
    NotificationService.instance.cancelTurn().ignore();
    _fuel = null;
    _guided = null;
    _hunt = null;
    _turnaround = null;
    _landmarks = const [];
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
      await _configureTts();
    }
    view.value = _snapshot();
  }

  /// Annuleert zonder op te slaan.
  Future<void> discard() async {
    await stop();
    view.value = const RecorderView();
  }
}
