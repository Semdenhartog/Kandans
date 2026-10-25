import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../domain/geo.dart';
import '../../domain/start_time_scoring.dart';
import 'route_map.dart';
import 'route_photos_strip.dart';

enum LengthFilter {
  all('Alle lengtes'),
  short('Tot 5 km'),
  mid('5–10 km'),
  long('Meer dan 10 km');

  const LengthFilter(this.label);
  final String label;

  bool fits(double m) => switch (this) {
        LengthFilter.all => true,
        LengthFilter.short => m < 5000,
        LengthFilter.mid => m >= 5000 && m <= 10000,
        LengthFilter.long => m > 10000,
      };
}

enum HillFilter {
  all('Alle'),
  flat('Vlak'),
  hilly('Heuvels');

  const HillFilter(this.label);
  final String label;

  /// Vlak: minder dan 10 hoogtemeter per 5 km.
  bool fits(RunRoute r) {
    final hm = r.elevationGainMeters ?? 0;
    final perKm = r.distanceMeters <= 0 ? 0 : hm / (r.distanceMeters / 1000);
    return switch (this) {
      HillFilter.all => true,
      HillFilter.flat => perKm < 2,
      HillFilter.hilly => perKm >= 2,
    };
  }
}

/// Al je routes op één grote kaart, met filters en een veegbare rij kaartjes (zoals Strava's kaarten).
class RoutesOverviewMap extends ConsumerStatefulWidget {
  const RoutesOverviewMap({super.key, required this.routes, required this.bests});
  final List<RunRoute> routes;
  final Map<String, StartTimeScore> bests;

  @override
  ConsumerState<RoutesOverviewMap> createState() => _RoutesOverviewMapState();
}

class _RoutesOverviewMapState extends ConsumerState<RoutesOverviewMap> {
  final _map = MapController();
  final _pages = PageController(viewportFraction: 0.88);
  LengthFilter _length = LengthFilter.all;
  HillFilter _hill = HillFilter.all;
  bool _favorites = false;
  int _selected = 0;
  bool _ready = false;

  List<RunRoute> get _shown => widget.routes
      .where((r) => _length.fits(r.distanceMeters) && _hill.fits(r) && (!_favorites || r.isFavorite))
      .toList();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  List<ll.LatLng> _pts(RunRoute r) => [for (final p in decodePolyline(r.polyline)) ll.LatLng(p.lat, p.lon)];

  void _focus(RunRoute r) {
    if (!_ready) return;
    final pts = _pts(r);
    if (pts.length < 2) return;
    _map.fitCamera(CameraFit.coordinates(
      coordinates: pts,
      padding: const EdgeInsets.fromLTRB(40, 120, 40, 200),
      maxZoom: 16,
    ));
  }

  void _select(int i, {bool fromMap = false}) {
    final shown = _shown;
    if (i < 0 || i >= shown.length) return;
    setState(() => _selected = i);
    _focus(shown[i]);
    if (fromMap && _pages.hasClients) {
      _pages.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _filtersChanged() {
    setState(() => _selected = 0);
    final shown = _shown;
    if (shown.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pages.hasClients) _pages.jumpToPage(0);
        _focus(shown.first);
      });
    }
  }

  Widget _chip<T>(String label, List<T> values, T value, String Function(T) name, ValueChanged<T> onChanged) {
    return PopupMenuButton<T>(
      tooltip: label,
      onSelected: onChanged,
      itemBuilder: (_) => [for (final v in values) CheckedPopupMenuItem(value: v, checked: v == value, child: Text(name(v)))],
      child: Chip(
        backgroundColor: RwColors.background.withValues(alpha: 0.9),
        side: BorderSide(color: values.first == value ? RwColors.border : RwColors.accent),
        label: Text(values.first == value ? label : name(value),
            style: TextStyle(color: values.first == value ? RwColors.text : RwColors.accent, fontWeight: FontWeight.w600)),
        avatar: const Icon(Icons.expand_more, size: 18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final sel = shown.isEmpty ? null : shown[_selected.clamp(0, shown.length - 1)];
    final all = [for (final r in widget.routes) ..._pts(r)];
    return ValueListenableBuilder<MapLayer>(
      valueListenable: mapLayerNotifier,
      builder: (context, layer, _) {
        final photo = layer == MapLayer.satelliet;
        return Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCameraFit: all.length >= 2
                    ? CameraFit.coordinates(coordinates: all, padding: const EdgeInsets.fromLTRB(40, 120, 40, 200), maxZoom: 15)
                    : null,
                initialCenter: const ll.LatLng(52.15, 5.4),
                initialZoom: 8,
                minZoom: 6,
                maxZoom: 19,
                backgroundColor: mapBackground,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onMapReady: () {
                  _ready = true;
                  if (sel != null) _focus(sel);
                },
              ),
              children: [
                baseTileLayer(photo),
                PolylineLayer(polylines: [
                  for (final r in shown)
                    if (r != sel) Polyline(points: _pts(r), strokeWidth: 3.5, color: RwColors.accent.withValues(alpha: 0.45)),
                  if (sel != null) ...[
                    Polyline(points: _pts(sel), strokeWidth: 10, color: routeHalo),
                    Polyline(points: _pts(sel), strokeWidth: 6, color: RwColors.accent),
                  ],
                ]),
                MarkerLayer(markers: [
                  for (final (i, r) in shown.indexed)
                    if (decodePolyline(r.polyline).isNotEmpty)
                      Marker(
                        point: ll.LatLng(r.startLatitude, r.startLongitude),
                        width: r == sel ? 34 : 26,
                        height: r == sel ? 34 : 26,
                        child: GestureDetector(
                          onTap: () => _select(i, fromMap: true),
                          child: Container(
                            decoration: BoxDecoration(
                              color: r == sel ? RwColors.accent : RwColors.background,
                              shape: BoxShape.circle,
                              border: Border.all(color: RwColors.accent, width: 2.5),
                              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
                            ),
                            child: Icon(Icons.directions_run, size: r == sel ? 18 : 14, color: r == sel ? RwColors.accentDark : RwColors.accent),
                          ),
                        ),
                      ),
                ]),
              ],
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip<LengthFilter>('Lengte', LengthFilter.values, _length, (v) => v.label, (v) {
                      _length = v;
                      _filtersChanged();
                    }),
                    const SizedBox(width: 8),
                    _chip<HillFilter>('Hoogteverschil', HillFilter.values, _hill, (v) => v.label, (v) {
                      _hill = v;
                      _filtersChanged();
                    }),
                    const SizedBox(width: 8),
                    FilterChip(
                      backgroundColor: RwColors.background.withValues(alpha: 0.9),
                      label: const Text('Favorieten'),
                      selected: _favorites,
                      onSelected: (v) {
                        _favorites = v;
                        _filtersChanged();
                      },
                    ),
                    const SizedBox(width: 8),
                    mapLayerToggle(layer),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              height: 128,
              child: shown.isEmpty
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: RwColors.background.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(14)),
                        child: const Text('Geen routes met deze filters.'),
                      ),
                    )
                  : PageView.builder(
                      controller: _pages,
                      itemCount: shown.length,
                      onPageChanged: _select,
                      itemBuilder: (context, i) {
                        final r = shown[i];
                        final best = r.id == null ? null : widget.bests[r.id];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Material(
                            color: RwColors.surface,
                            borderRadius: BorderRadius.circular(18),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: r.id == null ? null : () => context.go('/routes/${r.id}'),
                              child: Row(
                                children: [
                                  RouteThumb(polyline: r.polyline, size: 128),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(r.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                          const SizedBox(height: 6),
                                          Text(
                                            [
                                              Fmt.km(r.distanceMeters, decimals: 1),
                                              '${(r.elevationGainMeters ?? 0).round()} hm',
                                              if (r.estimatedDurationSeconds != null) Fmt.duration(r.estimatedDurationSeconds!),
                                            ].join(' · '),
                                            style: TextStyle(color: RwColors.muted),
                                          ),
                                          if (best != null) ...[
                                            const SizedBox(height: 4),
                                            Text('Beste moment ${Fmt.time(best.start)} · ${best.score}',
                                                style: TextStyle(color: RwColors.accent, fontWeight: FontWeight.w600, fontSize: 13)),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            mapAttribution(photo),
          ],
        );
      },
    );
  }
}
