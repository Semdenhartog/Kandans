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
            tooltip: 'Mijn records',
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => context.go('/runs/records'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/runs/new'),
        icon: const Icon(Icons.add),
        label: const Text('Run toevoegen'),
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
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final week = activities.where((a) => !a.startedAt.toLocal().isBefore(monday)).toList();
    final meters = week.fold<double>(0, (s, a) => s + a.distanceMeters);
    final seconds = week.fold<int>(0, (s, a) => s + a.movingTimeSeconds);
    return RwCard(
      title: 'DEZE WEEK',
      child: Row(
        children: [
          Expanded(child: StatTile(label: 'Afstand', value: Fmt.km(meters, decimals: 1))),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Runs', value: '${week.length}')),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Tijd', value: Fmt.duration(seconds))),
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
