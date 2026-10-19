import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/run_recorder_service.dart';
import '../../data/services/sync_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/geo.dart';
import '../../domain/intervals.dart';
import '../../domain/run_recorder.dart';
import '../../domain/shoes.dart';
import '../../shared/widgets.dart';
import '../routes/route_map.dart' show LiveTrackMap;
import 'interval_picker.dart';

void openRecorder(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const RecordRunScreen()));
}

/// Een run opnemen met GPS, met stemcoach per kilometer.
class RecordRunScreen extends ConsumerStatefulWidget {
  const RecordRunScreen({super.key});

  @override
  ConsumerState<RecordRunScreen> createState() => _RecordRunScreenState();
}

class _RecordRunScreenState extends ConsumerState<RecordRunScreen> {
  final _svc = RunRecorderService.instance;
  bool _voice = true;
  bool _share = false;
  bool _saving = false;
  bool _locked = false;
  String? _error;
  IntervalPlan? _plan;
  final _pages = PageController();
  int _page = 0;

  static const _planKey = 'last_interval_plan';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
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
      await _svc.start(voice: _voice, shareLive: _share, name: name == 'loper' ? '' : name, intervals: _plan);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
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
    final rec = await _svc.stop();
    if (rec == null || rec.distance < 200 || rec.movingSeconds < 60) {
      if (mounted) {
        showMessage(context, 'Te kort om op te slaan (minder dan 200 m of 1 minuut).');
        Navigator.of(context).pop();
      }
      return;
    }
    await _save(rec);
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
      final id = await repo.addActivityReturningId(Activity(
        startedAt: start,
        distanceMeters: double.parse(rec.distance.toStringAsFixed(1)),
        movingTimeSeconds: rec.movingSeconds.round(),
        source: 'runwise',
        temperatureCelsius: w?.temperature,
        feelsLikeCelsius: w?.feelsLike,
        windSpeedKmh: w?.windSpeed,
        windDirectionDegrees: w?.windDirection,
        humidityPct: w?.humidity,
        trackPolyline: track.length >= 2 ? encodePolyline(track) : '',
        shoeId: defaultShoe(shoes)?.id,
      ));
      ref.invalidate(activitiesProvider);
      await ref.read(syncServiceProvider).autoLinkRuns().catchError((_) => 0);
      if (!mounted) return;
      showMessage(context, 'Run opgeslagen: ${Fmt.km(rec.distance, decimals: 2)}.');
      Navigator.of(context).pop();
      context.go('/runs/$id');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Opslaan is niet gelukt: ${friendlyError(e)}', error: true);
      }
    }
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
        Semantics(
          label: 'Afstand ${Fmt.km(v.distance, decimals: 2)}',
          child: Text(
            (v.distance / 1000).toStringAsFixed(2).replaceAll('.', ','),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: RwFonts.display, fontSize: v.hasIntervals ? 72 : 96, fontWeight: FontWeight.w800, height: 1),
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
        const Spacer(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RecorderView>(
      valueListenable: _svc.view,
      builder: (context, v, _) {
        final started = v.status != RecorderStatus.idle && v.status != RecorderStatus.finished;
        final controls = !started
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timer_outlined, color: RwColors.accent),
                    title: Text(_plan == null ? 'Gewone run' : _plan!.name),
                    subtitle: Text(_plan == null ? 'Tik om een intervaltraining te kiezen' : 'Intervaltraining met stem · tik om te wijzigen'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _choosePlan,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _voice || _plan != null,
                    onChanged: _plan != null ? null : (x) => setState(() => _voice = x),
                    title: const Text('Stemcoach'),
                    subtitle: Text(_plan != null
                        ? 'Staat aan voor de intervallen'
                        : 'Elke kilometer je tijd en tempo, ook met je scherm uit. Muziek gaat even zachter.'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _share,
                    onChanged: (x) => setState(() => _share = x),
                    title: const Text('Live delen'),
                    subtitle: const Text('Iemand thuis kan meekijken via een link'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                    onPressed: _error != null && !v.gpsReady ? null : _start,
                    icon: const Icon(Icons.play_arrow, size: 30),
                    label: Text(v.gpsReady ? 'Start' : 'Start (GPS zoekt nog)', style: const TextStyle(fontSize: 18)),
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
              title: const Text('Run opnemen'),
              automaticallyImplyLeading: !started,
              actions: [
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
                          ? _stats(v)
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
                                              Expanded(child: LiveTrackMap(track: v.track, position: v.position)),
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
          Text(value, style: TextStyle(fontFamily: RwFonts.display, fontSize: small ? 22 : 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: RwColors.subtle, fontSize: 13)),
        ],
      );
}
