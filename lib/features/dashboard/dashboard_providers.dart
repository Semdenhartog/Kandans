import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/location_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/dashboard_layout.dart';
import '../../domain/geo.dart';
import '../../domain/performance_model.dart';
import '../../domain/start_time_scoring.dart';

/// Weersverwachting voor de komende 4 dagen op de weerlocatie (ook voor de weekendvooruitblik).
final forecastProvider = FutureProvider<Forecast>((ref) async {
  final loc = await ref.watch(weatherLocationProvider.future);
  return ref.watch(weatherServiceProvider).forecast(loc.latitude, loc.longitude, days: 4);
});

/// Persoonlijk loopprofiel op basis van je runs (standaardwaarden als er te weinig zijn).
final insightsProvider = Provider<PerformanceInsights>((ref) {
  final activities = ref.watch(activitiesProvider);
  final rain = ref.watch(rainPreferenceProvider);
  final base = activities.when(
    data: PerformanceInsights.compute,
    loading: () => PerformanceInsights.defaults,
    error: (_, _) => PerformanceInsights.defaults,
  );
  return rain == RainPreference.normal ? base : base.withRainWeight(rain.weight);
});

/// Jouw keuze over lopen in de regen (Ik → Loopvoorkeuren), bewaard op de telefoon.
final rainPreferenceProvider = NotifierProvider<RainPreferenceNotifier, RainPreference>(RainPreferenceNotifier.new);

class RainPreferenceNotifier extends Notifier<RainPreference> {
  static const _key = 'rain_preference';

  @override
  RainPreference build() {
    _load();
    return RainPreference.normal;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final name = p.getString(_key);
      final match = RainPreference.values.where((r) => r.name == name);
      if (match.isNotEmpty) state = match.first;
    } catch (_) {}
  }

  Future<void> set(RainPreference value) async {
    state = value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, value.name);
    } catch (_) {}
  }
}

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

/// Volgorde en zichtbaarheid van de kaarten op Vandaag, onthouden op het toestel.
final dashLayoutProvider = NotifierProvider<DashLayoutNotifier, DashLayout>(DashLayoutNotifier.new);

class DashLayoutNotifier extends Notifier<DashLayout> {
  static const _key = 'dash_layout_v1';

  @override
  DashLayout build() {
    _load();
    return DashLayout.standard;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_key);
      if (s != null) state = DashLayout.decode(s);
    } catch (_) {}
  }

  void _save() => SharedPreferences.getInstance().then((p) => p.setString(_key, state.encode())).ignore();

  void move(int from, int to) {
    state = state.move(from, to);
    _save();
  }

  void toggle(DashCard c) {
    state = state.toggle(c);
    _save();
  }

  void reset() {
    state = DashLayout.standard;
    _save();
  }
}
