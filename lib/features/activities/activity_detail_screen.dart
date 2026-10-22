import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/sync_service.dart';
import '../../domain/geo.dart';
import '../../domain/gpx_parser.dart';
import '../../domain/records.dart';
import '../../domain/shoes.dart';
import '../../domain/weather_correction.dart';
import '../../shared/widgets.dart';
import '../record/record_run_screen.dart';
import '../routes/route_map.dart';
import 'activities_screen.dart' show runTitle;
import 'activity_providers.dart';
import 'run_replay_screen.dart';
import 'share_run_screen.dart';
import 'photos_card.dart';
import 'elevation_card.dart';
import 'splits_card.dart';

/// Eén run: tijden, weer, records, route en delen.
class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({super.key, required this.activityId});
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
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Op welke route liep je?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                leading: const Icon(Icons.link_off, color: RwColors.danger),
                title: const Text('Losmaken van route'),
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
        body: loading ? const LoadingView() : const Center(child: Text('Deze run bestaat niet meer.')),
      );
    }
    final records = ref.watch(recordsProvider);
    final badges = records.badgesFor(a);
    final cost = weatherCost(a);
    final corrected = correctedSeconds(a);
    final routes = ref.watch(routesProvider).value ?? const <RunRoute>[];
    RunRoute? route;
    for (final r in routes) {
      if (r.id == a.routeId) route = r;
    }
    final all = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final history = a.routeId == null ? null : routeHistory(all, a.routeId!);

    final list = ListView(
        // Alles vooraf opbouwen, zodat de spring-chips elk onderdeel kunnen vinden.
        cacheExtent: 100000,
        padding: EdgeInsets.fromLTRB(16, a.hasTrack ? 0 : 4, 16, 32),
        children: [
          Text(
            runTitle(a, routeName: route?.name),
            style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 24, fontWeight: FontWeight.w800),
          ),
          Text(
            '${Fmt.dateLong(a.startedAt)} · ${Fmt.time(a.startedAt)}',
            style: const TextStyle(color: RwColors.subtle),
          ),
          const SizedBox(height: 4),
          Text(
            Fmt.km(a.distanceMeters),
            style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 48, fontWeight: FontWeight.w800, height: 1.1),
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final b in badges) RecordBadge(b)]),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: StatTile(label: 'Tijd', value: Fmt.duration(a.movingTimeSeconds))),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Tempo', value: Fmt.pace(a.paceSecondsPerKm))),
              const SizedBox(width: 8),
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
          const SizedBox(height: 12),
          if (a.id != null) _JumpChips(activity: a),
          const SizedBox(height: 12),
          RwCard(
            title: 'ROUTE',
            child: route == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (a.hasTrack) ...[
                        const Text(
                          'Dit rondje past bij geen van je routes. Bewaar het als route, dan koppelt RunWise je volgende runs hier vanzelf aan.',
                          style: TextStyle(color: RwColors.muted, height: 1.45),
                        ),
                      ] else
                        const Text(
                          'Koppel deze run aan een route. Dan zie je je tijden op die route naast elkaar, eerlijk vergeleken voor het weer.',
                          style: TextStyle(color: RwColors.muted, height: 1.45),
                        ),
                      const SizedBox(height: 12),
                      if (a.hasTrack)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: FilledButton.tonalIcon(
                            onPressed: a.id == null ? null : () => _saveAsRoute(context, ref, a),
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: const Text('Bewaar als route'),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: a.id == null ? null : () => _linkRoute(context, ref, a),
                        icon: const Icon(Icons.add_link),
                        label: const Text('Koppel aan route'),
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
                                Text(route.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                if (a.autoLinked)
                                  const Text('Automatisch herkend aan je GPS-spoor',
                                      style: TextStyle(color: RwColors.subtle, fontSize: 12)),
                              ],
                            ),
                          ),
                          TextButton(onPressed: () => _linkRoute(context, ref, a), child: const Text('Wijzig')),
                        ],
                      ),
                      const SizedBox(height: 8),
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
                        const SizedBox(height: 12),
                        Text(
                          _historyLine(a, history),
                          style: const TextStyle(color: RwColors.muted, height: 1.45),
                        ),
                      ],
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: RwColors.accent.withValues(alpha: 0.16),
                          foregroundColor: RwColors.accentLight,
                          side: BorderSide(color: RwColors.accent.withValues(alpha: 0.35)),
                        ),
                        onPressed: () => openRecorder(context, route: route),
                        icon: const Icon(Icons.replay),
                        label: const Text('Loop deze route opnieuw'),
                      ),
                      TextButton.icon(
                        onPressed: () => context.go('/routes/${route!.id}'),
                        icon: const Icon(Icons.timeline),
                        label: const Text('Al je runs op deze route'),
                      ),
                    ],
                  ),
          ),
          if (a.id != null && a.source != 'strava') ...[
            const SizedBox(height: 12),
            KeyedSubtree(key: _sectionKey(a, 'coach'), child: _CoachSummaryCard(activity: a)),
          ],
          const SizedBox(height: 12),
          RwCard(
            key: _sectionKey(a, 'weer'),
            title: 'HET WEER TIJDENS JE RUN',
            child: a.temperatureCelsius == null && a.windSpeedKmh == null
                ? const Text('Geen weergegevens bij deze run.', style: TextStyle(color: RwColors.muted))
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
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      if (cost.matters) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              Fmt.duration(corrected),
                              style: const TextStyle(
                                fontFamily: RwFonts.display, fontFeatures: rwTnum,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: RwColors.accent,
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                'bij ideaal weer · ${Fmt.pace(corrected / (a.distanceMeters / 1000))}',
                                style: const TextStyle(color: RwColors.muted),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Het weer kostte je ongeveer ${Fmt.duration(cost.totalSeconds)} (${cost.explanation}). '
                          'Zo vergelijk je runs eerlijk, ook als het hard waaide.',
                          style: const TextStyle(color: RwColors.muted, height: 1.45),
                        ),
                      ] else
                        const Text(
                          'Prima loopweer: het weer had nauwelijks invloed op je tijd.',
                          style: TextStyle(color: RwColors.muted),
                        ),
                    ],
                  ),
          ),
          if (a.id != null && (a.source == 'strava' || a.source == 'runwise' || (a.source == 'manual' && a.hasTrack))) ...[
            const SizedBox(height: 12),
            KeyedSubtree(key: _sectionKey(a, 'splits'), child: SplitsCard(activity: a)),
          ],
          if (a.id != null) ...[
            const SizedBox(height: 12),
            KeyedSubtree(key: _sectionKey(a, 'hoogte'), child: ElevationCard(activity: a)),
          ],
          if (a.id != null) ...[
            const SizedBox(height: 12),
            PhotosCard(activity: a),
          ],
          if (a.id != null) ...[
            const SizedBox(height: 12),
            _FeelCard(activity: a),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => openShareRun(context, a, route: route, badges: badges),
            icon: const Icon(Icons.ios_share),
            label: const Text('Deel je run'),
          ),
          if (a.source == 'strava') ...[
            const SizedBox(height: 12),
            const Text('Gegevens via Strava', textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
          ],
        ],
      );
    if (!a.hasTrack) {
      return Scaffold(
        appBar: AppBar(
        title: Text(Fmt.date(a.startedAt)),
        actions: [
          IconButton(
            tooltip: 'Delen',
            icon: const Icon(Icons.ios_share),
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
                  tooltip: 'Bekijk je run nog eens',
                  icon: const Icon(Icons.play_circle_outline),
                  onPressed: () => openRunReplay(context, a),
                ),
              IconButton(
                tooltip: 'Delen',
                icon: const Icon(Icons.ios_share),
                onPressed: () => openShareRun(context, a, route: route, badges: badges),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(fit: StackFit.expand, children: [
                Padding(
                  // Ruimte voor titel en knoppen, zodat ze niet over de kaartknoppen vallen.
                  padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + kToolbarHeight - 6),
                  child: RouteMap(
                  polyline: a.trackPolyline!,
                  windSpeedKmh: a.windSpeedKmh,
                  windFromDegrees: a.windDirectionDegrees,
                  compact: true,
                  interactive: false,
                  showLayerToggle: false,
                  animateIn: true,
                  ),
                ),
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xCC09090B), Color(0x0009090B), Color(0x0009090B), RwColors.background],
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
  const RecordBadge(this.label, {super.key, this.small = false});
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
    final shoes = (ref.watch(shoesProvider).value ?? const <Shoe>[]).where((s) => !s.retired).toList();
    final current = shoeFor(widget.activity, shoes);
    Widget chip(int v, String label, IconData icon) => ChoiceChip(
          avatar: Icon(icon, size: 18),
          label: Text(label),
          selected: _feel == v,
          onSelected: (on) => on ? _save(feel: v) : _save(clearFeel: true),
        );
    return RwCard(
      title: 'HOE VOELDE HET?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            chip(1, 'Zwaar', Icons.sentiment_dissatisfied_outlined),
            chip(2, 'Oké', Icons.sentiment_neutral_outlined),
            chip(3, 'Top', Icons.sentiment_very_satisfied_outlined),
          ]),
          const SizedBox(height: 12),
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
              hintText: 'Notitie, bijv. kuiten stijf of lekker gelopen',
              counterText: '',
              suffixIcon: _dirtyNote
                  ? IconButton(tooltip: 'Notitie opslaan', icon: const Icon(Icons.check), onPressed: () => _save())
                  : null,
            ),
          ),
          if (shoes.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: widget.activity.shoeId ?? current?.id,
              decoration: const InputDecoration(labelText: 'Schoen'),
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
      title: 'COACH',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (t != null)
            Text(t, style: const TextStyle(height: 1.45))
          else ...[
            const Text('Laat de coach in een paar zinnen vertellen wat goed ging, wat het weer deed en wat je volgende keer kunt doen.',
                style: TextStyle(color: RwColors.muted)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _ask,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_outlined),
              label: Text(_busy ? 'De coach kijkt…' : 'Laat de coach je run bekijken'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: RwColors.danger)),
          ],
          if (t != null) ...[
            const SizedBox(height: 6),
            const Text('Gemaakt door AI; kan fouten bevatten.', style: TextStyle(color: RwColors.subtle, fontSize: 11)),
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
        separatorBuilder: (_, _) => const SizedBox(width: 8),
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
              Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic, alignment: 0.05);
            },
          );
        },
      ),
    );
  }
}
