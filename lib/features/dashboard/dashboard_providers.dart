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

/// Wat je vandaag wilt lopen: soort training, route en duur.
class TrainingPlan {
  const TrainingPlan({this.type = TrainingType.easy, this.routeId, this.durationMinutes = 45});

  final TrainingType type;
  final String? routeId;
  final int durationMinutes;

  TrainingPlan copyWith({TrainingType? type, String? routeId, bool clearRoute = false, int? durationMinutes}) =>
      TrainingPlan(
        type: type ?? this.type,
        routeId: clearRoute ? null : (routeId ?? this.routeId),
        durationMinutes: durationMinutes ?? this.durationMinutes,
      );
}

class TrainingPlanNotifier extends Notifier<TrainingPlan> {
  @override
  TrainingPlan build() => const TrainingPlan();

  void setType(TrainingType t) => state = state.copyWith(type: t);
  void setDuration(int minutes) => state = state.copyWith(durationMinutes: minutes);
  void setRoute(RunRoute? r) {
    if (r == null) {
      state = state.copyWith(clearRoute: true);
    } else {
      state = state.copyWith(
        routeId: r.id,
        durationMinutes: r.estimatedDurationSeconds == null
            ? state.durationMinutes
            : (r.estimatedDurationSeconds! / 60).round().clamp(10, 300),
      );
    }
  }
}

final trainingPlanProvider = NotifierProvider<TrainingPlanNotifier, TrainingPlan>(TrainingPlanNotifier.new);

/// Jouw gebruikelijke tempo (mediaan van je laatste 10 runs), standaard 6:00/km.
final typicalPaceProvider = Provider<double>((ref) {
  final runs = ref.watch(activitiesProvider).when(
        data: (a) => a,
        loading: () => const <Activity>[],
        error: (_, _) => const <Activity>[],
      );
  final paces = runs.take(10).map((a) => a.paceSecondsPerKm).where((p) => p > 150 && p < 1200).toList()
    ..sort();
  if (paces.isEmpty) return 360;
  return paces[paces.length ~/ 2];
});

/// Tempo per soort training, afgeleid van je gebruikelijke tempo.
double paceFor(TrainingType type, double typical) => switch (type) {
      TrainingType.easy => typical + 15,
      TrainingType.quality => typical - 30,
      TrainingType.long => typical + 25,
      TrainingType.recovery => typical + 45,
    };

/// Beste score per route voor de gekozen training, gesorteerd van hoog naar laag.
class RouteScore {
  RouteScore(this.route, this.best);
  final RunRoute route;
  final StartTimeScore? best;
  int get score => best?.score ?? 0;
}

final routeScoresProvider = FutureProvider<List<RouteScore>>((ref) async {
  final routes = await ref.watch(routesProvider.future);
  final forecast = await ref.watch(forecastProvider.future);
  final profile = ref.watch(insightsProvider);
  final type = ref.watch(trainingPlanProvider.select((p) => p.type));
  if (forecast.hours.isEmpty) return routes.map((r) => RouteScore(r, null)).toList();
  final result = routes.map((r) {
    final planner = StartTimePlanner(
      forecast: forecast,
      profile: profile,
      track: decodePolyline(r.polyline),
      durationMinutes: ((r.estimatedDurationSeconds ?? 3600) / 60).round(),
    );
    return RouteScore(r, planner.best(type));
  }).toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  return result;
});
