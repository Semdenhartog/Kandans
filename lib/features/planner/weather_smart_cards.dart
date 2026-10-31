import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/availability.dart';
import '../../domain/performance_model.dart';
import '../../domain/plan_swap.dart';
import '../../domain/start_time_scoring.dart';
import '../../domain/training_plan.dart';
import '../../shared/widgets.dart';

const _dayNames = ['maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'];
String _dayName(DateTime d) => _dayNames[d.weekday - 1];

TrainingType _typeFor(SessionKind k) => switch (k) {
      SessionKind.long => TrainingType.long,
      SessionKind.tempo || SessionKind.interval || SessionKind.race => TrainingType.quality,
      SessionKind.easy => TrainingType.easy,
    };

int _minutesFor(PlanSession s) => switch (s.kind) {
      SessionKind.long => ((s.distanceMeters ?? 15000) / 1000 * 6.2).round().clamp(60, 180),
      _ => 50,
    };

/// Weerslim schema: stelt voor een zware training naar een dag met duidelijk beter weer te schuiven.
class PlanSwapCard extends ConsumerStatefulWidget {
  const PlanSwapCard({super.key, required this.forecast, required this.profile, required this.availability});
  final Forecast forecast;
  final PerformanceInsights profile;
  final Availability availability;

  @override
  ConsumerState<PlanSwapCard> createState() => _PlanSwapCardState();
}

class _PlanSwapCardState extends ConsumerState<PlanSwapCard> {
  bool _busy = false;

  StartTimeScore? _bestOn(DateTime day, SessionKind kind, int minutes) {
    final now = DateTime.now();
    final start = day.isAfter(now) ? day : now;
    final end = DateTime(day.year, day.month, day.day, 21, 30);
    if (!end.isAfter(start)) return null;
    return StartTimePlanner(forecast: widget.forecast, profile: widget.profile, durationMinutes: minutes, availability: widget.availability)
        .bestPrecise(_typeFor(kind), from: start, horizon: end.difference(start), stepMinutes: 30);
  }

  String _why(StartTimeScore from, StartTimeScore to) {
    final a = from.weather, b = to.weather;
    final parts = <String>[
      if ((a.precipitationProbability ?? 0) - (b.precipitationProbability ?? 0) >= 25)
        trf('{a}% → {b}% regenkans', {'a': (a.precipitationProbability ?? 0).round(), 'b': (b.precipitationProbability ?? 0).round()}),
      if (a.windSpeed - b.windSpeed >= 10) trf('wind {a} → {b} km/u', {'a': a.windSpeed.round(), 'b': b.windSpeed.round()}),
      if (((a.feelsLike ?? a.temperature) - (b.feelsLike ?? b.temperature)).abs() >= 4)
        '${Fmt.temp(a.feelsLike ?? a.temperature)} → ${Fmt.temp(b.feelsLike ?? b.temperature)}',
    ];
    return parts.isEmpty ? trf('score {a} → {b}', {'a': from.score, 'b': to.score}) : parts.join(' · ');
  }

  Future<void> _apply(List<PlanSession> plan, SwapSuggestion s) async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).savePlan(applySwap(plan, s));
      ref.invalidate(planProvider);
      if (mounted) showMessage(context, trf('{titel} staat nu op {dag}.', {'titel': s.session.title, 'dag': _dayName(s.toDay)}));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(planProvider).value ?? const <PlanSession>[];
    if (plan.isEmpty) return const SizedBox.shrink();
    final cache = <String, StartTimeScore?>{};
    StartTimeScore? best(DateTime d, PlanSession s) =>
        cache.putIfAbsent('${d.toIso8601String()}-${s.kind.name}', () => _bestOn(d, s.kind, _minutesFor(s)));
    final byKind = {for (final s in plan) s.kind: s};
    final swaps = weatherSwaps(plan, (d, k) => best(d, byKind[k]!)?.score);
    if (swaps.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: RwCard(
        title: tr('WEERSLIM SCHEMA'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final s in swaps) ...[
            Text(
              trf('Verschuif je {titel} van {van} naar {naar}', {'titel': s.session.title.toLowerCase(), 'van': _dayName(s.session.date), 'naar': _dayName(s.toDay)}),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              [
                _why(best(s.session.date, s.session)!, best(s.toDay, s.session)!),
                if (s.displaced != null) trf('je {titel} gaat naar {dag}', {'titel': s.displaced!.title.toLowerCase(), 'dag': _dayName(s.session.date)}),
              ].join(' · '),
              style: TextStyle(color: RwColors.muted, height: 1.4),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _apply(plan, s),
                icon: const Icon(Icons.swap_horiz),
                label: Text(tr('Verschuiven')),
              ),
            ),
          ],
          Text(tr('Zware trainingen komen nooit op twee dagen achter elkaar.'), style: TextStyle(color: RwColors.subtle, fontSize: 12)),
        ]),
      ),
    );
  }
}
