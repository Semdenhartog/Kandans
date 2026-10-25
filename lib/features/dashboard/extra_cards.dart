import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/location_service.dart';
import '../../domain/extras.dart';
import '../../domain/start_time_scoring.dart';
import '../../shared/widgets.dart';
import '../record/record_run_screen.dart';
import 'dashboard_providers.dart';

/// "Nog een keer": je laatste route met één tik opnieuw lopen.
class AgainCard extends ConsumerWidget {
  const AgainCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final routes = ref.watch(routesProvider).value ?? const <RunRoute>[];
    final last = lastRouteAgain(runs, routes);
    if (last == null) return const SizedBox.shrink();
    final days = calendarDaysBetween(last.run.startedAt, DateTime.now());
    return RwCard(
      title: 'NOG EEN KEER',
      onTap: () => context.go('/routes/${last.route.id}'),
      child: Row(children: [
        Icon(Icons.replay, color: RwColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(last.route.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: RwFonts.display, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              '${Fmt.km(last.route.distanceMeters, decimals: 1)} · ${daysAgoWords(days)} in ${Fmt.duration(last.run.movingTimeSeconds)}'
              '${last.times > 1 ? ' · ${last.times}× gelopen' : ''}',
              style: TextStyle(color: RwColors.muted),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Loop ${last.route.name} nog een keer',
          onPressed: () => openRecorder(context, route: last.route),
          icon: const Icon(Icons.play_arrow),
        ),
      ]),
    );
  }
}

/// "Op deze dag": wat je een of meer jaar geleden liep.
class OnThisDayCard extends ConsumerWidget {
  const OnThisDayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final list = onThisDay(runs, DateTime.now());
    if (list.isEmpty) return const SizedBox.shrink();
    final first = list.first;
    final a = first.run;
    final when = first.yearsAgo == 1 ? 'Precies een jaar geleden' : 'Precies ${first.yearsAgo} jaar geleden';
    return RwCard(
      title: 'OP DEZE DAG',
      onTap: a.id == null ? null : () => context.go('/runs/${a.id}'),
      child: Row(children: [
        Icon(Icons.history, color: RwColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '$when liep je ${Fmt.km(a.distanceMeters, decimals: 1)} in ${Fmt.duration(a.movingTimeSeconds)}'
            '${a.temperatureCelsius == null ? '' : ' bij ${Fmt.temp(a.temperatureCelsius)}'}.'
            '${list.length > 1 ? ' En nog ${list.length - 1}× eerder op deze datum.' : ''}',
            style: const TextStyle(height: 1.4),
          ),
        ),
        if (a.id != null) Icon(Icons.chevron_right, color: RwColors.muted),
      ]),
    );
  }
}

/// Gouden uur met de loopscore op dat moment.
final _goldenProvider = FutureProvider<({GoldenHour hour, StartTimeScore? score})?>((ref) async {
  final loc = await ref.watch(weatherLocationProvider.future);
  final g = nextGoldenHour(DateTime.now(), loc.latitude, loc.longitude);
  if (g == null) return null;
  StartTimeScore? score;
  try {
    final f = await ref.watch(forecastProvider.future);
    if (f.hours.isNotEmpty) {
      score = StartTimePlanner(forecast: f, profile: ref.watch(insightsProvider), durationMinutes: 45)
          .scoreAt(g.middle, TrainingType.easy);
    }
  } catch (_) {}
  return (hour: g, score: score);
});

class GoldenHourCard extends ConsumerWidget {
  const GoldenHourCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_goldenProvider).value;
    if (data == null) return const SizedBox.shrink();
    final g = data.hour;
    final now = DateTime.now();
    final today = g.start.day == now.day;
    final part = g.evening ? (today ? 'Vanavond' : 'Morgenavond') : (today ? 'Vanochtend' : 'Morgenochtend');
    final s = data.score;
    final active = !now.isBefore(g.start) && now.isBefore(g.end);
    return RwCard(
      title: 'GOUDEN UUR',
      child: Row(children: [
        Icon(g.evening ? Icons.wb_twilight : Icons.wb_sunny_outlined, color: const Color(0xFFFFB547)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(active ? 'Nu! Tot ${Fmt.time(g.end)}' : '$part ${Fmt.time(g.start)}–${Fmt.time(g.end)}',
                style: const TextStyle(fontFamily: RwFonts.display, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              s == null
                  ? 'Het zachtste licht van de dag: mooi voor een rustig rondje en foto\'s.'
                  : 'Loopweer om ${Fmt.time(s.start)}: ${s.verdict.toLowerCase()} (${s.score}/100), ${Fmt.temp(s.weather.temperature)}.',
              style: TextStyle(color: RwColors.muted, height: 1.35),
            ),
            if (g.evening)
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('Na zonsondergang wordt het snel donker: neem een lampje mee.',
                    style: TextStyle(color: RwColors.subtle, fontSize: 12)),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Vanaf donderdag: wanneer je in het weekend het best je lange duurloop doet.
class WeekendCard extends ConsumerWidget {
  const WeekendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    if (!weekendPreviewDay(now)) return const SizedBox.shrink();
    final f = ref.watch(forecastProvider).value;
    if (f == null || f.hours.isEmpty) return const SizedBox.shrink();
    final w = weekendLongRun(
      StartTimePlanner(forecast: f, profile: ref.watch(insightsProvider), durationMinutes: 90),
      now,
    );
    final text = weekendText(w, Fmt.time);
    if (text == null) return const SizedBox.shrink();
    return RwCard(
      title: 'WEEKEND',
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.weekend_outlined, color: RwColors.accent),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
      ]),
    );
  }
}

/// Jaardoel, op het toestel bewaard.
final yearGoalProvider = NotifierProvider<YearGoalNotifier, double?>(YearGoalNotifier.new);

class YearGoalNotifier extends Notifier<double?> {
  String get _key => 'year_goal_${DateTime.now().year}';

  @override
  double? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getDouble(_key);
      if (v != null) state = v;
    } catch (_) {}
  }

  Future<void> set(double? km) async {
    state = km;
    try {
      final p = await SharedPreferences.getInstance();
      if (km == null) {
        await p.remove(_key);
      } else {
        await p.setDouble(_key, km);
      }
    } catch (_) {}
  }
}

class YearGoalCard extends ConsumerWidget {
  const YearGoalCard({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, double suggestion) async {
    final ctrl = TextEditingController(text: (ref.read(yearGoalProvider) ?? suggestion).round().toString());
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Jaardoel ${DateTime.now().year}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'km', labelText: 'Hoeveel kilometer dit jaar?'),
        ),
        actions: [
          if (ref.read(yearGoalProvider) != null)
            TextButton(onPressed: () => Navigator.pop(ctx, 0.0), child: const Text('Geen doel')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, Fmt.parseDecimal(ctrl.text)),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    if (v == null) return;
    await ref.read(yearGoalProvider.notifier).set(v <= 0 ? null : v);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final done = kmInYear(runs, now);
    final target = ref.watch(yearGoalProvider);
    // Voorstel: wat je dit jaar tot nu toe deed, doorgetrokken, naar boven afgerond op 50 km.
    final proj = YearGoalProgress(targetKm: 1, doneKm: done, now: now).projectedKm;
    final suggestion = proj < 100 ? 500.0 : ((proj * 1.05) / 50).ceil() * 50.0;
    if (target == null) {
      return RwCard(
        title: 'JAARDOEL',
        onTap: () => _edit(context, ref, suggestion),
        child: Row(children: [
          Icon(Icons.flag_circle_outlined, color: RwColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Je liep dit jaar al ${done.round()} km. Kies een doel voor ${now.year}, dan zie je of je op koers ligt.',
                style: TextStyle(color: RwColors.muted, height: 1.4)),
          ),
          Icon(Icons.chevron_right, color: RwColors.muted),
        ]),
      );
    }
    final p = YearGoalProgress(targetKm: target, doneKm: done, now: now);
    return RwCard(
      title: 'JAARDOEL ${now.year}',
      onTap: () => _edit(context, ref, suggestion),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${done.round()}',
              style: const TextStyle(fontFamily: RwFonts.display, fontSize: 30, fontWeight: FontWeight.w800, fontFeatures: rwTnum)),
          Text(' / ${target.round()} km', style: TextStyle(color: RwColors.muted, fontSize: 16)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: p.fraction,
            minHeight: 10,
            backgroundColor: RwColors.surfaceHigh,
            color: p.onTrack ? RwColors.good : RwColors.accent,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          done >= target
              ? 'Gehaald! Alles wat je nu nog loopt is bonus.'
              : p.onTrack
                  ? 'Met dit tempo kom je uit op ${p.projectedKm.round()} km. Je ligt op koers.'
                  : 'Met dit tempo kom je uit op ${p.projectedKm.round()} km. Nog ${p.neededPerWeek.toStringAsFixed(1).replaceAll('.', ',')} km per week om het te halen.',
          style: TextStyle(color: RwColors.muted, height: 1.4),
        ),
        const SizedBox(height: 6),
        Text(monthClimbText(runs, now), style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.4)),
      ]),
    );
  }
}

/// Hoogtemeters deze maand, vergeleken met iets bekends.
String monthClimbText(List<Activity> runs, DateTime now) {
  var m = 0.0;
  for (final a in runs) {
    final t = a.startedAt.toLocal();
    if (t.year == now.year && t.month == now.month) m += a.elevationGainMeters ?? 0;
  }
  return 'Deze maand ${m.round()} hoogtemeters. ${climbComparison(m)}';
}
