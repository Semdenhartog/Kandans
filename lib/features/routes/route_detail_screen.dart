import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/poi_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/geo.dart';
import '../../domain/poi.dart';
import '../../domain/route_direction.dart';
import '../../domain/records.dart';
import '../../domain/route_geometry.dart';
import '../../domain/start_time_scoring.dart';
import '../../shared/widgets.dart';
import '../record/record_run_screen.dart';
import 'elevation_profile.dart';
import 'route_map.dart';
import 'route_photos_strip.dart';
import 'route_map_screen.dart';
import 'turn_list_card.dart';
import 'watch_export.dart';

/// Huidig weer bij de start van een route.
final _routeWeatherProvider = FutureProvider.family<HourWeather?, String>((ref, routeId) async {
  final route = await ref.watch(routeDetailProvider(routeId).future);
  final f = await ref
      .watch(weatherServiceProvider)
      .forecast(route.startLatitude, route.startLongitude, days: 1);
  return f.at(DateTime.now());
});

class RouteDetailScreen extends ConsumerWidget {
  const RouteDetailScreen({super.key, required this.routeId, this.isNew = false});
  final String routeId;

  /// Net gemaakt of geïmporteerd: dan bieden we meteen aan om hem op je horloge te zetten.
  final bool isNew;

  Future<void> _toggleFavorite(BuildContext context, WidgetRef ref, RunRoute r) async {
    try {
      await ref.read(repositoryProvider).setFavorite(r.id!, !r.isFavorite);
      ref.invalidate(routeDetailProvider(routeId));
      ref.invalidate(routesProvider);
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, RunRoute r) async {
    final ok = await confirmDialog(
      context,
      title: 'Route verwijderen?',
      message: '"${r.name}" wordt definitief verwijderd. Runs op deze route blijven bewaard.',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteRoute(r.id!);
      ref.invalidate(routesProvider);
      if (context.mounted) context.go('/routes');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeDetailProvider(routeId));
    final weather = ref.watch(_routeWeatherProvider(routeId));

    return route.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(routeDetailProvider(routeId)),
        ),
      ),
      data: (r) {
        final w = weather.when(data: (w) => w, loading: () => null, error: (_, _) => null);
        final track = decodePolyline(r.polyline);
        final segments = trackSegments(track);
        final rw = (w != null && w.windDirection != null)
            ? routeWind(segments, w.windSpeed, w.windDirection!)
            : null;

        final advice = w == null ? null : adviseDirection(track, w.windSpeed, w.windDirection);

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'run-route',
            onPressed: () => openRecorder(context, route: r),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Loop deze route'),
          ),
          appBar: AppBar(
            title: Text(r.name, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: r.isFavorite ? 'Geen favoriet meer' : 'Favoriet maken',
                icon: Icon(r.isFavorite ? Icons.star : Icons.star_border,
                    color: r.isFavorite ? RwColors.accent : null),
                onPressed: () => _toggleFavorite(context, ref, r),
              ),
              IconButton(
                tooltip: 'Naar je horloge',
                icon: const Icon(Icons.watch_outlined),
                onPressed: () => sendRouteToWatch(context, r, onRunWithPhone: () => openRecorder(context, route: r)),
              ),
              IconButton(
                tooltip: 'Verwijderen',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, ref, r),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (isNew) ...[
                _NewRouteCard(route: r),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Expanded(child: StatTile(label: 'Afstand', value: Fmt.km(r.distanceMeters))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Hoogtemeters',
                      value: r.elevationGainMeters == null ? '–' : '${r.elevationGainMeters!.round()} m',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Verwacht',
                      value: r.estimatedDurationSeconds == null
                          ? '–'
                          : Fmt.duration(r.estimatedDurationSeconds!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _WatchButton(route: r),
              const SizedBox(height: 12),
              _MapAndProfile(
                route: r,
                windSpeedKmh: w?.windSpeed,
                windFromDegrees: w?.windDirection,
                reversed: advice?.reverse ?? false,
                directionLabel: advice?.bestLabel,
              ),
              const SizedBox(height: 12),
              RwCard(
                title: 'WIND OP DEZE ROUTE, NU',
                child: w == null
                    ? const Text('Weer wordt geladen…', style: TextStyle(color: RwColors.muted))
                    : Text(
                        rw == null
                            ? 'Wind ${Fmt.wind(w.windSpeed)}.'
                            : 'Wind ${Fmt.wind(w.windSpeed)} uit het ${Fmt.compass(w.windDirection!)}. '
                                'Gemiddeld ${rw.headwindAvg.round()} km/u tegenwind en '
                                '${rw.tailwindAvg.round()} km/u rugwind. '
                                '${rw.secondHalfHead - rw.firstHalfHead > 4 ? 'De terugweg is het zwaarst.' : rw.firstHalfHead - rw.secondHalfHead > 4 ? 'De heenweg is het zwaarst.' : ''}',
                        style: const TextStyle(height: 1.5),
                      ),
              ),
              if (advice != null) ...[
                const SizedBox(height: 12),
                RwCard(
                  title: 'LOOPRICHTING, NU',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(advice.bestLabel == 'linksom' ? Icons.rotate_left : Icons.rotate_right,
                          color: RwColors.accent),
                      const SizedBox(width: 10),
                      Expanded(child: Text(advice.text, style: const TextStyle(height: 1.5))),
                    ],
                  ),
                ),
              ],
              if (track.length > 1) ...[
                const SizedBox(height: 12),
                TurnListCard(track: track),
              ],
              if (r.polyline.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SurfaceCard(routeId: routeId, polyline: r.polyline),
              ],
              const SizedBox(height: 12),
              _RouteHistoryCard(routeId: routeId),
              const SizedBox(height: 12),
              if (r.points.length > 1)
                RwCard(
                  title: 'PER KILOMETER',
                  child: Column(
                    children: [
                      for (final p in r.points)
                        _KmRow(point: p, weather: w),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _KmRow extends StatelessWidget {
  const _KmRow({required this.point, required this.weather});
  final RoutePoint point;
  final HourWeather? weather;

  @override
  Widget build(BuildContext context) {
    final b = point.bearing;
    String windText = '';
    Color color = RwColors.subtle;
    final w = weather;
    if (b != null && w != null && w.windDirection != null) {
      final comp = w.windSpeed * math.cos((w.windDirection! - b) * math.pi / 180);
      if (comp > 3) {
        windText = 'tegenwind ${comp.round()}';
        color = RwColors.warning;
      } else if (comp < -3) {
        windText = 'rugwind ${(-comp).round()}';
        color = RwColors.good;
      } else {
        windText = 'zijwind';
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text('km ${point.kmMarker.toStringAsFixed(1).replaceAll('.', ',')}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 70,
            child: Text(b == null ? '–' : 'naar ${Fmt.compass(b)}',
                style: const TextStyle(color: RwColors.muted)),
          ),
          Expanded(
            child: Text(
              point.elevation == null ? '' : '${point.elevation!.round()} m',
              style: const TextStyle(color: RwColors.subtle),
            ),
          ),
          Text(windText, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

/// Kaart met daaronder het hoogteprofiel; slepen over het profiel toont de plek op de kaart.
class _MapAndProfile extends ConsumerStatefulWidget {
  const _MapAndProfile({
    required this.route,
    required this.windSpeedKmh,
    required this.windFromDegrees,
    required this.reversed,
    required this.directionLabel,
  });

  final RunRoute route;
  final double? windSpeedKmh;
  final double? windFromDegrees;
  final bool reversed;
  final String? directionLabel;

  @override
  ConsumerState<_MapAndProfile> createState() => _MapAndProfileState();
}

class _MapAndProfileState extends ConsumerState<_MapAndProfile> {
  final _highlight = ValueNotifier<double?>(null);

  @override
  void dispose() {
    _highlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.route;
    final base = r.profileOrKmPoints;
    final profile = widget.reversed ? reverseProfile(base) : base;
    final poisAsync = ref.watch(routePoisProvider(r.polyline));
    final pois = poisAsync.value ?? const <RoutePoi>[];
    void expand() => openRouteMap(
          context,
          RouteMapData(
            title: r.name,
            polyline: r.polyline,
            distanceMeters: r.distanceMeters,
            windSpeedKmh: widget.windSpeedKmh,
            windFromDegrees: widget.windFromDegrees,
            reversed: widget.reversed,
            profile: profile,
            pois: pois,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1.1,
          child: RouteMap(
            polyline: r.polyline,
            windSpeedKmh: widget.windSpeedKmh,
            windFromDegrees: widget.windFromDegrees,
            reversed: widget.reversed,
            highlightFraction: _highlight,
            onExpand: expand,
            pois: pois,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.directionLabel == null
              ? 'Pijltjes tonen de looprichting. Tik op de kaart om hem groot te openen.'
              : 'Pijltjes tonen de beste richting van nu: ${widget.directionLabel}. Tik op de kaart om hem groot te openen.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: RwColors.subtle, fontSize: 12),
        ),
        if (profile.length >= 3) ...[
          const SizedBox(height: 12),
          RwCard(
            title: 'HOOGTEPROFIEL',
            child: ElevationProfileChart(profile: profile, highlight: _highlight),
          ),
        ],
        const SizedBox(height: 12),
        RoutePhotosCard(
          polyline: r.polyline,
          length: r.distanceMeters,
          reversed: widget.reversed,
          onHighlight: (f) => _highlight.value = f,
        ),
        const SizedBox(height: 12),
        _PoiCard(
          pois: pois,
          loading: poisAsync.isLoading,
          failed: poisAsync.hasError && pois.isEmpty,
          reversed: widget.reversed,
          length: r.distanceMeters,
          onRetry: () => ref.invalidate(routePoisProvider(r.polyline)),
        ),
      ],
    );
  }
}

/// Al je runs op deze route naast elkaar, eerlijk vergeleken voor het weer.
class _RouteHistoryCard extends ConsumerWidget {
  const _RouteHistoryCard({required this.routeId});
  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final h = routeHistory(all, routeId);
    if (h.isEmpty) {
      return const RwCard(
        title: 'JOUW RUNS OP DEZE ROUTE',
        child: Text(
          'Nog geen runs op deze route. Koppel een run aan deze route (open de run bij Runs) '
          'of kies de route als je een run toevoegt. Dan zie je hier je tijden naast elkaar, gecorrigeerd voor het weer.',
          style: TextStyle(color: RwColors.muted, height: 1.45),
        ),
      );
    }
    final fastest = h.fastest!;
    final fastestW = h.fastestCorrected!;
    final trend = h.trendSecPerKm;
    final maxShown = h.runs.take(8).toList();
    final paces = [for (final r in maxShown) r.correctedPace];
    final best = paces.reduce(math.min), worst = paces.reduce(math.max);

    return RwCard(
      title: 'JOUW RUNS OP DEZE ROUTE · ${h.runs.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: StatTile(label: 'Snelste tijd', value: Fmt.duration(fastest.activity.movingTimeSeconds))),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Bij ideaal weer', value: Fmt.duration(fastestW.correctedSeconds))),
            ],
          ),
          if (trend != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  trend < -2 ? Icons.trending_down : trend > 2 ? Icons.trending_up : Icons.trending_flat,
                  color: trend < -2 ? RwColors.good : trend > 2 ? RwColors.warning : RwColors.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trend < -2
                        ? 'Je wordt sneller: ${(-trend).round()} s/km vlotter dan je eerste keren, gecorrigeerd voor het weer.'
                        : trend > 2
                            ? 'Iets trager dan je eerste keren (${trend.round()} s/km, gecorrigeerd voor het weer). Rustig aan of moe?'
                            : 'Je tempo is stabiel op deze route.',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          for (final r in maxShown)
            InkWell(
              onTap: r.activity.id == null ? null : () => context.go('/runs/${r.activity.id}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 84,
                      child: Text(Fmt.date(r.activity.startedAt), style: const TextStyle(color: RwColors.muted, fontSize: 13)),
                    ),
                    SizedBox(
                      width: 62,
                      child: Text(Fmt.duration(r.activity.movingTimeSeconds),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: sameRun(r.activity, fastest.activity) ? const Color(0xFFF2D892) : RwColors.text,
                          )),
                    ),
                    // Balkje: korter = sneller (weergecorrigeerd tempo).
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final f = worst - best < 1 ? 1.0 : 1 - (r.correctedPace - best) / (worst - best) * 0.65;
                          final top = sameRun(r.activity, fastestW.activity);
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: (c.maxWidth - (top ? 20 : 0)).clamp(0.0, double.infinity) * f),
                                duration: const Duration(milliseconds: 900),
                                curve: Curves.easeOutCubic,
                                builder: (_, w, _) => Container(
                                  height: 8,
                                  width: w,
                                  decoration: BoxDecoration(
                                    gradient: top
                                        ? const LinearGradient(colors: [Color(0xFF9C7A2A), Color(0xFFD9B45A), Color(0xFFF6E3A1)])
                                        : null,
                                    color: top ? null : RwColors.bar,
                                    boxShadow: top ? [BoxShadow(color: const Color(0xFFD9B45A).withValues(alpha: 0.4), blurRadius: 8)] : null,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                              if (top) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.workspace_premium, size: 16, color: Color(0xFFD9B45A))),
                            ]),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 58,
                      child: Text(
                        r.activity.windSpeedKmh == null ? '' : '${r.activity.windSpeedKmh!.round()} km/u',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: RwColors.subtle, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'Balk: tempo gecorrigeerd voor het weer (langer = sneller). Goud = beste prestatie.',
            style: TextStyle(color: RwColors.subtle, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Watertappunten en toiletten langs de route.
class _PoiCard extends StatelessWidget {
  const _PoiCard({
    required this.pois,
    required this.loading,
    required this.failed,
    required this.reversed,
    required this.length,
    required this.onRetry,
  });

  final List<RoutePoi> pois;
  final bool loading;
  final bool failed;
  final bool reversed;
  final double length;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final water = pois.where((p) => p.kind == PoiKind.water).length;
    final toilets = pois.length - water;
    return RwCard(
      title: 'WATER EN TOILET',
      child: loading && pois.isEmpty
          ? const Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Expanded(child: Text('Zoeken in OpenStreetMap… dit kan even duren.', style: TextStyle(color: RwColors.muted))),
              ],
            )
          : failed
              ? Row(
                  children: [
                    const Expanded(
                      child: Text('Kon de voorzieningen nu niet laden.', style: TextStyle(color: RwColors.muted)),
                    ),
                    TextButton(onPressed: onRetry, child: const Text('Opnieuw')),
                  ],
                )
              : pois.isEmpty
                  ? const Text(
                      'Geen watertappunten of toiletten gevonden binnen 150 m van je route. Neem bij een lange run zelf drinken mee.',
                      style: TextStyle(color: RwColors.muted, height: 1.45),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          [
                            if (water > 0) '$water ${water == 1 ? 'watertappunt' : 'watertappunten'}',
                            if (toilets > 0) '$toilets ${toilets == 1 ? 'toilet' : 'toiletten'}',
                          ].join(' en '),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        for (final p in (reversed ? pois.reversed : pois).take(10))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                PoiIcon(p.kind, size: 24),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${p.label}${p.name == null ? '' : ' · ${p.name}'}${p.seasonal ? ' · niet het hele jaar' : ''}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  'km ${((reversed ? length - p.alongMeters : p.alongMeters) / 1000).toStringAsFixed(1).replaceAll('.', ',')}'
                                  '${p.offsetMeters > 40 ? ' · ${(p.offsetMeters / 10).round() * 10} m' : ''}',
                                  style: const TextStyle(color: RwColors.subtle, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 6),
                        const Text(
                          'Bron: OpenStreetMap-bijdragers. Controleer ter plekke of een kraan werkt.',
                          style: TextStyle(color: RwColors.subtle, fontSize: 11),
                        ),
                      ],
                    ),
    );
  }
}

/// Ondergrond van de route (zoals de padtypes bij Komoot en Strava), uit OpenStreetMap.
class _SurfaceCard extends ConsumerWidget {
  const _SurfaceCard({required this.routeId, required this.polyline});
  final String routeId;
  final String polyline;

  static const _order = ['verhard', 'klinkers', 'halfverhard', 'onverhard', 'onbekend'];
  static const _labels = {
    'verhard': 'Asfalt / verhard',
    'klinkers': 'Klinkers / tegels',
    'halfverhard': 'Gravel / halfverhard',
    'onverhard': 'Onverhard (zand, gras, bospad)',
    'onbekend': 'Onbekend',
  };
  static const _colors = {
    'verhard': Color(0xFF8D8D98),
    'klinkers': Color(0xFFC77D4A),
    'halfverhard': Color(0xFFD9B44A),
    'onverhard': Color(0xFF5BAE6B),
    'onbekend': Color(0xFF4A4A55),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(routeSurfaceProvider((id: routeId, polyline: polyline)));
    return RwCard(
      title: 'ONDERGROND',
      child: s.when(
        loading: () => const Text('Ondergrond wordt geladen…', style: TextStyle(color: RwColors.muted)),
        error: (_, _) => const Text('Ondergrond is nu niet beschikbaar.', style: TextStyle(color: RwColors.muted)),
        data: (m) {
          final total = m.values.fold<double>(0, (a, b) => a + b);
          if (total <= 0) return const Text('Geen gegevens over de ondergrond voor deze route.', style: TextStyle(color: RwColors.muted));
          final types = [for (final t in _order) if ((m[t] ?? 0) > 0) t];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 14,
                  child: Row(children: [
                    for (final t in types)
                      Expanded(flex: math.max(1, (m[t]! / total * 1000).round()), child: Container(color: _colors[t])),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              for (final t in types)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: _colors[t], shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_labels[t] ?? t)),
                    Text('${(m[t]! / total * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
              const SizedBox(height: 4),
              const Text('Bron: OpenStreetMap via openrouteservice. Niet overal is de ondergrond bekend.',
                  style: TextStyle(color: RwColors.subtle, fontSize: 11)),
            ],
          );
        },
      ),
    );
  }
}


/// Grote knop: route naar je horloge (laat zien voor welk horloge).
/// Net opgeslagen: één tik om hem op je horloge te zetten.
class _NewRouteCard extends StatelessWidget {
  const _NewRouteCard({required this.route});
  final RunRoute route;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RwColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RwColors.accent.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.check_circle, color: RwColors.accent),
          SizedBox(width: 8),
          Expanded(child: Text('Je route staat klaar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        ]),
        const SizedBox(height: 6),
        const Text('Zet hem nu op je horloge, dan wijst dat de weg. Of loop hem met je telefoon: RunWise zegt elke afslag.',
            style: TextStyle(color: RwColors.muted, height: 1.4)),
        const SizedBox(height: 10),
        _WatchButton(route: route),
      ]),
    );
  }
}

class _WatchButton extends StatefulWidget {
  const _WatchButton({required this.route});
  final RunRoute route;

  @override
  State<_WatchButton> createState() => _WatchButtonState();
}

class _WatchButtonState extends State<_WatchButton> {
  WatchBrand? _brand;

  @override
  void initState() {
    super.initState();
    loadWatchBrand().then((b) {
      if (mounted) setState(() => _brand = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = _brand;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: () async {
        await sendRouteToWatch(context, widget.route, onRunWithPhone: () => openRecorder(context, route: widget.route));
        final nb = await loadWatchBrand();
        if (mounted) setState(() => _brand = nb);
      },
      icon: const Icon(Icons.watch_outlined),
      label: Text(b == null || !b.canImport ? 'Route naar je horloge' : 'Zet op je ${b.label}'),
    );
  }
}
