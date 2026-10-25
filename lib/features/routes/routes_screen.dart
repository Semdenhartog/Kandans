import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/sync_service.dart';
import '../../domain/gpx_parser.dart';
import '../../domain/route_filter.dart';
import '../../shared/first_tips.dart';
import '../../shared/widgets.dart';
import '../dashboard/dashboard_providers.dart';
import 'route_photos_strip.dart';
import 'route_undo.dart';
import 'routes_overview_map.dart';
import 'strava_routes_screen.dart';

class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> {
  /// Moment dat de lijst verscheen (voor de instap-animatie).
  final _since = DateTime.now();
  bool _importing = false;
  bool _mapView = false;

  // Zoeken en filteren (alleen zichtbaar vanaf 4 routes).
  String _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    hiddenRoutes.addListener(_onHidden);
  }

  void _onHidden() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    hiddenRoutes.removeListener(_onHidden);
    _search.dispose();
    super.dispose();
  }
  bool _favOnly = false;
  RouteLength _length = RouteLength.all;
  RouteSort _sort = RouteSort.recent;

  Widget _filters(int total, int shown) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: 'Zoek een route',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Wissen',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _query = '';
                      _search.clear();
                    }),
                  ),
            isDense: true,
          ),
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                avatar: const Icon(Icons.star_outline, size: 18),
                label: const Text('Favorieten'),
                selected: _favOnly,
                onSelected: (v) => setState(() => _favOnly = v),
              ),
              const SizedBox(width: 8),
              for (final l in RouteLength.values.skip(1)) ...[
                ChoiceChip(
                  label: Text(l.label),
                  selected: _length == l,
                  onSelected: (v) => setState(() => _length = v ? l : RouteLength.all),
                ),
                const SizedBox(width: 8),
              ],
              PopupMenuButton<RouteSort>(
                tooltip: 'Sorteren',
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (_) => [for (final o in RouteSort.values) PopupMenuItem(value: o, child: Text(o.label))],
                child: Chip(avatar: const Icon(Icons.sort, size: 18), label: Text(_sort.label)),
              ),
            ],
          ),
        ),
        if (shown != total)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('$shown van $total routes', style: const TextStyle(color: RwColors.subtle, fontSize: 12)),
          ),
      ],
    );
  }

  /// Gemiddeld tempo van recente runs, voor de geschatte duur van een route.
  double _typicalPace() {
    final runs = ref.read(activitiesProvider).when(
          data: (a) => a,
          loading: () => const <Activity>[],
          error: (_, _) => const <Activity>[],
        );
    final recent = runs.take(10).where((a) => a.paceSecondsPerKm > 0).toList();
    if (recent.isEmpty) return 360;
    return recent.fold<double>(0, (s, a) => s + a.paceSecondsPerKm) / recent.length;
  }

  Future<void> _importGpx() async {
    setState(() => _importing = true);
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null) return;
      if (!file.name.toLowerCase().endsWith('.gpx')) {
        throw GpxParseException('Kies een .gpx-bestand.');
      }
      final bytes = await file.readAsBytes();
      final route = parseGpx(
        utf8.decode(bytes, allowMalformed: true),
        fallbackName: file.name.replaceAll(RegExp(r'\.gpx$', caseSensitive: false), ''),
        estimatedPaceSecPerKm: _typicalPace(),
      );
      final id = await ref.read(repositoryProvider).addRoute(route);
      ref.invalidate(routesProvider);
      final linked = await ref.read(syncServiceProvider).autoLinkRuns().catchError((_) => 0);
      if (!mounted) return;
      showMessage(
        context,
        'Route "${route.name}" toegevoegd (${Fmt.km(route.distanceMeters, decimals: 1)}).'
        '${linked > 0 ? ' $linked eerdere ${linked == 1 ? 'run' : 'runs'} op deze route gekoppeld.' : ''}',
      );
      context.go('/routes/$id?nieuw=1');
    } on GpxParseException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(routesProvider);
    final bests = ref.watch(routeBestProvider).value ?? const {};
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Mijn routes'),
        actions: [
          IconButton(
            tooltip: _mapView ? 'Toon als lijst' : 'Toon op de kaart',
            onPressed: () => setState(() => _mapView = !_mapView),
            icon: Icon(_mapView ? Icons.view_list_outlined : Icons.map_outlined),
          ),
          IconButton(
            tooltip: 'Zelf een route tekenen',
            onPressed: () => context.go('/routes/tekenen'),
            icon: const Icon(Icons.draw_outlined),
          ),
          IconButton(
            tooltip: 'GPX importeren',
            onPressed: _importing ? null : _importGpx,
            icon: _importing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
          ),
          // Alleen als Strava gekoppeld is: je Strava-routes importeren.
          if (ref.watch(stravaConnectionProvider).value != null)
            IconButton(
              tooltip: 'Routes uit Strava',
              onPressed: () => openStravaRoutes(context),
              icon: const Icon(Icons.cloud_download_outlined),
            ),
        ],
      ),
      floatingActionButton: _mapView
          ? null
          : FloatingActionButton.extended(
        heroTag: 'route-maken',
        onPressed: () => context.go('/routes/maken'),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Route maken'),
      ),
      body: Column(children: [
        const FirstTip(id: 'routes', icon: Icons.route, text: 'Maak of teken een route en zet hem met één knop op je horloge. Bij het lopen mag je overal instappen: Kadans wijst de weg.'),
        Expanded(child: routes.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(routesProvider),
        ),
        data: (all) {
          final hidden = hiddenRoutes.value;
          final list = hidden.isEmpty ? all : all.where((r) => !hidden.contains(r.id)).toList();
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.route_outlined,
              title: 'Nog geen routes',
              message: 'Laat Kadans een rondje maken vanaf je huis of een adres, op de afstand of tijd die jij wilt. '
                  'Of teken zelf een route (potloodje rechtsboven) of importeer een GPX-bestand van je vaste rondje.',
              actionLabel: 'Route maken',
              onAction: () => context.go('/routes/maken'),
            );
          }
          if (_mapView) return RoutesOverviewMap(routes: list, bests: bests);
          final withFilters = list.length >= 4;
          final shown = withFilters
              ? filterRoutes<RunRoute>(list,
                  name: (r) => r.name,
                  meters: (r) => r.distanceMeters,
                  favorite: (r) => r.isFavorite,
                  query: _query,
                  favoritesOnly: _favOnly,
                  length: _length,
                  sort: _sort)
              : list;
          final head = withFilters ? 1 : 0;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(routesProvider);
              await ref.read(routesProvider.future).catchError((Object _) => const <RunRoute>[]);
            },
            child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: shown.length + head + (withFilters && shown.isEmpty ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (withFilters && index == 0) return _filters(list.length, shown.length);
              if (shown.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Geen routes gevonden. Pas je zoekopdracht of filter aan.',
                      textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted)),
                );
              }
              final i = index - head;
              return StaggerIn(index: i, since: _since, child: Builder(builder: (context) {
              final r = shown[i];
              return RwCard(
                onTap: () => context.go('/routes/${r.id}'),
                child: Row(
                  children: [
                    RouteThumb(polyline: r.polyline),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (r.isFavorite)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(Icons.star, size: 16, color: RwColors.accent),
                                ),
                              Expanded(
                                child: Text(
                                  r.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              Fmt.km(r.distanceMeters, decimals: 1),
                              if (r.elevationGainMeters != null) '${r.elevationGainMeters!.round()} hm',
                              r.sourceLabel,
                            ].join(' · '),
                            style: const TextStyle(color: RwColors.subtle),
                          ),
                          if (r.profileOrKmPoints.length >= 3) ...[
                            const SizedBox(height: 6),
                            // Mini-hoogteprofiel: in één oogopslag vlak of heuvelachtig.
                            SizedBox(height: 18, child: CustomPaint(size: Size.infinite, painter: _Sparkline(r.profileOrKmPoints))),
                          ],
                          if (bests[r.id] != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: RwColors.accent.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: RwColors.accent.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                'Beste moment ${Fmt.time(bests[r.id]!.start)} · ${bests[r.id]!.score}',
                                style: const TextStyle(color: RwColors.accentLight, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: RwColors.subtle),
                  ],
                ),
              );
            }));
            },
          ),
          );
        },
      )),
      ]),
    );
  }
}


/// Heel klein hoogteprofiel als vlakje (relatief: ook kleine verschillen worden zichtbaar, maar vlak blijft vlak).
class _Sparkline extends CustomPainter {
  _Sparkline(this.p);
  final List<ElevationSample> p;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = p.first.ele, hi = p.first.ele;
    for (final s in p) {
      if (s.ele < lo) lo = s.ele;
      if (s.ele > hi) hi = s.ele;
    }
    // Minstens 20 m bereik, zodat een vlakke route er ook vlak uitziet.
    final span = (hi - lo) < 20 ? 20.0 : hi - lo;
    final total = p.last.meters <= 0 ? 1.0 : p.last.meters;
    Offset at(ElevationSample s) => Offset(s.meters / total * size.width, size.height - (s.ele - lo) / span * (size.height - 2) - 1);
    final line = Path()..moveTo(at(p.first).dx, at(p.first).dy);
    for (final s in p.skip(1)) {
      final o = at(s);
      line.lineTo(o.dx, o.dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [RwColors.accent.withValues(alpha: 0.35), RwColors.accent.withValues(alpha: 0.02)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(line, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = RwColors.accent.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(covariant _Sparkline old) => old.p != p;
}
