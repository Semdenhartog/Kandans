import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/best_efforts.dart';
import '../../domain/geo.dart';
import '../../domain/gps_spikes.dart';
import '../../domain/run_streams.dart';
import '../../shared/widgets.dart';
import '../routes/route_map.dart';

String _okKey(String id) => 'gps_spikes_ok_$id';

/// Heeft de loper gezegd dat de GPS van deze run goed is? Dan vragen we het niet nog eens.
final _gpsOkProvider = FutureProvider.family<bool, String>((ref, id) async {
  try {
    return (await SharedPreferences.getInstance()).getBool(_okKey(id)) ?? false;
  } catch (_) {
    return false;
  }
});

/// Sprongen in deze run (leeg als er geen verloop is of als het een Strava-run is).
final gpsSpikesProvider = FutureProvider.family<List<GpsSpike>, String>((ref, id) async {
  final s = await ref.watch(activityStreamsProvider(id).future);
  return s == null ? const [] : findGpsSpikes(s);
});

/// Kaartje onder een run als de GPS ergens een onmogelijke sprong maakte.
/// Niet bij runs uit Strava: die gegevens horen bij Strava en passen we niet aan.
class GpsSpikeCard extends ConsumerWidget {
  const GpsSpikeCard({super.key, required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = activity;
    if (a.id == null || a.viaStrava) return const SizedBox.shrink();
    final spikes = ref.watch(gpsSpikesProvider(a.id!)).value ?? const <GpsSpike>[];
    final ok = ref.watch(_gpsOkProvider(a.id!)).value ?? true;
    if (spikes.isEmpty || ok) return const SizedBox.shrink();
    final extra = spikes.fold<double>(0, (s, x) => s + x.extraMeters);
    final first = spikes.first;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: RwCard(
        title: 'GPS-SPRONG GEVONDEN',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            spikes.length == 1
                ? 'Rond ${Fmt.km(first.atMeters, decimals: 1)} sprong je GPS even weg. '
                    'Daardoor telt deze run ongeveer ${_m(extra)} te veel.'
                : 'Op ${spikes.length} plekken sprong je GPS even weg. '
                    'Daardoor telt deze run ongeveer ${_m(extra)} te veel.',
            style: const TextStyle(height: 1.4),
          ),
          const SizedBox(height: 4),
          Text('Jij kiest: herstellen of zo laten. We passen niets aan zonder het te vragen.',
              style: TextStyle(color: RwColors.subtle, fontSize: 12.5)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  try {
                    await (await SharedPreferences.getInstance()).setBool(_okKey(a.id!), true);
                  } catch (_) {}
                  ref.invalidate(_gpsOkProvider(a.id!));
                },
                child: const Text('Klopt wel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => GpsSpikeScreen(activity: a)),
                ),
                child: const Text('Bekijken'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

String _m(double meters) => meters >= 1000 ? Fmt.km(meters, decimals: 2) : '${meters.round()} m';

/// Laat zien waar de GPS sprong en laat de loper per sprong kiezen.
class GpsSpikeScreen extends ConsumerStatefulWidget {
  const GpsSpikeScreen({super.key, required this.activity});
  final Activity activity;

  @override
  ConsumerState<GpsSpikeScreen> createState() => _GpsSpikeScreenState();
}

class _GpsSpikeScreenState extends ConsumerState<GpsSpikeScreen> {
  Set<int>? _chosen; // indexen in de lijst met sprongen
  final _highlight = ValueNotifier<double?>(null);
  bool _saving = false;

  @override
  void dispose() {
    _highlight.dispose();
    super.dispose();
  }

  Future<void> _save(Map<String, dynamic> streams, List<GpsSpike> spikes) async {
    final a = widget.activity;
    final pick = [for (final i in _chosen ?? <int>{}) spikes[i]];
    final r = removeGpsSpikes(streams, pick);
    if (r == null || a.id == null) return;
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      final parsed = RunStreams.fromJson(r.streams);
      final efforts = parsed == null ? const <BestEffort>[] : bestEfforts(parsed);
      final repo = ref.read(repositoryProvider);
      await repo.saveTrimmedActivity(
        a.id!,
        startedAt: a.startedAt,
        distanceMeters: r.distanceMeters,
        movingSeconds: r.movingSeconds,
        averageHeartRate: r.averageHeartRate ?? a.averageHeartRate,
        trackPolyline: r.track.length >= 2 ? encodePolyline(r.track) : (a.trackPolyline ?? ''),
        streams: r.streams,
        bestEfforts: bestEffortsToJson(efforts),
      );
      repo.improveElevation(a.id!, r.streams).then((_) => ref.invalidate(activitiesProvider)).ignore();
      ref.invalidate(activitiesProvider);
      ref.invalidate(activityStreamsProvider(a.id!));
      if (!mounted) return;
      showMessage(context, 'Hersteld: je run is nu ${Fmt.km(r.distanceMeters)}.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final streams = ref.watch(activityStreamsProvider(a.id!)).value;
    final spikes = streams == null ? const <GpsSpike>[] : findGpsSpikes(streams);
    _chosen ??= {for (var i = 0; i < spikes.length; i++) i};
    final total = (streams?['d'] as List?)?.isNotEmpty == true ? ((streams!['d'] as List).last as num).toDouble() : a.distanceMeters;
    final pick = [for (final i in _chosen!) if (i < spikes.length) spikes[i]];
    final preview = streams == null || pick.isEmpty ? null : removeGpsSpikes(streams, pick);
    return Scaffold(
      appBar: AppBar(title: const Text('GPS-sprongen')),
      body: streams == null
          ? const LoadingView(cards: 2)
          : spikes.isEmpty
              ? Center(child: Text('Geen GPS-sprongen (meer) in deze run.', style: TextStyle(color: RwColors.muted)))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text(
                    'Op deze plekken ging je GPS sneller dan iemand kan lopen. Kies welke je wilt herstellen: '
                    'dat stuk telt dan als een rechte lijn op je gewone tempo. Je tijd blijft gelijk.',
                    style: TextStyle(color: RwColors.muted, height: 1.4),
                  ),
                  if (a.hasTrack) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 240,
                      child: RouteMap(
                        polyline: a.trackPolyline!,
                        compact: true,
                        showLayerToggle: false,
                        showLegend: false,
                        highlightFraction: _highlight,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  for (final (i, s) in spikes.indexed)
                    Card(
                      child: CheckboxListTile(
                        value: _chosen!.contains(i),
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => v == true ? _chosen!.add(i) : _chosen!.remove(i)),
                        secondary: IconButton(
                          tooltip: 'Op de kaart',
                          icon: const Icon(Icons.place_outlined),
                          onPressed: () => _highlight.value = total <= 0 ? null : (s.atMeters / total).clamp(0.0, 1.0),
                        ),
                        title: Text('Bij ${Fmt.km(s.atMeters, decimals: 1)}: ${_m(s.extraMeters)} te veel'),
                        subtitle: Text('GPS ging even ${s.peakKmh >= 199 ? 'meer dan 199' : s.peakKmh.round()} km/u'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  RwCard(
                    title: 'NA HET HERSTELLEN',
                    child: Text(
                      preview == null
                          ? 'Niets gekozen: je run blijft ${Fmt.km(a.distanceMeters)}.'
                          : '${Fmt.km(a.distanceMeters)} → ${Fmt.km(preview.distanceMeters)} · '
                              'tempo ${Fmt.pace(preview.movingSeconds / (preview.distanceMeters / 1000))}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving || preview == null ? null : () => _save(streams, spikes),
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_fix_high),
                    label: const Text('Herstellen en opslaan'),
                  ),
                ]),
    );
  }
}
