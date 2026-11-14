import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/sync_service.dart';
import '../../domain/geo.dart';
import '../../domain/run_streams.dart';
import '../../domain/gpx_parser.dart';
import '../../domain/records.dart';
import '../../domain/shoes.dart';
import '../../domain/weather_correction.dart';
import '../../domain/run_title.dart';
import '../../shared/widgets.dart';
import '../record/record_run_screen.dart';
import '../routes/route_map.dart';
import 'activities_screen.dart' show runTitle;
import 'activity_providers.dart';
import 'run_replay_screen.dart';
import 'route_anim_screen.dart';
import 'share_run_screen.dart';
import 'gps_spike_screen.dart';
import '../community/share_to_feed.dart';
import 'hindsight_card.dart';
import 'hydration_card.dart';
import 'hrr_card.dart';
import 'markers_card.dart';
import 'segments_screen.dart' show SegmentEffortsCard;
import 'photos_card.dart';
import 'elevation_card.dart';
import 'splits_card.dart';
import 'trim_run_screen.dart';

/// Eén run: tijden, weer, records, route en delen.
class ActivityDetailScreen extends ConsumerWidget {
  ActivityDetailScreen({super.key, required this.activityId});
  final String activityId;

  Future<void> _linkRoute(BuildContext context, WidgetRef ref, Activity a) async {
    final routes = await ref.read(routesProvider.future);
    if (!context.mounted) return;
    if (routes.isEmpty) {
      showMessage(context, 'Je hebt nog geen routes. Maak er een bij Routes.');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: RwColors.surface,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr('Op welke route liep je?'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final r in routes)
              ListTile(
                leading: Icon(
                  (r.distanceMeters - a.distanceMeters).abs() < 600 ? Icons.check_circle_outline : Icons.route_outlined,
                  color: (r.distanceMeters - a.distanceMeters).abs() < 600 ? RwColors.good : RwColors.subtle,
                ),
                title: Text(r.name),
                subtitle: Text(Fmt.km(r.distanceMeters, decimals: 1)),
                selected: r.id == a.routeId,
                onTap: () => Navigator.pop(ctx, r.id),
              ),
            if (a.routeId != null)
              ListTile(
                leading: Icon(Icons.link_off, color: RwColors.danger),
                title: Text(tr('Losmaken van route')),
                onTap: () => Navigator.pop(ctx, ''),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    try {
      await ref.read(repositoryProvider).setActivityRoute(a.id!, picked.isEmpty ? null : picked);
      ref.invalidate(activitiesProvider);
      if (context.mounted) showMessage(context, picked.isEmpty ? 'Run losgemaakt van de route.' : 'Run gekoppeld aan de route.');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  /// Maakt van het GPS-spoor van deze run een nieuwe route en koppelt de run eraan.
  Future<void> _saveAsRoute(BuildContext context, WidgetRef ref, Activity a) async {
    try {
      final pts = decodePolyline(a.trackPolyline!);
      final km = (a.distanceMeters / 1000).toStringAsFixed(1).replaceAll('.', ',');
      final route = buildRoute(
        pts,
        name: 'Rondje $km km (${Fmt.date(a.startedAt)})',
        source: a.source == 'strava' ? 'strava_import' : 'drawn',
        estimatedPaceSecPerKm: a.paceSecondsPerKm > 0 ? a.paceSecondsPerKm : 360,
      );
      final repo = ref.read(repositoryProvider);
      final id = await repo.addRoute(route);
      await repo.setActivityRoute(a.id!, id);
      ref.invalidate(routesProvider);
      ref.invalidate(activitiesProvider);
      final more = await ref.read(syncServiceProvider).autoLinkRuns().catchError((_) => 0);
      if (context.mounted) {
        showMessage(
          context,
          more > 0
              ? 'Route bewaard. Ook $more andere ${more == 1 ? 'run' : 'runs'} op dit rondje gekoppeld.'
              : 'Route bewaard en deze run gekoppeld.',
        );
      }
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(activitiesProvider).isLoading;
    final a = ref.watch(activityProvider(activityId));
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: loading ? LoadingView() : Center(child: Text(tr('Deze run bestaat niet meer.'))),
      );
    }
    final records = ref.watch(recordsProvider);
    final badges = records.badgesFor(a);
    final cost = weatherCost(a);
    final corrected = correctedSeconds(a);
    final routes = ref.watch(routesProvider).value ?? <RunRoute>[];
    RunRoute? route;
    for (final r in routes) {
      if (r.id == a.routeId) route = r;
    }
    final all = ref.watch(activitiesProvider).value ?? <Activity>[];
    final history = a.routeId == null ? null : routeHistory(all, a.routeId!);

    final list = ListView(
        // Alles vooraf opbouwen, zodat de spring-chips elk onderdeel kunnen vinden.
        cacheExtent: 100000,
        padding: EdgeInsets.fromLTRB(16, a.hasTrack ? 0 : 4, 16, 32),
        children: [
          // Titel: één tik om te wijzigen (punt 34), met slimme voorstellen.
          InkWell(
            borderRadius: BorderRadius.circular(RwRadius.s),
            onTap: a.id == null ? null : () => _editTitle(context, ref, a, route?.name),
            child: Row(children: [
              Flexible(
                child: Text(
                  runTitle(a, routeName: route?.name),
                  style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.edit_outlined, size: 18, color: RwColors.subtle),
            ]),
          ),
          Text(
            '${Fmt.dateLong(a.startedAt)} · ${Fmt.time(a.startedAt)}',
            style: TextStyle(color: RwColors.subtle),
          ),
          SizedBox(height: 4),
          Text(
            Fmt.km(a.distanceMeters),
            style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 48, fontWeight: FontWeight.w800, height: 1.1),
          ),
          if (badges.isNotEmpty) ...[
            SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final b in badges) RecordBadge(b)]),
          ],
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: StatTile(label: tr('Tijd'), value: Fmt.duration(a.movingTimeSeconds))),
              SizedBox(width: 8),
              Expanded(child: StatTile(label: tr('Tempo'), value: Fmt.pace(a.paceSecondsPerKm))),
              SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: a.averageHeartRate != null ? 'Hartslag' : 'Hoogte',
                  value: a.averageHeartRate != null
                      ? '${a.averageHeartRate}'
                      : (a.elevationGainMeters == null ? '–' : '${a.elevationGainMeters!.round()} m'),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          if (a.id != null) _JumpChips(activity: a),
          SizedBox(height: 12),
          RwCard(
            title: tr('ROUTE'),
            child: route == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (a.hasTrack) ...[
                        Text(tr('Dit rondje past bij geen van je routes. Bewaar het als route, dan koppelt Kadans je volgende runs hier vanzelf aan.'),
                          style: TextStyle(color: RwColors.muted, height: 1.45),
                        ),
                      ] else
                        Text(tr('Koppel deze run aan een route. Dan zie je je tijden op die route naast elkaar, eerlijk vergeleken voor het weer.'),
                          style: TextStyle(color: RwColors.muted, height: 1.45),
                        ),
                      SizedBox(height: 12),
                      if (a.hasTrack)
                        Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: FilledButton.tonalIcon(
                            onPressed: a.id == null ? null : () => _saveAsRoute(context, ref, a),
                            icon: Icon(Icons.bookmark_add_outlined),
                            label: Text(tr('Bewaar als route')),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: a.id == null ? null : () => _linkRoute(context, ref, a),
                        icon: Icon(Icons.add_link),
                        label: Text(tr('Koppel aan route')),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(route.name, style: TextStyle(fontWeight: FontWeight.w700)),
                                if (a.autoLinked)
                                  Text(tr('Automatisch herkend aan je GPS-spoor'),
                                      style: TextStyle(color: RwColors.subtle, fontSize: 12)),
                              ],
                            ),
                          ),
                          TextButton(onPressed: () => _linkRoute(context, ref, a), child: Text(tr('Wijzig'))),
                        ],
                      ),
                      SizedBox(height: 8),
                      SizedBox(
                        height: 180,
                        child: RouteMap(
                          polyline: route.polyline,
                          windSpeedKmh: a.windSpeedKmh,
                          windFromDegrees: a.windDirectionDegrees,
                          compact: true,
                          interactive: false,
                          showLayerToggle: false,
                          onExpand: () => context.go('/routes/${route!.id}'),
                        ),
                      ),
                      if (history != null && history.runs.length > 1) ...[
                        SizedBox(height: 12),
                        Text(
                          _historyLine(a, history),
                          style: TextStyle(color: RwColors.muted, height: 1.45),
                        ),
                      ],
                      SizedBox(height: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: RwColors.accent.withValues(alpha: 0.16),
                          foregroundColor: RwColors.accent,
                          side: BorderSide(color: RwColors.accent.withValues(alpha: 0.35)),
                        ),
                        onPressed: () => openRecorder(context, route: route),
                        icon: Icon(Icons.replay),
                        label: Text(tr('Loop deze route opnieuw')),
                      ),
                      TextButton.icon(
                        onPressed: () => context.go('/routes/${route!.id}'),
                        icon: Icon(Icons.timeline),
                        label: Text(tr('Al je runs op deze route')),
                      ),
                    ],
                  ),
          ),
          if (a.id != null && !a.viaStrava) ...[
            SizedBox(height: 12),
            KeyedSubtree(key: _sectionKey(a, 'coach'), child: _CoachSummaryCard(activity: a)),
          ],
          if (HindsightCard.applies(a)) HindsightCard(key: ValueKey('hindsight-${a.id}'), activity: a),
          SizedBox(height: 12),
          RwCard(
            key: _sectionKey(a, 'weer'),
            title: tr('HET WEER TIJDENS JE RUN'),
            child: a.temperatureCelsius == null && a.windSpeedKmh == null
                ? Text(tr('Geen weergegevens bij deze run.'), style: TextStyle(color: RwColors.muted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          if (a.temperatureCelsius != null) Fmt.temp(a.temperatureCelsius),
                          if (a.feelsLikeCelsius != null) 'voelt als ${Fmt.temp(a.feelsLikeCelsius)}',
                          if (a.windSpeedKmh != null)
                            'wind ${Fmt.wind(a.windSpeedKmh)}${a.windDirectionDegrees == null ? '' : ' uit het ${Fmt.compass(a.windDirectionDegrees!)}'}',
                        ].join(' · '),
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 12),
                      if (cost.matters) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              Fmt.duration(corrected),
                              style: TextStyle(
                                fontFamily: RwFonts.display, fontFeatures: rwTnum,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: RwColors.accent,
                                height: 1,
                              ),
                            ),
                            SizedBox(width: 8),
                            // Flexible: bij grote letters loopt de tekst door op de volgende regel.
                            Flexible(
                              child: Padding(
                                padding: EdgeInsets.only(bottom: 3),
                                child: Text(
                                  'bij ideaal weer · ${Fmt.pace(corrected / (a.distanceMeters / 1000))}',
                                  style: TextStyle(color: RwColors.muted),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Het weer kostte je ongeveer ${Fmt.duration(cost.totalSeconds)} (${cost.explanation}). '
                          'Zo vergelijk je runs eerlijk, ook als het hard waaide.',
                          style: TextStyle(color: RwColors.muted, height: 1.45),
                        ),
                      ] else
                        Text(tr('Prima loopweer: het weer had nauwelijks invloed op je tijd.'),
                          style: TextStyle(color: RwColors.muted),
                        ),
                    ],
                  ),
          ),
          if (a.id != null && (a.source == 'strava' || a.source == 'runwise' || (a.source == 'manual' && a.hasTrack))) ...[
            SizedBox(height: 12),
            KeyedSubtree(key: _sectionKey(a, 'splits'), child: SplitsCard(activity: a)),
          ],
          if (a.id != null) ...[
            SizedBox(height: 12),
            KeyedSubtree(key: _sectionKey(a, 'hoogte'), child: ElevationCard(activity: a)),
          ],
          // Verdieping (vocht, hartslagherstel, markeringen, stukken) achter één kopje: de run zelf blijft overzichtelijk.
          ...() {
            final extra = <Widget>[
              if (HydrationCard.applies(a)) HydrationCard(activity: a),
              if (a.averageHeartRate != null && a.source == 'runwise') HrrCard(activity: a),
              if (a.id != null && a.source == 'runwise') MarkersCard(activity: a),
              if (a.id != null && a.source == 'runwise') SegmentEffortsCard(activity: a),
            ];
            return extra.isEmpty ? <Widget>[] : <Widget>[SizedBox(height: 12), _MoreAnalysis(children: extra)];
          }(),
          if (a.id != null) ...[
            SizedBox(height: 12),
            PhotosCard(activity: a),
          ],
          if (a.id != null) ...[
            SizedBox(height: 12),
            _FeelCard(activity: a),
          ],
          GpsSpikeCard(activity: a),
          SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => openShareRun(context, a, route: route, badges: badges),
            icon: Icon(Icons.ios_share),
            label: Text(tr('Deel je run')),
          ),
          if (a.hasTrack || route != null) ...[
            SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => openRouteAnim(context, a, route: route),
              icon: Icon(Icons.movie_creation_outlined),
              label: Text(tr('Bewegende video van je route')),
            ),
          ],
          ShareToFeedButton(activity: a),
          // Alleen eigen opnames: die hebben het verloop per seconde dat nodig is om te knippen.
          if (a.source == 'runwise' && a.id != null) ...[
            SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => openTrimRun(context, a),
              icon: Icon(Icons.content_cut),
              label: Text(tr('Run bijsnijden')),
            ),
            if (ref.watch(stravaConnectionProvider).value != null) ...[
              SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await ref.read(syncServiceProvider).uploadToStrava(a.id!);
                    if (context.mounted) showMessage(context, tr('Verstuurd. Over een minuut staat je run op Strava.'));
                  } catch (e) {
                    if (context.mounted) showMessage(context, friendlyError(e), error: true);
                  }
                },
                icon: Icon(Icons.upload_outlined),
                label: Text(tr('Naar Strava sturen')),
              ),
            ],
          ],
          if (a.viaStrava) ...[
            SizedBox(height: 12),
            Text(a.source == 'strava' ? 'Gegevens via Strava' : 'Gegevens van de Strava-app (via Health Connect)',
                textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
          ],
        ],
      );
    if (!a.hasTrack) {
      return Scaffold(
        appBar: AppBar(
        title: Text(Fmt.date(a.startedAt)),
        actions: [
          IconButton(
            tooltip: tr('Delen'),
            icon: Icon(Icons.ios_share),
            onPressed: () => openShareRun(context, a, route: route, badges: badges),
          ),
        ],
      ),
        body: list,
      );
    }
    // Met GPS-spoor: de kaart als grote kop die bij scrollen langzamer meeschuift (parallax)
    // en onderin wegvloeit in de achtergrond.
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 300,
            backgroundColor: RwColors.background,
            surfaceTintColor: Colors.transparent,
            title: Text(Fmt.date(a.startedAt)),
            actions: [
              if (a.hasTrack)
                IconButton(
                  tooltip: tr('Bekijk je run nog eens'),
                  icon: Icon(Icons.play_circle_outline),
                  onPressed: () => openRunReplay(context, a),
                ),
              IconButton(
                tooltip: tr('Delen'),
                icon: Icon(Icons.ios_share),
                onPressed: () => openShareRun(context, a, route: route, badges: badges),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              stretchModes: [StretchMode.zoomBackground],
              background: Stack(fit: StackFit.expand, children: [
                Padding(
                  // Ruimte voor titel en knoppen, zodat ze niet over de kaartknoppen vallen.
                  padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + kToolbarHeight - 6),
                  // Routelijn gekleurd op tempo zodra de tijden binnen zijn (zoals Strava), anders effen goud.
                  child: Consumer(builder: (context, ref, _) {
                    final json = a.id == null ? null : ref.watch(activityStreamsProvider(a.id!)).value;
                    final s = json == null ? null : RunStreams.fromJson(json);
                    final colored = s == null ? <({List<LatLng> points, Color color})>[] : coloredRunSegments(s);
                    return Stack(fit: StackFit.expand, children: [
                      RouteMap(
                        polyline: a.trackPolyline!,
                        windSpeedKmh: a.windSpeedKmh,
                        windFromDegrees: a.windDirectionDegrees,
                        compact: true,
                        interactive: false,
                        showLayerToggle: false,
                        animateIn: true,
                        // Windlegenda alleen zonder tempokleuren (anders klopt de legenda niet bij de lijn).
                        showLegend: colored.isEmpty,
                        colorSegments: colored.isEmpty ? null : colored,
                      ),
                      if (colored.isNotEmpty) Positioned(left: 12, bottom: 34, child: IgnorePointer(child: PaceLegend())),
                    ]);
                  }),
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [RwColors.background.withValues(alpha: 0.8), RwColors.background.withValues(alpha: 0), RwColors.background.withValues(alpha: 0), RwColors.background],
                        stops: [0, 0.28, 0.62, 1],
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
        body: list,
      ),
    );
  }

  static String _historyLine(Activity a, RouteHistory h) {
    final n = h.runs.length;
    final pos = h.runs.indexWhere((r) => sameRun(r.activity, a));
    final rank = ([...h.runs]..sort((x, y) => x.correctedSeconds.compareTo(y.correctedSeconds)))
            .indexWhere((r) => sameRun(r.activity, a)) +
        1;
    final which = pos < 0 ? '' : 'Je ${n - pos}e keer op deze route. ';
    return '$which'
        '${rank == 1 ? 'Gecorrigeerd voor het weer is dit je snelste keer ooit!' : 'Gecorrigeerd voor het weer staat deze run op plek $rank van $n.'}';
  }
}

/// Labeltje voor een record.
class RecordBadge extends StatelessWidget {
  RecordBadge(this.label, {super.key, this.small = false});
  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final weather = label.startsWith('Weer');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 10, vertical: small ? 2 : 5),
      decoration: BoxDecoration(
        color: (weather ? RwColors.good : RwColors.accent).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: (weather ? RwColors.good : RwColors.accent).withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(weather ? Icons.air : Icons.emoji_events_outlined, size: small ? 12 : 15, color: weather ? RwColors.good : RwColors.accent),
          SizedBox(width: small ? 3 : 5),
          Text(
            label,
            style: TextStyle(
              fontSize: small ? 11 : 13,
              fontWeight: FontWeight.w700,
              color: weather ? RwColors.good : RwColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hoe voelde het, een notitie en welke schoen. De coach gebruikt dit ook.
class _FeelCard extends ConsumerStatefulWidget {
  const _FeelCard({required this.activity});
  final Activity activity;

  @override
  ConsumerState<_FeelCard> createState() => _FeelCardState();
}

class _FeelCardState extends ConsumerState<_FeelCard> {
  late final _note = TextEditingController(text: widget.activity.note ?? '');
  late int? _feel = widget.activity.feel;
  bool _dirtyNote = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save({int? feel, bool clearFeel = false}) async {
    final a = widget.activity;
    final next = clearFeel ? null : (feel ?? _feel);
    setState(() {
      _feel = next;
      _dirtyNote = false;
    });
    try {
      await ref.read(repositoryProvider).setActivityFeel(a.id!, feel: next, note: _note.text);
      ref.invalidate(activitiesProvider);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _setShoe(String? id) async {
    try {
      await ref.read(repositoryProvider).setActivityShoe(widget.activity.id!, id);
      ref.invalidate(activitiesProvider);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shoes = (ref.watch(shoesProvider).value ?? <Shoe>[]).where((s) => !s.retired).toList();
    final current = shoeFor(widget.activity, shoes);
    Widget chip(int v, String label, IconData icon) => ChoiceChip(
          avatar: Icon(icon, size: 18),
          label: Text(label),
          selected: _feel == v,
          onSelected: (on) => on ? _save(feel: v) : _save(clearFeel: true),
        );
    return RwCard(
      title: tr('HOE VOELDE HET?'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            chip(1, 'Zwaar', Icons.sentiment_dissatisfied_outlined),
            chip(2, 'Oké', Icons.sentiment_neutral_outlined),
            chip(3, 'Top', Icons.sentiment_very_satisfied_outlined),
          ]),
          SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 500,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (!_dirtyNote) setState(() => _dirtyNote = true);
            },
            decoration: InputDecoration(
              hintText: tr('Notitie, bijv. kuiten stijf of lekker gelopen'),
              counterText: '',
              suffixIcon: _dirtyNote
                  ? IconButton(tooltip: tr('Notitie opslaan'), icon: Icon(Icons.check), onPressed: () => _save())
                  : null,
            ),
          ),
          if (shoes.isNotEmpty) ...[
            SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: widget.activity.shoeId ?? current?.id,
              decoration: InputDecoration(labelText: tr('Schoen')),
              items: [
                for (final s in shoes) DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) => _setShoe(v),
            ),
          ],
        ],
      ),
    );
  }
}

/// Korte analyse van de coach (zoals Strava's Athlete Intelligence), met je schema en het weer erbij.
class _CoachSummaryCard extends ConsumerStatefulWidget {
  const _CoachSummaryCard({required this.activity});
  final Activity activity;

  @override
  ConsumerState<_CoachSummaryCard> createState() => _CoachSummaryCardState();
}

class _CoachSummaryCardState extends ConsumerState<_CoachSummaryCard> {
  late String? _text = widget.activity.aiSummary;
  bool _busy = false;
  String? _error;

  Future<void> _ask() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await ref.read(repositoryProvider).summarizeRun(widget.activity.id!);
      if (!mounted) return;
      setState(() => _text = t);
      ref.invalidate(activitiesProvider);
    } on PaywallRequired {
      if (mounted) context.push('/premium');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _text;
    return RwCard(
      title: tr('COACH'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (t != null)
            Text(t, style: TextStyle(height: 1.45))
          else ...[
            Text(tr('Laat de coach in een paar zinnen vertellen wat goed ging, wat het weer deed en wat je volgende keer kunt doen.'),
                style: TextStyle(color: RwColors.muted)),
            SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _ask,
              icon: _busy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.auto_awesome_outlined),
              label: Text(_busy ? 'De coach kijkt…' : 'Laat de coach je run bekijken'),
            ),
          ],
          if (_error != null) ...[
            SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: RwColors.danger)),
          ],
          if (t != null) ...[
            SizedBox(height: 6),
            Text(tr('Gemaakt door AI; kan fouten bevatten.'), style: TextStyle(color: RwColors.subtle, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}


/// Vaste sleutels per run en onderdeel, om ernaartoe te kunnen springen.
final _keys = <String, GlobalKey>{};
GlobalKey _sectionKey(Activity a, String name) => _keys.putIfAbsent('${a.id}-$name', () => GlobalKey(debugLabel: name));

/// Spring-chips: in één tik naar splits, hoogte, weer of coach (handig in een lange pagina).
class _JumpChips extends StatelessWidget {
  const _JumpChips({required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context) {
    const items = [
      ('splits', 'Splits', Icons.format_list_numbered),
      ('hoogte', 'Hoogte', Icons.terrain_outlined),
      ('weer', 'Weer', Icons.air),
      ('coach', 'Coach', Icons.auto_awesome_outlined),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (id, label, icon) = items[i];
          return ActionChip(
            avatar: Icon(icon, size: 16, color: RwColors.accentLight),
            label: Text(label),
            onPressed: () {
              final ctx = _sectionKey(activity, id).currentContext;
              if (ctx == null) {
                showMessage(context, '$label is er voor deze run niet.');
                return;
              }
              HapticFeedback.selectionClick();
              Scrollable.ensureVisible(ctx, duration: Duration(milliseconds: 500), curve: Curves.easeOutCubic, alignment: 0.05);
            },
          );
        },
      ),
    );
  }
}

/// Inklapbaar kopje "Meer analyse" in een run: standaard dicht, zodat de run zelf overzichtelijk blijft.
class _MoreAnalysis extends StatefulWidget {
  const _MoreAnalysis({required this.children});
  final List<Widget> children;

  @override
  State<_MoreAnalysis> createState() => _MoreAnalysisState();
}

class _MoreAnalysisState extends State<_MoreAnalysis> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
          label: Text(_open ? 'Minder analyse' : 'Meer analyse (${widget.children.length})'),
        ),
        if (_open) ...widget.children,
      ],
    );
  }
}


/// Titel van een run wijzigen: eigen tekst of een van de voorstellen.
Future<void> _editTitle(BuildContext context, WidgetRef ref, Activity a, String? routeName) async {
  final auto = smartTitle(a, routeName: routeName, fill: (t, v) => trf(t, v));
  final t = a.startedAt.toLocal();
  final part = t.hour < 12 ? tr('Ochtendrun') : (t.hour < 18 ? tr('Middagrun') : tr('Avondrun'));
  final km = (a.distanceMeters / 1000).toStringAsFixed(a.distanceMeters < 10000 ? 1 : 0).replaceAll('.', ',');
  final suggestions = <String>{auto, '$part $km km', if (routeName != null && routeName.trim().isNotEmpty) routeName.trim()}.toList();
  final c = TextEditingController(text: (a.title ?? '').trim().isEmpty ? auto : a.title!.trim());
  final picked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Titel van je run'), style: RwText.title),
        SizedBox(height: 12),
        TextField(controller: c, autofocus: true, maxLength: 80, textCapitalization: TextCapitalization.sentences),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in suggestions) ActionChip(label: Text(s), onPressed: () => c.text = s),
        ]),
        SizedBox(height: 16),
        Row(children: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text(tr('Automatisch'))),
          Spacer(),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('Opslaan'))),
        ]),
      ]),
    ),
  );
  if (picked == null || a.id == null) return;
  try {
    await ref.read(repositoryProvider).setActivityTitle(a.id!, picked == auto ? null : picked);
    ref.invalidate(activitiesProvider);
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
  }
}
