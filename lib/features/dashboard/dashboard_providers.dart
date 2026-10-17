import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/location_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/performance_model.dart';

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
