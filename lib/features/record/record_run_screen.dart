import 'dart:convert';
import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/heart_rate_service.dart';
import '../../data/services/run_recorder_service.dart';
import '../../data/services/sync_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/badges.dart' as bd;
import '../../domain/best_efforts.dart';
import '../../domain/geo.dart';
import '../../domain/heart_rate.dart';
import '../../domain/run_streams.dart';
import '../../domain/intervals.dart';
import '../../domain/run_coach.dart';
import '../../domain/run_recorder.dart';
import '../../domain/shoes.dart';
import '../../shared/widgets.dart';
import '../routes/route_map.dart' show LiveTrackMap;
import 'interval_picker.dart';
import '../profile/emergency_contact.dart';
import 'run_summary_screen.dart';

/// Opent het opnamescherm. Met [plan] of [targetPace] staat een training uit je schema al klaar.
void openRecorder(BuildContext context, {IntervalPlan? plan, double? targetPace, String? sessionTitle, RunRoute? route}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => RecordRunScreen(initialPlan: plan, initialTargetPace: targetPace, sessionTitle: sessionTitle, initialRoute: route),
  ));
}

/// Een run opnemen met GPS, met stemcoach per kilometer.
class RecordRunScreen extends ConsumerStatefulWidget {
  const RecordRunScreen({super.key, this.initialPlan, this.initialTargetPace, this.sessionTitle, this.initialRoute});

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
  bool _batteryDone = true;
  bool _indoor = false;
  double? _targetPace;
  CueSettings _cues = const CueSettings();
  String? _shoeId;
  bool _shoeChosen = false;
  RunRoute? _route;
  RunStreams? _ghost;
  int? _ghostTime;
  bool _raceGhost = true;
  String? _error;
  IntervalPlan? _plan;
  final _pages = PageController();
  int _page = 0;

  static const _planKey = 'last_interval_plan';

  @override
  void initState() {
    super.initState();
    final r = widget.initialRoute;
    if (r != null && r.id != null) {
      _route = r;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadGhost(r.id!));
    }
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() {
          _haptics = p.getBool('rec_haptics') ?? true;
          _indoor = p.getBool('rec_indoor') ?? false;
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
      _svc.warmUp().catchError((Object e) {
        if (mounted) setState(() => _error = friendlyError(e));
      });
    }
  }

  @override
  void dispose() {
    // Weggegaan zonder te starten: GPS weer uit.
    if (_svc.recording?.status == RecorderStatus.idle) _svc.discard();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final name = ref.read(profileProvider).value?.displayName ?? '';
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
        ghost: _raceGhost ? _ghost : null,
      );
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
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
              const Text('Laat RunWise doorlopen op de achtergrond',
                  style: TextStyle(fontFamily: RwFonts.display, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'Om batterij te sparen zetten veel telefoons apps in slaapstand als je scherm uit is. '
                'Dan stopt RunWise halverwege je run met meten. Zo voorkom je dat:',
                style: TextStyle(color: RwColors.muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text('1. Tik hieronder op "Batterij-instellingen" en kies bij RunWise "Niet optimaliseren" of "Onbeperkt".',
                  style: TextStyle(height: 1.4)),
              const SizedBox(height: 8),
              const Text(
                  '2. Samsung: Instellingen → Batterij → Achtergrondgebruik beperken → Apps nooit in slaapstand → voeg RunWise toe.',
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
    setState(() => _plan = plan);
    try {
      final p = await SharedPreferences.getInstance();
      plan == null ? await p.remove(_planKey) : await p.setString(_planKey, jsonEncode(plan.toJson()));
    } catch (_) {}
  }

  Future<void> _stop() async {
    final ok = await confirmDialog(context, title: 'Run stoppen?', message: 'Je run wordt opgeslagen.');
    if (!ok) return;
    double? indoorMeters;
    if (_svc.recording?.indoor ?? false) {
      indoorMeters = await _askDistance();
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
  Future<double?> _askDistance() async {
    final c = TextEditingController();
    final km = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hoe ver liep je?'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Afstand in km (van de loopband)', hintText: 'bijv. 5,2'),
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
                const Text('Doeltempo', style: TextStyle(fontFamily: RwFonts.display, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('De stem zegt het als je langer dan 20 seconden meer dan 15 s/km te snel of te langzaam gaat.',
                    style: TextStyle(color: RwColors.muted, height: 1.4)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(onPressed: () => set(() => sec = (sec - 5).clamp(180, 600)), icon: const Icon(Icons.remove_circle_outline)),
                    Text(Fmt.pace(sec), style: const TextStyle(fontFamily: RwFonts.display, fontSize: 34, fontWeight: FontWeight.w800)),
                    IconButton(onPressed: () => set(() => sec = (sec + 5).clamp(180, 600)), icon: const Icon(Icons.add_circle_outline)),
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

  Future<void> _chooseCues() async {
    var c = _cues;
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
                const Text('Stemcoach', style: TextStyle(fontFamily: RwFonts.display, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in CueEvery.values)
                      ChoiceChip(label: Text(e.label), selected: c.every == e, onSelected: (_) => set(() => c = c.copyWith(every: e))),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tempo van het laatste stuk'),
                  value: c.lap,
                  onChanged: (v) => set(() => c = c.copyWith(lap: v)),
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

  Future<void> _chooseRoute(List<RunRoute> routes) async {
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
              for (final r in routes)
                ListTile(
                  leading: const Icon(Icons.route_outlined, color: RwColors.accent),
                  title: Text(r.name),
                  subtitle: Text(Fmt.km(r.distanceMeters, decimals: 1)),
                  trailing: r.id == _route?.id ? const Icon(Icons.check, color: RwColors.accent) : null,
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
      _ghost = null;
      _ghostTime = null;
    });
    if (picked.isNotEmpty) _loadGhost(picked);
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
                trailing: s.id == (_shoeChosen ? _shoeId : defaultShoe(shoes)?.id) ? const Icon(Icons.check, color: RwColors.accent) : null,
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

  Future<void> _save(RunRecording rec) async {
    setState(() => _saving = true);
    try {
      final track = rec.simplifiedTrack();
      final start = rec.startedAt ?? DateTime.now();
      HourWeather? w;
      if (track.isNotEmpty) {
        w = await ref.read(weatherServiceProvider).historical(track.first.lat, track.first.lon, start);
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
      final id = await repo.addActivityReturningId(activity);
      if (streamsJson != null) {
        await repo
            .setActivityStreams(id, streamsJson, bestEfforts: bestEffortsToJson(efforts))
            .catchError((Object _) {}); // Het verloop is een extraatje; de run zelf staat er al.
        // Hoogte verbeteren met de hoogtekaart (op de achtergrond).
        if (!rec.indoor) repo.improveElevation(id, streamsJson).then((_) => ref.invalidate(activitiesProvider)).ignore();
      }
      final sync = ref.read(syncServiceProvider);
      final written = await sync.writeRunToHealth(activity);
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
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => RunSummaryScreen(
          activity: saved,
          streams: streams,
          efforts: efforts,
          previousBest: previousBest,
          healthWritten: written,
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
            Icon(_indoor ? Icons.fitness_center : Icons.directions_run, size: 56, color: RwColors.accent),
            const SizedBox(height: 8),
            Text(
              _indoor ? 'Klaar voor de loopband' : (v.gpsReady ? 'Klaar voor de start' : 'GPS zoeken…'),
              style: const TextStyle(fontFamily: RwFonts.display, fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _indoor
                  ? 'De klok loopt; na afloop vul je de afstand in.'
                  : 'Kies je opties en druk op Start. Je scherm mag uit.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: RwColors.muted),
            ),
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
          Text(
            Fmt.duration(v.movingSeconds),
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: RwFonts.display, fontSize: 80, fontWeight: FontWeight.w800, height: 1),
          ),
          const Text('loopband · de afstand vul je na afloop in',
              textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted, fontSize: 16)),
          if (v.heartRate != null || v.hrStatus == HrStatus.connecting || v.hrStatus == HrStatus.lost) ...[
            const SizedBox(height: 18),
            _HeartRow(view: v),
          ],
          const Spacer(),
        ] else ...[
        Semantics(
          label: 'Afstand ${Fmt.km(v.distance, decimals: 2)}',
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              (v.distance / 1000).toStringAsFixed(2).replaceAll('.', ','),
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(fontFamily: RwFonts.display, fontSize: v.hasIntervals ? 72 : 96, fontWeight: FontWeight.w800, height: 1),
            ),
          ),
        ),
        const Text('kilometer', textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted, fontSize: 18)),
        const SizedBox(height: 28),
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
        if (v.routeRemaining != null) ...[
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
                      const Text('vs record', style: TextStyle(color: RwColors.subtle, fontSize: 11)),
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
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, icon: Icon(Icons.terrain_outlined), label: Text('Buiten')),
                      ButtonSegment(value: true, icon: Icon(Icons.fitness_center), label: Text('Loopband')),
                    ],
                    selected: {_indoor},
                    onSelectionChanged: (x) {
                      setState(() => _indoor = x.first);
                      SharedPreferences.getInstance().then((p) => p.setBool('rec_indoor', x.first)).ignore();
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timer_outlined, color: RwColors.accent),
                    title: Text(_plan == null ? 'Gewone run' : _plan!.name),
                    subtitle: Text(_plan == null ? 'Tik om een intervaltraining te kiezen' : 'Intervaltraining met stem · tik om te wijzigen'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _choosePlan,
                  ),
                  if (!_batteryDone)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.battery_alert_outlined, color: RwColors.warning),
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
                      if (!_indoor)
                        FilterChip(
                          avatar: const Icon(Icons.share_location_outlined, size: 18),
                          label: const Text('Live delen'),
                          tooltip: 'Iemand thuis kan meekijken via een link',
                          selected: _share,
                          onSelected: (x) => setState(() => _share = x),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.tune, size: 18),
                        label: Text('Stem: ${_cues.every.label.toLowerCase()}'),
                        onPressed: _chooseCues,
                      ),
                      if (!_indoor)
                        ActionChip(
                          avatar: const Icon(Icons.speed, size: 18),
                          label: Text(_targetPace == null ? 'Doeltempo' : 'Doel ${Fmt.pace(_targetPace!)}'),
                          onPressed: _chooseTargetPace,
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
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                    onPressed: !_indoor && _error != null && !v.gpsReady ? null : _start,
                    icon: const Icon(Icons.play_arrow, size: 30),
                    label: Text(_indoor || v.gpsReady ? 'Start' : 'Start (GPS zoekt nog)', style: const TextStyle(fontSize: 18)),
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
                              onPressed: v.status == RecorderStatus.paused ? _svc.resume : _svc.pause,
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
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.sessionTitle ?? 'Run opnemen', overflow: TextOverflow.ellipsis),
              automaticallyImplyLeading: !started,
              actions: [
                if (started)
                  IconButton(
                    tooltip: 'SOS',
                    icon: const Icon(Icons.sos, color: RwColors.danger),
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
            body: SafeArea(
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
                      const Text('Live delen staat aan. De link deel je via Vandaag → Veilig onderweg.',
                          textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
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
        child: const Row(
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
      label: '${step.kind.label}${v.workNumber > 0 ? ', interval ${v.workNumber} van ${v.reps}' : ''}, nog $left.',
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
                          v.workNumber > 0 ? '${step.kind.label.toUpperCase()} · ${v.workNumber}/${v.reps}' : step.kind.label.toUpperCase(),
                          style: TextStyle(color: color, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                        ),
                        Text(left, style: const TextStyle(fontFamily: RwFonts.display, fontSize: 44, fontWeight: FontWeight.w800, height: 1.1)),
                        Text(next == null ? 'Daarna: klaar' : 'Daarna: ${next.kind.label.toLowerCase()} ${next.amount}',
                            style: const TextStyle(color: RwColors.muted)),
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
          if (view.km > 0) Text('${view.km} km', style: const TextStyle(color: RwColors.muted)),
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
  Widget build(BuildContext context) => Column(
        children: [
          // Altijd op één regel (ook bij runs boven het uur of met grote letters).
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, maxLines: 1, style: TextStyle(fontFamily: RwFonts.display, fontSize: small ? 22 : 30, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: RwColors.subtle, fontSize: 13)),
        ],
      );
}

/// Live hartslag met de zone als gekleurde balk.
class _HeartRow extends StatelessWidget {
  const _HeartRow({required this.view});
  final RecorderView view;

  static const _zoneColors = {
    1: Color(0xFF8D8D98),
    2: Color(0xFF5AA9FF),
    3: RwColors.good,
    4: RwColors.warning,
    5: RwColors.danger,
  };

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
            Icon(Icons.favorite, color: bpm == null ? RwColors.subtle : RwColors.danger),
            const SizedBox(width: 10),
            Text(bpm == null ? (view.hrStatus == HrStatus.lost ? 'Band kwijt…' : 'Band verbinden…') : '$bpm',
                style: TextStyle(fontFamily: RwFonts.display, fontSize: bpm == null ? 16 : 28, fontWeight: FontWeight.w800)),
            if (bpm != null) const Text('  bpm', style: TextStyle(color: RwColors.muted)),
            const Spacer(),
            if (zone > 0)
              Row(
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
          ],
        ),
      ),
    );
  }
}
