import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/records.dart';
import '../../domain/weather_correction.dart';
import '../../shared/widgets.dart';
import '../routes/route_map.dart';
import 'activity_providers.dart';
import 'share_run_screen.dart';

/// Eén run: tijden, weer, records, route en delen.
class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({super.key, required this.activityId});
  final String activityId;

  Future<void> _linkRoute(BuildContext context, WidgetRef ref, Activity a) async {
    final routes = await ref.read(routesProvider.future);
    if (!context.mounted) return;
    if (routes.isEmpty) {
      showMessage(context, 'Je hebt nog geen routes. Maak er een bij Routes.');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: RwColors.surface,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Op welke route liep je?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final r in routes)
              ListTile(
                leading: Icon(
                  (r.distanceMeters - a.distanceMeters).abs() < 600 ? Icons.check_circle_outline : Icons.route_outlined,
                  color: (r.distanceMeters - a.distanceMeters).abs() < 600 ? RwColors.good : RwColors.subtle,
                ),
                title: Text(r.name),
                subtitle: Text(Fmt.km(r.distanceMeters, decimals: 1)),
                selected: r.id == a.routeId,
                onTap: () => Navigator.pop(ctx, r.id),
              ),
            if (a.routeId != null)
              ListTile(
                leading: const Icon(Icons.link_off, color: RwColors.danger),
                title: const Text('Losmaken van route'),
                onTap: () => Navigator.pop(ctx, ''),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    try {
      await ref.read(repositoryProvider).setActivityRoute(a.id!, picked.isEmpty ? null : picked);
      ref.invalidate(activitiesProvider);
      if (context.mounted) showMessage(context, picked.isEmpty ? 'Run losgemaakt van de route.' : 'Run gekoppeld aan de route.');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(activitiesProvider).isLoading;
    final a = ref.watch(activityProvider(activityId));
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: loading ? const LoadingView() : const Center(child: Text('Deze run bestaat niet meer.')),
      );
    }
    final records = ref.watch(recordsProvider);
    final badges = records.badgesFor(a);
    final cost = weatherCost(a);
    final corrected = correctedSeconds(a);
    final routes = ref.watch(routesProvider).value ?? const <RunRoute>[];
    RunRoute? route;
    for (final r in routes) {
      if (r.id == a.routeId) route = r;
    }
    final all = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final history = a.routeId == null ? null : routeHistory(all, a.routeId!);

    return Scaffold(
      appBar: AppBar(
        title: Text(Fmt.date(a.startedAt)),
        actions: [
          IconButton(
            tooltip: 'Delen',
            icon: const Icon(Icons.ios_share),
            onPressed: () => openShareRun(context, a, route: route, badges: badges),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            '${Fmt.dateLong(a.startedAt)} · ${Fmt.time(a.startedAt)}',
            style: const TextStyle(color: RwColors.subtle),
          ),
          const SizedBox(height: 4),
          Text(
            Fmt.km(a.distanceMeters),
            style: const TextStyle(fontFamily: RwFonts.display, fontSize: 48, fontWeight: FontWeight.w800, height: 1.1),
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final b in badges) RecordBadge(b)]),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: StatTile(label: 'Tijd', value: Fmt.duration(a.movingTimeSeconds))),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Tempo', value: Fmt.pace(a.paceSecondsPerKm))),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: a.averageHeartRate != null ? 'Hartslag' : 'Hoogte',
                  value: a.averageHeartRate != null
                      ? '${a.averageHeartRate}'
                      : (a.elevationGainMeters == null ? '–' : '${a.elevationGainMeters!.round()} m'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RwCard(
            title: 'HET WEER TIJDENS JE RUN',
            child: a.temperatureCelsius == null && a.windSpeedKmh == null
                ? const Text('Geen weergegevens bij deze run.', style: TextStyle(color: RwColors.muted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          if (a.temperatureCelsius != null) Fmt.temp(a.temperatureCelsius),
                          if (a.feelsLikeCelsius != null) 'voelt als ${Fmt.temp(a.feelsLikeCelsius)}',
                          if (a.windSpeedKmh != null)
                            'wind ${Fmt.wind(a.windSpeedKmh)}${a.windDirectionDegrees == null ? '' : ' uit het ${Fmt.compass(a.windDirectionDegrees!)}'}',
                        ].join(' · '),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      if (cost.matters) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              Fmt.duration(corrected),
                              style: const TextStyle(
                                fontFamily: RwFonts.display,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: RwColors.accent,
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                'bij ideaal weer · ${Fmt.pace(corrected / (a.distanceMeters / 1000))}',
                                style: const TextStyle(color: RwColors.muted),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Het weer kostte je ongeveer ${Fmt.duration(cost.totalSeconds)} (${cost.explanation}). '
                          'Zo vergelijk je runs eerlijk, ook als het hard waaide.',
                          style: const TextStyle(color: RwColors.muted, height: 1.45),
                        ),
                      ] else
                        const Text(
                          'Prima loopweer: het weer had nauwelijks invloed op je tijd.',
                          style: TextStyle(color: RwColors.muted),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          RwCard(
            title: 'ROUTE',
            child: route == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Koppel deze run aan een route. Dan zie je je tijden op die route naast elkaar, eerlijk vergeleken voor het weer.',
                        style: TextStyle(color: RwColors.muted, height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: a.id == null ? null : () => _linkRoute(context, ref, a),
                        icon: const Icon(Icons.add_link),
                        label: const Text('Koppel aan route'),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(route.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                          TextButton(onPressed: () => _linkRoute(context, ref, a), child: const Text('Wijzig')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 180,
                        child: RouteMap(
                          polyline: route.polyline,
                          windSpeedKmh: a.windSpeedKmh,
                          windFromDegrees: a.windDirectionDegrees,
                          compact: true,
                          interactive: false,
                          showLayerToggle: false,
                          onExpand: () => context.go('/routes/${route!.id}'),
                        ),
                      ),
                      if (history != null && history.runs.length > 1) ...[
                        const SizedBox(height: 12),
                        Text(
                          _historyLine(a, history),
                          style: const TextStyle(color: RwColors.muted, height: 1.45),
                        ),
                      ],
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: () => context.go('/routes/${route!.id}'),
                        icon: const Icon(Icons.timeline),
                        label: const Text('Al je runs op deze route'),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => openShareRun(context, a, route: route, badges: badges),
            icon: const Icon(Icons.ios_share),
            label: const Text('Deel je run'),
          ),
          if (a.source == 'strava') ...[
            const SizedBox(height: 12),
            const Text('Gegevens via Strava', textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  static String _historyLine(Activity a, RouteHistory h) {
    final n = h.runs.length;
    final pos = h.runs.indexWhere((r) => sameRun(r.activity, a));
    final rank = ([...h.runs]..sort((x, y) => x.correctedSeconds.compareTo(y.correctedSeconds)))
            .indexWhere((r) => sameRun(r.activity, a)) +
        1;
    final which = pos < 0 ? '' : 'Je ${n - pos}e keer op deze route. ';
    return '$which'
        '${rank == 1 ? 'Gecorrigeerd voor het weer is dit je snelste keer ooit!' : 'Gecorrigeerd voor het weer staat deze run op plek $rank van $n.'}';
  }
}

/// Labeltje voor een record.
class RecordBadge extends StatelessWidget {
  const RecordBadge(this.label, {super.key, this.small = false});
  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final weather = label.startsWith('Weer');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 10, vertical: small ? 2 : 5),
      decoration: BoxDecoration(
        color: (weather ? RwColors.good : RwColors.accent).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: (weather ? RwColors.good : RwColors.accent).withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(weather ? Icons.air : Icons.emoji_events_outlined, size: small ? 12 : 15, color: weather ? RwColors.good : RwColors.accent),
          SizedBox(width: small ? 3 : 5),
          Text(
            label,
            style: TextStyle(
              fontSize: small ? 11 : 13,
              fontWeight: FontWeight.w700,
              color: weather ? RwColors.good : RwColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
