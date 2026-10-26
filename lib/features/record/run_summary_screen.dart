import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/supabase.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/badges.dart' as bd;
import '../../domain/best_efforts.dart';
import '../../domain/extras.dart';
import '../../domain/geo.dart';
import '../../domain/run_streams.dart';
import '../../shared/confetti.dart';
import '../../shared/widgets.dart';
import '../activities/badges_screen.dart';
import '../activities/share_run_screen.dart';
import '../activities/strength_screen.dart';
import '../profile/emergency_contact.dart';
import '../routes/route_map.dart';
import '../routes/route_poster_screen.dart';

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
    this.batteryUsedPct,
    this.laps = const [],
  });

  /// Handmatige rondes (knop tijdens het lopen).
  final List<({double seconds, double meters})> laps;

  /// Hoeveel procent accu de run kostte (null = onbekend, of de telefoon laadde).
  final int? batteryUsedPct;

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
            Text('${Fmt.dateLong(a.startedAt)} · ${Fmt.time(a.startedAt)}', style: TextStyle(color: RwColors.subtle)),
            const SizedBox(height: 16),
            // Kilometers tellen op tot je afstand.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: a.distanceMeters / 1000),
              duration: const Duration(milliseconds: 1400),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Text(
                v.toStringAsFixed(2).replaceAll('.', ','),
                style: TextStyle(
                  fontFamily: RwFonts.display, fontFeatures: rwTnum,
                  fontSize: 72,
                  fontWeight: FontWeight.w800,
                  color: RwColors.accent,
                  height: 1,
                ),
              ),
            ),
            Text('kilometer', style: TextStyle(color: RwColors.muted, fontSize: 16)),
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
            if (laps.length >= 2) ...[
              const SizedBox(height: 16),
              _LapsCard(laps: laps, indoor: a.distanceMeters <= 0),
            ],
            if (a.id != null) ...[
              const SizedBox(height: 16),
              _QuickFeel(activityId: a.id!),
            ],
            if (a.routeId != null) ...[
              const SizedBox(height: 12),
              _PosterTip(routeId: a.routeId!, record: records.isNotEmpty),
            ],
            const SizedBox(height: 12),
            const CooldownTip(),
            const _HomeSafe(),
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
                            Text(Fmt.pace(b.paceSecPerKm), style: TextStyle(color: RwColors.muted)),
                            if (_isRecord(b)) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.emoji_events, color: RwColors.accent, size: 18),
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
            const SizedBox(height: 12),
            _NewRoadsCard(activity: a),
            Builder(builder: (context) {
              final hr = streams?.heartRate;
              final maxHr = hr == null || hr.isEmpty ? null : hr.reduce((x, y) => x > y ? x : y);
              final tip = recoveryTip(
                movingSeconds: a.movingTimeSeconds,
                avgHeartRate: a.averageHeartRate?.toDouble(),
                // Zonder bekende maximale hartslag: je hoogste hartslag in deze run + 5 als schatting.
                maxHeartRate: maxHr == null ? null : maxHr + 5,
                temperature: a.temperatureCelsius,
                when: a.startedAt,
              );
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: RwCard(
                  title: 'HERSTEL',
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.restaurant_outlined, color: RwColors.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tip.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(tip.text, style: TextStyle(color: RwColors.muted, height: 1.45)),
                      ]),
                    ),
                  ]),
                ),
              );
            }),
            if (healthWritten) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.check_circle_outline, color: RwColors.good, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text('Ook opgeslagen in Health Connect (Samsung Health).', style: TextStyle(color: RwColors.muted))),
                ],
              ),
            ],
            if (batteryUsedPct != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.battery_std, color: RwColors.subtle, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      batteryUsedPct == 0 ? 'Deze run kostte minder dan 1% accu.' : 'Deze run kostte $batteryUsedPct% accu.',
                      style: TextStyle(color: RwColors.muted),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            // Voorproefje van je deelkaart: tik om te delen.
            if (a.hasTrack)
              RwCard(
                onTap: () => openShareRun(context, a, badges: [for (final r in records) 'Record ${r.label}', for (final b in badges) b.title]),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 72,
                      height: 90,
                      child: FittedBox(
                        child: IgnorePointer(
                          child: RunShareCard(
                            activity: a,
                            badges: [for (final r in records) 'Record ${r.label}', for (final b in badges) b.title],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Je deelkaart staat klaar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      SizedBox(height: 2),
                      Text('Voor Instagram, WhatsApp of je verhaal. Kies kaart, donker, oranje of sticker.',
                          style: TextStyle(color: RwColors.muted, height: 1.35)),
                    ]),
                  ),
                  Icon(Icons.ios_share, color: RwColors.accent),
                ]),
              ),
            if (a.hasTrack) const SizedBox(height: 12),
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
  static const _tags = ['Zware benen', 'Lekker ritme', 'Warm', 'Koud', 'Moe', 'Pijntje', 'Topdag', 'Met muziek'];
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
          // Snelle tags: één tik in plaats van typen.
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in _tags)
              FilterChip(
                label: Text(t),
                selected: _note.text.contains(t),
                visualDensity: VisualDensity.compact,
                onSelected: (on) {
                  HapticFeedback.selectionClick();
                  final parts = _note.text.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
                  on ? parts.add(t) : parts.remove(t);
                  setState(() => _note.text = parts.join(', '));
                  _repo.setActivityFeel(widget.activityId, feel: _feel, note: _note.text).then((_) => ref.invalidate(activitiesProvider)).ignore();
                },
              ),
          ]),
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
                  Text('Persoonlijk beste', style: TextStyle(fontFamily: RwFonts.display, fontSize: 18, fontWeight: FontWeight.w800, color: rwZandAvond.text)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            for (final (i, r) in records.indexed) ...[
              if (i > 0) Container(height: 1, color: _gold.withValues(alpha: 0.14)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  // Altijd donker-goud: tekst expliciet licht (anders onleesbaar als de app licht staat).
                  Expanded(child: Text(r.label, style: TextStyle(fontWeight: FontWeight.w600, color: rwZandAvond.text))),
                  Text(Fmt.duration(r.seconds),
                      style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFF2D892))),
                ]),
              ),
            ],
          ]),
        ),
      );
}


/// Eén tik: je noodcontact laten weten dat je weer veilig thuis bent (sms, of de app die je kiest).
class _HomeSafe extends StatefulWidget {
  const _HomeSafe();

  @override
  State<_HomeSafe> createState() => _HomeSafeState();
}

class _HomeSafeState extends State<_HomeSafe> {
  EmergencyContact? _c;

  @override
  void initState() {
    super.initState();
    EmergencyContact.load().then((c) {
      if (mounted) setState(() => _c = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return const SizedBox.shrink();
    final who = c.name.isEmpty ? 'je noodcontact' : c.name;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.home_outlined),
        label: Text('Laat $who weten dat je thuis bent'),
        onPressed: () async {
          HapticFeedback.selectionClick();
          final uri = Uri(scheme: 'sms', path: c.phone, queryParameters: {'body': 'Ik ben weer thuis van mijn run 👍'});
          try {
            if (!await launchUrl(uri) && context.mounted) showMessage(context, 'Kon je berichten-app niet openen.', error: true);
          } catch (_) {
            if (context.mounted) showMessage(context, 'Kon je berichten-app niet openen.', error: true);
          }
        },
      ),
    );
  }
}


/// Hoeveel van deze run over wegen ging waar je nog nooit liep. Met de badge-achtige titel "Ontdekker".
class _NewRoadsCard extends ConsumerWidget {
  const _NewRoadsCard({required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poly = activity.trackPolyline;
    if (poly == null || poly.isEmpty) return const SizedBox.shrink();
    final runs = ref.watch(activitiesProvider).value;
    if (runs == null) return const SizedBox.shrink();
    final previous = [
      for (final r in runs)
        if (r.id != activity.id && r.hasTrack && r.startedAt.isBefore(activity.startedAt)) decodePolyline(r.trackPolyline!),
    ];
    // Bij je eerste runs is alles nieuw: dan zeggen we nog niets.
    if (previous.length < 3) return const SizedBox.shrink();
    final m = newRoadMeters(decodePolyline(poly), previous);
    if (m < 200) return const SizedBox.shrink();
    final share = activity.distanceMeters <= 0 ? 0 : (m / activity.distanceMeters * 100).round().clamp(0, 100);
    return RwCard(
      title: m >= 1000 ? 'ONTDEKKER' : 'NIEUWE WEGEN',
      child: Row(children: [
        Icon(Icons.explore, color: RwColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Je liep ${Fmt.km(m, decimals: 1)} over wegen waar je nog nooit eerder liep ($share% van deze run).'
            '${m >= 1000 ? ' Echte ontdekker!' : ''}',
            style: const TextStyle(height: 1.4),
          ),
        ),
      ]),
    );
  }
}

/// Je eigen rondes, met de snelste in goud.
class _LapsCard extends StatelessWidget {
  const _LapsCard({required this.laps, required this.indoor});
  final List<({double seconds, double meters})> laps;
  final bool indoor;

  @override
  Widget build(BuildContext context) {
    final fastest = laps.map((l) => l.seconds).reduce((a, b) => a < b ? a : b);
    return RwCard(
      title: 'RONDES · ${laps.length}',
      child: Column(children: [
        for (final (i, l) in laps.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 34, child: Text('${i + 1}', style: TextStyle(color: RwColors.subtle))),
              Expanded(
                child: Text(Fmt.duration(l.seconds.round()),
                    style: TextStyle(
                      fontFamily: RwFonts.display,
                      fontFeatures: rwTnum,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: l.seconds == fastest ? RwColors.accent : RwColors.text,
                    )),
              ),
              if (!indoor && l.meters > 50) ...[
                Text(Fmt.km(l.meters, decimals: 2), style: TextStyle(color: RwColors.muted)),
                const SizedBox(width: 14),
                SizedBox(
                  width: 64,
                  child: Text('${Fmt.pace(l.seconds / (l.meters / 1000))}/km',
                      textAlign: TextAlign.right, style: TextStyle(color: RwColors.muted, fontFeatures: rwTnum)),
                ),
              ],
            ]),
          ),
      ]),
    );
  }
}

/// Na een run op een vaste route: "zet hem aan de muur" (poster). Alleen bij de 1e, 10e, 25e… keer of een record,
/// zodat het geen reclame na elke run wordt.
class _PosterTip extends ConsumerWidget {
  const _PosterTip({required this.routeId, required this.record});
  final String routeId;
  final bool record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = (ref.watch(routesProvider).value ?? const <RunRoute>[]).where((r) => r.id == routeId).firstOrNull;
    if (route == null || route.polyline.isEmpty) return const SizedBox.shrink();
    final runs = (ref.watch(activitiesProvider).value ?? const <Activity>[]).where((x) => x.routeId == routeId).toList();
    final n = runs.length;
    const milestones = {1, 10, 25, 50, 100};
    if (!record && !milestones.contains(n)) return const SizedBox.shrink();
    final fastest = runs.isEmpty ? null : runs.map((x) => x.movingTimeSeconds).reduce((x, y) => x < y ? x : y);
    final why = record ? 'Nieuw record op ${route.name}.' : (n == 1 ? 'Je eerste keer op ${route.name}.' : 'Al $n keer ${route.name} gelopen.');
    return RwCard(
      onTap: () => openRoutePoster(context, route, fastestSeconds: fastest, timesRun: n),
      child: Row(children: [
        Icon(Icons.image_outlined, color: RwColors.accent),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Zet hem aan de muur', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('$why Maak er een poster van, met je snelste tijd erop.',
                style: TextStyle(color: RwColors.muted, fontSize: 13, height: 1.35)),
          ]),
        ),
        Icon(Icons.chevron_right, color: RwColors.subtle),
      ]),
    );
  }
}
