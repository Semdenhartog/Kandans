import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/training_plan.dart';
import '../../shared/widgets.dart';
import '../planner/training_plan_screen.dart' show startSession;
import 'record_run_screen.dart';

/// Je "vaste rondje": favoriet, of anders de route waar je het vaakst op liep.
RunRoute? favoriteRoute(List<Activity> runs, List<RunRoute> routes) {
  if (routes.isEmpty) return null;
  final fav = routes.where((r) => r.isFavorite).firstOrNull;
  if (fav != null) return fav;
  final count = <String, int>{};
  for (final a in runs) {
    if (a.routeId != null) count[a.routeId!] = (count[a.routeId!] ?? 0) + 1;
  }
  if (count.isEmpty) return null;
  final top = count.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  return routes.where((r) => r.id == top).firstOrNull;
}

/// De training uit je schema voor vandaag (of null).
PlanSession? todaySession(List<PlanSession> plan) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return plan.where((s) => s.date == today).firstOrNull;
}

/// Lang drukken op "Start run": in één tik de juiste soort run.
Future<void> showQuickStart(BuildContext context, WidgetRef ref) async {
  HapticFeedback.heavyImpact();
  final runs = ref.read(activitiesProvider).value ?? const <Activity>[];
  final routes = ref.read(routesProvider).value ?? const <RunRoute>[];
  final session = todaySession(ref.read(planProvider).value ?? const <PlanSession>[]);
  final route = favoriteRoute(runs, routes);
  final pick = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(padding: EdgeInsets.fromLTRB(8, 0, 8, 8), child: Text('Snel starten', style: RwText.title)),
          if (session != null)
            ListTile(
              leading: const TileIcon(Icons.event_available_outlined, color: RwColors.accent),
              title: Text(session.title),
              subtitle: const Text('Je training van vandaag, met de juiste tempo\'s'),
              onTap: () => Navigator.pop(c, 'session'),
            ),
          if (route != null)
            ListTile(
              leading: const TileIcon(Icons.route_outlined, color: RwColors.accent),
              title: Text('Je vaste rondje: ${route.name}'),
              subtitle: Text('${Fmt.km(route.distanceMeters, decimals: 1)} · met route en tegen je record'),
              onTap: () => Navigator.pop(c, 'route'),
            ),
          ListTile(
            leading: const TileIcon(Icons.terrain_outlined, color: RwColors.good),
            title: const Text('Buiten lopen'),
            subtitle: const Text('Gewoon gaan, met GPS'),
            onTap: () => Navigator.pop(c, 'out'),
          ),
          ListTile(
            leading: const TileIcon(Icons.fitness_center, color: Color(0xFF5AA9FF)),
            title: const Text('Loopband'),
            subtitle: const Text('Zonder GPS, op tijd'),
            onTap: () => Navigator.pop(c, 'in'),
          ),
        ]),
      ),
    ),
  );
  if (!context.mounted || pick == null) return;
  switch (pick) {
    case 'session':
      startSession(context, session!);
    case 'route':
      openRecorder(context, route: route);
    case 'out':
      openRecorder(context, indoor: false);
    case 'in':
      openRecorder(context, indoor: true);
  }
}
