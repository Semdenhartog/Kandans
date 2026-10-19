import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/monthly_goal.dart';
import '../../shared/widgets.dart';

/// Doel voor deze maand (null = nog niet gekozen).
final monthlyGoalProvider = FutureProvider<double?>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(repositoryProvider).monthlyGoal(DateTime.now());
});

String _monthName(DateTime d) => DateFormat('MMMM', 'nl_NL').format(d);

/// Maanduitdaging op Vandaag: kies een doel en zie hoe je ervoor staat.
class MonthChallengeCard extends ConsumerWidget {
  const MonthChallengeCard({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, double? current, int suggested) async {
    final picked = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: RwColors.surface,
      builder: (_) => _GoalSheet(current: current, suggested: suggested),
    );
    if (picked == null) return;
    try {
      final repo = ref.read(repositoryProvider);
      if (picked <= 0) {
        await repo.deleteMonthlyGoal(DateTime.now());
      } else {
        await repo.setMonthlyGoal(DateTime.now(), picked);
      }
      ref.invalidate(monthlyGoalProvider);
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final month = _monthName(now);
    final goal = ref.watch(monthlyGoalProvider);
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final done = kmInMonth(runs, now);
    final suggested = suggestedGoalKm(runs, now);

    if (goal.isLoading && !goal.hasValue) return const SizedBox.shrink();
    final target = goal.value;

    if (target == null) {
      return RwCard(
        title: 'MAANDUITDAGING · ${month.toUpperCase()}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Hoeveel kilometer wil je in $month lopen? Op basis van je vorige maanden stellen we $suggested km voor.',
              style: const TextStyle(color: RwColors.muted, height: 1.45),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _edit(context, ref, null, suggested),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Kies je doel'),
            ),
          ],
        ),
      );
    }

    final p = GoalProgress(targetKm: target, doneKm: done, now: now);
    return RwCard(
      title: 'MAANDUITDAGING · ${month.toUpperCase()}',
      onTap: () => _edit(context, ref, target, suggested),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: CustomPaint(
              painter: _RingPainter(fraction: p.fraction, expected: p.expectedKm / target, achieved: p.achieved),
              child: Center(
                child: p.achieved
                    ? const Icon(Icons.emoji_events, color: RwColors.accent, size: 36)
                    : Text(
                        '${(p.fraction * 100).round()}%',
                        style: const TextStyle(fontFamily: RwFonts.display, fontSize: 22, fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: done.toStringAsFixed(done < 100 ? 1 : 0).replaceAll('.', ','),
                      style: const TextStyle(fontFamily: RwFonts.display, fontSize: 28, fontWeight: FontWeight.w800, color: RwColors.accent),
                    ),
                    TextSpan(
                      text: ' / ${target.round()} km',
                      style: const TextStyle(fontFamily: RwFonts.display, fontSize: 18, fontWeight: FontWeight.w800, color: RwColors.muted),
                    ),
                  ]),
                ),
                const SizedBox(height: 4),
                Text(p.statusText, style: const TextStyle(height: 1.4)),
                const SizedBox(height: 4),
                const Text('Tik om je doel aan te passen', style: TextStyle(color: RwColors.subtle, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.expected, required this.achieved});
  final double fraction;
  final double expected;
  final bool achieved;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 6;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()
      ..color = RwColors.bar
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10);
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * fraction,
        false,
        Paint()
          ..shader = const SweepGradient(
            colors: [RwColors.accentLight, RwColors.accent, RwColors.accentDeep],
            transform: GradientRotation(-math.pi / 2),
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
    }
    // Streepje: waar je volgens schema nu zou moeten zijn.
    if (!achieved && expected > 0 && expected < 1) {
      final a = -math.pi / 2 + 2 * math.pi * expected;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r - 8), c + dir * (r + 8), Paint()
        ..color = RwColors.text
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction || old.expected != expected || old.achieved != achieved;
}

class _GoalSheet extends StatefulWidget {
  const _GoalSheet({required this.current, required this.suggested});
  final double? current;
  final int suggested;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late double _km = (widget.current ?? widget.suggested.toDouble()).clamp(10, 400).toDouble();

  @override
  Widget build(BuildContext context) {
    final options = {widget.suggested, 25, 50, 75, 100, 150, 200}.toList()..sort();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Je doel voor ${_monthName(DateTime.now())}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFamily: RwFonts.display)),
            const SizedBox(height: 16),
            Center(
              child: Text(
                '${_km.round()} km',
                style: const TextStyle(fontFamily: RwFonts.display, fontSize: 44, fontWeight: FontWeight.w800, color: RwColors.accent),
              ),
            ),
            Slider(
              value: _km,
              min: 10,
              max: 400,
              divisions: 78,
              label: '${_km.round()} km',
              onChanged: (v) => setState(() => _km = v),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in options)
                  ChoiceChip(
                    label: Text(o == widget.suggested ? '$o km (voorstel)' : '$o km'),
                    selected: _km.round() == o,
                    onSelected: (_) => setState(() => _km = o.toDouble()),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => Navigator.pop(context, _km.roundToDouble()), child: const Text('Opslaan')),
            if (widget.current != null)
              TextButton(onPressed: () => Navigator.pop(context, 0.0), child: const Text('Geen doel deze maand')),
          ],
        ),
      ),
    );
  }
}
