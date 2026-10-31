import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/home_widget_service.dart';
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
import '../../data/services/run_recorder_service.dart';
import '../../domain/run_helpers.dart';
import '../../shared/calendar.dart';
import '../../shared/art/landscape.dart';
import '../../shared/art/sun_arc.dart';
import '../../shared/art/weather_icon.dart';
import '../../shared/shine_text.dart';
import '../../shared/first_tips.dart';
import '../../shared/widgets.dart';
import '../live/live_share_screen.dart';
import '../../domain/availability.dart';
import '../planner/availability_provider.dart';
import '../planner/week_planner_screen.dart';
import '../record/quick_start.dart';
import '../record/record_run_screen.dart';
import '../../domain/dashboard_layout.dart';
import '../profile/shoe_replace_card.dart';
import '../challenges/challenges.dart' show ChallengesCard;
import '../../domain/training_plan.dart';
import '../../domain/verdict.dart';
import 'confidence_chip.dart';
import 'dashboard_layout_sheet.dart';
import 'best_route_card.dart';
import 'bingo_card.dart';
import 'extra_cards.dart';
import 'month_challenge_card.dart';
import 'today_card.dart';
import 'dashboard_providers.dart';
import 'record_weather_card.dart';
import 'weather_ambience.dart';
import '../shop/shop_tile.dart';
import '../profile/sources_screen.dart';
import '../profile/run_pause_tile.dart' show PauseBanner;

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  /// Startknop uitgeklapt (boven in de lijst) of ingeklapt tot icoon (tijdens scrollen).
  final _fabExtended = ValueNotifier(true);

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
    _fabExtended.dispose();
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
          runStarts: [for (final a in ref.read(activitiesProvider).value ?? const <Activity>[]) a.startedAt],
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
    HapticFeedback.lightImpact();
    if (mounted) setState(() => _updatedAt = DateTime.now());
  }

  /// Wanneer het weer en het advies voor het laatst zijn opgehaald.
  DateTime? _updatedAt;

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

    final settings = _PlanRow(
      type: _type,
      route: selectedRoute,
      durationMinutes: _durationMinutes,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Wat ga je lopen?', style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  _TypePicker(
                    value: _type,
                    onChanged: (t) {
                      HapticFeedback.selectionClick();
                      setState(() => _type = t);
                      setSheet(() {});
                      NotificationService.instance.rememberTrainingType(t).then((_) => _rescheduleReminder()).ignore();
                    },
                  ),
                  const SizedBox(height: 16),
                  _RouteAndDuration(
                    routes: routes,
                    routeId: _routeId,
                    durationMinutes: _durationMinutes,
                    onRoute: (id) {
                      setState(() {
                        _routeId = id;
                        final r = routes.where((x) => x.id == id).firstOrNull;
                        if (r?.estimatedDurationSeconds != null) {
                          _durationMinutes = (r!.estimatedDurationSeconds! / 60).round().clamp(10, 300);
                        }
                      });
                      setSheet(() {});
                    },
                    onDuration: (m) {
                      setState(() => _durationMinutes = m);
                      setSheet(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Klaar')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    const extras = <DashCard, Widget>{
      DashCard.planner: WeekPlannerEntry(),
      DashCard.month: MonthChallengeCard(),
      DashCard.bingo: BingoCardView(),
      DashCard.live: LiveShareEntryCard(),
      DashCard.bestRoute: BestRouteNowCard(),
      DashCard.again: AgainCard(),
      DashCard.goldenHour: GoldenHourCard(),
      DashCard.weekend: WeekendCard(),
      DashCard.onThisDay: OnThisDayCard(),
      DashCard.yearGoal: YearGoalCard(),
      DashCard.shoes: ShoeReplaceCard(),
      DashCard.challenges: ChallengesCard(),
    };
    final extrasOnly = [
      for (final c in layout.visible)
        if (extras[c] case final w?) ...[const SizedBox(height: 12), w],
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: RwFab(
        heroTag: 'start-run-today',
        label: 'Start run',
        icon: Icons.play_arrow,
        extended: _fabExtended,
        onPressed: () => openRecorder(context),
        // Lang drukken: snelmenu (training van vandaag, vast rondje, buiten, loopband).
        onLongPress: () => showQuickStart(context, ref),
      ),
      body: SafeArea(
        child: FabScrollWatcher(
        extended: _fabExtended,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
            children: [
              const FirstTip(
                id: 'today',
                icon: Icons.wb_sunny_outlined,
                padding: EdgeInsets.only(bottom: 14),
                text: 'Vandaag zie je het beste moment om te lopen. Tik op een uur in de grafiek voor het weer en kledingadvies op dat moment. Kaarten verplaatsen of verbergen kan met het schuifje rechtsboven.',
              ),
              const PauseBanner(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: StaggerIn(
                      index: 0,
                      child: Text(
                        '${_greeting()}${name.isEmpty ? '' : ', $name'}.',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5, fontFamily: RwFonts.display, fontFeatures: rwTnum),
                      ),
                    ),
                  ),
                  const ShopIconButton(),
                  IconButton(
                    tooltip: 'Indeling van Vandaag aanpassen',
                    icon: Icon(Icons.tune, color: RwColors.subtle),
                    onPressed: () => showDashLayoutSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              StaggerIn(
                index: 2,
                child: Text(
                () {
                  final nowW = forecast.value?.at(DateTime.now());
                  final place = location.when(data: (l) => l.label, loading: () => '', error: (_, _) => '');
                  final weather = nowW == null ? '' : ' · ${Fmt.temp(nowW.temperature)}, ${weatherLabel(nowW.weatherCode).toLowerCase()}';
                  final where = place.isEmpty || place == 'je locatie' ? '' : ' · $place';
                  final upd = _updatedAt ?? (forecast.hasValue ? DateTime.now() : null);
                  _updatedAt ??= upd;
                  return '${Fmt.date(DateTime.now())}$weather$where${upd == null ? '' : ' · bijgewerkt ${Fmt.time(upd)}'}';
                }(),
                style: TextStyle(color: RwColors.subtle),
              ),
              ),
              const SizedBox(height: 18),
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
                      clothingFeel: ref.watch(clothingFeelProvider),
                      pollen: ref.watch(pollenSensitivityProvider),
                      recentMaxTemp: ref.watch(recentMaxRunTempProvider),
                      dog: ref.watch(dogModeProvider),
                    ),
                  ];
                },
              ),
            ],
          ),
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
                side: BorderSide(color: RwColors.border),
                showCheckmark: false,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(value.description, style: TextStyle(color: RwColors.subtle, fontSize: 13)),
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
    this.clothingFeel = ClothingFeel.normal,
    this.pollen = PollenSensitivity.normal,
    this.recentMaxTemp,
    this.dog = false,
  });
  final ClothingFeel clothingFeel;
  final PollenSensitivity pollen;
  final bool dog;
  final double? recentMaxTemp;
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
  void initState() {
    super.initState();
    // "Alleen goede uren" blijft aan als je het eerder aanzette.
    SharedPreferences.getInstance().then((p) {
      if (mounted && (p.getBool('hours_good_only') ?? false)) setState(() => _goodOnly = true);
    }).catchError((Object _) {});
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HomeWidgetService.instance
          .update(
            label: switch (verdict.kind) { VerdictKind.goNow => 'NU LOPEN', VerdictKind.later => 'BESTE MOMENT', VerdictKind.tough => 'LASTIGE DAG' },
            time: verdict.kind == VerdictKind.goNow ? 'Nu' : Fmt.time(best.start),
            detail: '${_dayLabel(best.start)} · ${Fmt.temp(best.weather.feelsLike ?? best.weather.temperature)} · wind ${Fmt.wind(best.weather.windSpeed)} · score ${best.score}',
          )
          .ignore();
    });
    final shown = _selected == null
        ? best
        : all.firstWhere((s) => s.start == _selected, orElse: () => best);
    final isBest = identical(shown, best) || shown.start == best.start;
    final bars = _goodOnly ? goodHoursOnly(all) : all;
    final warnings = runWarnings(widget.planner.forecast, shown.start, widget.planner.durationMinutes,
        air: airAt(widget.air, shown.start),
        pollen: widget.pollen,
        recentMaxTemp: widget.recentMaxTemp,
        hasRoute: widget.planner.track.length >= 2,
        route: widget.planner.track.length >= 2 ? trackSegments(widget.planner.track) : const [],
        dog: widget.dog);

    Widget? card(DashCard c) => switch (c) {
          DashCard.warnings => warnings.isEmpty ? null : _WarningsCard(warnings: warnings),
          DashCard.recordWeather => switch (RecordWeatherCard.bestMoment(widget.planner)) {
              final b? => RecordWeatherCard(best: b),
              null => null,
            },
          DashCard.clothing => _ClothingCard(
              advice: clothingFor(shown.weather, widget.type, durationMinutes: widget.planner.durationMinutes, feel: widget.clothingFeel),
              at: shown.start,
            ),
          DashCard.rain => widget.rain != null && widget.rain!.points.isNotEmpty ? _RainCard(rain: widget.rain!) : null,
          DashCard.hours => RwCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('PER UUR',
                            style: RwText.overline),
                      ),
                      FilterChip(
                        label: const Text('Alleen goede uren'),
                        selected: _goodOnly,
                        onSelected: (v) {
                          setState(() => _goodOnly = v);
                          SharedPreferences.getInstance().then((p) => p.setBool('hours_good_only', v)).ignore();
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (bars.isEmpty)
                    Padding(
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
                  if (bars.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Hoger en warmer = beter moment · het beste uur gloeit · tik voor details',
                          style: TextStyle(color: RwColors.subtle, fontSize: 12)),
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
        Consumer(builder: (context, ref, _) {
          final plan = ref.watch(planProvider).value ?? const <PlanSession>[];
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final session = plan.where((x) => x.date == today).firstOrNull;
          final line = personalLine(verdict, session, restDay: plan.isNotEmpty && session == null);
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(line, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.35)),
              ),
              // Voorlezen: handig terwijl je je omkleedt of je schoenen strikt.
              IconButton(
                tooltip: 'Voorlezen',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.volume_up_outlined, color: RwColors.subtle),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  final w = verdict.best.weather;
                  RunRecorderService.instance.say(
                    '$line Het beste moment is om ${Fmt.time(verdict.best.start)}, '
                    'met ${(w.feelsLike ?? w.temperature).round()} graden gevoel en wind ${w.windSpeed.round()} kilometer per uur.',
                  );
                },
              ),
            ]),
          );
        }),
        widget.settings,
        const SizedBox(height: 12),
        _HeroCard(
          verdict: verdict,
          shown: shown,
          isBest: isBest,
          onShowBest: () => setState(() => _selected = null),
          durationMinutes: widget.planner.durationMinutes,
          lat: widget.planner.forecast.latitude,
          lon: widget.planner.forecast.longitude,
        ),
        const SizedBox(height: 12),
        const TodayCard(),
        const RaceCountdownCard(),
        const WeeklyReportCard(),
        const YearStoryCard(),
        for (final c in widget.layout.visible)
          if (card(c) case final w?) ...[const SizedBox(height: 12), w],
        const SizedBox(height: 12),
        Text(
          widget.insightsPersonal
              ? 'Berekend met jouw persoonlijke loopprofiel.'
              : 'Log minimaal 8 runs om het advies op jouw eigen prestaties af te stemmen.',
          style: TextStyle(color: RwColors.subtle, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Eén persoonlijke zin over je dag: het weer op je beste moment, gekoppeld aan je training.
String personalLine(RunVerdict v, PlanSession? session, {bool restDay = false}) {
  final w = v.best.weather;
  final feels = (w.feelsLike ?? w.temperature).round();
  final rain = w.precipitationProbability ?? 0;
  final parts = <String>[
    if (rain < 20) 'droog' else if (rain < 50) 'kans op een bui' else 'regenachtig',
    '$feels°',
    if (w.windSpeed < 12) 'weinig wind' else if (w.windSpeed >= 28) 'stevige wind',
  ];
  final weather = parts.join(', ');
  final cap = weather[0].toUpperCase() + weather.substring(1);
  final day = _dayLabel(v.best.start);
  final when = v.kind == VerdictKind.goNow ? 'nu' : '${day == 'Vandaag' ? '' : '${day.toLowerCase()} '}om ${Fmt.time(v.best.start)}';
  if (session != null && session.kind != SessionKind.race) {
    final what = session.title[0].toLowerCase() + session.title.substring(1);
    return v.kind == VerdictKind.tough
        ? 'Lastig weer vandaag. Je $what kan het best $when, of maak hem lichter.'
        : '$cap $when: mooi voor je $what.';
  }
  if (session?.kind == SessionKind.race) return 'Wedstrijddag! $cap. Start rustig, je wint hem in de tweede helft.';
  if (restDay) return 'Rustdag in je schema. Zin om toch te bewegen? $cap $when.';
  return switch (v.kind) {
    VerdictKind.goNow => '$cap: nu is het goed loopweer.',
    VerdictKind.later => '$cap $when: dan loop je het lekkerst.',
    VerdictKind.tough => 'Lastig loopweer vandaag. Het beste moment is $when.',
  };
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

/// Hoofdkaart: één oordeel, het beste moment en het weer dan (vervangt de losse oordeel-, beste- en nu-kaarten).
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.verdict,
    required this.shown,
    required this.isBest,
    required this.onShowBest,
    required this.durationMinutes,
    required this.lat,
    required this.lon,
  });
  final int durationMinutes;
  final double lat, lon;
  final RunVerdict verdict;
  final StartTimeScore shown;
  final bool isBest;
  final VoidCallback onShowBest;

  @override
  Widget build(BuildContext context) {
    final v = verdict;
    final (color, label) = switch (v.kind) {
      VerdictKind.goNow => (RwColors.good, 'NU LOPEN'),
      VerdictKind.later => (RwColors.accent, 'LATER LOPEN'),
      VerdictKind.tough => (RwColors.warning, 'LASTIGE DAG'),
    };
    final s = shown;
    final w = s.weather;
    final goNowShown = isBest && v.kind == VerdictKind.goNow;
    final remindAt = s.start.subtract(const Duration(minutes: 15));
    final gain = v.best.score - v.now.score;
    // Redenen die nog niet in de tekst hierboven staan.
    final shownText = isBest ? v.detail.toLowerCase() : '';
    final extraReasons = [
      for (final r in s.reasons)
        if (!r.startsWith('Prima') && !shownText.contains(r.toLowerCase())) r,
    ];
    return Semantics(
      container: true,
      label: '${v.title}. ${v.detail}',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.18), RwColors.surface],
            stops: const [0, 0.7],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Positioned.fill(child: WeatherAmbience(weather: w, golden: _golden(s.start, lat, lon))),
          // Seizoenslandschap onderin, heel zacht, beweegt mee als je de telefoon kantelt.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 150,
            child: KadansLandscape(date: s.start, wind: w.windSpeed, opacity: 0.55, showPath: false),
          ),
          Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
                    child: Text(isBest ? label : 'GEKOZEN MOMENT',
                        style: TextStyle(color: RwColors.background, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.6)),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Nodig iemand uit om mee te lopen',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.group_add_outlined, size: 20, color: RwColors.muted),
                    onPressed: () {
                      final when = goNowShown ? 'nu meteen' : '${_dayLabel(s.start).toLowerCase()} om ${Fmt.time(s.start)}';
                      SharePlus.instance.share(ShareParams(
                        text: 'Zin om mee te lopen? Volgens Kadans is $when het beste moment: '
                            '${Fmt.temp(w.feelsLike ?? w.temperature)} gevoel, wind ${Fmt.wind(w.windSpeed)}'
                            '${(w.precipitationProbability ?? 0) < 20 ? ', droog' : ', regenkans ${Fmt.pct(w.precipitationProbability)}'}. Doe je mee?',
                      )).ignore();
                    },
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: s.score.toDouble()),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => Text('${v.round()}',
                        style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800, fontSize: 22, color: _scoreColor(s.score))),
                  ),
                  const SizedBox(width: 4),
                  Text(s.verdict, style: TextStyle(color: _scoreColor(s.score), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ExcludeSemantics(
              // Wrap: met grote letters gaat "Morgen / bewolkt" netjes onder de tijd in plaats van letter voor letter.
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 12,
                runSpacing: 4,
                children: [
                  ShineText(
                    goNowShown ? 'Nu' : Fmt.time(s.start),
                    style: TextStyle(
                      fontFamily: RwFonts.display, fontFeatures: rwTnum,
                      fontSize: 64,
                      fontWeight: FontWeight.w800,
                      color: RwColors.text,
                      height: 1,
                      letterSpacing: -1.5,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AnimatedWeatherIcon(code: w.weatherCode, day: w.isDay, size: 40),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${_dayLabel(s.start)}\n${weatherLabel(w.weatherCode)}',
                      style: TextStyle(color: RwColors.muted, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            ConfidenceChip(lat: lat, lon: lon, start: s.start, minutes: durationMinutes, weather: w, isBest: isBest),
            const SizedBox(height: 8),
            Text(isBest ? v.detail : 'Je bekijkt ${Fmt.time(s.start)}. Het beste moment is ${Fmt.time(v.best.start)} (score ${v.best.score}).',
                style: TextStyle(color: RwColors.muted, height: 1.4)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _HeroStat(icon: Icons.thermostat, label: 'Gevoel', value: Fmt.temp(w.feelsLike ?? w.temperature))),
                Expanded(
                  child: _HeroStat(
                    icon: Icons.air,
                    lead: w.windDirection == null ? null : _WindNeedle(fromDegrees: w.windDirection!),
                    label: 'Wind',
                    value: w.windDirection == null ? Fmt.wind(w.windSpeed) : '${Fmt.wind(w.windSpeed)} ${Fmt.compass(w.windDirection!)}',
                  ),
                ),
                Expanded(child: _HeroStat(icon: Icons.water_drop_outlined, label: 'Regen', value: Fmt.pct(w.precipitationProbability))),
              ],
            ),
            if (extraReasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final r in extraReasons.take(2))
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.info_outline, size: 15, color: RwColors.subtle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r, style: TextStyle(color: RwColors.muted, fontSize: 13))),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 10),
            // Wanneer ben je terug, en is het dan nog licht?
            Builder(builder: (context) {
              final start = goNowShown ? DateTime.now() : s.start;
              final back = start.add(Duration(minutes: durationMinutes));
              final dark = darkWarning(start, Duration(minutes: durationMinutes), lat, lon);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.home_outlined, size: 16, color: RwColors.subtle),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${goNowShown ? 'Ga je nu' : 'Ga je om ${Fmt.time(start)}'}, dan ben je rond ${Fmt.time(back)} terug ($durationMinutes min).',
                      style: TextStyle(color: RwColors.muted, fontSize: 13),
                    ),
                  ),
                ]),
                if (dark != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.nights_stay_outlined, size: 16, color: RwColors.warning)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(dark, style: TextStyle(color: RwColors.warning, fontSize: 13, height: 1.35))),
                    ]),
                  ),
              ]);
            }),
            const SizedBox(height: 8),
            SunArc(start: s.start, minutes: durationMinutes, lat: lat, lon: lon),
            const SizedBox(height: 10),
            Row(
              children: [
                if (goNowShown)
                  Expanded(
                    // Glas-stijl: de oranje hoofdknop "Start run" zweeft al onderin.
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: RwColors.surface.withValues(alpha: 0.6),
                        foregroundColor: RwColors.text,
                        side: BorderSide(color: RwColors.good.withValues(alpha: 0.6)),
                      ),
                      onPressed: () => openRecorder(context),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start run'),
                    ),
                  )
                else if (remindAt.isAfter(DateTime.now()))
                  Expanded(
                    // Secundair (glas met oranje rand): de oranje hoofdknop is "Start run".
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: RwColors.surface.withValues(alpha: 0.6),
                        foregroundColor: RwColors.text,
                        side: BorderSide(color: RwColors.accent.withValues(alpha: 0.55)),
                      ),
                      onPressed: () async {
                        final ok = await setAlarm(remindAt, 'Kadans: om ${Fmt.time(s.start)} lopen');
                        if (!ok && context.mounted) {
                          showMessage(context, 'Kon geen wekker zetten. Zet hem zelf op ${Fmt.time(remindAt)}.', error: true);
                        }
                      },
                      icon: Icon(Icons.alarm_add_outlined, color: RwColors.accentLight),
                      label: Text('Wekker ${Fmt.time(remindAt)}'),
                    ),
                  )
                else
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => openRecorder(context),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start run'),
                    ),
                  ),
                if (!goNowShown) ...[
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'In je agenda zetten',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(52, 52),
                      side: BorderSide(color: RwColors.accent.withValues(alpha: 0.55)),
                      backgroundColor: RwColors.surface.withValues(alpha: 0.6),
                    ),
                    onPressed: () => addToCalendar(
                      context,
                      title: 'Hardlopen (Kadans)',
                      start: s.start,
                      minutes: durationMinutes,
                      details: 'Beste moment volgens Kadans: score ${s.score}. ${Fmt.temp(w.feelsLike ?? w.temperature)} gevoel, wind ${Fmt.wind(w.windSpeed)}.',
                    ),
                    icon: Icon(Icons.event_available_outlined, color: RwColors.accentLight),
                  ),
                ],
                if (v.kind == VerdictKind.tough) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => openWeekPlanner(context),
                      child: const Text('Betere dag'),
                    ),
                  ),
                ],
              ],
            ),
            if (!isBest)
              Center(child: TextButton(onPressed: onShowBest, child: const Text('Terug naar het beste moment')))
            else if (v.kind != VerdictKind.goNow && gain > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Icon(Icons.directions_run, size: 16, color: RwColors.subtle),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Nu vertrekken kan ook: score ${v.now.score} (${gain <= 3 ? 'bijna even goed' : '$gain punten minder'}).',
                          style: TextStyle(color: RwColors.subtle, fontSize: 13)),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: RwColors.accentLight),
                      onPressed: () => openRecorder(context),
                      child: const Text('Toch nu'),
                    ),
                  ],
                ),
              ),
          ],
        ),
          ),
        ]),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.icon, required this.label, required this.value, this.lead});
  final IconData icon;
  final Widget? lead;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          lead ?? Icon(icon, size: 18, color: RwColors.subtle),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: RwColors.subtle, fontSize: 11)),
                Text(value, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2)),
              ],
            ),
          ),
        ],
      );
}

/// Compacte regel "wat ga je lopen" (type, duur, route); tik om aan te passen.
class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.type, required this.route, required this.durationMinutes, required this.onTap});
  final TrainingType type;
  final RunRoute? route;
  final int durationMinutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: RwColors.surface,
        shape: StadiumBorder(side: BorderSide(color: RwColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Icon(Icons.directions_run, size: 20, color: RwColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${type.label} · ${Fmt.duration(durationMinutes * 60)}${route == null ? '' : ' · ${route!.name}'}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('Wijzig', style: TextStyle(color: RwColors.accent, fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right, color: RwColors.accent, size: 20),
              ],
            ),
          ),
        ),
      );
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
      height: 146,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: scores.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final s = scores[i];
          final isSel = s.start == selected;
          final isBest = s.start.day == best.start.day && s.start.hour == best.start.hour;
          final newDay = i == 0 || scores[i - 1].start.day != s.start.day;
          // Voor TalkBack: elk staafje als knop met tijd en score, in plaats van alleen het uur.
          return Semantics(
            button: true,
            selected: isSel,
            excludeSemantics: true,
            label: '${_dayLabel(s.start)} ${Fmt.time(s.start)}, score ${s.score}, ${s.verdict.toLowerCase()}${isBest ? ', beste moment' : ''}',
            child: GestureDetector(
            onTap: () => onTap(s),
            child: SizedBox(
              width: 30,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    newDay ? (_dayLabel(s.start) == 'Vandaag' ? 'nu' : _dayLabel(s.start).toLowerCase()) : '',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(fontSize: 10, color: RwColors.accent, fontWeight: FontWeight.w700),
                  ),
                  // Score boven het gekozen en het beste uur, zodat je niet hoeft te raden.
                  Text(
                    isSel || isBest ? '${s.score}' : '',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontFeatures: rwTnum,
                      fontWeight: FontWeight.w800,
                      color: isBest ? RwColors.accent : RwColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      // Staafjes groeien bij openen één voor één omhoog; het beste uur gloeit.
                      child: TweenAnimationBuilder<double>(
                        // Bij "minder beweging" (Android-toegankelijkheid) meteen op hoogte.
                        tween: Tween(begin: MediaQuery.disableAnimationsOf(context) ? (s.score.clamp(5, 100)) / 100 : 0, end: (s.score.clamp(5, 100)) / 100),
                        duration: Duration(milliseconds: 500 + 35 * i.clamp(0, 16)),
                        curve: Curves.easeOutCubic,
                        builder: (_, h, _) => FractionallySizedBox(
                          heightFactor: h,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: isBest
                                    ? [RwColors.accentLight, RwColors.accent, RwColors.accentDeep]
                                    : isSel
                                        ? [RwColors.subtle, RwColors.muted]
                                        // Kleur volgt de score: goede uren warmer, matige uren vager.
                                        : s.score >= 80
                                            ? [RwColors.accentLight.withValues(alpha: 0.75), RwColors.accent.withValues(alpha: 0.6)]
                                            : s.score >= 60
                                                ? [RwColors.border, RwColors.bar]
                                                : [RwColors.bar.withValues(alpha: 0.55), RwColors.bar.withValues(alpha: 0.45)],
                              ),
                              boxShadow: isBest ? [BoxShadow(color: RwColors.accent.withValues(alpha: 0.45), blurRadius: 12, spreadRadius: -2)] : null,
                              borderRadius: BorderRadius.circular(6),
                            ),
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
          Text(text, style: TextStyle(height: 1.5, color: RwColors.muted)),
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
                  padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [RwColors.surface, RwColors.surfaceHigh]),
                    border: Border.all(color: RwColors.hairline),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_clothingIcon(item), size: 16, color: RwColors.accentLight),
                    const SizedBox(width: 6),
                    Text(item, style: const TextStyle(fontSize: 13)),
                  ]),
                ),
            ],
          ),
          for (final tip in advice.extras)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: RwColors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tip, style: TextStyle(color: RwColors.muted, height: 1.4))),
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
              Text(Fmt.time(rain.points.first.time), style: TextStyle(fontSize: 11, color: RwColors.subtle)),
              const Spacer(),
              Text(Fmt.time(rain.points.last.time), style: TextStyle(fontSize: 11, color: RwColors.subtle)),
            ],
          ),
          const SizedBox(height: 8),
          SourcesLink(prefix: 'Bijgewerkt ${Fmt.time(rain.fetchedAt)} · '),
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
        'sun' => Icons.wb_twilight,
        'dog' => Icons.pets_outlined,
        'water' => Icons.water_drop_outlined,
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
                      Text(w.text, style: TextStyle(color: RwColors.muted, height: 1.4)),
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


/// Kompasnaaldje dat de kant op wijst waar de wind naartoe waait; draait bij openen in.
class _WindNeedle extends StatelessWidget {
  const _WindNeedle({required this.fromDegrees});
  final double fromDegrees;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: RwColors.text.withValues(alpha: 0.18))),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: fromDegrees - 140, end: fromDegrees + 180),
          duration: const Duration(milliseconds: 1400),
          curve: Curves.elasticOut,
          builder: (_, deg, child) => Transform.rotate(angle: deg * math.pi / 180, child: child),
          child: Icon(Icons.navigation, size: 13, color: RwColors.accentLight),
        ),
      );
}


/// Passend icoontje bij een kledingstuk.
IconData _clothingIcon(String item) {
  final i = item.toLowerCase();
  // Material heeft geen broek- of shirt-icoon: daarvoor een kledinghanger, die leest het rustigst.
  if (i.contains('handschoen')) return Icons.back_hand_outlined;
  if (i.contains('jack')) return Icons.dry_cleaning_outlined;
  if (i.contains('pet')) return Icons.wb_sunny_outlined;
  if (i.contains('muts')) return Icons.ac_unit;
  return Icons.checkroom;
}

/// Binnen een uur van zonsopkomst of -ondergang (gouden uur).
bool _golden(DateTime t, double lat, double lon) {
  final st = sunTimes(t, lat, lon);
  bool near(DateTime? x) => x != null && t.difference(x).inMinutes.abs() <= 60;
  return near(st.sunrise) || near(st.sunset);
}
