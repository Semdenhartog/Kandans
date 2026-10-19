import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/location_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/geo.dart';
import '../../domain/performance_model.dart';
import '../../domain/start_time_scoring.dart';

/// Weersverwachting voor de komende 2 dagen op de weerlocatie.
final forecastProvider = FutureProvider<Forecast>((ref) async {
  final loc = await ref.watch(weatherLocationProvider.future);
  return ref.watch(weatherServiceProvider).forecast(loc.latitude, loc.longitude, days: 2);
});

/// Persoonlijk loopprofiel op basis van je runs (standaardwaarden als er te weinig zijn).
final insightsProvider = Provider<PerformanceInsights>((ref) {
  final activities = ref.watch(activitiesProvider);
  return activities.when(
    data: PerformanceInsights.compute,
    loading: () => PerformanceInsights.defaults,
    error: (_, _) => PerformanceInsights.defaults,
  );
});

/// Beste vertrekmoment per route (rustige duurloop), voor de routelijst.
/// Sleutel = route-id.
final routeBestProvider = FutureProvider<Map<String, StartTimeScore>>((ref) async {
  final routes = await ref.watch(routesProvider.future);
  final forecast = await ref.watch(forecastProvider.future);
  final profile = ref.watch(insightsProvider);
  if (forecast.hours.isEmpty) return const {};
  final out = <String, StartTimeScore>{};
  for (final r in routes) {
    if (r.id == null) continue;
    final best = StartTimePlanner(
      forecast: forecast,
      profile: profile,
      track: decodePolyline(r.polyline),
      durationMinutes: ((r.estimatedDurationSeconds ?? 2700) / 60).round(),
    ).best(TrainingType.easy, horizon: const Duration(hours: 24));
    if (best != null) out[r.id!] = best;
  }
  return out;
});
