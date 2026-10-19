import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/run_recorder_service.dart';
import '../../data/services/sync_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/geo.dart';
import '../../domain/run_recorder.dart';
import '../../domain/shoes.dart';
import '../../shared/widgets.dart';

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
  String? _error;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final name = ref.read(profileProvider).value?.displayName ?? '';
      await _svc.start(voice: _voice, shareLive: _share, name: name == 'loper' ? '' : name);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RecorderView>(
      valueListenable: _svc.view,
      builder: (context, v, _) {
        final started = v.status != RecorderStatus.idle && v.status != RecorderStatus.finished;
        return PopScope(
          canPop: !started,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) showMessage(context, 'Je run loopt nog. Stop eerst, of ga met de thuisknop naar een andere app.');
          },
          child: Scaffold(
            appBar: AppBar(title: const Text('Run opnemen')),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusBar(view: v, error: _error),
                    const Spacer(),
                    Semantics(
                      label: 'Afstand ${Fmt.km(v.distance, decimals: 2)}',
                      child: Text(
                        (v.distance / 1000).toStringAsFixed(2).replaceAll('.', ','),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: RwFonts.display, fontSize: 96, fontWeight: FontWeight.w800, height: 1),
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
                    if (!started) ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _voice,
                        onChanged: (x) => setState(() => _voice = x),
                        title: const Text('Stemcoach'),
                        subtitle: const Text('Elke kilometer je tijd en tempo, ook met je scherm uit'),
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
                    ] else if (_saving)
                      const Center(child: CircularProgressIndicator())
                    else
                      Row(
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
                      ),
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
  const _Big({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value, style: const TextStyle(fontFamily: RwFonts.display, fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: RwColors.subtle, fontSize: 13)),
        ],
      );
}
