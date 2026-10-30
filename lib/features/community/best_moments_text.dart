import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../domain/availability.dart';
import '../../domain/performance_model.dart';
import '../../domain/start_time_scoring.dart';
import '../dashboard/dashboard_providers.dart';
import '../planner/availability_provider.dart';

/// Je drie beste loopmomenten van de komende dagen (één per dag), voor een afspreek-oproep.
List<StartTimeScore> bestMomentsAhead(Forecast f, PerformanceInsights profile, Availability availability, {int days = 4, int minutes = 60}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final out = <StartTimeScore>[];
  for (var i = 0; i < days; i++) {
    final d = today.add(Duration(days: i));
    final start = d.isAfter(now) ? d : now.add(const Duration(minutes: 30));
    final end = DateTime(d.year, d.month, d.day, 21, 30);
    if (!end.isAfter(start)) continue;
    final best = StartTimePlanner(forecast: f, profile: profile, durationMinutes: minutes, availability: availability)
        .bestPrecise(TrainingType.easy, from: start, horizon: end.difference(start), stepMinutes: 15);
    if (best != null) out.add(best);
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out.take(3).toList()..sort((a, b) => a.start.compareTo(b.start));
}

const _days = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];

/// "Mijn beste momenten volgens Kadans: za 09:15 (droog, 8 °C), zo 10:30 (droog, 9 °C). Wie sluit aan?"
Future<String?> bestMomentsText(WidgetRef ref) async {
  try {
    final f = await ref.read(weekForecastProvider.future);
    final availability = await ref.read(availabilityProvider.future);
    final best = bestMomentsAhead(f, ref.read(insightsProvider), availability);
    if (best.isEmpty) return null;
    String one(StartTimeScore s) {
      final w = s.weather;
      final dry = (w.precipitationProbability ?? 0) < 30 ? 'droog, ' : '';
      return '${_days[s.start.weekday - 1]} ${Fmt.time(s.start)} ($dry${Fmt.temp(w.feelsLike ?? w.temperature)})';
    }

    return 'Mijn beste loopmomenten volgens Kadans: ${best.map(one).join(', ')}. Wie sluit aan?';
  } catch (_) {
    return null;
  }
}
