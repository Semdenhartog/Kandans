import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/heart_rate_service.dart';
import '../../domain/training_load.dart';
import '../../domain/training_plan.dart';
import '../../shared/widgets.dart';
import '../activities/fitness_screen.dart';
import '../planner/training_plan_screen.dart';

/// "Jij vandaag": training uit je schema, hoe hersteld je bent en je vorm.
class TodayCard extends ConsumerWidget {
  const TodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final plan = ref.watch(planProvider).value ?? const <PlanSession>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final session = plan.where((s) => s.date == today).firstOrNull;
    final next = plan.where((s) => s.date.isAfter(today)).firstOrNull;
    final doneToday = session != null &&
        sessionDone(session, [for (final a in runs) (start: a.startedAt, meters: a.distanceMeters, seconds: a.movingTimeSeconds)]);

    final maxHr = HeartRateService.instance.maxHr.value;
    final threshold = estimateThresholdPace(runs);
    final recent = [
      for (final a in runs)
        if (now.difference(a.startedAt).inHours < 96)
          (end: a.startedAt.add(Duration(seconds: a.movingTimeSeconds)), load: runLoad(a, thresholdPace: threshold, maxHr: maxHr)),
    ];
    final recovery = recoveryHours(recent, now);
    final series = runs.isEmpty ? const <FitnessDay>[] : fitnessSeries(runs, now, days: 1, maxHr: maxHr);
    final form = series.isEmpty ? null : formAdvice(series.last);

    if (plan.isEmpty && runs.isEmpty) return const SizedBox.shrink();
    return RwCard(
      title: 'JIJ VANDAAG',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session != null) ...[
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: sessionColor(session.kind).withValues(alpha: 0.18),
                  child: doneToday
                      ? const Icon(Icons.check, color: RwColors.good)
                      : Icon(sessionIcon(session.kind), color: sessionColor(session.kind)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doneToday ? 'Gedaan: ${session.title}' : session.title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(session.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: RwColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
            if (!doneToday && session.kind != SessionKind.race) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => startSession(context, session),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start de training van vandaag'),
              ),
            ],
          ] else if (plan.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.hotel_outlined, color: RwColors.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    next == null ? 'Je schema is klaar.' : 'Rustdag. Volgende: ${next.title} (${Fmt.date(next.date)}).',
                    style: const TextStyle(color: RwColors.muted),
                  ),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openTrainingPlan(context),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Maak een gratis trainingsschema'),
              ),
            ),
          if (runs.isNotEmpty) ...[
            const Divider(height: 22),
            Row(
              children: [
                Expanded(
                  child: _Mini(
                    icon: Icons.battery_charging_full,
                    label: 'Herstel',
                    value: recovery < 1 ? 'Hersteld' : 'nog ${recovery.round()} u',
                    color: recovery < 1 ? RwColors.good : (recovery > 36 ? RwColors.warning : RwColors.muted),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => openFitness(context),
                    child: _Mini(icon: Icons.show_chart, label: 'Vorm', value: form?.title ?? '–', color: RwColors.accent),
                  ),
                ),
                if (plan.isNotEmpty)
                  Expanded(
                    child: InkWell(
                      onTap: () => openTrainingPlan(context),
                      child: const _Mini(icon: Icons.calendar_month_outlined, label: 'Schema', value: 'Bekijk', color: RwColors.muted),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: RwColors.subtle, fontSize: 11)),
                Text(value, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: color == RwColors.muted ? RwColors.text : color)),
              ],
            ),
          ),
        ],
      );
}
