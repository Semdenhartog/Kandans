import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/sync_service.dart';
import '../../shared/widgets.dart';
import '../../domain/weekly_load.dart';
import '../record/record_run_screen.dart';
import 'activity_detail_screen.dart';
import 'activity_providers.dart';

class ActivitiesScreen extends ConsumerWidget {
  const ActivitiesScreen({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref, Activity a) async {
    final ok = await confirmDialog(
      context,
      title: 'Run verwijderen?',
      message: 'Deze run van ${Fmt.date(a.startedAt)} wordt definitief verwijderd.',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteActivity(a.id!);
      ref.invalidate(activitiesProvider);
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activitiesProvider);
    final records = ref.watch(recordsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mijn runs'),
        actions: [
          IconButton(
            tooltip: 'Run met de hand toevoegen',
            icon: const Icon(Icons.edit_note),
            onPressed: () => context.go('/runs/new'),
          ),
          IconButton(
            tooltip: 'Mijn records',
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => context.go('/runs/records'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'start-run',
        onPressed: () => openRecorder(context),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start run'),
      ),
      body: activities.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(activitiesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.directions_run,
              title: 'Nog geen runs',
              message: 'Voeg je runs toe of koppel je horloge of Strava (tabblad Ik). Na 8 runs leert RunWise bij welk weer jij het snelst loopt.',
              actionLabel: 'Eerste run toevoegen',
              onAction: () => context.go('/runs/new'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              try {
                await ref.read(syncServiceProvider).syncAll(force: true);
              } catch (e) {
                if (context.mounted) showMessage(context, friendlyError(e), error: true);
              }
              ref.invalidate(activitiesProvider);
              await ref.read(activitiesProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: list.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i == 0) return _WeekSummary(activities: list);
                final a = list[i - 1];
                return _ActivityTile(
                  activity: a,
                  badges: records.badgesFor(a),
                  onTap: a.id == null ? null : () => context.go('/runs/${a.id}'),
                  onDelete: () => _delete(context, ref, a),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _WeekSummary extends StatelessWidget {
  const _WeekSummary({required this.activities});
  final List<Activity> activities;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weeks = weeklyTotals(activities, now);
    final week = weeks.last;
    final check = loadCheck(activities, now);
    final streak = weekStreak(activities, now);
    final maxKm = weeks.map((w) => w.km).fold<double>(0, (a, b) => a > b ? a : b);
    final msg = check.message;
    return RwCard(
      title: 'DEZE WEEK',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: StatTile(label: 'Afstand', value: Fmt.km(week.km * 1000, decimals: 1))),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Runs', value: '${week.runs}')),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Tijd', value: Fmt.duration(week.seconds))),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(
            label: 'Kilometers per week, laatste 8 weken: ${weeks.map((w) => w.km.round()).join(', ')}.',
            excludeSemantics: true,
            child: SizedBox(
              height: 92,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, w) in weeks.indexed)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(w.km < 0.5 ? '' : '${w.km.round()}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: i == weeks.length - 1 ? RwColors.accent : RwColors.subtle,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Container(
                              height: maxKm <= 0 ? 3 : 3 + 54 * (w.km / maxKm),
                              decoration: BoxDecoration(
                                color: i == weeks.length - 1 ? RwColors.accent : RwColors.bar,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(i == weeks.length - 1 ? 'nu' : '${w.start.day}/${w.start.month}',
                                style: const TextStyle(fontSize: 10, color: RwColors.subtle)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (streak >= 2) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.local_fire_department, color: RwColors.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('$streak weken op rij gelopen${week.runs == 0 ? '. Loop deze week om je reeks te houden.' : '.'}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
          if (msg != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(check.tooFast ? Icons.warning_amber_rounded : Icons.info_outline,
                    color: check.tooFast ? RwColors.warning : RwColors.muted, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(msg, style: const TextStyle(color: RwColors.muted, height: 1.4))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity, required this.badges, required this.onTap, required this.onDelete});
  final Activity activity;
  final List<String> badges;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final weather = [
      if (a.temperatureCelsius != null) Fmt.temp(a.temperatureCelsius),
      if (a.windSpeedKmh != null) Fmt.wind(a.windSpeedKmh),
    ].join(' · ');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: RwColors.surfaceHigh,
          child: Icon(
            switch (a.source) {
              'strava' => Icons.sync,
              'health_connect' => Icons.watch_outlined,
              'runwise' => Icons.gps_fixed,
              _ => Icons.directions_run,
            },
            color: RwColors.accent,
          ),
        ),
        onTap: onTap,
        title: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${Fmt.km(a.distanceMeters)} · ${Fmt.pace(a.paceSecondsPerKm)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final b in badges.take(2)) RecordBadge(b, small: true),
          ],
        ),
        subtitle: Text(
          '${Fmt.date(a.startedAt)} ${Fmt.time(a.startedAt)} · ${Fmt.duration(a.movingTimeSeconds)}'
          '${weather.isEmpty ? '' : '\n$weather'}',
          style: const TextStyle(color: RwColors.subtle),
        ),
        isThreeLine: weather.isNotEmpty,
        trailing: IconButton(
          tooltip: 'Verwijderen',
          icon: const Icon(Icons.delete_outline, color: RwColors.subtle),
          onPressed: onDelete,
        ),
      ),
    );
  }
}
