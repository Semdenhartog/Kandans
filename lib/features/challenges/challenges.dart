import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/run_recorder_service.dart';
import '../../domain/challenges.dart';
import '../../domain/monthly_goal.dart' show suggestedGoalKm;
import '../../shared/widgets.dart';
import '../activities/badges_screen.dart' show badgeIcon;
import 'community_screen.dart' show openCommunity;

const challengeGold = Color(0xFFD9B45A);

/// Uitdagingen waar je aan meedoet (bewaard op de telefoon).
final joinedChallengesProvider = NotifierProvider<JoinedChallenges, List<Challenge>>(JoinedChallenges.new);

class JoinedChallenges extends Notifier<List<Challenge>> {
  static const _key = 'joined_challenges_v1';

  @override
  List<Challenge> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = jsonDecode(p.getString(_key) ?? '[]') as List;
      state = [for (final j in raw) Challenge.fromJson(j)].whereType<Challenge>().toList();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode([for (final c in state) c.toJson()]));
    } catch (_) {}
  }

  Future<void> join(Challenge c) async {
    if (state.any((x) => x.key == c.key)) return;
    state = [...state, c];
    await _save();
  }

  Future<void> leave(String key) async {
    state = [for (final c in state) if (c.key != key) c];
    await _save();
  }
}

/// Voortgang van al je uitdagingen, nieuwste eerst.
final challengeProgressProvider = Provider<List<ChallengeProgress>>((ref) {
  final joined = ref.watch(joinedChallengesProvider);
  final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
  return [for (final c in joined.reversed) challengeProgress(c, runs)];
});

/// Uitdagingen die nu lopen en nog niet gehaald zijn.
final activeChallengesProvider = Provider<List<ChallengeProgress>>((ref) {
  final now = DateTime.now();
  return [
    for (final p in ref.watch(challengeProgressProvider))
      if (!p.completed && p.challenge.isRunning(now) && p.stillPossible(now)) p,
  ];
});

/// Gehaalde uitdagingen: je medailles.
final challengeMedalsProvider = Provider<List<ChallengeProgress>>((ref) => [
      for (final p in ref.watch(challengeProgressProvider))
        if (p.completed) p,
    ]);

void openChallenges(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChallengesScreen()));

String _period(Challenge c) {
  final f = DateFormat('d MMM', 'nl');
  final last = c.end.subtract(const Duration(days: 1));
  return '${f.format(c.start)} – ${f.format(last)}';
}

String _value(ChallengeProgress p) {
  final c = p.challenge;
  String n(double v) => c.kind == ChallengeKind.hours || c.kind == ChallengeKind.distance || c.kind == ChallengeKind.longRun
      ? v.toStringAsFixed(v < 100 ? 1 : 0).replaceAll('.', ',')
      : v.round().toString();
  return '${n(p.value)} / ${n(c.goal)} ${c.unit}';
}

/// Overzicht: bezig, kiezen en gehaald.
class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final joined = ref.watch(joinedChallengesProvider);
    final progress = ref.watch(challengeProgressProvider);
    final active = [for (final p in progress) if (!p.completed && !now.isAfter(p.challenge.end)) p];
    final medals = ref.watch(challengeMedalsProvider);
    final offer = [
      for (final c in availableChallenges(now, suggestedMonthKm: suggestedGoalKm(runs, now).toDouble()))
        if (!joined.any((j) => j.key == c.key)) c,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Uitdagingen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          RwCard(
            onTap: () => openCommunity(context),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: challengeGold.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.groups_rounded, color: challengeGold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Samen', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  SizedBox(height: 2),
                  Text('Ranglijsten met andere lopers en vrienden. Alleen je bijnaam en totaal zijn zichtbaar.',
                      style: TextStyle(color: RwColors.muted, fontSize: 13, height: 1.35)),
                ]),
              ),
              Icon(Icons.chevron_right, color: RwColors.subtle),
            ]),
          ),
          const SizedBox(height: 18),
          if (active.isNotEmpty) ...[
            const _Heading('BEZIG'),
            for (final p in active) ...[
              _ActiveCard(progress: p, onLeave: () => _leave(context, ref, p.challenge)),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 12),
          ],
          const _Heading('KIES EEN UITDAGING'),
          if (offer.isEmpty)
            Text('Je doet al aan alle uitdagingen van nu mee. Volgende maand komen er nieuwe.',
                style: TextStyle(color: RwColors.muted))
          else
            for (final c in offer) ...[
              _OfferTile(challenge: c, onJoin: () => _join(context, ref, c)),
              const SizedBox(height: 10),
            ],
          if (medals.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _Heading('GEHAALD'),
            Wrap(spacing: 12, runSpacing: 12, children: [for (final m in medals) ChallengeMedal(progress: m)]),
          ],
        ],
      ),
    );
  }

  Future<void> _join(BuildContext context, WidgetRef ref, Challenge c) async {
    HapticFeedback.mediumImpact();
    await ref.read(joinedChallengesProvider.notifier).join(c);
    if (context.mounted) showMessage(context, 'Je doet mee aan "${c.title}". Succes!');
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, Challenge c) async {
    final ok = await confirmDialog(context, title: 'Stoppen met "${c.title}"?', message: 'Je voortgang verdwijnt uit je overzicht.', confirmLabel: 'Stoppen');
    if (ok) await ref.read(joinedChallengesProvider.notifier).leave(c.key);
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: RwText.overline),
      );
}

/// Ring met voortgang (goud als hij vol is).
class ChallengeRing extends StatelessWidget {
  const ChallengeRing({super.key, required this.fraction, required this.icon, this.size = 58});
  final double fraction;
  final String icon;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (_, f, _) => CustomPaint(
            painter: _RingPainter(f),
            child: Center(child: Icon(badgeIcon(icon), size: size * 0.38, color: f >= 1 ? challengeGold : RwColors.accent)),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.f);
  final double f;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = RwColors.bar);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * f,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = f >= 1 ? challengeGold : RwColors.accent,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.f != f;
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.progress, required this.onLeave});
  final ChallengeProgress progress;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final c = progress.challenge;
    final now = DateTime.now();
    final daysLeft = math.max(0, c.end.difference(DateTime(now.year, now.month, now.day)).inDays);
    final failed = !progress.stillPossible(now);
    return RwCard(
      child: Row(children: [
        ChallengeRing(fraction: progress.fraction, icon: c.icon),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 2),
            Text(_value(progress), style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              failed
                  ? 'Helaas, een dag gemist. Probeer een andere uitdaging.'
                  : c.isRunning(now)
                      ? '${remainingText(progress)} · nog $daysLeft ${daysLeft == 1 ? 'dag' : 'dagen'}'
                      : 'Begint ${DateFormat('d MMMM', 'nl').format(c.start)}',
              style: TextStyle(color: failed ? RwColors.warning : RwColors.muted, fontSize: 13),
            ),
          ]),
        ),
        IconButton(tooltip: 'Stoppen met deze uitdaging', onPressed: onLeave, icon: Icon(Icons.close, color: RwColors.subtle)),
      ]),
    );
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.challenge, required this.onJoin});
  final Challenge challenge;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) => RwCard(
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: RwColors.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: Icon(badgeIcon(challenge.icon), color: RwColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(challenge.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(challenge.description, style: TextStyle(color: RwColors.muted, fontSize: 13, height: 1.35)),
              const SizedBox(height: 2),
              Text(_period(challenge), style: TextStyle(color: RwColors.subtle, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: onJoin,
            // Het thema maakt knoppen volle breedte; in een rij moet dat smal.
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 16)),
            child: const Text('Doe mee'),
          ),
        ]),
      );
}

/// Gouden medaille voor een gehaalde uitdaging.
class ChallengeMedal extends StatelessWidget {
  const ChallengeMedal({super.key, required this.progress, this.size = 96});
  final ChallengeProgress progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = progress.challenge;
    return Semantics(
      label: 'Medaille: ${c.title}, gehaald op ${DateFormat('d MMMM yyyy', 'nl').format(progress.completedAt!.toLocal())}',
      child: SizedBox(
        width: size,
        child: Column(children: [
          Container(
            width: size * 0.72,
            height: size * 0.72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [Color(0xFFF3DC95), challengeGold, Color(0xFF8A6A22)], stops: [0, 0.6, 1]),
              boxShadow: [BoxShadow(color: challengeGold.withValues(alpha: 0.35), blurRadius: 16, spreadRadius: -4)],
            ),
            child: Icon(badgeIcon(c.icon), color: const Color(0xFF1C1405), size: size * 0.32),
          ),
          const SizedBox(height: 6),
          Text(c.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Kaart op Vandaag: je uitdagingen in het kort, of een uitnodiging om er een te kiezen.
class ChallengesCard extends ConsumerWidget {
  const ChallengesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeChallengesProvider);
    return RwCard(
      title: 'UITDAGINGEN',
      onTap: () => openChallenges(context),
      child: active.isEmpty
          ? Row(children: [
              Icon(Icons.emoji_events_outlined, color: RwColors.accent),
              SizedBox(width: 12),
              Expanded(child: Text('Kies een uitdaging voor deze maand en verdien een gouden medaille.', style: TextStyle(color: RwColors.muted, height: 1.4))),
              Icon(Icons.chevron_right, color: RwColors.subtle),
            ])
          : Column(children: [
              for (final p in active.take(2))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    ChallengeRing(fraction: p.fraction, icon: p.challenge.icon, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.challenge.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${_value(p)} · ${remainingText(p)}', style: TextStyle(color: RwColors.muted, fontSize: 13)),
                      ]),
                    ),
                  ]),
                ),
              if (active.length > 2)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('+ ${active.length - 2} meer', style: TextStyle(color: RwColors.subtle, fontSize: 12)),
                ),
            ]),
    );
  }
}

/// Tijdens de run: hoe deze run meetelt voor je eerste uitdaging. Zegt het hardop als je hem nu haalt.
class ChallengeLiveChip extends ConsumerStatefulWidget {
  const ChallengeLiveChip({super.key, required this.view});
  final RecorderView view;

  @override
  ConsumerState<ChallengeLiveChip> createState() => _ChallengeLiveChipState();
}

class _ChallengeLiveChipState extends ConsumerState<ChallengeLiveChip> {
  final _announced = <String>{};

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeChallengesProvider);
    final live = [
      for (final p in active)
        if (p.challenge.kind != ChallengeKind.weekly && p.challenge.kind != ChallengeKind.runs) p,
    ];
    if (live.isEmpty || widget.view.distance < 10) return const SizedBox.shrink();
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    // Deze run alvast meetellen.
    final now = Activity(
      startedAt: DateTime.now(),
      distanceMeters: widget.view.distance,
      movingTimeSeconds: widget.view.movingSeconds.round(),
    );
    final p = challengeProgress(live.first.challenge, [...runs, now]);
    final c = p.challenge;
    if (p.completed && _announced.add(c.key)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HapticFeedback.heavyImpact();
        RunRecorderService.instance.say('Uitdaging gehaald: ${c.title}. Goed bezig!');
      });
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        liveRegion: true,
        label: '${c.title}: ${remainingText(p)}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (p.completed ? challengeGold : RwColors.accent).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(p.completed ? Icons.emoji_events : Icons.flag_outlined, size: 18, color: p.completed ? challengeGold : RwColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${c.title} · ${remainingText(p)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              width: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: p.fraction,
                  minHeight: 5,
                  color: p.completed ? challengeGold : RwColors.accent,
                  backgroundColor: RwColors.bar,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
