import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/location_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/best_route_now.dart';
import '../../domain/geo.dart';
import '../../shared/widgets.dart';
import '../record/record_run_screen.dart';

/// Welke van je eigen routes nu de minste last van de wind geeft.
final bestRouteNowProvider = FutureProvider<BestRouteNow?>((ref) async {
  final routes = await ref.watch(routesProvider.future);
  if (routes.length < 2) return null;
  final here = await ref.watch(weatherLocationProvider.future);
  final f = await ref.watch(weatherServiceProvider).forecast(here.latitude, here.longitude, days: 1);
  final w = f.at(DateTime.now());
  if (w == null) return null;
  return bestRouteForWind(
    [
      for (final r in routes)
        if (r.id != null && r.polyline.isNotEmpty) RouteCandidate(id: r.id!, name: r.name, track: decodePolyline(r.polyline)),
    ],
    windSpeed: w.windSpeed,
    windFromDegrees: w.windDirection,
    near: LatLng(here.latitude, here.longitude),
  );
});

class BestRouteNowCard extends ConsumerWidget {
  const BestRouteNowCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final best = ref.watch(bestRouteNowProvider).value;
    if (best == null) return const SizedBox.shrink();
    final routes = ref.watch(routesProvider).value ?? const [];
    final route = routes.where((r) => r.id == best.route.id).firstOrNull;
    return RwCard(
      title: 'BESTE ROUTE MET DEZE WIND',
      onTap: () => context.go('/routes/${best.route.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.air, color: RwColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(best.route.name,
                    style: const TextStyle(fontFamily: RwFonts.display, fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              if (route != null) Text(Fmt.km(route.distanceMeters, decimals: 1), style: TextStyle(color: RwColors.muted)),
            ],
          ),
          const SizedBox(height: 6),
          Text(best.summary, style: TextStyle(color: RwColors.muted, height: 1.4)),
          Text('Vergeleken met ${best.compared - 1} andere routes in de buurt.',
              style: TextStyle(color: RwColors.subtle, fontSize: 12)),
          if (route != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => openRecorder(context, route: route),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Loop deze route'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
