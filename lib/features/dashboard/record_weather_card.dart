import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/best_efforts.dart';
import '../../domain/record_weather.dart';
import '../../domain/start_time_scoring.dart';
import '../../shared/calendar.dart';
import '../../shared/widgets.dart';

/// Recordweer: verschijnt alleen als er de komende 2 dagen ideaal weer is voor een snelle run.
class RecordWeatherCard extends ConsumerWidget {
  const RecordWeatherCard({super.key, required this.best});
  final StartTimeScore best;

  /// Het beste moment met recordweer in de komende 2 dagen, of null.
  static StartTimeScore? bestMoment(StartTimePlanner planner) {
    final ideal = [
      for (final s in planner.scoreAll(TrainingType.quality, horizon: const Duration(hours: 48)))
        if (isRecordWeather(s.weather)) s,
    ];
    return ideal.isEmpty ? null : ideal.reduce((a, b) => b.score > a.score ? b : a);
  }

  static String _day(DateTime t) {
    final now = DateTime.now();
    final diff = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    return diff == 0 ? tr('Vandaag') : (diff == 1 ? tr('Morgen') : Fmt.date(t));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final overall = bestOverall([
      for (final a in runs)
        if (a.id != null && a.bestEfforts != null) (id: a.id!, efforts: a.bestEfforts!),
    ]);
    final target = recordTarget({for (final e in overall.entries) e.key: e.value.seconds});
    final w = best.weather;
    final weather = '${Fmt.temp(w.feelsLike ?? w.temperature)} ${tr('gevoel')}, ${tr('wind')} ${Fmt.wind(w.windSpeed)}, ${tr('droog')}';
    return RwCard(
      title: tr('RECORDWEER'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.bolt, color: RwColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${_day(best.start)} ${Fmt.time(best.start)}: $weather',
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          target == null
              ? tr('Koel, windstil en droog: ideaal voor een tempotraining of een snelle 5 km.')
              : trf('Koel, windstil en droog: zo goed wordt het zelden. Val je {afstand}-record ({tijd}) aan!',
                  {'afstand': target.label, 'tijd': Fmt.duration(target.seconds)}),
          style: TextStyle(color: RwColors.muted, height: 1.4),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => addToCalendar(
              context,
              title: target == null ? tr('Snelle run (Kadans)') : trf('Recordpoging {afstand} (Kadans)', {'afstand': target.label}),
              start: best.start,
              minutes: 45,
              details: weather,
            ),
            icon: const Icon(Icons.event_available_outlined),
            label: Text(tr('In je agenda')),
          ),
        ),
      ]),
    );
  }
}
