import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/location_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/rain_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/clothing.dart';
import '../../domain/geo.dart';
import '../../domain/route_direction.dart';
import '../../domain/start_time_scoring.dart';
import '../../data/services/air_quality_service.dart';
import '../../domain/run_warnings.dart';
import '../../shared/alarm.dart';
import '../../shared/widgets.dart';
import '../live/live_share_screen.dart';
import '../../domain/availability.dart';
import '../planner/availability_provider.dart';
import '../planner/week_planner_screen.dart';
import '../record/record_run_screen.dart';
import '../../domain/dashboard_layout.dart';
import '../../domain/verdict.dart';
import 'dashboard_layout_sheet.dart';
import 'month_challenge_card.dart';
import 'dashboard_providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  TrainingType _type = TrainingType.easy;
  String? _routeId;
  int _durationMinutes = 45;
  Timer? _live;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.lastTrainingType().then((t) {
      if (mounted) setState(() => _type = t);
    });
    // Live: elke 5 minuten de buienradar en de berekening verversen.
    _live = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) ref.invalidate(rainNowcastProvider);
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  /// Plant de dagelijkse melding opnieuw in met de nieuwste verwachting.
  void _rescheduleReminder() {
    final f = ref.read(forecastProvider).value;
    if (f == null || f.hours.isEmpty) return;
    final routes = ref.read(routesProvider).value ?? const <RunRoute>[];
    final route = routes.where((r) => r.id == _routeId).firstOrNull;
    NotificationService.instance
        .reschedule(
          forecast: f,
          profile: ref.read(insightsProvider),
          track: route == null ? const [] : decodePolyline(route.polyline),
          durationMinutes: _durationMinutes,
          rain: ref.read(rainNowcastProvider).value,
          availability: ref.read(availabilityProvider).value ?? Availability.always,
        )
        .ignore();
  }

  Future<void> _refresh() async {
    ref.invalidate(rainNowcastProvider);
    ref.invalidate(weatherLocationProvider);
    ref.invalidate(forecastProvider);
    ref.invalidate(activitiesProvider);
    ref.invalidate(routesProvider);
    await ref.read(forecastProvider.future).catchError((_) => Forecast(latitude: 0, longitude: 0, hours: []));
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
    final routes = ref.watch(routesProvider).when(
          data: (r) => r,
          loading: () => const <RunRoute>[],
          error: (_, _) => const <RunRoute>[],
        );
    final insights = ref.watch(insightsProvider);
    final rain = ref.watch(rainNowcastProvider).value;
    ref.listen(forecastProvider, (_, next) {
      if (next.hasValue) _rescheduleReminder();
    });

    final name = profile.when(
      data: (p) => p?.displayName ?? 'loper',
      loading: () => '',
      error: (_, _) => 'loper',
    );
    final selectedRoute = routes.where((r) => r.id == _routeId).firstOrNull;
    final layout = ref.watch(dashLayoutProvider);

    final settings = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TypePicker(
          value: _type,
          onChanged: (t) {
            setState(() => _type = t);
            NotificationService.instance.rememberTrainingType(t).then((_) => _rescheduleReminder()).ignore();
          },
        ),
        const SizedBox(height: 12),
        _RouteAndDuration(
          routes: routes,
          routeId: _routeId,
          durationMinutes: _durationMinutes,
          onRoute: (id) => setState(() {
            _routeId = id;
            final r = routes.where((x) => x.id == id).firstOrNull;
            if (r?.estimatedDurationSeconds != null) {
              _durationMinutes = (r!.estimatedDurationSeconds! / 60).round().clamp(10, 300);
            }
          }),
          onDuration: (m) => setState(() => _durationMinutes = m),
        ),
      ],
    );
    const extras = <DashCard, Widget>{
      DashCard.planner: WeekPlannerEntry(),
      DashCard.month: MonthChallengeCard(),
      DashCard.live: LiveShareEntryCard(),
    };
    final extrasOnly = [
      for (final c in layout.visible)
        if (extras[c] case final w?) ...[const SizedBox(height: 12), w],
    ];

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'start-run-today',
        onPressed: () => openRecorder(context),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start run'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${_greeting()}${name.isEmpty ? '' : ', $name'}.',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5, fontFamily: RwFonts.display),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Indeling van Vandaag aanpassen',
                    icon: const Icon(Icons.tune, color: RwColors.subtle),
                    onPressed: () => showDashLayoutSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                location.when(
                  data: (l) => 'Weer voor: ${l.label}',
                  loading: () => 'Locatie bepalen…',
                  error: (_, _) => 'Locatie onbekend',
                ),
                style: const TextStyle(color: RwColors.subtle),
              ),
              const SizedBox(height: 16),
              ...forecast.when<List<Widget>>(
                loading: () => [
                  settings,
                  const Padding(padding: EdgeInsets.only(top: 60), child: LoadingView()),
                  ...extrasOnly,
                ],
                error: (e, _) => [
                  settings,
                  const SizedBox(height: 20),
                  ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(forecastProvider)),
                  ...extrasOnly,
                ],
                data: (f) {
                  if (f.hours.isEmpty) {
                    return [
                      settings,
                      const SizedBox(height: 20),
                      ErrorView(message: 'Er is geen weerdata beschikbaar.', onRetry: () => ref.invalidate(forecastProvider)),
                      ...extrasOnly,
                    ];
                  }
                  final planner = StartTimePlanner(
                    forecast: f,
                    profile: insights,
                    track: selectedRoute == null ? const [] : decodePolyline(selectedRoute.polyline),
                    durationMinutes: _durationMinutes,
                    rain: rain,
                    availability: ref.watch(availabilityProvider).value ?? Availability.always,
                  );
                  return [
                    _Results(
                      planner: planner,
                      type: _type,
                      insightsPersonal: insights.isPersonal,
                      rain: rain,
                      air: ref.watch(airQualityProvider).value ?? const [],
                      settings: settings,
                      layout: layout,
                      extras: extras,
                    ),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypePicker extends StatelessWidget {
  const _TypePicker({required this.value, required this.onChanged});
  final TrainingType value;
  final ValueChanged<TrainingType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in TrainingType.values)
              ChoiceChip(
                label: Text(t.label),
                selected: t == value,
                onSelected: (_) => onChanged(t),
                selectedColor: RwColors.accent,
                labelStyle: TextStyle(
                  color: t == value ? RwColors.accentDark : RwColors.text,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: RwColors.surfaceHigh,
                side: const BorderSide(color: RwColors.border),
                showCheckmark: false,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(value.description, style: const TextStyle(color: RwColors.subtle, fontSize: 13)),
      ],
    );
  }
}

class _RouteAndDuration extends StatelessWidget {
  const _RouteAndDuration({
    required this.routes,
    required this.routeId,
    required this.durationMinutes,
    required this.onRoute,
    required this.onDuration,
  });

  final List<RunRoute> routes;
  final String? routeId;
  final int durationMinutes;
  final ValueChanged<String?> onRoute;
  final ValueChanged<int> onDuration;

  @override
  Widget build(BuildContext context) {
    const durations = [20, 30, 45, 60, 75, 90, 120, 150, 180];
    final durationItems = {...durations, durationMinutes}.toList()..sort();
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String?>(
            initialValue: routes.any((r) => r.id == routeId) ? routeId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Route', isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Geen route')),
              for (final r in routes)
                DropdownMenuItem<String?>(
                  value: r.id,
                  child: Text('${r.name} · ${Fmt.km(r.distanceMeters, decimals: 1)}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onRoute,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<int>(
            key: ValueKey(durationMinutes),
            initialValue: durationMinutes,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Duur', isDense: true),
            items: [
              for (final d in durationItems)
                DropdownMenuItem(value: d, child: Text(Fmt.duration(d * 60))),
            ],
            onChanged: (v) {
              if (v != null) onDuration(v);
            },
          ),
        ),
      ],
    );
  }
}

class _Results extends StatefulWidget {
  const _Results({
    required this.planner,
    required this.type,
    required this.insightsPersonal,
    this.rain,
    this.air = const [],
    required this.settings,
    required this.layout,
    required this.extras,
  });
  final StartTimePlanner planner;
  final TrainingType type;
  final bool insightsPersonal;
  final RainNowcast? rain;
  final List<AirQuality> air;
  final Widget settings;
  final DashLayout layout;
  final Map<DashCard, Widget> extras;

  @override
  State<_Results> createState() => _ResultsState();
}

class _ResultsState extends State<_Results> {
  DateTime? _selected;
  bool _goodOnly = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.planner.scoreAll(widget.type);
    final extras = [
      for (final c in widget.layout.visible)
        if (widget.extras[c] case final w?) ...[const SizedBox(height: 12), w],
    ];
    if (all.isEmpty) {
      final custom = !widget.planner.availability.isAlways;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.settings,
          const SizedBox(height: 20),
          EmptyState(
            icon: Icons.nights_stay_outlined,
            title: 'Geen loopmomenten meer',
            message: custom
                ? 'Binnen je looptijden is er de komende 36 uur geen moment meer. Pas je looptijden aan of kijk in de weekplanner.'
                : 'Er zijn in de komende uren geen geschikte tijden tussen 05:00 en 22:00.',
            actionLabel: 'Weekplanner',
            onAction: () => openWeekPlanner(context),
          ),
          ...extras,
        ],
      );
    }
    // Beste moment op 5 minuten nauwkeurig; de staafjes blijven per uur.
    final best = widget.planner.bestPrecise(widget.type) ?? all.reduce((a, b) => b.score > a.score ? b : a);
    final nowStart = StartTimePlanner.roundUp(DateTime.now(), 5);
    final now = widget.planner.scoreAt(nowStart, widget.type);
    final verdict = runVerdict(now, best,
        nowAllowed: widget.planner.availability.allows(nowStart, widget.planner.durationMinutes), time: Fmt.time);
    final shown = _selected == null
        ? best
        : all.firstWhere((s) => s.start == _selected, orElse: () => best);
    final isBest = identical(shown, best) || shown.start == best.start;
    final bars = _goodOnly ? goodHoursOnly(all) : all;
    final warnings = runWarnings(widget.planner.forecast, shown.start, widget.planner.durationMinutes,
        air: airAt(widget.air, shown.start));

    Widget? card(DashCard c) => switch (c) {
          DashCard.warnings => warnings.isEmpty ? null : _WarningsCard(warnings: warnings),
          DashCard.clothing => _ClothingCard(
              advice: clothingFor(shown.weather, widget.type, durationMinutes: widget.planner.durationMinutes),
              at: shown.start,
            ),
          DashCard.rain => widget.rain != null && widget.rain!.points.isNotEmpty ? _RainCard(rain: widget.rain!) : null,
          DashCard.now => !isBest || now.start != best.start ? _NowCard(now: now, best: best) : null,
          DashCard.hours => RwCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('LOOPOMSTANDIGHEDEN PER UUR',
                            style: TextStyle(fontSize: 13, color: RwColors.subtle, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                      ),
                      FilterChip(
                        label: const Text('Alleen goede uren'),
                        selected: _goodOnly,
                        onSelected: (v) => setState(() => _goodOnly = v),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (bars.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Geen uren met een goede score (70 of hoger) in de komende 36 uur.',
                          style: TextStyle(color: RwColors.muted)),
                    )
                  else
                    _HourBars(
                      scores: bars,
                      best: best,
                      selected: shown.start,
                      onTap: (s) => setState(() => _selected = s.start),
                    ),
                ],
              ),
            ),
          DashCard.routeWind => shown.routeWind != null ? _RouteWindCard(score: shown, track: widget.planner.track) : null,
          _ => widget.extras[c],
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VerdictBanner(verdict: verdict, onShowBest: () => setState(() => _selected = null)),
        const SizedBox(height: 16),
        widget.settings,
        const SizedBox(height: 16),
        _BestCard(score: shown, isBest: isBest),
        for (final c in widget.layout.visible)
          if (card(c) case final w?) ...[const SizedBox(height: 12), w],
        const SizedBox(height: 12),
        Text(
          widget.insightsPersonal
              ? 'Berekend met jouw persoonlijke loopprofiel.'
              : 'Log minimaal 8 runs om het advies op jouw eigen prestaties af te stemmen.',
          style: const TextStyle(color: RwColors.subtle, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Eén oordeel in één oogopslag: nu lopen, later lopen of vandaag lastig.
class _VerdictBanner extends StatelessWidget {
  const _VerdictBanner({required this.verdict, required this.onShowBest});
  final RunVerdict verdict;
  final VoidCallback onShowBest;

  @override
  Widget build(BuildContext context) {
    final v = verdict;
    final (color, icon) = switch (v.kind) {
      VerdictKind.goNow => (RwColors.good, Icons.directions_run),
      VerdictKind.later => (RwColors.accent, Icons.schedule),
      VerdictKind.tough => (RwColors.warning, Icons.wb_cloudy_outlined),
    };
    final remindAt = v.best.start.subtract(const Duration(minutes: 15));
    return Semantics(
      container: true,
      label: '${v.title}. ${v.detail}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Icon(icon, color: RwColors.background, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.title,
                            style: TextStyle(
                                fontFamily: RwFonts.display, fontSize: 24, fontWeight: FontWeight.w800, color: color, height: 1.1)),
                        const SizedBox(height: 3),
                        Text(v.detail, style: const TextStyle(color: RwColors.muted, height: 1.35)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (v.kind == VerdictKind.goNow)
                  FilledButton.icon(
                    onPressed: () => openRecorder(context),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start run'),
                  )
                else if (remindAt.isAfter(DateTime.now()))
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await setAlarm(remindAt, 'RunWise: om ${Fmt.time(v.best.start)} lopen');
                      if (!ok && context.mounted) {
                        showMessage(context, 'Kon geen wekker zetten. Zet hem zelf op ${Fmt.time(remindAt)}.', error: true);
                      }
                    },
                    icon: const Icon(Icons.alarm_add_outlined),
                    label: Text('Wekker ${Fmt.time(remindAt)}'),
                  ),
                if (v.kind == VerdictKind.tough)
                  OutlinedButton.icon(
                    onPressed: () => openWeekPlanner(context),
                    icon: const Icon(Icons.calendar_view_week_outlined),
                    label: const Text('Betere dag zoeken'),
                  ),
                if (v.kind != VerdictKind.goNow)
                  TextButton(onPressed: onShowBest, child: const Text('Waarom?')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Vandaag';
  if (diff == 1) return 'Morgen';
  return Fmt.date(t);
}

Color _scoreColor(int score) {
  if (score >= 70) return RwColors.good;
  if (score >= 45) return RwColors.warning;
  return RwColors.danger;
}

class _BestCard extends StatelessWidget {
  const _BestCard({required this.score, required this.isBest});
  final StartTimeScore score;
  final bool isBest;

  @override
  Widget build(BuildContext context) {
    final w = score.weather;
    final remindAt = score.start.subtract(const Duration(minutes: 15));
    return RwCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${isBest ? 'Beste vertrektijd' : 'Vertrekken om'} · ${_dayLabel(score.start)}',
                style: const TextStyle(color: RwColors.muted),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _scoreColor(score.score).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${score.score} · ${score.verdict}',
                  style: TextStyle(color: _scoreColor(score.score), fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            Fmt.time(score.start),
            style: const TextStyle(
              fontSize: 64,
              fontFamily: RwFonts.display,
              fontWeight: FontWeight.w800,
              color: RwColors.accent,
              height: 1.05,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(weatherLabel(w.weatherCode), style: const TextStyle(color: RwColors.muted)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: StatTile(label: 'Gevoel', value: Fmt.temp(w.feelsLike ?? w.temperature))),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: 'Wind',
                  value: w.windDirection == null
                      ? Fmt.wind(w.windSpeed)
                      : '${Fmt.wind(w.windSpeed)} ${Fmt.compass(w.windDirection!)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Regen', value: Fmt.pct(w.precipitationProbability))),
            ],
          ),
          const SizedBox(height: 14),
          for (final r in score.reasons)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    score.reasons.length == 1 && r.startsWith('Prima')
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 16,
                    color: RwColors.subtle,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r, style: const TextStyle(color: RwColors.muted))),
                ],
              ),
            ),
          if (remindAt.isAfter(DateTime.now())) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await setAlarm(remindAt, 'RunWise: om ${Fmt.time(score.start)} lopen');
                if (!ok && context.mounted) {
                  showMessage(context, 'Kon geen wekker zetten. Zet hem zelf op ${Fmt.time(remindAt)}.', error: true);
                }
              },
              icon: const Icon(Icons.alarm_add_outlined, size: 18),
              label: Text('Wekker om ${Fmt.time(remindAt)} (15 min ervoor)'),
            ),
          ],
        ],
      ),
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard({required this.now, required this.best});
  final StartTimeScore now;
  final StartTimeScore best;

  @override
  Widget build(BuildContext context) {
    final gain = best.score - now.score;
    return RwCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nu vertrekken', style: TextStyle(color: RwColors.muted)),
                const SizedBox(height: 2),
                Text(
                  gain <= 3
                      ? 'Bijna net zo goed als het beste moment.'
                      : 'Wachten tot ${Fmt.time(best.start)} scoort $gain punten beter.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${now.score}',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _scoreColor(now.score), fontFamily: RwFonts.display),
          ),
        ],
      ),
    );
  }
}

class _HourBars extends StatelessWidget {
  const _HourBars({
    required this.scores,
    required this.best,
    required this.selected,
    required this.onTap,
  });

  final List<StartTimeScore> scores;
  final StartTimeScore best;
  final DateTime selected;
  final ValueChanged<StartTimeScore> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: scores.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final s = scores[i];
          final isSel = s.start == selected;
          final isBest = s.start.day == best.start.day && s.start.hour == best.start.hour;
          final newDay = i == 0 || scores[i - 1].start.day != s.start.day;
          return GestureDetector(
            onTap: () => onTap(s),
            child: SizedBox(
              width: 30,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    newDay ? _dayLabel(s.start).substring(0, 2) : '',
                    style: const TextStyle(fontSize: 10, color: RwColors.subtle),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: (s.score.clamp(5, 100)) / 100,
                        child: Container(
                          decoration: BoxDecoration(
                            color: isBest
                                ? RwColors.accent
                                : (isSel ? RwColors.muted : RwColors.bar),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.start.hour.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 11,
                      color: isSel ? RwColors.text : RwColors.subtle,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RouteWindCard extends StatelessWidget {
  const _RouteWindCard({required this.score, required this.track});
  final StartTimeScore score;
  final List<LatLng> track;

  @override
  Widget build(BuildContext context) {
    final rw = score.routeWind!;
    final diff = rw.secondHalfHead - rw.firstHalfHead;
    final String text;
    if (rw.headwindAvg < 5) {
      text = 'Weinig tegenwind op je route. Lekker lopen!';
    } else if (diff > 4) {
      text = 'Let op: tegenwind op de terugweg (gem. ${rw.secondHalfHead.round()} km/u). '
          'Loop de eerste helft rustig, zodat je energie overhoudt.';
    } else if (diff < -4) {
      text = 'Tegenwind in de eerste helft (gem. ${rw.firstHalfHead.round()} km/u), '
          'rugwind op de terugweg. Start rustig, je haalt het terug.';
    } else {
      text = 'De tegenwind is gelijk verdeeld over je route (gem. ${rw.headwindAvg.round()} km/u).';
    }
    final w = score.weather;
    final advice = adviseDirection(track, w.windSpeed, w.windDirection);
    return RwCard(
      title: 'WIND OP JE ROUTE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (advice != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  advice.bestLabel == 'linksom' ? Icons.rotate_left : Icons.rotate_right,
                  color: RwColors.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(advice.text, style: const TextStyle(height: 1.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Text(text, style: const TextStyle(height: 1.5, color: RwColors.muted)),
        ],
      ),
    );
  }
}

/// Wat je aantrekt voor het gekozen vertrekmoment.
class _ClothingCard extends StatelessWidget {
  const _ClothingCard({required this.advice, required this.at});
  final ClothingAdvice advice;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    return RwCard(
      title: 'AANTREKKEN OM ${Fmt.time(at)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(advice.summary, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in advice.items)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: RwColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(item, style: const TextStyle(fontSize: 13)),
                ),
            ],
          ),
          for (final tip in advice.extras)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: RwColors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tip, style: const TextStyle(color: RwColors.muted, height: 1.4))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}


/// Live buien voor de komende 2 uur, per 5 minuten (Buienradar).
class _RainCard extends StatelessWidget {
  const _RainCard({required this.rain});
  final RainNowcast rain;

  String get _summary {
    final firstRain = rain.firstRain;
    if (rain.rainingNow) {
      final dry = rain.firstDry;
      return dry == null ? 'Het regent de komende 2 uur.' : 'Het regent nu; droog vanaf ${Fmt.time(dry)}.';
    }
    if (firstRain == null) return 'Droog de komende 2 uur.';
    return 'Droog tot ${Fmt.time(firstRain)}, daarna buien.';
  }

  @override
  Widget build(BuildContext context) {
    final maxMm = rain.points.fold<double>(1, (m, p) => p.mmPerHour > m ? p.mmPerHour : m);
    return RwCard(
      title: 'BUIEN KOMENDE 2 UUR · LIVE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_summary, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final p in rain.points)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: FractionallySizedBox(
                        alignment: Alignment.bottomCenter,
                        heightFactor: p.mmPerHour < 0.1 ? 0.06 : (0.2 + 0.8 * (p.mmPerHour / maxMm)).clamp(0.2, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: p.mmPerHour < 0.1 ? RwColors.bar : const Color(0xFF5AA9FF),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(Fmt.time(rain.points.first.time), style: const TextStyle(fontSize: 11, color: RwColors.subtle)),
              const Spacer(),
              Text(Fmt.time(rain.points.last.time), style: const TextStyle(fontSize: 11, color: RwColors.subtle)),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => launchUrl(Uri.parse('https://www.buienradar.nl'), mode: LaunchMode.externalApplication),
            child: Text(
              'Neerslagverwachting: Buienradar.nl · bijgewerkt ${Fmt.time(rain.fetchedAt)}',
              style: const TextStyle(fontSize: 11, color: RwColors.subtle, decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
    );
  }
}

/// Waarschuwingen voor het gekozen moment: onweer, wind, hitte, gladheid, donker, lucht en pollen.
class _WarningsCard extends StatelessWidget {
  const _WarningsCard({required this.warnings});
  final List<RunWarning> warnings;

  static IconData _icon(String kind) => switch (kind) {
        'thunder' => Icons.thunderstorm_outlined,
        'gusts' => Icons.air,
        'heat' => Icons.local_fire_department_outlined,
        'ice' => Icons.ac_unit,
        'dark' => Icons.dark_mode_outlined,
        'air' => Icons.masks_outlined,
        'pollen' => Icons.local_florist_outlined,
        _ => Icons.info_outline,
      };

  static Color _color(WarningLevel l) => switch (l) {
        WarningLevel.danger => RwColors.danger,
        WarningLevel.caution => RwColors.warning,
        WarningLevel.info => RwColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    return RwCard(
      title: 'LET OP',
      child: Column(
        children: [
          for (final (i, w) in warnings.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon(w.kind), color: _color(w.level), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.title, style: TextStyle(fontWeight: FontWeight.w700, color: _color(w.level) == RwColors.muted ? RwColors.text : _color(w.level))),
                      const SizedBox(height: 2),
                      Text(w.text, style: const TextStyle(color: RwColors.muted, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
