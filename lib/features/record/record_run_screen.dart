import 'dart:convert';
import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/device_extras.dart';
import '../../data/services/heart_rate_service.dart';
import '../../data/services/location_service.dart' show quickPosition;
import '../../core/error_reporter.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/pending_runs.dart';
import '../challenges/challenges.dart' show ChallengeLiveChip;
import '../../data/services/review_service.dart';
import '../../data/services/poi_service.dart';
import '../../data/services/route_photos_service.dart' show routePhotosProvider;
import '../../data/services/run_recorder_service.dart';
import '../../data/services/sound_service.dart';
import '../../data/services/sync_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/badges.dart' as bd;
import '../../domain/best_efforts.dart';
import '../../domain/geo.dart';
import '../../domain/guided_runs.dart';
import '../../domain/live_quests.dart';
import '../../domain/heart_rate.dart';
import '../../domain/run_streams.dart';
import '../../domain/intervals.dart';
import '../../domain/run_coach.dart';
import '../../domain/run_helpers.dart';
import '../../domain/run_recorder.dart';
import '../../domain/training_plan.dart';
import '../../domain/route_geometry.dart';
import '../../domain/route_photos.dart' show projectOnTrack, PhotoSource;
import '../../domain/start_time_scoring.dart' show RouteWind, routeWind;
import '../../domain/route_turns.dart';
import '../../domain/extras.dart' show daysAgoWords, calendarDaysBetween;
import '../../domain/shoes.dart';
import '../../shared/permission_primer.dart';
import '../../shared/rolling_text.dart';
import '../../shared/segmented.dart';
import '../../shared/widgets.dart';
import '../routes/route_map.dart' show LiveTrackMap;
import '../routes/turn_list_card.dart' show TurnArrow;
import 'interval_picker.dart';
import 'quick_start.dart';
import '../profile/emergency_contact.dart';
import 'run_summary_screen.dart';
import '../challenges/community_screen.dart' show refreshCommunityQuietly;
import '../../data/services/community_service.dart' show communityServiceProvider;

/// Opent het opnamescherm. Met [plan] of [targetPace] staat een training uit je schema al klaar.
void openRecorder(BuildContext context, {IntervalPlan? plan, double? targetPace, String? sessionTitle, RunRoute? route, bool? indoor}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => RecordRunScreen(initialPlan: plan, initialTargetPace: targetPace, sessionTitle: sessionTitle, initialRoute: route, initialIndoor: indoor),
  ));
}

/// Een run opnemen met GPS, met stemcoach per kilometer.
class RecordRunScreen extends ConsumerStatefulWidget {
  const RecordRunScreen({super.key, this.initialPlan, this.initialTargetPace, this.sessionTitle, this.initialRoute, this.initialIndoor});

  /// Vanuit de snelkoppeling "Loopband": meteen binnen-modus.
  final bool? initialIndoor;

  /// Vanuit een route: deze route volgen (en tegen je record racen).
  final RunRoute? initialRoute;

  /// Vanuit je trainingsschema: deze training staat al klaar.
  final IntervalPlan? initialPlan;
  final double? initialTargetPace;
  final String? sessionTitle;

  @override
  ConsumerState<RecordRunScreen> createState() => _RecordRunScreenState();
}

class _RecordRunScreenState extends ConsumerState<RecordRunScreen> {
  final _svc = RunRecorderService.instance;
  bool _voice = true;
  bool _share = false;
  bool _saving = false;
  bool _locked = false;
  bool _haptics = true;

  /// Afslagen aankondigen bij het volgen van een route.
  bool _turnByTurn = true;

  /// Cadans-tik (stappen per minuut), null = uit.
  int? _cadence;
  bool _batteryDone = true;
  bool _indoor = false;
  bool _sounds = true;

  /// Live opdrachten (sprints, snelle minuut) tijdens een gewone run.
  bool _quests = false;

  /// Doelafstand (km): de ring loopt vol naar dit doel. Null = per kilometer.
  double? _targetKm;
  bool _targetReached = false;

  /// Alle opties tonen (anders alleen de meestgebruikte en wat aan staat).
  bool _moreOpts = false;

  /// Zonmodus: pikzwart, scherm op volle helderheid en grotere cijfers.
  bool _sunMode = false;

  /// Nachtmodus: rood en gedimd beeld tijdens het lopen in het donker.
  bool _nightMode = false;

  /// Start ingedrukt terwijl de GPS nog zoekt: begint vanzelf zodra hij klaar is.
  bool _armed = false;

  int? _battery;
  bool _charging = false;

  /// Loopbandsnelheid (km/u) om mee te starten; null = alleen de klok.
  double? _tmKmh;
  double? _targetPace;
  CueSettings _cues = const CueSettings();
  String? _shoeId;
  bool _shoeChosen = false;
  RunRoute? _route;

  /// Heen en terug op tijd (minuten); null = uit.
  double? _turnaroundMin;

  /// Weer en wind voor de briefing bij de start (vooraf opgehaald).
  String? _briefing;
  RunStreams? _ghost;
  int? _ghostTime;
  bool _raceGhost = true;
  GuidedRun? _guided;
  String? _error;
  IntervalPlan? _plan;
  final _pages = PageController();
  int _page = 0;

  static const _planKey = 'last_interval_plan';

  @override
  void initState() {
    super.initState();
    _svc.stopRequested.addListener(_stopFromNotification);
    _svc.view.addListener(_onView);
    _readBattery();
    final r = widget.initialRoute;
    if (r != null && r.id != null) {
      _route = r;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadGhost(r.id!));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareBriefing());
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() {
          _haptics = p.getBool('rec_haptics') ?? true;
          _quests = p.getBool('rec_quests') ?? false;
          _turnByTurn = p.getBool('rec_turns') ?? true;
          final sr = p.getDouble('rec_speech_rate');
          if (sr != null && sr >= 0.3 && sr <= 0.7) _svc.speechRate = sr;
          final vn = p.getString('rec_voice_name'), vl = p.getString('rec_voice_locale');
          if (vn != null && vl != null) _svc.voiceChoice = (name: vn, locale: vl);
          final cad = p.getInt('rec_cadence');
          _cadence = cad == null || cad <= 0 ? null : cad;
          _indoor = widget.initialIndoor ?? p.getBool('rec_indoor') ?? false;
          final tk = p.getDouble('rec_target_km');
          _targetKm = tk == null || tk <= 0 ? null : tk;
          _sunMode = p.getBool('rec_sun_mode') ?? false;
          _nightMode = !_sunMode && (p.getBool('rec_night') ?? false);
          _tmKmh = p.getDouble('rec_tm_kmh');
          _sounds = p.getBool('sounds_on') ?? true;
          final tp = p.getDouble('rec_target_pace');
          _targetPace = tp == null || tp <= 0 ? null : tp;
          try {
            final c = p.getString('rec_cues');
            if (c != null) _cues = CueSettings.fromJson(jsonDecode(c));
          } catch (_) {}
          _batteryDone = !Platform.isAndroid || (p.getBool('battery_explained') ?? false);
        });
      }
      if (widget.sessionTitle != null) {
        // Training uit je schema gaat voor de laatst gebruikte instellingen.
        if (mounted) {
          setState(() {
            _plan = widget.initialPlan;
            _targetPace = widget.initialTargetPace;
            _indoor = false;
          });
        }
        return;
      }
      final raw = p.getString(_planKey);
      if (raw == null || !mounted) return;
      try {
        setState(() => _plan = IntervalPlan.fromJson(jsonDecode(raw)));
      } catch (_) {}
    }).ignore();
    if (!_svc.isRecording) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!_indoor) {
          await explainLocationFirst(context,
              why: 'Om je run op te nemen meet Kadans met GPS waar je loopt: afstand, tempo en je route op de kaart.');
        }
        if (!mounted) return;
        _svc.warmUp().catchError((Object e) {
          if (mounted) setState(() => _error = friendlyError(e));
        });
      });
    }
  }

  void _stopFromNotification() {
    if (mounted && _svc.isRecording && !_saving) _stop();
  }

  @override
  void dispose() {
    _svc.stopRequested.removeListener(_stopFromNotification);
    _svc.view.removeListener(_onView);
    if (_sunMode) setMaxBrightness(false);
    if (_nightMode) setNightBrightness(false);
    // Weggegaan zonder te starten: GPS weer uit.
    if (_svc.recording?.status == RecorderStatus.idle) _svc.discard();
    _pages.dispose();
    super.dispose();
  }

  /// Accu bij de start (null = onbekend of aan de lader); om na afloop het verbruik te tonen.
  int? _batteryAtStart;

  /// Huidige accu in procent, of null als de telefoon laadt of het niet lukt.
  Future<int?> _batteryLevel() async {
    try {
      final b = Battery();
      final state = await b.batteryState;
      if (state == BatteryState.charging || state == BatteryState.full) return null;
      return await b.batteryLevel;
    } catch (_) {
      return null;
    }
  }

  Future<void> _readBattery() async {
    try {
      final b = Battery();
      final level = await b.batteryLevel;
      final state = await b.batteryState;
      if (mounted) setState(() {
        _battery = level;
        _charging = state == BatteryState.charging || state == BatteryState.full;
      });
    } catch (_) {}
  }

  /// Volgt de opname: start zodra de GPS klaar is (als je dat vroeg) en meldt je doelafstand.
  void _onView() {
    final v = _svc.view.value;
    if (_armed && v.gpsReady && v.status == RecorderStatus.idle && _countdown == null) {
      setState(() => _armed = false);
      _start();
    }
    final t = _targetKm;
    if (t != null && !_targetReached && v.distance >= t * 1000 && v.status != RecorderStatus.idle) {
      _targetReached = true;
      _svc.say('Je doel van ${_kmWords(t)} kilometer is bereikt. Goed gedaan!', buzz: true);
    }
  }

  String _kmWords(double km) => km == km.roundToDouble() ? '${km.round()}' : km.toStringAsFixed(1).replaceAll('.', ',');

  /// Start-knop: GPS klaar (of loopband) → aftellen; GPS zoekt nog → klaarzetten.
  void _onStartPressed(RecorderView v) {
    if (_indoor || v.gpsReady) {
      _start();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _armed = !_armed);
    if (_armed) showMessage(context, 'Klaar! Je run start vanzelf zodra je GPS goed is. Je mag je telefoon wegstoppen.');
  }

  Future<void> _chooseTargetKm() async {
    const options = [3.0, 5.0, 8.0, 10.0, 15.0, 21.1, 42.2];
    final picked = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Doelafstand', style: RwText.title),
            const SizedBox(height: 4),
            Text('De ring loopt vol naar je doel en de stem meldt het als je er bent.', style: TextStyle(color: RwColors.muted)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final o in options)
                ChoiceChip(
                  label: Text(o == 21.1 ? 'Halve (21,1)' : (o == 42.2 ? 'Hele (42,2)' : '${o.round()} km')),
                  selected: _targetKm == o,
                  onSelected: (_) => Navigator.pop(c, o),
                ),
              ChoiceChip(label: const Text('Geen doel'), selected: _targetKm == null, onSelected: (_) => Navigator.pop(c, 0)),
            ]),
          ]),
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _targetKm = picked <= 0 ? null : picked;
      _targetReached = false;
    });
    SharedPreferences.getInstance().then((p) => p.setDouble('rec_target_km', picked)).ignore();
  }

  void _toggleSunMode(bool on) {
    if (on && _nightMode) _toggleNightMode(false);
    setState(() => _sunMode = on);
    setMaxBrightness(on);
    SharedPreferences.getInstance().then((p) => p.setBool('rec_sun_mode', on)).ignore();
  }

  void _toggleNightMode(bool on) {
    if (on && _sunMode) _toggleSunMode(false);
    setState(() => _nightMode = on);
    if (!on || _svc.isRecording) setNightBrightness(on);
    SharedPreferences.getInstance().then((p) => p.setBool('rec_night', on)).ignore();
  }

  /// Aftellen 3-2-1 (met tikjes en een belletje), dan starten.
  int? _countdown;

  Future<void> _start() async {
    if (_countdown != null) return;
    await _askTurnNotifications();
    if (!mounted) return;
    if (_sunMode) setMaxBrightness(true);
    if (_nightMode) setNightBrightness(true);
    for (final n in [3, 2, 1]) {
      if (!mounted) return;
      setState(() => _countdown = n);
      HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    if (!mounted) return;
    setState(() => _countdown = 0);
    await _begin();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (mounted) setState(() => _countdown = null);
  }

  Future<void> _pickCadence() async {
    const options = [0, 160, 165, 170, 175, 180, 185, 190];
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: RwColors.surface,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text('Cadans-tik', style: RwText.title),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Loop mee op de tik. Weet je het niet? Begin met 5 stappen boven wat je nu loopt; '
                  'de meeste lopers zitten tussen 165 en 180.',
                  style: TextStyle(color: RwColors.muted, height: 1.4),
                ),
              ),
              for (final o in options)
                ListTile(
                  title: Text(o == 0 ? 'Uit' : '$o stappen per minuut'),
                  trailing: (o == 0 ? _cadence == null : _cadence == o) ? Icon(Icons.check, color: RwColors.accent) : null,
                  onTap: () => Navigator.pop(ctx, o),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _cadence = picked == 0 ? null : picked);
    SharedPreferences.getInstance().then((p) => p.setInt('rec_cadence', picked)).ignore();
  }

  /// Afslagen ook op je horloge: daarvoor moet Kadans meldingen mogen tonen. Eén keer uitleggen en vragen.
  Future<void> _askTurnNotifications() async {
    if (_route == null || _indoor || !_turnByTurn) return;
    final n = NotificationService.instance;
    if (await n.allowed()) return;
    final p = await SharedPreferences.getInstance();
    if (p.getBool('turn_notif_asked') ?? false) return;
    await p.setBool('turn_notif_asked', true);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.watch_outlined),
        title: const Text('Afslagen op je horloge?'),
        content: const Text(
            'Kadans kan bij elke afslag een melding sturen. Die komt ook op je horloge, dat dan trilt en de richting laat zien.\n\n'
            'Daarvoor vraagt je telefoon zo of Kadans meldingen mag sturen. Je krijgt alleen meldingen over je run.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Niet nu')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ja, graag')),
        ],
      ),
    );
    if (ok == true) await n.requestPermission();
  }

  /// Haalt het weer van nu op voor de briefing bij de start ("12 graden, eerste helft tegenwind").
  Future<void> _prepareBriefing() async {
    try {
      final here = await quickPosition();
      final route = _route;
      final lat = route?.startLatitude ?? here?.latitude;
      final lon = route?.startLongitude ?? here?.longitude;
      if (lat == null || lon == null) return;
      final f = await ref.read(weatherServiceProvider).forecast(lat, lon, days: 1).timeout(const Duration(seconds: 8));
      final w = f.at(DateTime.now());
      if (w == null || !mounted) return;
      RouteWind? rw;
      if (route != null && w.windDirection != null) {
        rw = routeWind(trackSegments(decodePolyline(route.polyline)), w.windSpeed, w.windDirection!);
      }
      final text = startBriefing(
        temperature: w.temperature,
        feelsLike: w.feelsLike,
        windKmh: w.windSpeed,
        windFrom: w.windDirection,
        rainChance: w.precipitationProbability,
        firstHalfHead: rw?.firstHalfHead,
        secondHalfHead: rw?.secondHalfHead,
      );
      if (mounted && identical(route, _route)) setState(() => _briefing = text);
    } catch (_) {}
  }

  Future<void> _chooseTurnaround() async {
    final picked = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Heen en terug', style: TextStyle(fontFamily: RwFonts.display, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Hoe lang wil je in totaal lopen? Halverwege zegt Kadans dat je moet omdraaien. Daarna wijst de pijl je de weg terug naar je start.',
                style: TextStyle(color: RwColors.muted, height: 1.4)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in const [20.0, 30.0, 40.0, 50.0, 60.0, 75.0, 90.0])
                ChoiceChip(
                  label: Text('${m.round()} min'),
                  selected: _turnaroundMin == m,
                  onSelected: (_) => Navigator.pop(ctx, m),
                ),
            ]),
            if (_turnaroundMin != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(ctx, 0.0), child: const Text('Uitzetten')),
            ],
          ]),
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _turnaroundMin = picked <= 0 ? null : picked;
      if (_turnaroundMin != null) _route = null;
    });
  }

  Future<void> _begin() async {
    HapticFeedback.heavyImpact();
    try {
      final name = ref.read(profileProvider).value?.displayName ?? '';
      _svc.turnByTurn = _turnByTurn;
      _svc.cadence = _cadence;
      _batteryLevel().then((v) => _batteryAtStart = v).ignore(); // niet wachten: start niet vertragen
      await _svc.start(
        voice: _voice,
        shareLive: _share,
        name: name == 'loper' ? '' : name,
        intervals: _plan,
        haptics: _haptics,
        indoor: _indoor,
        cues: _cues,
        targetPace: _targetPace,
        followRoute: _route == null ? const [] : decodePolyline(_route!.polyline),
        followProfile: _route == null ? const [] : _route!.profileOrKmPoints,
        ghost: _raceGhost ? _ghost : null,
        guided: _guided,
        treadmillKmh: _indoor ? _tmKmh : null,
        bests: _bests(),
        recordLabels: {for (final e in bestEffortDistances) e.meters.round(): e.label},
        longestBefore: _longest(),
        turnaroundMinutes: _route == null && !_indoor ? _turnaroundMin : null,
        routeTimesBefore: _route == null ? 0 : _routeTimes(_route!),
        briefing: _indoor ? null : _briefing,
        targetMeters: _targetKm == null ? null : _targetKm! * 1000,
        quests: _quests && _plan == null && _guided == null && !_indoor,
      );
      final route = _route;
      if (route != null && !_indoor && route.polyline.isNotEmpty) {
        // Water en toiletten onderweg aankondigen (ophalen kan even duren; de run loopt al).
        ref.read(routePoisProvider(route.polyline).future).then(_svc.setRoutePois).catchError((Object _) {});
        // Bezienswaardigheden (Wikipedia) langs de route: "over 150 meter kom je langs ...".
        ref
            .read(routePhotosProvider(route.polyline).future)
            .then((p) => _svc.setRouteLandmarks([
                  for (final ph in p.photos)
                    if (ph.source == PhotoSource.landmark && (ph.title ?? '').isNotEmpty) (meters: ph.meters, name: ph.title!),
                ]))
            .catchError((Object _) {});
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  /// Je snelste tijden per afstand van vóór deze run (voor de recordjacht onderweg).
  Map<int, double> _bests() {
    final runs = ref.read(activitiesProvider).value ?? const <Activity>[];
    final all = bestOverall([
      for (final a in runs)
        if (a.id != null && a.bestEfforts != null) (id: a.id!, efforts: a.bestEfforts!),
    ]);
    return {for (final e in all.entries) e.key: e.value.seconds};
  }

  double _longest() {
    final runs = ref.read(activitiesProvider).value ?? const <Activity>[];
    var m = 0.0;
    for (final a in runs) {
      if (a.distanceMeters > m) m = a.distanceMeters;
    }
    return m;
  }

  int _routeTimes(RunRoute r) {
    final runs = ref.read(activitiesProvider).value ?? const <Activity>[];
    return runs.where((a) => a.routeId != null && a.routeId == r.id).length;
  }

  /// Samsung en andere merken zetten apps op de achtergrond soms in slaapstand; dan stopt de opname.
  Future<void> _explainBattery() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Laat Kadans doorlopen op de achtergrond',
                  style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Om batterij te sparen zetten veel telefoons apps in slaapstand als je scherm uit is. '
                'Dan stopt Kadans halverwege je run met meten. Zo voorkom je dat:',
                style: TextStyle(color: RwColors.muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text('1. Tik hieronder op "Batterij-instellingen" en kies bij Kadans "Niet optimaliseren" of "Onbeperkt".',
                  style: TextStyle(height: 1.4)),
              const SizedBox(height: 8),
              const Text(
                  '2. Samsung: Instellingen → Batterij → Achtergrondgebruik beperken → Apps nooit in slaapstand → voeg Kadans toe.',
                  style: TextStyle(height: 1.4)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => AndroidIntent(action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS')
                    .launch()
                    .catchError((Object _) => AndroidIntent(action: 'android.settings.SETTINGS').launch()),
                icon: const Icon(Icons.settings),
                label: const Text('Batterij-instellingen'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gedaan')),
            ],
          ),
        ),
      ),
    );
    if (done == true) {
      setState(() => _batteryDone = true);
      final p = await SharedPreferences.getInstance();
      await p.setBool('battery_explained', true);
    }
  }

  Future<void> _choosePlan() async {
    final chosen = await pickIntervalPlan(context, current: _plan);
    if (chosen == null) return;
    final plan = chosen.plan;
    setState(() {
      _plan = plan;
      if (plan != null) _guided = null;
    });
    try {
      final p = await SharedPreferences.getInstance();
      plan == null ? await p.remove(_planKey) : await p.setString(_planKey, jsonEncode(plan.toJson()));
    } catch (_) {}
  }

  Future<void> _stop() async {
    HapticFeedback.mediumImpact();
    final ok = await confirmDialog(
      context,
      title: 'Run afronden?',
      message: 'Je run stopt en wordt opgeslagen.',
      confirmLabel: 'Afronden en opslaan',
      destructive: false,
    );
    if (!ok) return;
    double? indoorMeters;
    if (_svc.recording?.indoor ?? false) {
      indoorMeters = await _askDistance(estimate: _svc.recording!.distance);
      if (indoorMeters == null) return; // Toch nog niet stoppen.
    }
    final rec = await _svc.stop();
    if (indoorMeters != null) rec?.setIndoorDistance(indoorMeters);
    if (rec == null || rec.distance < 200 || rec.movingSeconds < 60) {
      if (mounted) {
        showMessage(context, 'Te kort om op te slaan (minder dan 200 m of 1 minuut).');
        Navigator.of(context).pop();
      }
      return;
    }
    await _save(rec);
  }

  /// Loopband: afstand van het display van de loopband invullen.
  Future<double?> _askDistance({double estimate = 0}) async {
    final c = TextEditingController(text: estimate >= 100 ? (estimate / 1000).toStringAsFixed(2).replaceAll('.', ',') : '');
    final km = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hoe ver liep je?'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Afstand in km (van de loopband)',
            hintText: 'bijv. 5,2',
            helperText: estimate >= 100 ? 'Geschat uit je snelheid. Klopt het display anders? Pas het aan.' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Terug')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
              if (v != null && v > 0 && v < 100) Navigator.pop(ctx, v);
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    c.dispose();
    return km == null ? null : km * 1000;
  }

  Future<void> _chooseTargetPace() async {
    var sec = (_targetPace ?? 330).round();
    final result = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Doeltempo', style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('De stem zegt het als je langer dan 20 seconden meer dan 15 s/km te snel of te langzaam gaat.',
                    style: TextStyle(color: RwColors.muted, height: 1.4)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(tooltip: '5 seconden sneller', onPressed: () => set(() => sec = (sec - 5).clamp(180, 600)), icon: const Icon(Icons.remove_circle_outline)),
                    Text(Fmt.pace(sec), style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 34, fontWeight: FontWeight.w800)),
                    IconButton(tooltip: '5 seconden langzamer', onPressed: () => set(() => sec = (sec + 5).clamp(180, 600)), icon: const Icon(Icons.add_circle_outline)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, 0), child: const Text('Geen doeltempo'))),
                    const SizedBox(width: 12),
                    Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, sec), child: const Text('Gebruiken'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null) return;
    setState(() => _targetPace = result == 0 ? null : result.toDouble());
    final p = await SharedPreferences.getInstance();
    await p.setDouble('rec_target_pace', result.toDouble());
  }

  /// Begeleide run kiezen (de coach praat je erdoorheen).
  Future<void> _chooseGuided() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text('Begeleide runs', style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('De coach praat je door je run heen, met tips op het juiste moment. Doe je oortjes in.',
                  style: TextStyle(color: RwColors.muted)),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Geen begeleiding'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final g in GuidedRun.all)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: RwColors.accent.withValues(alpha: 0.15),
                  child: Text('${g.minutes}', style: TextStyle(color: RwColors.accent, fontWeight: FontWeight.w800)),
                ),
                title: Text(g.title),
                subtitle: Text('${g.minutes} min · ${g.subtitle}'),
                trailing: _guided?.id == g.id ? Icon(Icons.check, color: RwColors.accent) : null,
                onTap: () => Navigator.pop(ctx, g.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _guided = picked.isEmpty ? null : GuidedRun.all.firstWhere((g) => g.id == picked);
      if (_guided != null) {
        _plan = null;
        _voice = true;
      }
    });
  }

  Future<void> _chooseCues() async {
    var c = _cues;
    var rate = _svc.speechRate;
    final result = await showModalBottomSheet<CueSettings>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Stemcoach', style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in CueEvery.values)
                      ChoiceChip(label: Text(e.label), selected: c.every == e, onSelected: (_) => set(() => c = c.copyWith(every: e))),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('Hoe klinkt je coach?', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<CoachStyle>(
                  segments: [
                    for (final st in CoachStyle.values) ButtonSegment(value: st, label: Text(st.label)),
                  ],
                  selected: {c.style},
                  onSelectionChanged: (v) {
                    set(() => c = c.copyWith(style: v.first));
                    _svc
                        .previewVoice(switch (v.first) {
                          CoachStyle.calm => 'Kilometer 3. Dit stuk 5 minuten 30 per kilometer.',
                          CoachStyle.motivating => 'Kilometer 3. Dit stuk 5 minuten 30 per kilometer. Lekker bezig!',
                          CoachStyle.short => 'Kilometer 3. 5 minuten 30.',
                        })
                        .ignore();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(c.style.description, style: TextStyle(color: RwColors.muted, fontSize: 13)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tempo van het laatste stuk'),
                  value: c.lap,
                  onChanged: (v) => set(() => c = c.copyWith(lap: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Vergelijk met het vorige stuk'),
                  subtitle: const Text('"6 seconden sneller dan het vorige stuk"'),
                  value: c.compare,
                  onChanged: c.style == CoachStyle.short || !c.lap ? null : (v) => set(() => c = c.copyWith(compare: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Verwachte eindtijd'),
                  subtitle: const Text('Als je een route volgt: "met dit tempo ben je klaar na 52 minuten"'),
                  value: c.finish,
                  onChanged: c.style == CoachStyle.short ? null : (v) => set(() => c = c.copyWith(finish: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gemiddeld tempo'),
                  value: c.average,
                  onChanged: (v) => set(() => c = c.copyWith(average: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Totale tijd'),
                  value: c.total,
                  onChanged: (v) => set(() => c = c.copyWith(total: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hartslag (met hartslagband)'),
                  value: c.heartRate,
                  onChanged: (v) => set(() => c = c.copyWith(heartRate: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Drink- en gelherinnering'),
                  subtitle: const Text('Voor lange runs: drinken elke 20 min, een gel elke 35 min vanaf 45 min'),
                  value: c.fuel,
                  onChanged: (v) => set(() => c = c.copyWith(fuel: v)),
                ),
                const SizedBox(height: 8),
                const Text('Spreektempo', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<double>(
                        segments: const [
                          ButtonSegment(value: 0.4, label: Text('Rustig')),
                          ButtonSegment(value: 0.5, label: Text('Normaal')),
                          ButtonSegment(value: 0.6, label: Text('Vlot')),
                        ],
                        selected: {rate},
                        onSelectionChanged: (v) {
                          set(() => rate = v.first);
                          _svc.speechRate = rate;
                          SharedPreferences.getInstance().then((p) => p.setDouble('rec_speech_rate', rate)).ignore();
                          _svc.previewVoice('Over 100 meter rechtsaf. Kilometer 3 in 5 minuten 30.').ignore();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Stem', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const _VoicePicker(),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => Navigator.pop(ctx, c), child: const Text('Klaar')),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null) return;
    setState(() => _cues = result);
    final p = await SharedPreferences.getInstance();
    await p.setString('rec_cues', jsonEncode(result.toJson()));
  }

  Future<void> _chooseRoute(List<RunRoute> unsorted) async {
    // Handigste routes bovenaan: favorieten, dan wat dichtbij begint, dan wat je het laatst liep.
    var here = _svc.view.value.position;
    if (here == null) {
      final q = await quickPosition();
      if (q != null) here = LatLng(q.latitude, q.longitude);
    }
    if (!mounted) return;
    final runs = ref.read(activitiesProvider).value ?? const <Activity>[];
    final lastRun = <String, DateTime>{};
    for (final a in runs) {
      final id = a.routeId;
      if (id == null) continue;
      final cur = lastRun[id];
      if (cur == null || a.startedAt.isAfter(cur)) lastRun[id] = a.startedAt;
    }
    final near = <String, double>{};
    if (here != null) {
      for (final r in unsorted) {
        final pts = decodePolyline(r.polyline);
        if (r.id == null || pts.length < 2) continue;
        near[r.id!] = projectOnTrack(RouteTrack(pts), here).off;
      }
    }
    double rank(RunRoute r) {
      var v = 0.0;
      if (r.isFavorite) v -= 1e7;
      final d = near[r.id];
      if (d != null) v += d.clamp(0, 50000).toDouble();
      final last = lastRun[r.id];
      v += last == null ? 20000 : (DateTime.now().difference(last).inDays * 50).clamp(0, 15000).toDouble();
      return v;
    }

    final routes = [...unsorted]..sort((a, b) => rank(a).compareTo(rank(b)));
    String sub(RunRoute r) {
      final d = near[r.id];
      final last = lastRun[r.id];
      return [
        Fmt.km(r.distanceMeters, decimals: 1),
        if (d != null) d < 60 ? 'je staat erop' : 'op ${d < 1000 ? '${(d / 10).round() * 10} m' : Fmt.km(d, decimals: 1)} van je',
        if (last != null) 'laatst ${daysAgoWords(calendarDaysBetween(last, DateTime.now()))}',
      ].join(' · ');
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.explore_outlined),
                title: const Text('Vrij lopen (geen route)'),
                onTap: () => Navigator.pop(ctx, ''),
              ),
              if (routes.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text('Je mag overal op een route instappen. Kadans wijst je de weg ernaartoe.',
                      style: TextStyle(color: RwColors.muted, fontSize: 13, height: 1.35)),
                ),
              for (final r in routes)
                ListTile(
                  leading: Icon(r.isFavorite ? Icons.star : Icons.route_outlined, color: RwColors.accent),
                  title: Text(r.name),
                  subtitle: Text(sub(r)),
                  trailing: r.id == _route?.id ? Icon(Icons.check, color: RwColors.accent) : null,
                  onTap: () => Navigator.pop(ctx, r.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _route = picked.isEmpty ? null : routes.where((r) => r.id == picked).firstOrNull;
      if (_route != null) _turnaroundMin = null;
      _ghost = null;
      _ghostTime = null;
      _briefing = null;
    });
    if (picked.isNotEmpty) _loadGhost(picked);
    _prepareBriefing();
  }

  /// Je snelste eerdere run op deze route, om tegen te racen (zoals Apple's Race Route).
  Future<void> _loadGhost(String routeId) async {
    final runs = ref.read(activitiesProvider).value ?? const <Activity>[];
    final route = _route;
    final same = [
      for (final a in runs)
        if (a.id != null && a.routeId == routeId && route != null && (a.distanceMeters - route.distanceMeters).abs() < route.distanceMeters * 0.15) a,
    ]..sort((a, b) => a.movingTimeSeconds.compareTo(b.movingTimeSeconds));
    if (same.isEmpty) return;
    try {
      final json = await ref.read(repositoryProvider).activityStreams(same.first.id!);
      final st = json == null ? null : RunStreams.fromJson(json);
      if (!mounted || st == null || _route?.id != routeId) return;
      setState(() {
        _ghost = st;
        _ghostTime = same.first.movingTimeSeconds;
      });
    } catch (_) {}
  }

  Future<void> _chooseShoe(List<Shoe> shoes) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in shoes.where((s) => !s.retired))
              ListTile(
                leading: const Icon(Icons.directions_run),
                title: Text(s.name),
                subtitle: Text('${shoeKm(s, ref.read(activitiesProvider).value ?? const <Activity>[]).round()} km'),
                trailing: s.id == (_shoeChosen ? _shoeId : defaultShoe(shoes)?.id) ? Icon(Icons.check, color: RwColors.accent) : null,
                onTap: () => Navigator.pop(ctx, s.id),
              ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Geen schoen'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _shoeChosen = true;
      _shoeId = picked.isEmpty ? null : picked;
    });
  }

  /// Opslaan lukte niet (meestal geen internet): bewaren op de telefoon en later versturen.
  Future<void> _savePending(PendingRun run) async {
    try {
      await PendingRunStore.add(run);
    } catch (e) {
      // Zelfs lokaal bewaren lukt niet: eerlijk melden, de opname niet stilletjes weggooien.
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Opslaan is niet gelukt: ${friendlyError(e)}', error: true);
      }
      return;
    }
    await ref.read(syncServiceProvider).writeRunToHealth(run.activity).catchError((Object _) => false);
    if (!mounted) return;
    showMessage(context, 'Geen internet. Je run staat veilig op je telefoon en wordt opgeslagen zodra je weer verbinding hebt.');
    Navigator.of(context).pop();
  }

  Future<void> _save(RunRecording rec) async {
    setState(() => _saving = true);
    try {
      final track = rec.simplifiedTrack();
      final start = rec.startedAt ?? DateTime.now();
      HourWeather? w;
      if (track.isNotEmpty) {
        // Kort wachten: zonder internet wil je niet 15 s naar een draaiend rondje kijken.
        w = await ref
            .read(weatherServiceProvider)
            .historical(track.first.lat, track.first.lon, start)
            .timeout(const Duration(seconds: 6), onTimeout: () => null);
      }
      final shoes = ref.read(shoesProvider).value ?? const <Shoe>[];
      final repo = ref.read(repositoryProvider);
      final streamsJson = rec.streamsJson();
      final streams = streamsJson == null ? null : RunStreams.fromJson(streamsJson);
      final efforts = streams == null ? const <BestEffort>[] : bestEfforts(streams);
      // Je snelste tijden van vóór deze run, om nieuwe records te herkennen.
      final before = ref.read(activitiesProvider).value ?? const <Activity>[];
      final previousBest = bestOverall([
        for (final x in before)
          if (x.id != null && x.bestEfforts != null) (id: x.id!, efforts: x.bestEfforts!),
      ]);
      final activity = Activity(
        startedAt: start,
        distanceMeters: double.parse(rec.distance.toStringAsFixed(1)),
        movingTimeSeconds: rec.movingSeconds.round(),
        source: 'runwise',
        averageHeartRate: rec.averageHeartRate,
        temperatureCelsius: w?.temperature,
        feelsLikeCelsius: w?.feelsLike,
        windSpeedKmh: w?.windSpeed,
        windDirectionDegrees: w?.windDirection,
        humidityPct: w?.humidity,
        trackPolyline: track.length >= 2 ? encodePolyline(track) : '',
        shoeId: _shoeChosen ? _shoeId : defaultShoe(shoes)?.id,
      );
      final localId = PendingRun.newLocalId();
      final String id;
      try {
        id = await repo.addRecordedRun(activity, localId);
      } catch (_) {
        // Geen verbinding: de run blijft veilig op de telefoon en gaat later vanzelf mee.
        await _savePending(PendingRun(
          localId: localId,
          activity: activity,
          createdAt: DateTime.now(),
          streams: streamsJson,
          bestEfforts: streamsJson == null ? null : bestEffortsToJson(efforts),
        ));
        return;
      }
      if (streamsJson != null) {
        await repo
            .setActivityStreams(id, streamsJson, bestEfforts: bestEffortsToJson(efforts))
            .catchError((Object e, StackTrace st) {
              // Het verloop is een extraatje; de run zelf staat er al. Wel melden: anders ontbreken stil de km-tijden.
              ErrorReporter.report(e, st, context: 'setActivityStreams').ignore();
            });
        // Hoogte verbeteren met de hoogtekaart (op de achtergrond).
        if (!rec.indoor) repo.improveElevation(id, streamsJson).then((_) => ref.invalidate(activitiesProvider)).ignore();
      }
      // Ranglijsten van Samen bijwerken (alleen als je meedoet; op de achtergrond).
      refreshCommunityQuietly(ref.read(communityServiceProvider)).ignore();
      final sync = ref.read(syncServiceProvider);
      final written = await sync.writeRunToHealth(activity);
      final startPct = _batteryAtStart;
      final endPct = startPct == null ? null : await _batteryLevel();
      final batteryUsed = (startPct != null && endPct != null && startPct >= endPct) ? startPct - endPct : null;
      ref.invalidate(activitiesProvider);
      await sync.autoLinkRuns().catchError((_) => 0);
      if (!mounted) return;
      final saved = Activity(
        id: id,
        startedAt: activity.startedAt,
        distanceMeters: activity.distanceMeters,
        movingTimeSeconds: activity.movingTimeSeconds,
        source: activity.source,
        averageHeartRate: activity.averageHeartRate,
        temperatureCelsius: activity.temperatureCelsius,
        feelsLikeCelsius: activity.feelsLikeCelsius,
        windSpeedKmh: activity.windSpeedKmh,
        windDirectionDegrees: activity.windDirectionDegrees,
        humidityPct: activity.humidityPct,
        trackPolyline: activity.trackPolyline,
        shoeId: activity.shoeId,
        bestEfforts: bestEffortsToJson(efforts),
      );
      // Na de 5e eigen run één keer om een beoordeling vragen (even later, na het felicitatiescherm).
      final ownRuns = before.where((x) => x.source == 'runwise').length + 1;
      Future<void>.delayed(const Duration(seconds: 4), () => ReviewService.maybeAsk(ownRuns)).ignore();
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => RunSummaryScreen(
          activity: saved,
          streams: streams,
          efforts: efforts,
          previousBest: previousBest,
          healthWritten: written,
          batteryUsedPct: batteryUsed,
          badges: bd.newBadges(before, [...before, saved]),
        ),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Opslaan is niet gelukt: ${friendlyError(e)}', error: true);
      }
    }
  }

  /// Voor de start: compact, zodat alle opties passen (ook op een klein scherm).
  Widget _preStats(RecorderView v) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_indoor)
              Icon(Icons.fitness_center, size: 56, color: RwColors.accent)
            else
              _GpsRadar(accuracy: v.gpsAccuracy, ready: v.gpsReady),
            const SizedBox(height: 8),
            Text(
              _indoor ? 'Klaar voor de loopband' : (v.gpsReady ? 'Klaar voor de start' : 'GPS zoeken…'),
              style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _indoor
                  ? 'Stel de snelheid van de band in, dan zie je je afstand en tempo live. Je kunt hem onderweg aanpassen.'
                  : 'Kies je opties en druk op Start. Je scherm mag uit.',
              textAlign: TextAlign.center,
              style: TextStyle(color: RwColors.muted),
            ),
            const SizedBox(height: 14),
            _QuickPresets(
              show: widget.sessionTitle == null,
              routeChosen: _route != null,
              planChosen: _plan != null,
              onSession: (sess) {
                HapticFeedback.selectionClick();
                setState(() {
                  _plan = sess.intervals;
                  _targetPace = sess.intervals == null ? sess.targetPace : null;
                  _indoor = false;
                });
                showMessage(context, '${sess.title} staat klaar.');
              },
              onRoute: (r) {
                HapticFeedback.selectionClick();
                setState(() {
                  _route = r;
                  _ghost = null;
                  _ghostTime = null;
                  _indoor = false;
                });
                if (r.id != null) _loadGhost(r.id!);
              },
            ),

            if (_indoor) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _TreadmillSpeed(
                  kmh: _tmKmh,
                  onChanged: (k) {
                    setState(() => _tmKmh = k);
                    SharedPreferences.getInstance().then((p) => k == null ? p.remove('rec_tm_kmh') : p.setDouble('rec_tm_kmh', k)).ignore();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stats(RecorderView v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (v.hasIntervals) ...[
          const SizedBox(height: 12),
          _IntervalPanel(view: v, onSkip: _locked ? null : _svc.skipStep),
        ],
        const Spacer(),
        if (v.indoor || (!_svc.isRecording && _indoor)) ...[
          FittedBox(
            fit: BoxFit.scaleDown,
            child: RollingText(
              Fmt.duration(v.movingSeconds),
              style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 80, fontWeight: FontWeight.w800, height: 1),
            ),
          ),
          if (v.indoor && v.treadmillKmh != null) ...[
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: _Big(label: 'Afstand (geschat)', value: Fmt.km(v.distance, decimals: 2))),
              Expanded(child: _Big(label: 'Tempo', value: Fmt.pace(3600 / v.treadmillKmh!).replaceAll(' /km', ''))),
            ]),
          ] else
            Text(
              v.indoor ? 'loopband · stel je snelheid in, of vul de afstand na afloop in' : 'loopband',
              textAlign: TextAlign.center,
              style: TextStyle(color: RwColors.muted, fontSize: 16),
            ),
          const SizedBox(height: 16),
          _TreadmillSpeed(
            kmh: v.indoor ? v.treadmillKmh : _tmKmh,
            onChanged: _locked
                ? null
                : (k) {
                    if (v.indoor) {
                      _svc.setTreadmillSpeed(k);
                    } else {
                      setState(() => _tmKmh = k);
                    }
                    SharedPreferences.getInstance().then((p) => k == null ? p.remove('rec_tm_kmh') : p.setDouble('rec_tm_kmh', k)).ignore();
                  },
          ),
          if (v.heartRate != null || v.hrStatus == HrStatus.connecting || v.hrStatus == HrStatus.lost) ...[
            const SizedBox(height: 18),
            _HeartRow(view: v),
          ],
          const Spacer(),
        ] else ...[
        if (v.hasIntervals) ...[
          Semantics(
            label: 'Afstand ${Fmt.km(v.distance, decimals: 2)}',
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: RollingText(
                (v.distance / 1000).toStringAsFixed(2).replaceAll('.', ','),
                style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 72, fontWeight: FontWeight.w800, height: 1),
              ),
            ),
          ),
          Text('kilometer', textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted, fontSize: 18)),
          const SizedBox(height: 28),
        ] else ...[
          // De afstand in een ring die per kilometer volloopt.
          Center(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _svc.announceNow();
              },
              child: _KmRing(
              fraction: _targetKm == null ? (v.distance % 1000) / 1000 : (v.distance / (_targetKm! * 1000)).clamp(0.0, 1.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Semantics(
                  label: 'Afstand ${Fmt.km(v.distance, decimals: 2)}',
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: RollingText(
                      (v.distance / 1000).toStringAsFixed(2).replaceAll('.', ','),
                      style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 84, fontWeight: FontWeight.w800, height: 1),
                    ),
                  ),
                ),
                Text('kilometer', textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  _targetKm != null
                      ? (v.distance >= _targetKm! * 1000
                          ? 'Doel ${_kmWords(_targetKm!)} km gehaald!'
                          : 'nog ${((_targetKm! * 1000 - v.distance) / 1000).toStringAsFixed(1).replaceAll('.', ',')} km tot je doel')
                      : 'nog ${(1000 - v.distance % 1000).round()} m tot km ${(v.distance / 1000).floor() + 1}',
                  style: TextStyle(
                      color: _targetKm != null && v.distance >= _targetKm! * 1000 ? RwColors.good : RwColors.subtle,
                      fontSize: 12,
                      fontFeatures: rwTnum),
                ),
                const SizedBox(height: 2),
                Text('tik om te horen', style: TextStyle(color: RwColors.subtle, fontSize: 10, letterSpacing: 0.4)),
              ]),
            ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        Row(
          children: [
            Expanded(child: _Big(label: 'Tijd', value: Fmt.duration(v.movingSeconds))),
            Expanded(child: _Big(label: 'Tempo nu', value: v.currentPace <= 0 ? '–' : Fmt.pace(v.currentPace).replaceAll(' /km', ''))),
            Expanded(child: _Big(label: 'Gemiddeld', value: v.averagePace <= 0 ? '–' : Fmt.pace(v.averagePace).replaceAll(' /km', ''))),
          ],
        ),
        if (v.heartRate != null || v.hrStatus == HrStatus.connecting || v.hrStatus == HrStatus.lost) ...[
          const SizedBox(height: 18),
          _HeartRow(view: v),
        ],
        if (!v.indoor && v.routeRemaining == null) _BackToStart(track: v.track),
        // Uitdaging: hoeveel deze run je dichterbij brengt (niet naast route-aanwijzingen, dan wordt het te vol).
        if (v.quest != null) _QuestCard(view: v) else if (v.questsOn && v.questsTotal > 0) _QuestTally(view: v),
        if (v.routeRemaining == null && v.quest == null) ChallengeLiveChip(view: v),
        if (v.routeRemaining != null && v.nextTurn != null && !v.offRoute && (v.nextTurnIn ?? 1e9) < 400) ...[
          const SizedBox(height: 14),
          _NextTurnCard(turn: v.nextTurn!, inMeters: v.nextTurnIn!),
        ],
        if (v.routeRemaining != null && (v.offRoute || v.approachingRoute) && v.wayToRoute != null) ...[
          const SizedBox(height: 14),
          _WayToRouteCard(way: v.wayToRoute!, approaching: v.approachingRoute),
        ] else if (v.routeRemaining != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (v.offRoute ? RwColors.warning : RwColors.accent).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(v.offRoute ? Icons.wrong_location_outlined : Icons.route, color: v.offRoute ? RwColors.warning : RwColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    v.offRoute ? 'Je bent van je route af. Veeg naar de kaart.' : 'Nog ${Fmt.km(v.routeRemaining!, decimals: 1)} van je route',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (v.ghostDelta != null && !v.offRoute)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('vs record', style: TextStyle(color: RwColors.subtle, fontSize: 11)),
                      Text(
                        '${v.ghostDelta! <= 0 ? '−' : '+'}${Fmt.duration(v.ghostDelta!.abs().round())}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: v.ghostDelta! <= 0 ? RwColors.good : RwColors.danger,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
        const Spacer(),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RecorderView>(
      valueListenable: _svc.view,
      builder: (context, v, _) {
        final started = v.status != RecorderStatus.idle && v.status != RecorderStatus.finished;
        final shoes = ref.watch(shoesProvider).value ?? const <Shoe>[];
        final routes = ref.watch(routesProvider).value ?? const <RunRoute>[];
        final controls = !started
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RwSegmented<bool>(
                    items: const [
                      (value: false, label: 'Buiten', icon: Icons.terrain_outlined),
                      (value: true, label: 'Loopband', icon: Icons.fitness_center),
                    ],
                    selected: _indoor,
                    onChanged: (x) {
                      setState(() => _indoor = x);
                      SharedPreferences.getInstance().then((p) => p.setBool('rec_indoor', x)).ignore();
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.timer_outlined, color: RwColors.accent),
                    title: Text(_plan == null ? 'Gewone run' : _plan!.name),
                    subtitle: Text(_plan == null ? 'Tik om een intervaltraining te kiezen' : 'Intervaltraining met stem · tik om te wijzigen'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _choosePlan,
                  ),
                  if (_battery != null && _battery! < 20 && !_charging)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.battery_1_bar, color: RwColors.danger),
                      title: Text('Batterij $_battery%'),
                      subtitle: Text(_battery! < 10
                          ? 'Te weinig voor een run met GPS. Laad eerst even op.'
                          : 'Genoeg voor ongeveer ${(_battery! * 3).round()} minuten met GPS. Zet zonmodus uit en houd het kort.'),
                    ),
                  if (!_batteryDone)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.battery_alert_outlined, color: RwColors.warning),
                      title: const Text('Zorg dat je telefoon je run niet stopt'),
                      subtitle: const Text('Eenmalig instellen, duurt 1 minuut'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _explainBattery,
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        avatar: const Icon(Icons.record_voice_over_outlined, size: 18),
                        label: const Text('Stemcoach'),
                        tooltip: 'Elke kilometer je tijd en tempo, ook met je scherm uit. Muziek gaat even zachter.',
                        selected: _voice || _plan != null,
                        onSelected: _plan != null ? null : (x) => setState(() => _voice = x),
                      ),
                      if (!_indoor && _plan == null && _guided == null)
                        FilterChip(
                          avatar: const Icon(Icons.bolt_outlined, size: 18),
                          label: const Text('Live opdrachten'),
                          tooltip: 'Na het inlopen af en toe een korte opdracht: sprint 20 s, een snelle minuut of een km op tempo. '
                              'Op jouw tempo, met de uitslag via je oortjes en je horloge.',
                          selected: _quests,
                          onSelected: (x) {
                            setState(() => _quests = x);
                            SharedPreferences.getInstance().then((p) => p.setBool('rec_quests', x)).ignore();
                          },
                        ),
                      FilterChip(
                        avatar: const Icon(Icons.music_note_outlined, size: 18),
                        label: const Text('Geluidjes'),
                        tooltip: 'Een zacht belletje bij de start, elke km en intervalwissels',
                        selected: _sounds,
                        onSelected: (x) {
                          setState(() => _sounds = x);
                          SoundService.instance.setEnabled(x).ignore();
                          if (x) SoundService.instance.play(RwSound.km).ignore();
                        },
                      ),
                      FilterChip(
                        avatar: const Icon(Icons.vibration, size: 18),
                        label: const Text('Trillen'),
                        tooltip: 'Bij elke kilometer en bij intervalwissels',
                        selected: _haptics,
                        onSelected: (x) {
                          setState(() => _haptics = x);
                          SharedPreferences.getInstance().then((p) => p.setBool('rec_haptics', x)).ignore();
                        },
                      ),
                      if (_moreOpts || _cadence != null)
                      FilterChip(
                        avatar: const Icon(Icons.graphic_eq, size: 18),
                        label: Text(_cadence == null ? 'Cadans-tik' : 'Cadans $_cadence'),
                        tooltip: 'Een zachte tik op je stappen per minuut. Helpt je kortere, lichtere passen te maken.',
                        selected: _cadence != null,
                        onSelected: (_) => _pickCadence(),
                      ),
                      if (!_indoor && _route != null)
                        FilterChip(
                          avatar: const Icon(Icons.turn_right, size: 18),
                          label: const Text('Afslagen melden'),
                          tooltip: 'Stem, trillen en een melding op je horloge bij elke afslag. Links: twee tikken, rechts: één lange.',
                          selected: _turnByTurn,
                          onSelected: (x) {
                            setState(() => _turnByTurn = x);
                            SharedPreferences.getInstance().then((p) => p.setBool('rec_turns', x)).ignore();
                          },
                        ),
                      if (!_indoor && (_moreOpts || _share))
                        FilterChip(
                          avatar: const Icon(Icons.share_location_outlined, size: 18),
                          label: const Text('Live delen'),
                          tooltip: 'Iemand thuis kan meekijken via een link',
                          selected: _share,
                          onSelected: (x) => setState(() => _share = x),
                        ),
                      if (_moreOpts || _guided != null)
                      ActionChip(
                        avatar: Icon(Icons.record_voice_over_outlined, size: 18, color: _guided == null ? null : RwColors.accentDark),
                        backgroundColor: _guided == null ? null : RwColors.accent,
                        label: Text(_guided == null ? 'Begeleide run' : _guided!.title,
                            style: TextStyle(color: _guided == null ? null : RwColors.accentDark)),
                        onPressed: _chooseGuided,
                      ),
                      if (_moreOpts)
                      ActionChip(
                        avatar: const Icon(Icons.tune, size: 18),
                        label: Text('Stem: ${_cues.every.label.toLowerCase()}'),
                        onPressed: _chooseCues,
                      ),
                      if (!_indoor)
                        ActionChip(
                          avatar: const Icon(Icons.flag_outlined, size: 18),
                          label: Text(_targetKm == null ? 'Doelafstand' : 'Doel ${_kmWords(_targetKm!)} km'),
                          onPressed: _chooseTargetKm,
                        ),
                      if (_moreOpts || _sunMode)
                      FilterChip(
                        avatar: const Icon(Icons.wb_sunny_outlined, size: 18),
                        label: const Text('Zonmodus'),
                        tooltip: 'Pikzwart, volle helderheid en grotere cijfers: leesbaar in fel zonlicht',
                        selected: _sunMode,
                        onSelected: _toggleSunMode,
                      ),
                      if (_moreOpts || _nightMode)
                      FilterChip(
                        avatar: const Icon(Icons.nightlight_outlined, size: 18),
                        label: const Text('Nachtmodus'),
                        tooltip: 'Rood en gedimd beeld: je ogen blijven aan het donker gewend en je verblindt niemand',
                        selected: _nightMode,
                        onSelected: _toggleNightMode,
                      ),
                      if (!_indoor && (_moreOpts || _targetPace != null))
                        ActionChip(
                          avatar: const Icon(Icons.speed, size: 18),
                          label: Text(_targetPace == null ? 'Doeltempo' : 'Doel ${Fmt.pace(_targetPace!)}'),
                          onPressed: _chooseTargetPace,
                        ),
                      if (!_indoor && _route == null)
                        ActionChip(
                          avatar: const Icon(Icons.u_turn_left, size: 18),
                          label: Text(_turnaroundMin == null ? 'Heen en terug' : 'Heen en terug ${_turnaroundMin!.round()} min'),
                          onPressed: _chooseTurnaround,
                        ),
                      if (!_indoor && routes.isNotEmpty)
                        ActionChip(
                          avatar: const Icon(Icons.route_outlined, size: 18),
                          label: Text(_route == null ? 'Route volgen' : _route!.name, overflow: TextOverflow.ellipsis),
                          onPressed: () => _chooseRoute(routes),
                        ),
                      if (!_indoor && _route != null && _ghost != null)
                        FilterChip(
                          avatar: const Icon(Icons.flag_outlined, size: 18),
                          label: Text('Race tegen record${_ghostTime == null ? '' : ' (${Fmt.duration(_ghostTime!)})'}'),
                          tooltip: 'De stem zegt elke km of je voor of achter ligt op je snelste run hier',
                          selected: _raceGhost,
                          onSelected: (x) => setState(() => _raceGhost = x),
                        ),
                      if (shoes.isNotEmpty)
                        ActionChip(
                          avatar: const Icon(Icons.directions_run, size: 18),
                          label: Text(() {
                            final id = _shoeChosen ? _shoeId : defaultShoe(shoes)?.id;
                            final name = shoes.where((x) => x.id == id).map((x) => x.name).firstOrNull;
                            return name == null ? 'Geen schoen' : name;
                          }()),
                          onPressed: () => _chooseShoe(shoes),
                        ),
                      // Minder gebruikte opties achter "Meer": rustiger scherm, alles nog binnen één tik.
                      ActionChip(
                        avatar: Icon(_moreOpts ? Icons.expand_less : Icons.more_horiz, size: 18),
                        label: Text(_moreOpts ? 'Minder' : 'Meer opties'),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _moreOpts = !_moreOpts);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _GlowPulse(
                    active: _indoor || v.gpsReady,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                      onPressed: !_indoor && _error != null && !v.gpsReady ? null : () => _onStartPressed(v),
                      icon: Icon(_armed ? Icons.hourglass_top : Icons.play_arrow, size: 30),
                      label: Text(
                        _indoor || v.gpsReady ? 'Start' : (_armed ? 'Start zodra GPS klaar is' : 'Start (begint als GPS klaar is)'),
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  if (_armed && !_indoor && !v.gpsReady)
                    TextButton(
                      onPressed: () {
                        setState(() => _armed = false);
                        _start();
                      },
                      child: const Text('Nu toch starten (minder nauwkeurig)'),
                    ),
                ],
              )
            : _saving
                ? const Center(child: CircularProgressIndicator())
                : _locked
                    ? _UnlockButton(onUnlock: () => setState(() => _locked = false))
                    : Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                v.status == RecorderStatus.paused ? _svc.resume() : _svc.pause();
                              },
                              icon: Icon(v.status == RecorderStatus.paused ? Icons.play_arrow : Icons.pause, size: 28),
                              label: Text(v.status == RecorderStatus.paused ? 'Verder' : 'Pauze', style: const TextStyle(fontSize: 17)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(64),
                                backgroundColor: RwColors.danger,
                                foregroundColor: RwColors.background,
                              ),
                              onPressed: _stop,
                              icon: const Icon(Icons.stop, size: 28),
                              label: const Text('Stop', style: TextStyle(fontSize: 17)),
                            ),
                          ),
                        ],
                      );
        return PopScope(
          canPop: !started,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) showMessage(context, 'Je run loopt nog. Stop eerst, of ga met de thuisknop naar een andere app.');
          },
          child: MediaQuery(
            // Zonmodus: tijdens het lopen alles een maat groter.
            data: _sunMode && started
                ? MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1) * 1.12))
                : MediaQuery.of(context),
            child: Scaffold(
            backgroundColor: (_sunMode || _nightMode) && started ? Colors.black : null,
            appBar: AppBar(
              title: Text(widget.sessionTitle ?? 'Run opnemen', overflow: TextOverflow.ellipsis),
              automaticallyImplyLeading: !started,
              actions: [
                if (started)
                  IconButton(
                    tooltip: 'SOS',
                    icon: Icon(Icons.sos, color: RwColors.danger),
                    onPressed: () => showSosSheet(context),
                  ),
                if (started)
                  IconButton(
                    tooltip: _locked ? 'Scherm is vergrendeld' : 'Scherm vergrendelen',
                    icon: Icon(_locked ? Icons.lock : Icons.lock_open),
                    onPressed: _locked ? null : () => setState(() => _locked = true),
                  ),
              ],
            ),
            body: ColorFiltered(
              // Nachtmodus: alles in rood (helderheid blijft, kleur gaat eruit).
              colorFilter: _nightMode && started
                  ? const ColorFilter.matrix([0.5, 0.4, 0.1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0])
                  : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
              child: Stack(children: [
              if (started && !_sunMode && !_nightMode) Positioned.fill(child: _ZoneGlow(view: v)),
              SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusBar(view: v, error: _error),
                    Expanded(
                      child: !started
                          ? _preStats(v)
                          : AbsorbPointer(
                              absorbing: _locked,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: PageView(
                                      controller: _pages,
                                      onPageChanged: (i) => setState(() => _page = i),
                                      children: [
                                        _stats(v),
                                        Padding(
                                          padding: const EdgeInsets.only(top: 12, bottom: 8),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(child: LiveTrackMap(track: v.track, position: v.position, planned: v.followRoute)),
                                              const SizedBox(height: 10),
                                              Row(
                                                children: [
                                                  Expanded(child: _Big(label: 'Afstand', value: Fmt.km(v.distance, decimals: 2), small: true)),
                                                  Expanded(child: _Big(label: 'Tijd', value: Fmt.duration(v.movingSeconds), small: true)),
                                                  Expanded(
                                                    child: _Big(
                                                        label: 'Tempo nu',
                                                        value: v.currentPace <= 0 ? '–' : Fmt.pace(v.currentPace).replaceAll(' /km', ''),
                                                        small: true),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Semantics(
                                    label: _page == 0 ? 'Cijfers, veeg voor de kaart' : 'Kaart, veeg terug voor de cijfers',
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        for (var i = 0; i < 2; i++)
                                          AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                                            width: _page == i ? 22 : 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: _page == i ? RwColors.accent : RwColors.bar,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    controls,
                    if (_share && started) ...[
                      const SizedBox(height: 10),
                      Text('Live delen staat aan. De link deel je via Vandaag → Veilig onderweg.',
                          textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
              Positioned.fill(child: _KmMoment(view: v, kmTimes: _svc.recording?.kmTimes ?? const [])),
              if (_countdown != null) _Countdown(value: _countdown!),
            ]),
            ),
          ),
          ),
        );
      },
    );
  }
}

/// Bij elke hele kilometer: even groot "KM 5" met je tijd voor die km (zoals een sporthorloge).
class _KmMoment extends StatefulWidget {
  const _KmMoment({required this.view, required this.kmTimes});
  final RecorderView view;
  final List<double> kmTimes;

  @override
  State<_KmMoment> createState() => _KmMomentState();
}

class _KmMomentState extends State<_KmMoment> {
  int _seen = 0;
  ({int km, double split, double? prev})? _show;

  @override
  void initState() {
    super.initState();
    _seen = widget.view.km;
  }

  @override
  void didUpdateWidget(covariant _KmMoment old) {
    super.didUpdateWidget(old);
    final km = widget.view.km;
    if (km > _seen && km >= 1 && widget.kmTimes.length >= km) {
      final t = widget.kmTimes;
      final split = t[km - 1] - (km >= 2 ? t[km - 2] : 0);
      final prev = km >= 2 ? t[km - 2] - (km >= 3 ? t[km - 3] : 0) : null;
      _show = (km: km, split: split, prev: prev);
      Future<void>.delayed(const Duration(milliseconds: 3200), () {
        if (mounted) setState(() => _show = null);
      });
    }
    _seen = km;
  }

  @override
  Widget build(BuildContext context) {
    final s = _show;
    final diff = s == null || s.prev == null ? null : s.split - s.prev!;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: s == null ? 0 : 1,
        duration: const Duration(milliseconds: 380),
        child: AnimatedScale(
          scale: s == null ? 1.06 : 1,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          child: Container(
            color: RwColors.background.withValues(alpha: 0.88),
            alignment: Alignment.center,
            child: s == null
                ? const SizedBox.shrink()
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('KILOMETER', style: RwText.overline),
                    Text('${s.km}',
                        style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 140, fontWeight: FontWeight.w800, color: RwColors.accent, height: 1)),
                    Text(Fmt.pace(s.split), style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 40, fontWeight: FontWeight.w800)),
                    if (diff != null && diff.abs() >= 2)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          diff < 0 ? '${diff.abs().round()} s sneller dan je vorige km' : '${diff.round()} s trager dan je vorige km',
                          style: TextStyle(color: diff < 0 ? RwColors.good : RwColors.muted, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ]),
          ),
        ),
      ),
    );
  }
}

/// Aftellen 3-2-1 voor de start, groot en met een tikje per tel.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: ColoredBox(
          color: RwColors.background.withValues(alpha: 0.94),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: 1.6, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: c)),
              child: Text(
                value == 0 ? 'GO' : '$value',
                key: ValueKey(value),
                style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 180, fontWeight: FontWeight.w800, color: RwColors.accent, height: 1),
              ),
            ),
          ),
        ),
      );
}

/// Houd 1 seconde ingedrukt om het scherm te ontgrendelen (tegen per ongeluk tikken in je zak).
class _UnlockButton extends StatefulWidget {
  const _UnlockButton({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  State<_UnlockButton> createState() => _UnlockButtonState();
}

class _UnlockButtonState extends State<_UnlockButton> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onUnlock();
    });

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Scherm ontgrendelen',
      onTap: widget.onUnlock,
      child: GestureDetector(
        onTapDown: (_) => _anim.forward(from: 0),
        onTapUp: (_) => _anim.reverse(),
        onTapCancel: () => _anim.reverse(),
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) => Container(
            height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: RwColors.surfaceHigh,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: RwColors.border),
            ),
            child: Stack(
              children: [
                FractionallySizedBox(
                  widthFactor: _anim.value,
                  child: Container(color: RwColors.accent.withValues(alpha: 0.35)),
                ),
                const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 20),
                      SizedBox(width: 8),
                      Text('Houd ingedrukt om te ontgrendelen', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Grote aanwijzing voor de huidige intervalstap.
class _IntervalPanel extends StatelessWidget {
  const _IntervalPanel({required this.view, required this.onSkip});
  final RecorderView view;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final step = v.step;
    if (step == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: RwColors.good.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: RwColors.good),
            SizedBox(width: 10),
            Expanded(child: Text('Intervallen klaar. Loop rustig uit of stop je run.', style: TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
    }
    final color = switch (step.kind) {
      StepKind.work => RwColors.accent,
      StepKind.rest => RwColors.good,
      _ => RwColors.muted,
    };
    final left = step.byDistance
        ? '${v.stepRemaining.round()} m'
        : () {
            final t = v.stepRemaining.ceil();
            return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
          }();
    final next = v.nextStep;
    return Semantics(
      container: true,
      label: '${stepLabel(step.kind, walkRun: v.walkRun)}${v.workNumber > 0 ? ', blok ${v.workNumber} van ${v.reps}' : ''}, nog $left.',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v.workNumber > 0 ? '${stepLabel(step.kind, walkRun: v.walkRun).toUpperCase()} · ${v.workNumber}/${v.reps}' : stepLabel(step.kind, walkRun: v.walkRun).toUpperCase(),
                          style: TextStyle(color: color, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                        ),
                        Text(left, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 44, fontWeight: FontWeight.w800, height: 1.1)),
                        Text(next == null ? 'Daarna: klaar' : 'Daarna: ${stepLabel(next.kind, walkRun: v.walkRun).toLowerCase()} ${next.amount}',
                            style: TextStyle(color: RwColors.muted)),
                      ],
                    ),
                  ),
                  if (onSkip != null)
                    TextButton.icon(onPressed: onSkip, icon: const Icon(Icons.skip_next), label: const Text('Volgende')),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: v.stepProgress,
                minHeight: 6,
                color: color,
                backgroundColor: RwColors.bar,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.view, required this.error});
  final RecorderView view;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final (text, color, icon) = error != null
        ? (error!, RwColors.danger, Icons.error_outline)
        : switch (view.status) {
            RecorderStatus.running => ('Bezig', RwColors.good, Icons.directions_run),
            RecorderStatus.autoPaused => ('Automatisch gepauzeerd: je staat stil', RwColors.warning, Icons.pause_circle_outline),
            RecorderStatus.paused => ('Gepauzeerd', RwColors.warning, Icons.pause_circle_outline),
            _ => view.gpsReady
                ? ('GPS gevonden (${view.gpsAccuracy!.round()} m nauwkeurig)', RwColors.good, Icons.gps_fixed)
                : ('GPS zoeken… ga even buiten staan', RwColors.muted, Icons.gps_not_fixed),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
          if (view.km > 0) Text('${view.km} km', style: TextStyle(color: RwColors.muted)),
        ],
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.value, this.small = false});
  final String label;
  final String value;
  final bool small;

  @override
  Widget build(BuildContext context) => Semantics(
        // Schermlezer (TalkBack): lees "Tempo nu 5:30" in één keer voor, niet cijfer voor cijfer.
        label: '$label $value',
        excludeSemantics: true,
        child: Column(
        children: [
          // Altijd op één regel (ook bij runs boven het uur of met grote letters).
          FittedBox(
            fit: BoxFit.scaleDown,
            child: RollingText(value, style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: small ? 22 : 30, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: RwColors.subtle, fontSize: 13)),
        ],
      ),
      );
}

/// Live hartslag met de zone als gekleurde balk.
class _HeartRow extends StatelessWidget {
  const _HeartRow({required this.view});
  final RecorderView view;

  static Map<int, Color> get _zoneColors => {for (var z = 1; z <= 5; z++) z: rwZoneColor(z)};

  @override
  Widget build(BuildContext context) {
    final bpm = view.heartRate;
    final max = HeartRateService.instance.maxHr.value;
    final zone = bpm == null ? 0 : heartRateZone(bpm, max);
    final color = _zoneColors[zone] ?? RwColors.subtle;
    return Semantics(
      label: bpm == null ? 'Hartslagband verbinden' : 'Hartslag $bpm, zone $zone',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            _BeatingHeart(bpm: bpm),
            const SizedBox(width: 10),
            Text(bpm == null ? (view.hrStatus == HrStatus.lost ? 'Band kwijt…' : 'Band verbinden…') : '$bpm',
                style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: bpm == null ? 16 : 28, fontWeight: FontWeight.w800)),
            if (bpm != null) Text('  bpm', style: TextStyle(color: RwColors.muted)),
            // De zone krimpt mee als er weinig ruimte is (grote letters), in plaats van uit beeld te vallen.
            Expanded(
              child: zone <= 0
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                  for (var z = 1; z <= 5; z++)
                    Container(
                      width: 14,
                      height: z == zone ? 18 : 10,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: z <= zone ? _zoneColors[z] : RwColors.bar,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text('Zone $zone', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Snelheid van de loopband instellen (stappen van 0,5 km/u), zoals op het display.
class _TreadmillSpeed extends StatelessWidget {
  const _TreadmillSpeed({required this.kmh, required this.onChanged});
  final double? kmh;
  final ValueChanged<double?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final k = kmh;
    void set(double v) {
      HapticFeedback.selectionClick();
      onChanged?.call(double.parse(v.clamp(3, 25).toStringAsFixed(1)));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: RwColors.surfaceHigh, borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Langzamer',
            onPressed: onChanged == null ? null : () => set((k ?? 10.5) - 0.5),
            icon: const Icon(Icons.remove_circle_outline, size: 30),
          ),
          Expanded(
            child: InkWell(
              onTap: onChanged == null || k == null ? null : () => onChanged!(null),
              child: Column(
                children: [
                  Text(k == null ? 'Snelheid' : '${k.toStringAsFixed(1).replaceAll('.', ',')} km/u',
                      style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800, fontSize: 22)),
                  Text(k == null ? 'tik + of − om in te stellen' : 'van de loopband · tik om uit te zetten',
                      style: TextStyle(color: RwColors.subtle, fontSize: 11)),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sneller',
            onPressed: onChanged == null ? null : () => set((k ?? 10.0) + 0.5),
            icon: const Icon(Icons.add_circle_outline, size: 30),
          ),
        ],
      ),
    );
  }
}


/// Radar die pulseert zolang de GPS zoekt; wordt een rustige groene ring met vinkje als hij klaar is.
/// Onderaan signaalbalkjes en de nauwkeurigheid in meters.
class _GpsRadar extends StatefulWidget {
  const _GpsRadar({required this.accuracy, required this.ready});
  final double? accuracy;
  final bool ready;

  @override
  State<_GpsRadar> createState() => _GpsRadarState();
}

class _GpsRadarState extends State<_GpsRadar> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    if (!WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int get _bars {
    final a = widget.accuracy;
    if (a == null) return 0;
    if (a <= 8) return 4;
    if (a <= 15) return 3;
    if (a <= 30) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.ready;
    final color = ready ? RwColors.good : RwColors.accent;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 150,
        height: 150,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            painter: _RadarPainter(t: _c.value, color: color, ready: ready),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                child: Icon(
                  ready ? Icons.check_rounded : Icons.my_location,
                  key: ValueKey(ready),
                  size: 40,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < 4; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 5,
            height: 6.0 + i * 4,
            decoration: BoxDecoration(
              color: i < _bars ? color : RwColors.bar,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 8),
        Text(
          widget.accuracy == null ? 'Geen signaal' : '± ${widget.accuracy!.round()} m',
          style: TextStyle(color: RwColors.subtle, fontSize: 12, fontFeatures: rwTnum),
        ),
      ]),
    ]);
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.t, required this.color, required this.ready});
  final double t;
  final Color color;
  final bool ready;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r * 0.36, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawCircle(
      c,
      r * 0.36,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.6),
    );
    if (ready) {
      // Rustige, ademende ring.
      final b = 0.5 + 0.5 * (1 - (2 * t - 1).abs());
      canvas.drawCircle(
        c,
        r * (0.52 + 0.04 * b),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.25 + 0.2 * b),
      );
      return;
    }
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      canvas.drawCircle(
        c,
        r * (0.36 + 0.64 * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = color.withValues(alpha: (1 - p) * 0.5),
      );
    }
    // Draaiende veeg, zoals een echte radar.
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      rect.deflate(r * 0.02),
      t * 6.283 - 0.9,
      0.9,
      true,
      Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: 6.283,
          transform: GradientRotation(t * 6.283 - 0.9),
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.18)],
          stops: const [0, 0.1432],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.t != t || old.ready != ready || old.color != color;
}

/// Zachte, ademende gloed rond een knop (alleen als [active]).
class _GlowPulse extends StatefulWidget {
  const _GlowPulse({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<_GlowPulse> createState() => _GlowPulseState();
}

class _GlowPulseState extends State<_GlowPulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (!WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (_, child) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            boxShadow: widget.active
                ? [BoxShadow(color: RwColors.accent.withValues(alpha: 0.18 + 0.22 * _c.value), blurRadius: 14 + 16 * _c.value, spreadRadius: -2)]
                : const [],
          ),
          child: child,
        ),
      );
}


/// Ring rond de afstand die per kilometer volloopt, met een gloeiend kopje.
class _KmRing extends StatelessWidget {
  const _KmRing({required this.fraction, required this.child});
  final double fraction;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        // Bij grote letters (telefooninstelling) een kleinere ring, zodat de rest van het scherm past.
        final text = MediaQuery.textScalerOf(context).scale(1);
        final size = math.min(280.0, c.maxWidth) / (text > 1.2 ? text / 1.2 : 1);
        return TweenAnimationBuilder<double>(
          tween: Tween(end: fraction),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, f, child) => CustomPaint(
            painter: _KmRingPainter(f),
            child: SizedBox(
              width: size,
              height: size,
              // FittedBox: de cijfers schalen mee als de ring kleiner is.
              child: Padding(padding: EdgeInsets.all(size * 0.12), child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: child))),
            ),
          ),
          child: child,
        );
      });
}

class _KmRingPainter extends CustomPainter {
  _KmRingPainter(this.f);
  final double f;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = RwColors.text.withValues(alpha: 0.06));
    // Fijne streepjes per 100 m.
    final tick = Paint()
      ..color = RwColors.text.withValues(alpha: 0.12)
      ..strokeWidth = 1.5;
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r - 12), c + d * (r - 7), tick);
    }
    if (f <= 0.002) return;
    final sweep = 2 * math.pi * f.clamp(0.0, 1.0);
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      transform: const GradientRotation(-math.pi / 2),
      colors: [RwColors.accentDeep, RwColors.accent, RwColors.accentLight],
      stops: [0, f * 0.7, f],
    ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = RwColors.accent.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawArc(rect, -math.pi / 2, sweep, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..shader = shader);
    final a = -math.pi / 2 + sweep;
    final tip = c + Offset(math.cos(a), math.sin(a)) * r;
    canvas.drawCircle(tip, 9, Paint()..color = RwColors.accent.withValues(alpha: 0.3));
    canvas.drawCircle(tip, 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _KmRingPainter old) => old.f != f;
}

/// Hartje dat op het ritme van je eigen hartslag klopt.
class _BeatingHeart extends StatefulWidget {
  const _BeatingHeart({required this.bpm});
  final int? bpm;

  @override
  State<_BeatingHeart> createState() => _BeatingHeartState();
}

class _BeatingHeartState extends State<_BeatingHeart> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  void _sync() {
    final b = widget.bpm;
    if (b == null || b < 30 || WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      _c.stop();
      _c.value = 0;
      return;
    }
    _c.duration = Duration(milliseconds: (60000 / b.clamp(30, 230)).round());
    _c.repeat();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _BeatingHeart old) {
    super.didUpdateWidget(old);
    // Alleen bij een merkbare verandering opnieuw starten, anders hapert het ritme.
    if ((old.bpm == null) != (widget.bpm == null) || ((old.bpm ?? 0) - (widget.bpm ?? 0)).abs() >= 4) _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          // "Lub-dub": twee korte tikken aan het begin van elke slag.
          final t = _c.value;
          final beat = t < 0.12 ? math.sin(t / 0.12 * math.pi) : (t > 0.18 && t < 0.28 ? 0.6 * math.sin((t - 0.18) / 0.1 * math.pi) : 0.0);
          return Transform.scale(
            scale: 1 + 0.2 * beat,
            child: Icon(Icons.favorite, color: widget.bpm == null ? RwColors.subtle : RwColors.danger, shadows: [
              if (widget.bpm != null) Shadow(color: RwColors.danger.withValues(alpha: 0.6 * beat), blurRadius: 12),
            ]),
          );
        },
      );
}

/// Zachte gloed bovenin het scherm in de kleur van je hartslagzone (of oranje zonder band).
class _ZoneGlow extends StatelessWidget {
  const _ZoneGlow({required this.view});
  final RecorderView view;

  @override
  Widget build(BuildContext context) {
    final bpm = view.heartRate;
    final zone = bpm == null ? 0 : heartRateZone(bpm, HeartRateService.instance.maxHr.value);
    final color = _HeartRow._zoneColors[zone] ?? RwColors.accent;
    final paused = view.status == RecorderStatus.paused;
    return IgnorePointer(
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: paused ? RwColors.subtle : color),
        duration: const Duration(milliseconds: 1200),
        builder: (_, c, _) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.75),
              radius: 1.0,
              colors: [(c ?? color).withValues(alpha: 0.13), (c ?? color).withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}


/// Pijl en afstand terug naar je startpunt (zichtbaar zodra je meer dan 300 m van je start bent).
class _BackToStart extends StatelessWidget {
  const _BackToStart({required this.track});
  final List<LatLng> track;

  @override
  Widget build(BuildContext context) {
    final b = backToStart(track);
    if (b == null || b.meters < 300) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        label: 'Je start ligt ${Fmt.km(b.meters, decimals: 1)} ${b.relative == null ? '' : directionWords(b.relative!)}',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: RwColors.surfaceHigh, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            if (b.relative != null)
              TweenAnimationBuilder<double>(
                tween: Tween(end: b.relative!),
                duration: const Duration(milliseconds: 500),
                builder: (_, deg, child) => Transform.rotate(angle: deg * math.pi / 180, child: child),
                child: Icon(Icons.navigation, color: RwColors.accent),
              )
            else
              Icon(Icons.home_outlined, color: RwColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                b.relative == null ? 'Terug naar start' : 'Terug naar start: ${directionWords(b.relative!)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(Fmt.km(b.meters, decimals: 1), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: rwTnum)),
          ]),
        ),
      ),
    );
  }
}


/// Je staat (nog) niet op je route: grote pijl en afstand naar de route.
class _WayToRouteCard extends StatelessWidget {
  const _WayToRouteCard({required this.way, required this.approaching});
  final WayToRoute way;
  final bool approaching;

  @override
  Widget build(BuildContext context) {
    final color = approaching ? RwColors.accent : RwColors.warning;
    final dist = way.meters < 1000 ? '${(way.meters / 10).round() * 10} m' : Fmt.km(way.meters, decimals: 1);
    final title = approaching ? 'Naar je route' : 'Terug naar je route';
    return Semantics(
      liveRegion: true,
      label: '$title: $dist ${way.words}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          if (way.relative != null)
            TweenAnimationBuilder<double>(
              tween: Tween(end: way.relative!),
              duration: const Duration(milliseconds: 500),
              builder: (_, deg, child) => Transform.rotate(angle: deg * math.pi / 180, child: child),
              child: Icon(Icons.navigation, color: color, size: 40),
            )
          else
            Icon(Icons.explore_outlined, color: color, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontFamily: RwFonts.display, fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(
                approaching
                    ? 'Ligt ${way.words}. Je mag overal instappen.'
                    : 'Ligt ${way.words}. Volg de pijl.',
                style: TextStyle(color: RwColors.muted, height: 1.3),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Text(dist,
              style: const TextStyle(
                  fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 26, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

/// Grote pijl met de volgende afslag, zoals een navigatie-app.
class _NextTurnCard extends StatelessWidget {
  const _NextTurnCard({required this.turn, required this.inMeters});
  final RouteTurn turn;
  final double inMeters;

  @override
  Widget build(BuildContext context) {
    final soon = inMeters < 40;
    final dist = inMeters < 20 ? 'Nu' : '${(inMeters >= 150 ? (inMeters / 50).round() * 50 : (inMeters / 10).round() * 10)} m';
    return Semantics(
      liveRegion: true,
      label: '${turn.kind.label}, $dist',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: soon ? RwColors.accent : RwColors.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: RwColors.accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            TurnArrow(turn.kind, size: 44, color: soon ? RwColors.accentDark : RwColors.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Text(turn.kind.label,
                  maxLines: 2,
                  style: TextStyle(
                      fontFamily: RwFonts.display,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: soon ? RwColors.accentDark : RwColors.text)),
            ),
            const SizedBox(width: 10),
            Text(dist,
                style: TextStyle(
                    fontFamily: RwFonts.display,
                    fontFeatures: rwTnum,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: soon ? RwColors.accentDark : RwColors.text)),
          ],
        ),
      ),
    );
  }
}


/// Kies welke Nederlandse stem je hoort (met voorbeeld). Toont alleen stemmen die op je toestel staan.
class _VoicePicker extends StatefulWidget {
  const _VoicePicker();

  @override
  State<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<_VoicePicker> {
  final _svc = RunRecorderService.instance;
  List<({String name, String locale, bool network, int quality})>? _voices;
  static const _sample = 'Kilometer 3. Dit stuk 5 minuten 30 per kilometer. Lekker bezig!';

  @override
  void initState() {
    super.initState();
    _svc.dutchVoices().then((v) {
      if (mounted) setState(() => _voices = v);
    });
  }

  String _label(int i, ({String name, String locale, bool network, int quality}) v) {
    final region = v.locale.toLowerCase().contains('be') ? 'Vlaams' : 'Nederlands';
    final q = v.quality >= 400 ? 'hoge kwaliteit' : 'standaard';
    return 'Stem ${i + 1} · $region · $q${v.network ? ' · alleen met internet' : ''}';
  }

  Future<void> _pick(({String name, String locale})? v) async {
    HapticFeedback.selectionClick();
    setState(() {});
    await _svc.setVoice(v, preview: _sample);
    final p = await SharedPreferences.getInstance();
    if (v == null) {
      await p.remove('rec_voice_name');
      await p.remove('rec_voice_locale');
    } else {
      await p.setString('rec_voice_name', v.name);
      await p.setString('rec_voice_locale', v.locale);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final list = _voices;
    if (list == null) {
      return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
    }
    final chosen = _svc.voiceChoice;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(chosen == null ? Icons.radio_button_checked : Icons.radio_button_off, color: chosen == null ? RwColors.accent : RwColors.subtle),
        title: const Text('Automatisch (beste stem zonder internet)'),
        onTap: () => _pick(null),
      ),
      for (final (i, v) in list.take(8).indexed)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(chosen?.name == v.name ? Icons.radio_button_checked : Icons.radio_button_off,
              color: chosen?.name == v.name ? RwColors.accent : RwColors.subtle),
          title: Text(_label(i, v)),
          trailing: const Icon(Icons.play_circle_outline),
          onTap: () => _pick((name: v.name, locale: v.locale)),
        ),
      if (list.length <= 1)
        Text(
          'Er staat maar één Nederlandse stem op je telefoon. Mooiere stemmen installeer je gratis via de knop hieronder: '
          'kies Spraakservices van Google → Stemgegevens installeren → Nederlands.',
          style: TextStyle(color: RwColors.muted, fontSize: 12, height: 1.4),
        ),
      if (Platform.isAndroid)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Meer stemmen installeren'),
            onPressed: () => const AndroidIntent(action: 'com.android.settings.TTS_SETTINGS').launch().catchError((Object _) {}),
          ),
        ),
    ]);
  }
}


/// "Snel starten": kaartjes met je training van vandaag en je vaste rondje. Eén tik en alles staat goed.
class _QuickPresets extends ConsumerWidget {
  const _QuickPresets({required this.show, required this.routeChosen, required this.planChosen, required this.onSession, required this.onRoute});
  final bool show, routeChosen, planChosen;
  final ValueChanged<PlanSession> onSession;
  final ValueChanged<RunRoute> onRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!show) return const SizedBox.shrink();
    final session = todaySession(ref.watch(planProvider).value ?? const <PlanSession>[]);
    final route = favoriteRoute(ref.watch(activitiesProvider).value ?? const <Activity>[], ref.watch(routesProvider).value ?? const <RunRoute>[]);
    final cards = <Widget>[
      if (session != null && !planChosen && session.kind != SessionKind.race)
        _PresetCard(icon: Icons.event_available_outlined, title: 'Vandaag', subtitle: session.title, onTap: () => onSession(session)),
      if (route != null && !routeChosen)
        _PresetCard(icon: Icons.route_outlined, title: 'Vast rondje', subtitle: route.name, onTap: () => onRoute(route)),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        for (final (i, c) in cards.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: c),
        ],
      ]),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [RwColors.accent.withValues(alpha: 0.18), RwColors.accent.withValues(alpha: 0.06)]),
              border: Border.all(color: RwColors.accent.withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              Icon(icon, color: RwColors.accentLight, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title.toUpperCase(), style: TextStyle(color: RwColors.accentLight, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

/// Kaart met de live opdracht die nu loopt.
class _QuestCard extends StatelessWidget {
  const _QuestCard({required this.view});
  final RecorderView view;

  @override
  Widget build(BuildContext context) {
    final q = view.quest!;
    final left = q.seconds != null ? '${view.questRemaining.ceil()} s' : '${view.questRemaining.round()} m';
    final pace = view.currentPace;
    final onPace = pace > 0 && pace <= q.targetPace;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        liveRegion: true,
        label: 'Opdracht ${q.title}, nog $left, doel sneller dan ${questPace(q.targetPace)} per kilometer',
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: RwColors.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: RwColors.accent, width: 1.4),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.bolt, size: 20, color: RwColors.accent),
              const SizedBox(width: 6),
              Expanded(child: Text(q.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              Text(left, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800, fontSize: 20)),
            ]),
            const SizedBox(height: 6),
            Text.rich(TextSpan(children: [
              TextSpan(text: 'Doel: sneller dan ${questPace(q.targetPace)}/km · nu ', style: TextStyle(color: RwColors.muted)),
              TextSpan(
                text: pace > 0 ? questPace(pace) : '–',
                style: TextStyle(fontWeight: FontWeight.w700, color: onPace ? RwColors.good : RwColors.text),
              ),
            ])),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: view.questProgress,
                minHeight: 6,
                color: RwColors.accent,
                backgroundColor: RwColors.bar,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Stand van de opdrachten tussen twee opdrachten door.
class _QuestTally extends StatelessWidget {
  const _QuestTally({required this.view});
  final RecorderView view;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          Icon(Icons.bolt_outlined, size: 18, color: RwColors.accent),
          const SizedBox(width: 6),
          Text('Opdrachten: ${view.questsDone} van ${view.questsTotal} gehaald',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}
