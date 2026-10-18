import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/location_service.dart';
import '../../domain/geo.dart';
import '../../domain/start_time_scoring.dart';
import '../../shared/alarm.dart';
import '../../shared/rw_components.dart';
import '../../shared/widgets.dart';
import 'dashboard_providers.dart';

/// Startscherm "Vandaag" volgens het Figma-ontwerp.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DateTime? _selected;

  Future<void> _refresh() async {
    ref.invalidate(weatherLocationProvider);
    ref.invalidate(forecastProvider);
    ref.invalidate(activitiesProvider);
    ref.invalidate(routesProvider);
    try {
      await ref.read(forecastProvider.future);
    } catch (_) {
      // De foutmelding wordt al in het scherm getoond.
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return 'Goedenacht';
    if (h < 12) return 'Goedemorgen';
    if (h < 18) return 'Goedemiddag';
    return 'Goedenavond';
  }

  @override
  Widget build(BuildContext context) {
    final forecast = ref.watch(forecastProvider);
    final location = ref.watch(weatherLocationProvider);
    final profile = ref.watch(profileProvider);
    final plan = ref.watch(trainingPlanProvider);
    final insights = ref.watch(insightsProvider);
    final routes = ref.watch(routesProvider).when(
          data: (r) => r,
          loading: () => const <RunRoute>[],
          error: (_, _) => const <RunRoute>[],
        );
    final route = routes.where((r) => r.id == plan.routeId).firstOrNull;

    final name = profile.when(data: (p) => p?.displayName ?? '', loading: () => '', error: (_, _) => '');
    final place = location.when(data: (l) => l.label, loading: () => 'Locatie bepalen…', error: (_, _) => 'Locatie onbekend');

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _Header(
                greeting: '${_greeting()}${name.isEmpty ? '' : ', $name'}',
                subline: '$place · ${Fmt.dateLong(DateTime.now()).replaceAll(RegExp(r' \d{4}$'), '')}',
                onBell: () => showMessage(
                  context,
                  'Pushmeldingen komen in een volgende versie. Gebruik "Herinner me" voor een wekker.',
                ),
              ),
              const SizedBox(height: 16),
              forecast.when(
                loading: () => const Padding(padding: EdgeInsets.only(top: 80), child: LoadingView()),
                error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(forecastProvider)),
                data: (f) {
                  if (f.hours.isEmpty) {
                    return ErrorView(
                      message: 'Er is geen weerdata beschikbaar.',
                      onRetry: () => ref.invalidate(forecastProvider),
                    );
                  }
                  final planner = StartTimePlanner(
                    forecast: f,
                    profile: insights,
                    track: route == null ? const [] : decodePolyline(route.polyline),
                    durationMinutes: plan.durationMinutes,
                  );
                  return _Content(
                    planner: planner,
                    plan: plan,
                    route: route,
                    selected: _selected,
                    onSelect: (t) => setState(() => _selected = t),
                    personal: insights.isPersonal,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.greeting, required this.subline, required this.onBell});
  final String greeting;
  final String subline;
  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: RwColors.tekst)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: RwColors.tekstZacht),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(subline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: RwColors.tekstZacht)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        RoundIconButton(icon: Icons.notifications_none, onTap: onBell, tooltip: 'Meldingen'),
      ],
    );
  }
}

String _dayWord(DateTime t) {
  final now = DateTime.now();
  final diff = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (diff == 0) return 'vandaag';
  if (diff == 1) return 'morgen';
  return Fmt.date(t);
}

class _Content extends ConsumerWidget {
  const _Content({
    required this.planner,
    required this.plan,
    required this.route,
    required this.selected,
    required this.onSelect,
    required this.personal,
  });

  final StartTimePlanner planner;
  final TrainingPlan plan;
  final RunRoute? route;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;
  final bool personal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = planner.scoreAll(plan.type);
    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.nights_stay_outlined,
        title: 'Geen loopmomenten meer',
        message: 'Er zijn in de komende uren geen geschikte tijden tussen 05:00 en 22:00.',
      );
    }
    final best = all.reduce((a, b) => b.score > a.score ? b : a);
    final shown = selected == null ? best : all.firstWhere((s) => s.start == selected, orElse: () => best);
    final isBest = shown.start == best.start;

    // Venster: aansluitende uren die bijna net zo goed scoren.
    var windowEnd = shown.start.add(const Duration(hours: 1));
    final idx = all.indexWhere((s) => s.start == shown.start);
    for (var i = idx + 1; i < all.length; i++) {
      if (all[i].score < shown.score - 8 || all[i].start.difference(windowEnd).inMinutes > 0) break;
      windowEnd = all[i].start.add(const Duration(hours: 1));
    }

    final typical = ref.watch(typicalPaceProvider);
    final pace = paceFor(plan.type, typical);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BestCard(
          score: shown,
          title: isBest
              ? 'BESTE VERTREKTIJD ${_dayWord(shown.start).toUpperCase()}'
              : 'VERTREKKEN ${_dayWord(shown.start).toUpperCase()} OM',
          windowText: 'Venster tot ${Fmt.time(windowEnd)} · '
              '${shown.score >= 70 ? 'ideaal' : 'prima'} voor je ${plan.type.label.toLowerCase()}',
        ),
        const SizedBox(height: 16),
        _HourScores(all: all, best: best, selected: shown.start, onSelect: onSelect),
        const SizedBox(height: 16),
        _TrainingCard(plan: plan, route: route, pace: pace),
        const SizedBox(height: 16),
        _CoachTip(score: shown, plan: plan, route: route),
        if (!personal) ...[
          const SizedBox(height: 16),
          const Text(
            'Log minimaal 8 runs, dan stemt RunWise het advies af op jouw eigen prestaties.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: RwColors.tekstZacht),
          ),
        ],
      ],
    );
  }
}

class _BestCard extends StatelessWidget {
  const _BestCard({required this.score, required this.title, required this.windowText});
  final StartTimeScore score;
  final String title;
  final String windowText;

  @override
  Widget build(BuildContext context) {
    final w = score.weather;
    final remindAt = score.start.subtract(const Duration(minutes: 30));
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: RwColors.primair, borderRadius: BorderRadius.circular(RwRadius.r24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.72,
                        color: RwColors.primairZacht)),
              ),
              Pill('Score ${score.score}'),
            ],
          ),
          const SizedBox(height: 16),
          Text(Fmt.time(score.start),
              style: const TextStyle(
                  fontSize: 56, height: 60 / 56, fontWeight: FontWeight.w700, color: RwColors.opPrimair)),
          const SizedBox(height: 4),
          Text(windowText, style: const TextStyle(fontSize: 14, color: RwColors.primairZacht)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: WeatherTile(
                  icon: Icons.thermostat,
                  value: Fmt.temp(w.feelsLike ?? w.temperature),
                  label: 'Temperatuur',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: WeatherTile(
                  icon: Icons.air,
                  value: Fmt.wind(w.windSpeed),
                  label: w.windDirection == null ? 'Wind' : 'Wind (${Fmt.compass(w.windDirection!)})',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: WeatherTile(
                  icon: Icons.water_drop_outlined,
                  value: Fmt.pct(w.precipitationProbability),
                  label: 'Regenkans',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Material(
            color: RwColors.oppervlak,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () async {
                final ok = await setAlarm(remindAt, 'RunWise: om ${Fmt.time(score.start)} lopen');
                if (!ok && context.mounted) {
                  showMessage(context, 'Kon geen wekker zetten. Zet hem zelf op ${Fmt.time(remindAt)}.', error: true);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.schedule, size: 18, color: RwColors.primair),
                    const SizedBox(width: 8),
                    Text('Herinner me om ${Fmt.time(remindAt)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: RwColors.primair)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HourScores extends StatelessWidget {
  const _HourScores({required this.all, required this.best, required this.selected, required this.onSelect});
  final List<StartTimeScore> all;
  final StartTimeScore best;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = all.where((s) => _sameDay(s.start, now)).toList();
    var day = today.length >= 3 ? today : all.where((s) => !_sameDay(s.start, now)).take(18).toList();
    if (day.isEmpty) day = all;
    final dayLabel = today.length >= 3 ? 'Vandaag' : 'Morgen';
    final dayBest = day.reduce((a, b) => b.score > a.score ? b : a);

    // Maximaal 8 staven, gelijk verdeeld, en het beste moment altijd erbij.
    final slots = <StartTimeScore>[];
    if (day.length <= 8) {
      slots.addAll(day);
    } else {
      for (var i = 0; i < 8; i++) {
        slots.add(day[(i * (day.length - 1) / 7).round()]);
      }
      if (!slots.any((s) => s.start == dayBest.start)) {
        var nearest = 0;
        for (var i = 1; i < slots.length; i++) {
          if ((slots[i].start.difference(dayBest.start)).abs() <
              (slots[nearest].start.difference(dayBest.start)).abs()) {
            nearest = i;
          }
        }
        slots[nearest] = dayBest;
      }
    }

    return RwPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Hardloopscore per uur',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: RwColors.tekst)),
              ),
              Text(dayLabel, style: const TextStyle(fontSize: 13, color: RwColors.tekstZacht)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final s in slots)
                TimeSlotBar(
                  label: s.start == dayBest.start ? Fmt.time(s.start) : s.start.hour.toString().padLeft(2, '0'),
                  score: s.score,
                  best: s.start == dayBest.start,
                  selected: s.start == selected,
                  onTap: () => onSelect(s.start),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Hoe hoger de staaf, hoe beter weer, wind en licht samen uitkomen. Tik op een staaf voor details.',
            style: TextStyle(fontSize: 12, height: 16 / 12, color: RwColors.tekstZacht),
          ),
        ],
      ),
    );
  }
}

class _TrainingCard extends ConsumerWidget {
  const _TrainingCard({required this.plan, required this.route, required this.pace});
  final TrainingPlan plan;
  final RunRoute? route;
  final double pace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final km = route != null ? route!.distanceMeters / 1000 : plan.durationMinutes * 60 / pace;
    final minutes = route != null ? (km * pace / 60).round() : plan.durationMinutes;
    final tempoWord = switch (plan.type) {
      TrainingType.easy => 'Rustig tempo',
      TrainingType.quality => 'Stevig tempo',
      TrainingType.long => 'Rustig tempo',
      TrainingType.recovery => 'Heel rustig',
    };
    return RwPanel(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _PlanSheet(),
      ),
      child: Row(
        children: [
          const IconBox(icon: Icons.route),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Training van vandaag', style: TextStyle(fontSize: 12, color: RwColors.tekstZacht)),
                const SizedBox(height: 4),
                Text('${plan.type.label} · ${km.toStringAsFixed(km < 10 ? 1 : 0).replaceAll('.', ',')} km',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: RwColors.tekst)),
                const SizedBox(height: 4),
                Text(
                  '$tempoWord ${Fmt.pace(pace)} · ca. $minutes min${route == null ? '' : ' · ${route!.name}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: RwColors.tekstZacht),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: RwColors.tekst),
        ],
      ),
    );
  }
}

/// Kies soort training, route en duur.
class _PlanSheet extends ConsumerWidget {
  const _PlanSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(trainingPlanProvider);
    final notifier = ref.read(trainingPlanProvider.notifier);
    final routes = ref.watch(routesProvider).when(
          data: (r) => r,
          loading: () => const <RunRoute>[],
          error: (_, _) => const <RunRoute>[],
        );
    const durations = [20, 30, 45, 60, 75, 90, 120];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Training van vandaag', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            const Text('Soort training', style: TextStyle(fontSize: 13, color: RwColors.tekstZacht)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in TrainingType.values)
                  RwChip(label: t.label, active: t == plan.type, onTap: () => notifier.setType(t)),
              ],
            ),
            const SizedBox(height: 6),
            Text(plan.type.description, style: const TextStyle(fontSize: 12, color: RwColors.tekstZacht)),
            const SizedBox(height: 16),
            const Text('Route', style: TextStyle(fontSize: 13, color: RwColors.tekstZacht)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                RwChip(label: 'Geen route', active: plan.routeId == null, onTap: () => notifier.setRoute(null)),
                for (final r in routes)
                  RwChip(
                    label: '${r.name} · ${Fmt.km(r.distanceMeters, decimals: 1)}',
                    active: r.id == plan.routeId,
                    onTap: () => notifier.setRoute(r),
                  ),
              ],
            ),
            if (plan.routeId == null) ...[
              const SizedBox(height: 16),
              const Text('Duur', style: TextStyle(fontSize: 13, color: RwColors.tekstZacht)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in durations)
                    RwChip(
                      label: Fmt.duration(d * 60),
                      active: d == plan.durationMinutes,
                      onTap: () => notifier.setDuration(d),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Klaar')),
          ],
        ),
      ),
    );
  }
}

class _CoachTip extends StatelessWidget {
  const _CoachTip({required this.score, required this.plan, required this.route});
  final StartTimeScore score;
  final TrainingPlan plan;
  final RunRoute? route;

  String _tip() {
    final w = score.weather;
    final rw = score.routeWind;
    final feels = w.feelsLike ?? w.temperature;
    if (rw != null && rw.headwindAvg >= 5) {
      if (rw.secondHalfHead - rw.firstHalfHead > 4) {
        return 'Op de terugweg heb je tegenwind (${rw.secondHalfHead.round()} km/u). '
            'Loop de eerste helft rustig, dan heb je energie over voor het laatste stuk.';
      }
      if (rw.firstHalfHead - rw.secondHalfHead > 4) {
        return 'Je start met tegenwind en hebt hem op de terugweg in je rug. '
            'Begin rustig, je haalt de tijd straks terug.';
      }
    }
    if (feels >= 22) return 'Het voelt als ${feels.round()}°C. Neem water mee en loop 10 tot 15 seconden per km rustiger.';
    if ((w.precipitationProbability ?? 0) >= 50) {
      return 'Grote kans op regen rond ${Fmt.time(score.start)}. Een pet houdt de druppels uit je ogen.';
    }
    if (w.windSpeed >= 25) return 'Er staat flink wind. Kies een beschutte route, bijvoorbeeld door het bos.';
    if (feels <= 3) return 'Het is koud. Warm binnen kort op en draag handschoenen; die doe je onderweg zo uit.';
    if (!w.isDay) return 'Het is donker op dit tijdstip. Draag reflecterende kleding of een lampje.';
    if (route == null) return 'Kies een route bij "Training van vandaag", dan houd ik rekening met de wind op jouw rondje.';
    return 'Mooie omstandigheden. Geniet ervan en houd het tempo de eerste kilometers bewust rustig.';
  }

  @override
  Widget build(BuildContext context) {
    return RwPanel(
      color: RwColors.primairZacht,
      border: false,
      onTap: () => context.go('/coach'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconBox(
            icon: Icons.auto_awesome_outlined,
            size: 40,
            iconSize: 20,
            background: RwColors.primair,
            color: RwColors.opPrimair,
            circle: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('RunWise Coach',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: RwColors.tekst)),
                    SizedBox(width: 8),
                    Pill('PRO', small: true),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_tip(), style: const TextStyle(fontSize: 14, height: 20 / 14, color: RwColors.tekst)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
