import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/supabase.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/badges.dart' as bd;
import '../../domain/best_efforts.dart';
import '../../domain/run_streams.dart';
import '../../shared/confetti.dart';
import '../../shared/widgets.dart';
import '../activities/badges_screen.dart';
import '../activities/share_run_screen.dart';
import '../activities/strength_screen.dart';
import '../routes/route_map.dart';

/// Direct na het opslaan: je run in één oogopslag, met snelste stukken en records.
class RunSummaryScreen extends StatelessWidget {
  const RunSummaryScreen({
    super.key,
    required this.activity,
    this.streams,
    this.efforts = const [],
    this.previousBest = const {},
    this.healthWritten = false,
    this.badges = const [],
  });

  /// Badges die je met deze run voor het eerst hebt verdiend.
  final List<bd.Badge> badges;

  final Activity activity;
  final RunStreams? streams;
  final List<BestEffort> efforts;

  /// Snelste tijden van vóór deze run, per afstand in meters.
  final Map<int, ({double seconds, String activityId})> previousBest;
  final bool healthWritten;

  bool _isRecord(BestEffort b) {
    if (previousBest.isEmpty) return false;
    final prev = previousBest[b.meters.round()];
    return prev == null || b.seconds + 0.5 < prev.seconds;
  }

  void _close(BuildContext context) {
    Navigator.of(context).pop();
    if (activity.id != null) GoRouter.of(context).go('/runs/${activity.id}');
  }

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final records = efforts.where(_isRecord).toList();
    final splits = streams == null ? const <KmSplit>[] : splitsOf(streams!);
    final ex = extremes(splits);
    final hour = a.startedAt.toLocal().hour;
    final greeting = hour < 12 ? 'Lekker begonnen aan je dag!' : (hour < 18 ? 'Goed gelopen!' : 'Mooi afgesloten!');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Run opgeslagen'),
          actions: [IconButton(tooltip: 'Sluiten', onPressed: () => _close(context), icon: const Icon(Icons.close))],
        ),
        body: Stack(children: [
          ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Text(greeting, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 28, fontWeight: FontWeight.w800)),
            Text('${Fmt.dateLong(a.startedAt)} · ${Fmt.time(a.startedAt)}', style: const TextStyle(color: RwColors.subtle)),
            const SizedBox(height: 16),
            // Kilometers tellen op tot je afstand.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: a.distanceMeters / 1000),
              duration: const Duration(milliseconds: 1400),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Text(
                v.toStringAsFixed(2).replaceAll('.', ','),
                style: const TextStyle(
                  fontFamily: RwFonts.display, fontFeatures: rwTnum,
                  fontSize: 72,
                  fontWeight: FontWeight.w800,
                  color: RwColors.accent,
                  height: 1,
                ),
              ),
            ),
            const Text('kilometer', style: TextStyle(color: RwColors.muted, fontSize: 16)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: StatTile(label: 'Tijd', value: Fmt.duration(a.movingTimeSeconds))),
                const SizedBox(width: 8),
                Expanded(child: StatTile(label: 'Tempo', value: Fmt.pace(a.paceSecondsPerKm).replaceAll(' /km', ''))),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(label: 'Hartslag', value: a.averageHeartRate == null ? '–' : '${a.averageHeartRate}'),
                ),
              ],
            ),
            if (records.isNotEmpty) ...[
              const SizedBox(height: 16),
              _RecordPlaque(records: [for (final r in records) (label: r.label, seconds: r.seconds)]),
            ],
            if (a.id != null) ...[
              const SizedBox(height: 16),
              _QuickFeel(activityId: a.id!),
            ],
            const SizedBox(height: 12),
            const CooldownTip(),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 16),
              NewBadgesBanner(badges: badges),
            ],
            if (a.hasTrack) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: RouteMap(
                  polyline: a.trackPolyline!,
                  windSpeedKmh: a.windSpeedKmh,
                  windFromDegrees: a.windDirectionDegrees,
                  compact: true,
                  showLegend: false,
                  animateIn: true,
                ),
              ),
            ],
            if (efforts.isNotEmpty) ...[
              const SizedBox(height: 16),
              RwCard(
                title: 'SNELSTE STUKKEN',
                child: Column(
                  children: [
                    for (final b in efforts)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            SizedBox(width: 120, child: Text(b.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                            Expanded(child: Text(Fmt.duration(b.seconds), style: const TextStyle(fontWeight: FontWeight.w700))),
                            Text(Fmt.pace(b.paceSecPerKm), style: const TextStyle(color: RwColors.muted)),
                            if (_isRecord(b)) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.emoji_events, color: RwColors.accent, size: 18),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (splits.isNotEmpty) ...[
              const SizedBox(height: 12),
              RwCard(
                title: 'PER KILOMETER',
                child: Column(
                  children: [
                    for (final sp in splits)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 48,
                              child: Text(sp.partial ? (sp.meters / 1000).toStringAsFixed(2).replaceAll('.', ',') : '${sp.index}',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, c) {
                                  final fastest = ex.fastest?.paceSecPerKm ?? sp.paceSecPerKm;
                                  final f = sp.paceSecPerKm <= 0 ? 0.0 : (fastest / sp.paceSecPerKm).clamp(0.2, 1.0);
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      height: 10,
                                      width: c.maxWidth * f,
                                      decoration: BoxDecoration(
                                        color: identical(sp, ex.fastest) ? RwColors.accent : RwColors.bar,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 52,
                              child: Text(Fmt.pace(sp.paceSecPerKm).replaceAll(' /km', ''),
                                  textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (healthWritten) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: RwColors.good, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text('Ook opgeslagen in Health Connect (Samsung Health).', style: TextStyle(color: RwColors.muted))),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => openShareRun(context, a, badges: [for (final r in records) 'Record ${r.label}', for (final b in badges) b.title]),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Delen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => _close(context),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Bekijk run'),
                  ),
                ),
              ],
            ),
          ],
        ),
          if (records.isNotEmpty || badges.isNotEmpty) const Positioned.fill(child: IgnorePointer(child: Confetti())),
        ]),
      ),
    );
  }
}

/// Meteen na je run: hoe voelde het? (zoals Strava's "ervaren inspanning"). Helpt de coach en je klaar-score.
class _QuickFeel extends ConsumerStatefulWidget {
  const _QuickFeel({required this.activityId});
  final String activityId;

  @override
  ConsumerState<_QuickFeel> createState() => _QuickFeelState();
}

class _QuickFeelState extends ConsumerState<_QuickFeel> {
  int? _feel;
  final _note = TextEditingController();
  late final RunWiseRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(repositoryProvider);
  }

  @override
  void dispose() {
    // Notitie bewaren als je weggaat zonder op Enter te drukken.
    if (_note.text.trim().isNotEmpty) {
      _repo.setActivityFeel(widget.activityId, feel: _feel, note: _note.text).ignore();
    }
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(int f) async {
    HapticFeedback.selectionClick();
    setState(() => _feel = f);
    try {
      await ref.read(repositoryProvider).setActivityFeel(widget.activityId, feel: f, note: _note.text);
      ref.invalidate(activitiesProvider);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const options = [(1, 'Zwaar', Icons.sentiment_dissatisfied), (2, 'Oké', Icons.sentiment_neutral), (3, 'Top', Icons.sentiment_very_satisfied)];
    return RwCard(
      title: 'HOE VOELDE HET?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (v, label, icon) in options)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _save(v),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _feel == v ? RwColors.accent : RwColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Icon(icon, size: 30, color: _feel == v ? RwColors.accentDark : RwColors.muted),
                            const SizedBox(height: 4),
                            Text(label,
                                style: TextStyle(fontWeight: FontWeight.w700, color: _feel == v ? RwColors.accentDark : RwColors.text)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Notitie (optioneel), bijv. zware benen', isDense: true),
            onSubmitted: (_) => _feel == null ? null : _save(_feel!),
          ),
        ],
      ),
    );
  }
}


/// Gouden plaquette met je nieuwe records, elk op een eigen regel met de tijd ernaast.
class _RecordPlaque extends StatelessWidget {
  const _RecordPlaque({required this.records});
  final List<({String label, num seconds})> records;

  static const _gold = Color(0xFFD9B45A);
  static const _goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF6E3A1), Color(0xFFD9B45A), Color(0xFF9C7A2A), Color(0xFFE9CF7A)],
  );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(1.4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: _goldGradient,
          boxShadow: [BoxShadow(color: _gold.withValues(alpha: 0.25), blurRadius: 26, spreadRadius: -4)],
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF221A0B), Color(0xFF110D06)],
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _goldGradient),
                child: const Icon(Icons.emoji_events, color: Color(0xFF1C1405), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(records.length == 1 ? 'NIEUW RECORD' : '${records.length} NIEUWE RECORDS',
                      style: const TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.8)),
                  const Text('Persoonlijk beste', style: TextStyle(fontFamily: RwFonts.display, fontSize: 18, fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            for (final (i, r) in records.indexed) ...[
              if (i > 0) Container(height: 1, color: _gold.withValues(alpha: 0.14)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Expanded(child: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(Fmt.duration(r.seconds),
                      style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFF2D892))),
                ]),
              ),
            ],
          ]),
        ),
      );
}
