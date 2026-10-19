import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/weather_service.dart';
import '../../domain/geo.dart';
import '../../domain/route_direction.dart';
import '../../domain/start_time_scoring.dart';
import '../../shared/widgets.dart';
import 'route_shape.dart';

/// Huidig weer bij de start van een route.
final _routeWeatherProvider = FutureProvider.family<HourWeather?, String>((ref, routeId) async {
  final route = await ref.watch(routeDetailProvider(routeId).future);
  final f = await ref
      .watch(weatherServiceProvider)
      .forecast(route.startLatitude, route.startLongitude, days: 1);
  return f.at(DateTime.now());
});

class RouteDetailScreen extends ConsumerWidget {
  const RouteDetailScreen({super.key, required this.routeId});
  final String routeId;

  Future<void> _toggleFavorite(BuildContext context, WidgetRef ref, RunRoute r) async {
    try {
      await ref.read(repositoryProvider).setFavorite(r.id!, !r.isFavorite);
      ref.invalidate(routeDetailProvider(routeId));
      ref.invalidate(routesProvider);
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, RunRoute r) async {
    final ok = await confirmDialog(
      context,
      title: 'Route verwijderen?',
      message: '"${r.name}" wordt definitief verwijderd. Runs op deze route blijven bewaard.',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteRoute(r.id!);
      ref.invalidate(routesProvider);
      if (context.mounted) context.go('/routes');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeDetailProvider(routeId));
    final weather = ref.watch(_routeWeatherProvider(routeId));

    return route.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(routeDetailProvider(routeId)),
        ),
      ),
      data: (r) {
        final w = weather.when(data: (w) => w, loading: () => null, error: (_, _) => null);
        final track = decodePolyline(r.polyline);
        final segments = trackSegments(track);
        final rw = (w != null && w.windDirection != null)
            ? routeWind(segments, w.windSpeed, w.windDirection!)
            : null;

        final advice = w == null ? null : adviseDirection(track, w.windSpeed, w.windDirection);

        return Scaffold(
          appBar: AppBar(
            title: Text(r.name, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: r.isFavorite ? 'Geen favoriet meer' : 'Favoriet maken',
                icon: Icon(r.isFavorite ? Icons.star : Icons.star_border,
                    color: r.isFavorite ? RwColors.accent : null),
                onPressed: () => _toggleFavorite(context, ref, r),
              ),
              IconButton(
                tooltip: 'Verwijderen',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, ref, r),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              AspectRatio(
                aspectRatio: 1.3,
                child: RouteShape(
                  polyline: r.polyline,
                  windFromDegrees: w?.windDirection,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '● start   ● finish   ➝ windrichting nu',
                style: TextStyle(color: RwColors.subtle, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: StatTile(label: 'Afstand', value: Fmt.km(r.distanceMeters))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Hoogtemeters',
                      value: r.elevationGainMeters == null ? '–' : '${r.elevationGainMeters!.round()} m',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Verwacht',
                      value: r.estimatedDurationSeconds == null
                          ? '–'
                          : Fmt.duration(r.estimatedDurationSeconds!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              RwCard(
                title: 'WIND OP DEZE ROUTE, NU',
                child: w == null
                    ? const Text('Weer wordt geladen…', style: TextStyle(color: RwColors.muted))
                    : Text(
                        rw == null
                            ? 'Wind ${Fmt.wind(w.windSpeed)}.'
                            : 'Wind ${Fmt.wind(w.windSpeed)} uit het ${Fmt.compass(w.windDirection!)}. '
                                'Gemiddeld ${rw.headwindAvg.round()} km/u tegenwind en '
                                '${rw.tailwindAvg.round()} km/u rugwind. '
                                '${rw.secondHalfHead - rw.firstHalfHead > 4 ? 'De terugweg is het zwaarst.' : rw.firstHalfHead - rw.secondHalfHead > 4 ? 'De heenweg is het zwaarst.' : ''}',
                        style: const TextStyle(height: 1.5),
                      ),
              ),
              if (advice != null) ...[
                const SizedBox(height: 12),
                RwCard(
                  title: 'LOOPRICHTING, NU',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(advice.bestLabel == 'linksom' ? Icons.rotate_left : Icons.rotate_right,
                          color: RwColors.accent),
                      const SizedBox(width: 10),
                      Expanded(child: Text(advice.text, style: const TextStyle(height: 1.5))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (r.points.length > 1)
                RwCard(
                  title: 'PER KILOMETER',
                  child: Column(
                    children: [
                      for (final p in r.points)
                        _KmRow(point: p, weather: w),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _KmRow extends StatelessWidget {
  const _KmRow({required this.point, required this.weather});
  final RoutePoint point;
  final HourWeather? weather;

  @override
  Widget build(BuildContext context) {
    final b = point.bearing;
    String windText = '';
    Color color = RwColors.subtle;
    final w = weather;
    if (b != null && w != null && w.windDirection != null) {
      final comp = w.windSpeed * math.cos((w.windDirection! - b) * math.pi / 180);
      if (comp > 3) {
        windText = 'tegenwind ${comp.round()}';
        color = RwColors.warning;
      } else if (comp < -3) {
        windText = 'rugwind ${(-comp).round()}';
        color = RwColors.good;
      } else {
        windText = 'zijwind';
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text('km ${point.kmMarker.toStringAsFixed(1).replaceAll('.', ',')}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 70,
            child: Text(b == null ? '–' : 'naar ${Fmt.compass(b)}',
                style: const TextStyle(color: RwColors.muted)),
          ),
          Expanded(
            child: Text(
              point.elevation == null ? '' : '${point.elevation!.round()} m',
              style: const TextStyle(color: RwColors.subtle),
            ),
          ),
          Text(windText, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
