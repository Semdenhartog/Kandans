import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../domain/geo.dart';
import '../../domain/route_geometry.dart';
import 'elevation_profile.dart';
import 'route_map.dart';

/// Vlieg over de route (punt 72): de camera volgt de route van start tot finish, schuin van boven
/// (3D-gevoel), met het hoogteprofiel eronder. Eigen animatie op de gewone kaart, geen extra pakketten.
void openRouteFlyover(BuildContext context, RunRoute route) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RouteFlyoverScreen(route: route)));

/// Punt en kijkrichting op een fractie [t] (0–1) van de route.
({LatLng at, double bearing}) flyoverPose(List<LatLng> track, List<double> cumulative, double t, {double lookAhead = 150}) {
  final total = cumulative.last;
  final d = (t.clamp(0.0, 1.0)) * total;
  LatLng pointAt(double m) {
    if (m <= 0) return track.first;
    if (m >= total) return track.last;
    var lo = 0, hi = cumulative.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (cumulative[mid] <= m) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = cumulative[hi] - cumulative[lo];
    final f = span <= 0 ? 0.0 : (m - cumulative[lo]) / span;
    final a = track[lo], b = track[hi];
    return LatLng(a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f);
  }

  final here = pointAt(d);
  // Kijk een stukje vooruit (en aan het eind een stukje terug), dan draait de camera rustig mee.
  final ahead = d + lookAhead <= total ? pointAt(d + lookAhead) : null;
  final bearing = ahead != null ? bearingDegrees(here, ahead) : bearingDegrees(pointAt(math.max(0, d - lookAhead)), here);
  return (at: here, bearing: bearing);
}

class RouteFlyoverScreen extends StatefulWidget {
  const RouteFlyoverScreen({super.key, required this.route});
  final RunRoute route;

  @override
  State<RouteFlyoverScreen> createState() => _RouteFlyoverScreenState();
}

class _RouteFlyoverScreenState extends State<RouteFlyoverScreen> with SingleTickerProviderStateMixin {
  late final List<LatLng> _track = decodePolyline(widget.route.polyline);
  late final List<double> _cum = () {
    final c = <double>[0];
    for (var i = 1; i < _track.length; i++) {
      c.add(c.last + distanceMeters(_track[i - 1], _track[i]));
    }
    return c;
  }();
  late final List<ElevationSample> _profile = widget.route.profileOrKmPoints;
  final _map = MapController();
  final _highlight = ValueNotifier<double?>(0);
  late final AnimationController _anim;
  bool _ready = false, _tilt = true, _fast = false;
  double _bearing = 0;

  Duration get _duration {
    // Ongeveer 5 seconden per kilometer, tussen 15 en 60 seconden.
    final s = (widget.route.distanceMeters / 1000 * 5).clamp(15, 60) * (_fast ? 0.5 : 1);
    return Duration(milliseconds: (s * 1000).round());
  }

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: _duration)..addListener(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Minder beweging aan: niet vanzelf vliegen, wel met de schuif.
    if (MediaQuery.of(context).disableAnimations) _anim.stop();
  }

  @override
  void dispose() {
    _anim.dispose();
    _highlight.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!_ready || _track.length < 2) return;
    final pose = flyoverPose(_track, _cum, _anim.value);
    // Draaiing gladstrijken zodat bochten niet schokken.
    var diff = ((pose.bearing - _bearing + 540) % 360) - 180;
    _bearing = (_bearing + diff * 0.12 + 360) % 360;
    if (_anim.value == 0) _bearing = pose.bearing;
    _map.moveAndRotate(ll.LatLng(pose.at.lat, pose.at.lon), _tilt ? 16.4 : 15.6, -_bearing);
    _highlight.value = _anim.value;
    setState(() {});
  }

  void _toggle() {
    if (_anim.isAnimating) {
      _anim.stop();
    } else {
      if (_anim.value >= 1) _anim.value = 0;
      _anim.forward();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.route;
    final done = _anim.value * _cum.last;
    final pose = _track.length < 2 ? null : flyoverPose(_track, _cum, _anim.value);
    double? ele;
    if (_profile.length >= 2) {
      final m = _anim.value * _profile.last.meters;
      ele = _profile.lastWhere((s) => s.meters <= m, orElse: () => _profile.first).ele;
    }
    final full = [for (final p in _track) ll.LatLng(p.lat, p.lon)];
    final walked = <ll.LatLng>[
      for (var i = 0; i < _track.length && _cum[i] <= done; i++) full[i],
      if (pose != null) ll.LatLng(pose.at.lat, pose.at.lon),
    ];
    return Scaffold(
      backgroundColor: mapBackground,
      appBar: AppBar(title: Text(r.name, overflow: TextOverflow.ellipsis), actions: [
        IconButton(
          tooltip: _tilt ? tr('Van boven') : tr('Schuin (3D)'),
          icon: Icon(_tilt ? Icons.map_outlined : Icons.threed_rotation),
          onPressed: () {
            setState(() => _tilt = !_tilt);
            _onTick();
          },
        ),
      ]),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: LayoutBuilder(builder: (context, box) {
                // Een grotere kaart, schuin gekanteld: zo blijft de bovenrand gevuld.
                final w = box.maxWidth * (_tilt ? 1.7 : 1), h = box.maxHeight * (_tilt ? 1.7 : 1);
                return ClipRect(
                  child: OverflowBox(
                    maxWidth: w,
                    maxHeight: h,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0011)
                        ..rotateX(_tilt ? -0.9 : 0),
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: ValueListenableBuilder<MapLayer>(
                          valueListenable: mapLayerNotifier,
                          builder: (context, layer, _) => FlutterMap(
                            mapController: _map,
                            options: MapOptions(
                              initialCenter: full.isEmpty ? const ll.LatLng(52.1, 5.1) : full.first,
                              initialZoom: 15.6,
                              backgroundColor: mapBackground,
                              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                              onMapReady: () {
                                _ready = true;
                                _onTick();
                                if (!MediaQuery.of(context).disableAnimations) {
                                  Future<void>.delayed(const Duration(milliseconds: 600), () {
                                    if (mounted && _anim.value == 0) _anim.forward();
                                  });
                                }
                              },
                            ),
                            children: [
                              baseTileLayer(layer == MapLayer.satelliet),
                              PolylineLayer(polylines: [
                                if (full.length >= 2) Polyline(points: full, strokeWidth: 6, color: RwColors.accent.withValues(alpha: 0.35)),
                                if (walked.length >= 2) Polyline(points: walked, strokeWidth: 7, color: RwColors.accent),
                              ]),
                              if (pose != null)
                                MarkerLayer(markers: [
                                  Marker(
                                    point: ll.LatLng(pose.at.lat, pose.at.lon),
                                    width: 22,
                                    height: 22,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: RwColors.accent,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 3),
                                      ),
                                    ),
                                  ),
                                ]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            // Cijfers bovenop, niet gekanteld.
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: RwColors.surface.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(RwRadius.s)),
                child: Text(
                  [
                    '${Fmt.km(done, decimals: 1)} / ${Fmt.km(r.distanceMeters, decimals: 1)}',
                    if (ele != null) '${ele.round()} m',
                  ].join(' · '),
                  style: const TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontFeatures: rwTnum),
                ),
              ),
            ),
            // mapAttribution is zelf al een Positioned (dubbel gaf een fout).
            ValueListenableBuilder<MapLayer>(
              valueListenable: mapLayerNotifier,
              builder: (_, layer, _) => Stack(fit: StackFit.expand, children: [mapAttribution(layer == MapLayer.satelliet)]),
            ),
          ]),
        ),
        Material(
          color: RwColors.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_profile.length >= 3) ElevationProfileChart(profile: _profile, highlight: _highlight, height: 90),
                Slider(
                  value: _anim.value,
                  onChanged: (v) {
                    _anim.stop();
                    _anim.value = v;
                  },
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(
                    tooltip: tr('Opnieuw'),
                    icon: const Icon(Icons.replay),
                    onPressed: () {
                      _anim.value = 0;
                      _anim.forward();
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    // Het thema geeft knoppen de volle breedte; in een rij moet dat begrensd zijn.
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: _toggle,
                    icon: Icon(_anim.isAnimating ? Icons.pause : Icons.play_arrow),
                    label: Text(_anim.isAnimating ? tr('Pauze') : tr('Vliegen')),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () {
                      final going = _anim.isAnimating;
                      setState(() => _fast = !_fast);
                      _anim.duration = _duration;
                      if (going) _anim.forward();
                    },
                    child: Text(_fast ? '2×' : '1×', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
