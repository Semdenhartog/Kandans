import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/sync_service.dart';
import '../../shared/widgets.dart';
import '../../data/services/weather_service.dart';
import '../../domain/best_efforts.dart';
import '../../domain/geo.dart';
import '../../domain/run_export.dart';
import '../../domain/run_file_import.dart';
import '../../domain/run_streams.dart';
import '../../domain/shoes.dart';
import '../../domain/run_filter.dart';
import '../../domain/weekly_load.dart';
import '../record/record_run_screen.dart';
import '../routes/route_shape.dart';
import 'activity_detail_screen.dart';
import 'activity_providers.dart';
import 'fitness_screen.dart';
import 'run_insights_screens.dart';
import 'year_story_screen.dart';

class ActivitiesScreen extends ConsumerStatefulWidget {
  const ActivitiesScreen({super.key});

  @override
  ConsumerState<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends ConsumerState<ActivitiesScreen> {
  /// Moment dat de lijst verscheen (voor de instap-animatie).
  final _since = DateTime.now();

  final _fabExtended = ValueNotifier(true);

  @override
  void dispose() {
    _fabExtended.dispose();
    super.dispose();
  }
  RunFilter _filter = const RunFilter();

  Future<void> _delete(Activity a) async {
    final ok = await confirmDialog(
      context,
      title: 'Run verwijderen?',
      message: 'Deze run van ${Fmt.date(a.startedAt)} wordt definitief verwijderd.',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteActivity(a.id!);
      ref.invalidate(activitiesProvider);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _export(bool gpx) async {
    final all = ref.read(activitiesProvider).value ?? const <Activity>[];
    // Strava-runs exporteer je in Strava zelf; hier alleen je eigen runs.
    final runs = all.where((a) => a.source != 'strava').toList();
    if (runs.isEmpty) {
      showMessage(context, 'Er zijn nog geen eigen runs om te exporteren.');
      return;
    }
    final shoes = {for (final s in ref.read(shoesProvider).value ?? const <Shoe>[]) if (s.id != null) s.id!: s.name};
    final routes = {for (final r in ref.read(routesProvider).value ?? const <RunRoute>[]) if (r.id != null) r.id!: r.name};
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final String text, name, mime;
    if (gpx) {
      if (!runs.any((a) => a.hasTrack)) {
        showMessage(context, 'Geen runs met een GPS-spoor om te exporteren.');
        return;
      }
      text = runsGpx(runs);
      name = 'runwise-sporen-$date.gpx';
      mime = 'application/gpx+xml';
    } else {
      text = runsCsv(runs, shoeNames: shoes, routeNames: routes);
      name = 'runwise-runs-$date.csv';
      mime = 'text/csv';
    }
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(Uint8List.fromList(utf8.encode(text)), mimeType: mime, name: name)],
        subject: 'Mijn runs uit RunWise',
      ));
    } catch (e) {
      if (mounted) showMessage(context, 'Exporteren is niet gelukt: ${friendlyError(e)}', error: true);
    }
  }

  /// Een run uit een bestand (horloge, andere app) toevoegen, met tijden per km.
  Future<void> _import() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null) return;
      final lower = file.name.toLowerCase();
      if (!lower.endsWith('.gpx') && !lower.endsWith('.tcx')) {
        throw RunFileException('Kies een .gpx- of .tcx-bestand.');
      }
      final run = parseRunFile(utf8.decode(await file.readAsBytes(), allowMalformed: true));
      final existing = ref.read(activitiesProvider).value ?? const <Activity>[];
      if (existing.any((a) => a.startedAt.difference(run.start).inMinutes.abs() < 20)) {
        if (mounted) showMessage(context, 'Deze run staat er al in (rond hetzelfde tijdstip).');
        return;
      }
      if (mounted) showMessage(context, 'Run importeren…');
      HourWeather? w;
      final first = run.track.isNotEmpty ? run.track.first : null;
      if (first != null) w = await ref.read(weatherServiceProvider).historical(first.lat, first.lon, run.start);
      final shoes = ref.read(shoesProvider).value ?? const <Shoe>[];
      final repo = ref.read(repositoryProvider);
      final id = await repo.addActivityReturningId(Activity(
        startedAt: run.start,
        distanceMeters: double.parse(run.distanceMeters.toStringAsFixed(1)),
        movingTimeSeconds: run.movingSeconds,
        source: 'manual',
        averageHeartRate: run.averageHeartRate,
        elevationGainMeters: run.elevationGain,
        temperatureCelsius: w?.temperature,
        feelsLikeCelsius: w?.feelsLike,
        windSpeedKmh: w?.windSpeed,
        windDirectionDegrees: w?.windDirection,
        humidityPct: w?.humidity,
        trackPolyline: run.track.length >= 2 ? encodePolyline(run.track) : null,
        shoeId: defaultShoe(shoes)?.id,
      ));
      final streams = RunStreams.fromJson(run.streams);
      await repo
          .setActivityStreams(id, run.streams, bestEfforts: streams == null ? null : bestEffortsToJson(bestEfforts(streams)))
          .catchError((Object _) {});
      if (run.track.isNotEmpty && run.elevationGain == null) repo.improveElevation(id, run.streams).ignore();
      ref.invalidate(activitiesProvider);
      await ref.read(syncServiceProvider).autoLinkRuns().catchError((_) => 0);
      if (!mounted) return;
      showMessage(context, 'Run van ${Fmt.date(run.start)} toegevoegd (${Fmt.km(run.distanceMeters, decimals: 2)}).');
      context.go('/runs/$id');
    } on RunFileException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, 'Importeren is niet gelukt: ${friendlyError(e)}', error: true);
    }
  }

  Future<void> _openFilter() async {
    final f = await showModalBottomSheet<RunFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(initial: _filter),
    );
    if (f != null) setState(() => _filter = f);
  }

  @override
  Widget build(BuildContext context) {
    final activities = ref.watch(activitiesProvider);
    final records = ref.watch(recordsProvider);
    final active = _filter.activeCount;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Mijn runs'),
        actions: [
          IconButton(
            tooltip: active == 0 ? 'Runs filteren' : 'Filters ($active aan)',
            icon: Badge(
              isLabelVisible: active > 0,
              label: Text('$active'),
              child: const Icon(Icons.filter_list),
            ),
            onPressed: _openFilter,
          ),
          IconButton(
            tooltip: 'Mijn records',
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => context.go('/runs/records'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Meer',
            onSelected: (v) {
              switch (v) {
                case 'new':
                  context.go('/runs/new');
                case 'import':
                  _import();
                case 'calendar':
                  openCalendar(context);
                case 'heatmap':
                  openHeatmap(context);
                case 'year':
                  final now = DateTime.now();
                  openYearStory(context, year: now.month == 1 ? now.year - 1 : now.year);
                case 'csv':
                  _export(false);
                case 'gpx':
                  _export(true);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'calendar', child: ListTile(leading: Icon(Icons.calendar_month_outlined), title: Text('Kalender'))),
              PopupMenuItem(value: 'heatmap', child: ListTile(leading: Icon(Icons.map_outlined), title: Text('Mijn heatmap'))),
              PopupMenuItem(value: 'year', child: ListTile(leading: Icon(Icons.insights), title: Text('Jaaroverzicht'))),
              PopupMenuDivider(),
              PopupMenuItem(value: 'new', child: ListTile(leading: Icon(Icons.edit_note), title: Text('Run met de hand toevoegen'))),
              PopupMenuItem(value: 'import', child: ListTile(leading: Icon(Icons.file_open_outlined), title: Text('Run importeren (GPX/TCX)'))),
              PopupMenuItem(value: 'csv', child: ListTile(leading: Icon(Icons.table_view_outlined), title: Text('Exporteer runs (CSV)'))),
              PopupMenuItem(value: 'gpx', child: ListTile(leading: Icon(Icons.route_outlined), title: Text('Exporteer GPS-sporen (GPX)'))),
            ],
          ),
        ],
      ),
      floatingActionButton: RwFab(
        heroTag: 'start-run',
        label: 'Start run',
        icon: Icons.play_arrow,
        extended: _fabExtended,
        onPressed: () => openRecorder(context),
      ),
      body: FabScrollWatcher(
        extended: _fabExtended,
        child: activities.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(activitiesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.directions_run,
              title: 'Nog geen runs',
              message: 'Neem een run op met Start run, voeg er een met de hand toe of koppel je horloge of Strava (tabblad Ik). Na 8 runs leert RunWise bij welk weer jij het snelst loopt.',
              actionLabel: 'Eerste run toevoegen',
              onAction: () => context.go('/runs/new'),
            );
          }
          final shown = _filter.apply(list);
          final km = shown.fold<double>(0, (s, a) => s + a.distanceMeters);
          final routeNames = {for (final r in ref.watch(routesProvider).value ?? const <RunRoute>[]) if (r.id != null) r.id!: r.name};
          // Runs per week, met een kopje per week.
          final rows = <Object>[];
          DateTime? week;
          for (final a in shown) {
            final w = weekStart(a.startedAt);
            if (w != week) {
              week = w;
              final inWeek = shown.where((x) => weekStart(x.startedAt) == w);
              rows.add((start: w, km: inWeek.fold<double>(0, (s, x) => s + x.distanceMeters / 1000), runs: inWeek.length));
            }
            rows.add(a);
          }
          return RefreshIndicator(
            onRefresh: () async {
              try {
                await ref.read(syncServiceProvider).syncAll(force: true);
              } catch (e) {
                if (context.mounted) showMessage(context, friendlyError(e), error: true);
              }
              ref.invalidate(activitiesProvider);
              await ref.read(activitiesProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: rows.length + 2,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => StaggerIn(index: i, since: _since, child: Builder(builder: (context) {
                if (i == 0) return _Overview(activities: list);
                if (i == 1) {
                  if (_filter.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _filter.isEmpty
                                ? 'ALLE RUNS · ${list.length}'
                                : '${shown.length} VAN ${list.length} RUNS · ${Fmt.km(km, decimals: 0)}',
                            style: RwText.overline,
                          ),
                        ),
                        if (!_filter.isEmpty)
                          TextButton(onPressed: () => setState(() => _filter = const RunFilter()), child: const Text('Wis filters')),
                      ],
                    ),
                  );
                }
                final row = rows[i - 2];
                if (row is ({DateTime start, double km, int runs})) {
                  return _WeekHeader(start: row.start, km: row.km, runs: row.runs);
                }
                final a = row as Activity;
                return _ActivityTile(
                  activity: a,
                  routeName: a.routeId == null ? null : routeNames[a.routeId],
                  badges: records.badgesFor(a),
                  onTap: a.id == null ? null : () => context.go('/runs/${a.id}'),
                  onDelete: () => _delete(a),
                );
              })),
            ),
          );
        },
      ),
      ),
    );
  }
}

/// Bovenaan Runs: de week in bolletjes (zoals Runna) en totalen per week, maand of jaar.
class _Overview extends StatefulWidget {
  const _Overview({required this.activities});
  final List<Activity> activities;

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  Period _period = Period.week;
  double? _goalKm;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final g = p.getDouble('week_goal_km');
      if (mounted && g != null && g > 0) setState(() => _goalKm = g);
    }).ignore();
  }

  Future<void> _setGoal() async {
    var km = (_goalKm ?? 20).round();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Weekdoel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Hoeveel kilometer wil je per week lopen?', style: TextStyle(color: RwColors.muted)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(onPressed: () => set(() => km = (km - 1).clamp(1, 300)), icon: const Icon(Icons.remove_circle_outline)),
                  Text('$km km', style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 30, fontWeight: FontWeight.w800)),
                  IconButton(onPressed: () => set(() => km = (km + 1).clamp(1, 300)), icon: const Icon(Icons.add_circle_outline)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 0), child: const Text('Geen doel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, km), child: const Text('Opslaan')),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() => _goalKm = result == 0 ? null : result.toDouble());
    final p = await SharedPreferences.getInstance();
    await p.setDouble('week_goal_km', result.toDouble());
  }

  static const _months = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
  static const _days = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];

  String _barLabel(PeriodTotal t, bool current) {
    if (current) return switch (_period) { Period.week => 'nu', Period.month => _months[t.start.month - 1], Period.year => '${t.start.year}' };
    return switch (_period) {
      Period.week => '${t.start.day}/${t.start.month}',
      Period.month => _months[t.start.month - 1],
      Period.year => '${t.start.year}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final runs = widget.activities;
    final now = DateTime.now();
    final strip = weekStrip(runs, now);
    final totals = periodTotals(runs, now, _period, count: switch (_period) { Period.week => 8, Period.month => 12, Period.year => 5 });
    final cur = totals.last;
    final check = loadCheck(runs, now);
    final streak = weekStreak(runs, now);
    final maxKm = totals.map((w) => w.km).fold<double>(0, (a, b) => a > b ? a : b);
    final weekKm = strip.fold<double>(0, (s, d) => s + d.km);
    final msg = check.message;
    final periodWord = switch (_period) { Period.week => 'deze week', Period.month => 'deze maand', Period.year => 'dit jaar' };
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('DEZE WEEK',
                    style: RwText.overline),
              ),
              Text(Fmt.km(weekKm * 1000, decimals: 1), style: const TextStyle(fontWeight: FontWeight.w700, color: RwColors.accent)),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            label: 'Deze week: ${[for (final d in strip) if (d.runs > 0) '${_days[d.date.weekday - 1]} ${d.km.toStringAsFixed(1)} km'].join(', ')}.',
            excludeSemantics: true,
            child: Row(
              children: [
                for (final d in strip)
                  Expanded(
                    child: Column(
                      children: [
                        Text(_days[d.date.weekday - 1],
                            style: TextStyle(
                                fontSize: 11,
                                color: d.isToday ? RwColors.text : RwColors.subtle,
                                fontWeight: d.isToday ? FontWeight.w700 : FontWeight.w400)),
                        const SizedBox(height: 5),
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: d.runs > 0 ? null : (d.isFuture ? Colors.transparent : RwColors.surfaceHigh),
                            // Gelopen dagen als kleine oranje munten met gloed; vandaag met een lichtrand.
                            gradient: d.runs > 0
                                ? const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [RwColors.accentLight, RwColors.accent, RwColors.accentDeep],
                                  )
                                : null,
                            boxShadow: d.runs > 0
                                ? [BoxShadow(color: RwColors.accent.withValues(alpha: 0.35), blurRadius: 10, spreadRadius: -2)]
                                : (d.isToday ? [BoxShadow(color: RwColors.accent.withValues(alpha: 0.25), blurRadius: 12)] : null),
                            border: Border.all(
                              color: d.isToday ? (d.runs > 0 ? RwColors.text : RwColors.accent) : (d.runs > 0 ? Colors.white.withValues(alpha: 0.25) : RwColors.border),
                              width: d.isToday ? 2 : 1,
                            ),
                          ),
                          child: d.runs > 0
                              ? Text(d.km >= 10 ? d.km.round().toString() : d.km.toStringAsFixed(1).replaceAll('.', ','),
                                  style: const TextStyle(color: RwColors.accentDark, fontWeight: FontWeight.w800, fontSize: 12))
                              : null,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_goalKm == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _setGoal,
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Stel een weekdoel in'),
              ),
            )
          else
            InkWell(
              onTap: _setGoal,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            weekKm >= _goalKm!
                                ? 'Weekdoel gehaald! ${Fmt.km(weekKm * 1000, decimals: 1)} van ${_goalKm!.round()} km'
                                : 'Weekdoel: ${Fmt.km(weekKm * 1000, decimals: 1)} van ${_goalKm!.round()} km',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          weekKm >= _goalKm! ? '🎉' : 'nog ${(_goalKm! - weekKm).toStringAsFixed(1).replaceAll('.', ',')} km',
                          style: const TextStyle(color: RwColors.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (weekKm / _goalKm!).clamp(0, 1).toDouble(),
                        minHeight: 8,
                        color: weekKm >= _goalKm! ? RwColors.good : RwColors.accent,
                        backgroundColor: RwColors.bar,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (streak >= 2) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.local_fire_department, color: RwColors.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      '$streak weken op rij gelopen${strip.every((d) => d.runs == 0) ? '. Loop deze week om je reeks te houden.' : '.'}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
          if (msg != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(check.tooFast ? Icons.warning_amber_rounded : Icons.info_outline,
                    color: check.tooFast ? RwColors.warning : RwColors.muted, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(msg, style: const TextStyle(color: RwColors.muted, height: 1.4))),
              ],
            ),
          ],
          const SizedBox(height: 4),
          // Slanke doorklikregel i.p.v. een grote knop: rustiger in de weekkaart.
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => openFitness(context),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Icon(Icons.show_chart, color: RwColors.accent, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text('Fitheid en vorm', style: TextStyle(fontWeight: FontWeight.w600))),
                Icon(Icons.chevron_right, color: RwColors.subtle),
              ]),
            ),
          ),
          const Divider(height: 20),
          SegmentedButton<Period>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: Period.week, label: Text('Week')),
              ButtonSegment(value: Period.month, label: Text('Maand')),
              ButtonSegment(value: Period.year, label: Text('Jaar')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: StatTile(label: 'Afstand', value: Fmt.km(cur.km * 1000, decimals: cur.km >= 100 ? 0 : 1))),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Runs', value: '${cur.runs}')),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Tijd', value: Fmt.duration(cur.seconds))),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Tempo', value: cur.paceSecPerKm <= 0 ? '–' : Fmt.pace(cur.paceSecPerKm).replaceAll(' /km', ''))),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(
            label: 'Kilometers per ${_period == Period.week ? 'week' : _period == Period.month ? 'maand' : 'jaar'}: '
                '${totals.map((w) => w.km.round()).join(', ')}. Laatste is $periodWord.',
            excludeSemantics: true,
            child: SizedBox(
              // Meegroeien met grotere letters, anders vallen de labels eraf.
              height: 60 + 36 * MediaQuery.textScalerOf(context).scale(10) / 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, w) in totals.indexed)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            FittedBox(
                              child: Text(w.km < 0.5 ? '' : '${w.km.round()}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: i == totals.length - 1 ? RwColors.accent : RwColors.subtle,
                                      fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(height: 3),
                            // Groeit bij openen omhoog; huidige periode in oranje verloop met gloed.
                            TweenAnimationBuilder<double>(
                              key: ValueKey('$_period$i'),
                              tween: Tween(begin: 3, end: maxKm <= 0 ? 3 : 3 + 54 * (w.km / maxKm)),
                              duration: Duration(milliseconds: 550 + 45 * i),
                              curve: Curves.easeOutCubic,
                              builder: (_, h, _) => Container(
                                height: h,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: i == totals.length - 1
                                        ? const [RwColors.accentLight, RwColors.accent, RwColors.accentDeep]
                                        : const [Color(0xFF34343B), RwColors.bar],
                                  ),
                                  boxShadow: i == totals.length - 1 && w.km > 0
                                      ? [BoxShadow(color: RwColors.accent.withValues(alpha: 0.4), blurRadius: 10, spreadRadius: -2)]
                                      : null,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              child: Text(_barLabel(w, i == totals.length - 1),
                                  style: const TextStyle(fontSize: 10, color: RwColors.subtle)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Filteren op afstand, bron, route, schoen, wind en notities.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});
  final RunFilter initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late RunFilter _f = widget.initial;

  static const _sources = {
    'runwise': 'Opgenomen in RunWise',
    'strava': 'Strava',
    'health_connect': 'Horloge',
    'manual': 'Met de hand',
  };

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t, style: RwText.overline),
      );

  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(routesProvider).value ?? const <RunRoute>[];
    final shoes = ref.watch(shoesProvider).value ?? const <Shoe>[];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Runs filteren', style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 20, fontWeight: FontWeight.w800)),
              _label('AFSTAND'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final b in DistanceBand.values)
                  ChoiceChip(label: Text(b.label), selected: _f.band == b, onSelected: (_) => setState(() => _f = _f.copyWith(band: b))),
              ]),
              _label('BRON'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(label: const Text('Alles'), selected: _f.source == null, onSelected: (_) => setState(() => _f = _f.copyWith(source: () => null))),
                for (final e in _sources.entries)
                  ChoiceChip(label: Text(e.value), selected: _f.source == e.key, onSelected: (_) => setState(() => _f = _f.copyWith(source: () => e.key))),
              ]),
              if (routes.isNotEmpty) ...[
                _label('ROUTE'),
                DropdownButtonFormField<String?>(
                  initialValue: routes.any((r) => r.id == _f.routeId) ? _f.routeId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Alle routes')),
                    for (final r in routes) DropdownMenuItem<String?>(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _f = _f.copyWith(routeId: () => v)),
                ),
              ],
              if (shoes.isNotEmpty) ...[
                _label('SCHOEN'),
                DropdownButtonFormField<String?>(
                  initialValue: shoes.any((s) => s.id == _f.shoeId) ? _f.shoeId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Alle schoenen')),
                    for (final s in shoes) DropdownMenuItem<String?>(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _f = _f.copyWith(shoeId: () => v)),
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Alleen met veel wind'),
                subtitle: const Text('20 km/u of meer'),
                value: _f.windyOnly,
                onChanged: (v) => setState(() => _f = _f.copyWith(windyOnly: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Alleen met gevoel of notitie'),
                value: _f.withNote,
                onChanged: (v) => setState(() => _f = _f.copyWith(withNote: v)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => Navigator.pop(context, const RunFilter()), child: const Text('Wissen')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(onPressed: () => Navigator.pop(context, _f), child: const Text('Toon runs')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String runTitle(Activity a, {String? routeName}) {
  if (routeName != null) return routeName;
  // Opgenomen zonder GPS-spoor en zonder weer: loopband.
  if (a.source == 'runwise' && !a.hasTrack && a.temperatureCelsius == null) return 'Loopbandrun';
  final h = a.startedAt.toLocal().hour;
  if (h < 6) return 'Nachtrun';
  if (h < 12) return 'Ochtendrun';
  if (h < 17) return 'Middagrun';
  if (h < 22) return 'Avondrun';
  return 'Nachtrun';
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity, required this.badges, required this.onTap, required this.onDelete, this.routeName});
  final Activity activity;
  final List<String> badges;
  final VoidCallback? onTap;
  final VoidCallback onDelete;
  final String? routeName;

  Future<void> _menu(BuildContext context) async {
    final del = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Openen'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: RwColors.danger),
            title: const Text('Verwijderen', style: TextStyle(color: RwColors.danger)),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ]),
      ),
    );
    if (del == true) {
      onDelete();
    } else if (del == false) {
      onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final weather = [
      if (a.temperatureCelsius != null) Fmt.temp(a.temperatureCelsius),
      if (a.windSpeedKmh != null) 'wind ${Fmt.wind(a.windSpeedKmh)}',
    ].join(' · ');
    final sourceIcon = switch (a.source) {
      'strava' => Icons.sync,
      'health_connect' => Icons.watch_outlined,
      'runwise' => Icons.gps_fixed,
      _ => Icons.edit_note,
    };
    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _menu(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: RwColors.surfaceHigh, borderRadius: BorderRadius.circular(14)),
                child: a.hasTrack
                    ? RouteShape(polyline: a.trackPolyline!, strokeWidth: 2.2)
                    : Icon(sourceIcon, color: RwColors.accent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(runTitle(a, routeName: routeName),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        if (a.feel != null)
                          Icon(
                            switch (a.feel) { 1 => Icons.sentiment_dissatisfied, 3 => Icons.sentiment_very_satisfied, _ => Icons.sentiment_neutral },
                            size: 18,
                            color: switch (a.feel) { 1 => RwColors.warning, 3 => RwColors.good, _ => RwColors.subtle },
                          ),
                      ],
                    ),
                    Text('${Fmt.date(a.startedAt)} · ${Fmt.time(a.startedAt)}${weather.isEmpty ? '' : ' · $weather'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: RwColors.subtle, fontSize: 12)),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          _TileStat(Fmt.km(a.distanceMeters).replaceAll(' km', ''), 'km'),
                          _TileStat(Fmt.pace(a.paceSecondsPerKm).replaceAll(' /km', ''), '/km'),
                          _TileStat(Fmt.duration(a.movingTimeSeconds), ''),
                        ],
                      ),
                    ),
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 4, children: [for (final b in badges.take(2)) RecordBadge(b, small: true)]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileStat extends StatelessWidget {
  const _TileStat(this.value, this.unit);
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: value, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w700, fontSize: 18)),
          if (unit.isNotEmpty) TextSpan(text: ' $unit', style: const TextStyle(color: RwColors.subtle, fontSize: 12)),
        ])),
      );
}

/// Kopje boven de runs van één week.
class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.start, required this.km, required this.runs});
  final DateTime start;
  final double km;
  final int runs;

  @override
  Widget build(BuildContext context) {
    final thisWeek = weekStart(DateTime.now());
    final diff = (thisWeek.difference(start).inHours / 24 / 7).round();
    final label = diff == 0 ? 'DEZE WEEK' : (diff == 1 ? 'VORIGE WEEK' : 'WEEK VAN ${Fmt.date(start).toUpperCase()}');
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: RwText.overline),
          ),
          Text('${km.toStringAsFixed(1).replaceAll('.', ',')} km · $runs ${runs == 1 ? 'run' : 'runs'}',
              style: const TextStyle(fontSize: 13, color: RwColors.subtle)),
        ],
      ),
    );
  }
}
