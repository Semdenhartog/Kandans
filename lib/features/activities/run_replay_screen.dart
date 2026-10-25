import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../domain/geo.dart';
import '../../domain/route_geometry.dart';
import '../routes/route_map.dart' show baseTileLayer, mapAttribution, mapBackground;

/// Je run nog eens zien: het spoor tekent zich in ongeveer 12 seconden, met een stip, de afstand en de tijd.
void openRunReplay(BuildContext context, Activity a) {
  if (!a.hasTrack) return;
  Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => RunReplayScreen(activity: a)));
}

class RunReplayScreen extends StatefulWidget {
  const RunReplayScreen({super.key, required this.activity});
  final Activity activity;

  @override
  State<RunReplayScreen> createState() => _RunReplayScreenState();
}

class _RunReplayScreenState extends State<RunReplayScreen> with SingleTickerProviderStateMixin {
  late final RouteTrack _track = RouteTrack(decodePolyline(widget.activity.trackPolyline ?? ''));
  late final List<ll.LatLng> _pts = [for (final p in _track.points) ll.LatLng(p.lat, p.lon)];
  late final AnimationController _c = AnimationController(vsync: this, duration: _duration(1))..forward();
  double _speed = 1;

  static Duration _duration(double speed) => Duration(milliseconds: (12000 / speed).round());

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      if (_c.isAnimating) {
        _c.stop();
      } else if (_c.isCompleted) {
        _c.forward(from: 0);
      } else {
        _c.forward();
      }
    });
  }

  void _setSpeed(double s) {
    setState(() {
      _speed = s;
      final running = _c.isAnimating;
      _c.duration = _duration(s);
      if (running) _c.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    if (_pts.length < 2) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Deze run heeft geen GPS-spoor.')));
    }
    return Scaffold(
      backgroundColor: RwColors.background,
      appBar: AppBar(title: Text('Je run van ${Fmt.date(a.startedAt)}')),
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final meters = _track.length * t;
          final here = _track.at(meters);
          // Punten tot nu toe, met het precieze punt als kop (zo loopt de lijn vloeiend).
          final shown = <ll.LatLng>[
            for (var i = 0; i < _pts.length && _track.cumulative[i] <= meters; i++) _pts[i],
            ll.LatLng(here.lat, here.lon),
          ];
          final km = a.distanceMeters * t;
          final secs = a.movingTimeSeconds * t;
          return Stack(children: [
            FlutterMap(
              options: MapOptions(
                initialCameraFit: CameraFit.coordinates(coordinates: _pts, padding: const EdgeInsets.fromLTRB(40, 40, 40, 160)),
                backgroundColor: mapBackground,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                baseTileLayer(false),
                PolylineLayer(polylines: [
                  Polyline(points: _pts, strokeWidth: 4, color: RwColors.text.withValues(alpha: 0.14)),
                  if (shown.length >= 2) ...[
                    Polyline(points: shown, strokeWidth: 12, color: RwColors.accent.withValues(alpha: 0.22)),
                    Polyline(points: shown, strokeWidth: 5, color: RwColors.accent),
                  ],
                ]),
                MarkerLayer(markers: [
                  Marker(
                    point: ll.LatLng(here.lat, here.lon),
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: RwColors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
                      ),
                    ),
                  ),
                ]),
              ],
            ),
            mapAttribution(false),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  decoration: BoxDecoration(
                    color: RwColors.surface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Expanded(
                        child: Text(Fmt.km(km, decimals: 2),
                            style: const TextStyle(
                                fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 28, fontWeight: FontWeight.w800)),
                      ),
                      Text(Fmt.duration(secs.round()),
                          style: const TextStyle(
                              fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 28, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 4),
                      IconButton.filled(
                        tooltip: _c.isAnimating ? 'Pauze' : 'Afspelen',
                        onPressed: _toggle,
                        icon: Icon(_c.isAnimating ? Icons.pause : (_c.isCompleted ? Icons.replay : Icons.play_arrow)),
                      ),
                    ]),
                    Slider(
                      value: t,
                      onChanged: (v) {
                        _c.stop();
                        _c.value = v;
                        setState(() {});
                      },
                    ),
                    SegmentedButton<double>(
                      segments: const [
                        ButtonSegment(value: 0.5, label: Text('½×')),
                        ButtonSegment(value: 1, label: Text('1×')),
                        ButtonSegment(value: 2, label: Text('2×')),
                      ],
                      selected: {_speed},
                      onSelectionChanged: (v) => _setSpeed(v.first),
                    ),
                  ]),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
