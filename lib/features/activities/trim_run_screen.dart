import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/best_efforts.dart';
import '../../domain/geo.dart';
import '../../domain/run_streams.dart';
import '../../domain/run_trim.dart';
import '../../shared/widgets.dart';
import '../routes/route_map.dart';

/// Opent het bijsnijden van een eigen opgenomen run.
Future<void> openTrimRun(BuildContext context, Activity a) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TrimRunScreen(activity: a)),
    );

/// Begin en eind van een run wegknippen, bijvoorbeeld als je vergat te stoppen.
class TrimRunScreen extends ConsumerStatefulWidget {
  const TrimRunScreen({super.key, required this.activity});
  final Activity activity;

  @override
  ConsumerState<TrimRunScreen> createState() => _TrimRunScreenState();
}

class _TrimRunScreenState extends ConsumerState<TrimRunScreen> {
  Map<String, dynamic>? _streams;
  bool _loaded = false;
  List<double> _d = const [];
  RangeValues? _range;
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(repositoryProvider).activityStreams(widget.activity.id!);
      final d = (s?['d'] as List?)?.map((x) => (x as num).toDouble()).toList() ?? const <double>[];
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _streams = s;
        _d = d;
        if (d.length >= 2) _range = RangeValues(0, d.last);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  TrimmedRun? get _result {
    final s = _streams, r = _range;
    if (s == null || r == null || _d.length < 2) return null;
    return trimRun(s, indexAtDistance(_d, r.start), indexAtDistance(_d, r.end));
  }

  Future<void> _save() async {
    final r = _result;
    final a = widget.activity;
    if (r == null || a.id == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Run bijsnijden?',
      message: 'Je run wordt ${Fmt.km(r.distanceMeters)} in ${Fmt.duration(r.movingSeconds)}. '
          'Het weggeknipte stuk kun je daarna niet terughalen.',
      confirmLabel: 'Bijsnijden',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      final parsed = RunStreams.fromJson(r.streams);
      final efforts = parsed == null ? const <BestEffort>[] : bestEfforts(parsed);
      final repo = ref.read(repositoryProvider);
      await repo.saveTrimmedActivity(
        a.id!,
        startedAt: a.startedAt.add(Duration(milliseconds: (r.startOffsetSeconds * 1000).round())),
        distanceMeters: r.distanceMeters,
        movingSeconds: r.movingSeconds,
        averageHeartRate: r.averageHeartRate ?? a.averageHeartRate,
        trackPolyline: r.track.length >= 2 ? encodePolyline(r.track) : '',
        streams: r.streams,
        bestEfforts: bestEffortsToJson(efforts),
      );
      // Hoogtemeters opnieuw bepalen voor het overgebleven stuk (op de achtergrond).
      repo.improveElevation(a.id!, r.streams).then((_) => ref.invalidate(activitiesProvider)).ignore();
      ref.invalidate(activitiesProvider);
      if (!mounted) return;
      showMessage(context, 'Run bijgesneden.');
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
    final range = _range;
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Run bijsnijden')),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Het verloop van deze run kon niet worden geladen.\n${friendlyError(_error!)}',
                    textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted)),
              ),
            )
          : !_loaded
              ? const LoadingView(cards: 2)
              : range == null
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Deze run heeft geen verloop per seconde, dus bijsnijden kan niet.',
                            textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted)),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          'Vergeten te stoppen, of te laat gestart? Schuif het begin en het eind naar waar je echt liep.',
                          style: TextStyle(color: RwColors.muted, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        if (r != null && r.track.length >= 2)
                          SizedBox(
                            height: 220,
                            child: RouteMap(
                              polyline: encodePolyline(r.track),
                              compact: true,
                              interactive: false,
                              showLayerToggle: false,
                              showLegend: false,
                            ),
                          ),
                        const SizedBox(height: 16),
                        RwCard(
                          title: 'BEGIN EN EIND',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Semantics(
                                label: 'Begin en eind van de run',
                                child: RangeSlider(
                                  values: range,
                                  min: 0,
                                  max: _d.last,
                                  labels: RangeLabels(Fmt.km(range.start), Fmt.km(range.end)),
                                  onChanged: _saving
                                      ? null
                                      : (v) {
                                          if (v.end - v.start < 100) return; // minstens 100 m overhouden
                                          setState(() => _range = v);
                                        },
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Begin ${Fmt.km(range.start)}', style: TextStyle(color: RwColors.muted)),
                                  Text('Eind ${Fmt.km(range.end)}', style: TextStyle(color: RwColors.muted)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (r != null)
                          RwCard(
                            title: 'NA HET BIJSNIJDEN',
                            child: Wrap(
                              spacing: 24,
                              runSpacing: 12,
                              children: [
                                _Stat(label: 'Afstand', value: Fmt.km(r.distanceMeters), was: Fmt.km(widget.activity.distanceMeters)),
                                _Stat(label: 'Tijd', value: Fmt.duration(r.movingSeconds), was: Fmt.duration(widget.activity.movingTimeSeconds)),
                                if (r.distanceMeters > 0)
                                  _Stat(
                                    label: 'Tempo',
                                    value: '${Fmt.pace(r.movingSeconds / (r.distanceMeters / 1000))} /km',
                                    was: '${Fmt.pace(widget.activity.paceSecondsPerKm)} /km',
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _saving || r == null ? null : _save,
                          icon: _saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.content_cut),
                          label: const Text('Bijsnijden en opslaan'),
                        ),
                      ],
                    ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.was});
  final String label;
  final String value;
  final String was;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: RwColors.muted, fontSize: 12)),
        Text(value,
            style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 22, fontWeight: FontWeight.w800)),
        Text('was $was', style: TextStyle(color: RwColors.subtle, fontSize: 12)),
      ],
    );
  }
}
