import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/geo.dart';
import '../../domain/poi.dart';
import '../../domain/route_geometry.dart';

/// Ondergrond van de kaart.
enum MapLayer { kaart, satelliet }

/// Gekozen ondergrond, gedeeld door alle kaarten en onthouden op het toestel.
final mapLayerNotifier = _MapLayerNotifier();

class _MapLayerNotifier extends ValueNotifier<MapLayer> {
  _MapLayerNotifier() : super(MapLayer.kaart) {
    _load();
  }

  static const _key = 'map_layer';

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getString(_key) == 'satelliet') value = MapLayer.satelliet;
    } catch (_) {}
  }

  void choose(MapLayer layer) {
    value = layer;
    SharedPreferences.getInstance().then((p) => p.setString(_key, layer.name)).ignore();
  }
}

/// Gratis Nederlandse kaarten van PDOK (Kadaster), zonder sleutel.
/// Buiten Nederland blijft de ondergrond leeg; de route wordt wel getekend.
const _greyTiles = 'https://service.pdok.nl/brt/achtergrondkaart/wmts/v2_0/grijs/EPSG:3857/{z}/{x}/{y}.png';
const _photoTiles = 'https://service.pdok.nl/hwh/luchtfotorgb/wmts/v1_0/Actueel_orthoHR/EPSG:3857/{z}/{x}/{y}.jpeg';

/// Maakt van de lichtgrijze kaart een donkere kaart in RunWise-stijl:
/// omkeren, dimmen en een tikje koel, zodat de oranje route eruit springt.
const _darkMap = ColorFilter.matrix(<double>[
  -0.60, 0, 0, 0, 165, //
  0, -0.60, 0, 0, 166, //
  0, 0, -0.60, 0, 172, //
  0, 0, 0, 1, 0,
]);

/// Luchtfoto iets donkerder en minder fel, zodat de route leesbaar blijft.
const _dimPhoto = ColorFilter.matrix(<double>[
  0.74, 0.04, 0.02, 0, 0, //
  0.03, 0.76, 0.03, 0, 0, //
  0.02, 0.04, 0.74, 0, 0, //
  0, 0, 0, 1, 0,
]);

Color windColor(WindClass c) => switch (c) {
      WindClass.head => RwColors.danger,
      WindClass.tail => RwColors.good,
      WindClass.side || WindClass.calm => RwColors.accent,
    };

ll.LatLng _ll(LatLng p) => ll.LatLng(p.lat, p.lon);

/// Route op een echte kaart: donkere kaart of luchtfoto, gekleurd op de wind,
/// met looprichting, kilometerbordjes, start en finish.
class RouteMap extends StatefulWidget {
  const RouteMap({
    super.key,
    required this.polyline,
    this.windSpeedKmh,
    this.windFromDegrees,
    this.reversed = false,
    this.compact = false,
    this.interactive = true,
    this.showLayerToggle = true,
    this.showLegend = true,
    this.showMyLocation = false,
    this.onExpand,
    this.highlightFraction,
    this.controller,
    this.overlayPadding = EdgeInsets.zero,
    this.borderRadius = 16,
    this.pois = const [],
  });

  final String polyline;
  final double? windSpeedKmh;
  final double? windFromDegrees;

  /// Toon de route in omgekeerde looprichting (bijv. als dat vandaag beter is).
  final bool reversed;

  /// Kleine kaart: minder pijltjes, geen kilometerbordjes.
  final bool compact;
  final bool interactive;
  final bool showLayerToggle;
  final bool showLegend;
  final bool showMyLocation;

  /// Als gezet: tikken op de kaart opent hem groot.
  final VoidCallback? onExpand;

  /// Markeert een plek op de route (0 = start, 1 = finish), bijv. vanuit het hoogteprofiel.
  final ValueListenable<double?>? highlightFraction;
  final MapController? controller;

  /// Ruimte rond de knoppen op de kaart (voor statusbalk of terugknop).
  final EdgeInsets overlayPadding;
  final double borderRadius;

  /// Watertappunten en toiletten langs de route.
  final List<RoutePoi> pois;

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  late RouteTrack _track;
  late List<ll.LatLng> _pts;
  late List<WindSegment> _segments;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant RouteMap old) {
    super.didUpdateWidget(old);
    if (old.polyline != widget.polyline ||
        old.reversed != widget.reversed ||
        old.windSpeedKmh != widget.windSpeedKmh ||
        old.windFromDegrees != widget.windFromDegrees) {
      _prepare();
    }
  }

  void _prepare() {
    final raw = decodePolyline(widget.polyline);
    _track = RouteTrack(widget.reversed ? raw.reversed.toList() : raw);
    _pts = [for (final p in _track.points) _ll(p)];
    _segments = windSegments(
      _track,
      windSpeedKmh: widget.windSpeedKmh ?? 0,
      windFromDegrees: widget.windSpeedKmh == null ? null : widget.windFromDegrees,
    );
  }

  bool get _windColored => _segments.any((s) => s.windClass != WindClass.calm);

  @override
  Widget build(BuildContext context) {
    if (!_track.isValid) {
      return Container(
        decoration: BoxDecoration(color: RwColors.surfaceHigh, borderRadius: BorderRadius.circular(widget.borderRadius)),
        alignment: Alignment.center,
        child: const Text('Geen route om te tonen', style: TextStyle(color: RwColors.subtle)),
      );
    }
    final km = (_track.length / 1000).toStringAsFixed(1).replaceAll('.', ',');
    final windText = !_windColored
        ? ''
        : ' Rood is tegenwind, groen is wind mee.';
    return Semantics(
      label: 'Kaart van de route, $km kilometer.$windText${widget.onExpand != null ? ' Dubbeltik om de kaart groot te openen.' : ''}',
      button: widget.onExpand != null,
      onTap: widget.onExpand,
      child: ValueListenableBuilder<MapLayer>(
        valueListenable: mapLayerNotifier,
        builder: (context, layer, _) => _buildMap(context, layer),
      ),
    );
  }

  Widget _buildMap(BuildContext context, MapLayer layer) {
    final photo = layer == MapLayer.satelliet;
    final density = markerDensity(_track.length, compact: widget.compact);
    final arrows = arrowPositions(_track, density.arrowSpacing);
    final kms = density.kmEvery == 0 ? const <({LatLng point, int km})>[] : kmPositions(_track, everyKm: density.kmEvery);
    final start = _track.points.first, finish = _track.points.last;
    final separateFinish = distanceMeters(start, finish) > 80;
    final pad = widget.overlayPadding;
    final line = widget.compact ? 4.0 : 5.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        children: [
          FlutterMap(
            mapController: widget.controller,
            options: MapOptions(
              initialCameraFit: CameraFit.coordinates(
                coordinates: _pts,
                padding: EdgeInsets.fromLTRB(32, 32 + pad.top, 32, 40 + pad.bottom),
                maxZoom: 17,
              ),
              backgroundColor: photo ? const Color(0xFF1B1D1A) : const Color(0xFF17171A),
              minZoom: 6,
              maxZoom: 19,
              interactionOptions: InteractionOptions(
                flags: widget.interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
              ),
              onTap: widget.onExpand == null ? null : (_, _) => widget.onExpand!(),
            ),
            children: [
              TileLayer(
                urlTemplate: photo ? _photoTiles : _greyTiles,
                userAgentPackageName: 'nl.runwise.app',
                maxNativeZoom: 19,
                tileBuilder: (context, tile, _) => ColorFiltered(colorFilter: photo ? _dimPhoto : _darkMap, child: tile),
              ),
              PolylineLayer(
                polylines: [
                  // Gloed onder de route.
                  Polyline(
                    points: _pts,
                    strokeWidth: line + 10,
                    color: (photo ? Colors.white : RwColors.accent).withValues(alpha: photo ? 0.16 : 0.22),
                  ),
                  // Donkere rand, zodat de route op elke ondergrond leesbaar is.
                  Polyline(points: _pts, strokeWidth: line + 3.5, color: Colors.black.withValues(alpha: 0.8)),
                  for (final s in _segments)
                    Polyline(points: [for (final p in s.points) _ll(p)], strokeWidth: line, color: windColor(s.windClass)),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (final a in arrows)
                    Marker(
                      point: _ll(a.point),
                      width: 16,
                      height: 16,
                      child: _Arrow(bearing: a.bearing),
                    ),
                  for (final k in kms)
                    Marker(point: _ll(k.point), width: 24, height: 24, child: _KmBadge(k.km)),
                  for (final p in widget.pois)
                    Marker(point: _ll(p.point), width: 26, height: 26, child: PoiIcon(p.kind)),
                  if (separateFinish)
                    Marker(point: _ll(finish), width: 30, height: 30, child: const _Pin(icon: Icons.sports_score, color: RwColors.text)),
                  Marker(
                    point: _ll(start),
                    width: 32,
                    height: 32,
                    child: _Pin(icon: separateFinish ? Icons.flag : Icons.flag_circle_outlined, color: RwColors.accent),
                  ),
                ],
              ),
              if (widget.highlightFraction != null)
                ValueListenableBuilder<double?>(
                  valueListenable: widget.highlightFraction!,
                  builder: (context, f, _) => f == null
                      ? const SizedBox.shrink()
                      : MarkerLayer(markers: [
                          Marker(point: _ll(_track.at(f * _track.length)), width: 22, height: 22, child: const _HighlightDot()),
                        ]),
                ),
              if (widget.showMyLocation) const _MyLocationLayer(),
            ],
          ),
          if (widget.showLayerToggle)
            Positioned(
              top: 10 + pad.top,
              left: 10 + pad.left,
              child: _LayerToggle(layer: layer, onChanged: mapLayerNotifier.choose),
            ),
          if (widget.windFromDegrees != null && widget.windSpeedKmh != null)
            Positioned(
              top: 10 + pad.top,
              right: 10 + pad.right,
              child: _WindBadge(fromDegrees: widget.windFromDegrees!, speed: widget.windSpeedKmh!, compact: widget.compact),
            ),
          if (widget.showLegend)
            Positioned(
              left: 10 + pad.left,
              bottom: 10 + pad.bottom,
              child: _Legend(windColored: _windColored, compact: widget.compact),
            ),
          if (widget.onExpand != null)
            Positioned(
              right: 10 + pad.right,
              bottom: 24 + pad.bottom,
              child: _RoundButton(icon: Icons.open_in_full, tooltip: 'Kaart groot openen', onTap: widget.onExpand!),
            ),
          Positioned(
            right: 0,
            bottom: pad.bottom,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: Colors.black.withValues(alpha: 0.55),
                child: Text(
                  photo ? 'Luchtfoto © Beeldmateriaal.nl, PDOK' : 'Kaart © Kadaster, PDOK',
                  style: const TextStyle(fontSize: 9, color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Onderdelen op de kaart
// ---------------------------------------------------------------------------

class _Arrow extends StatelessWidget {
  const _Arrow({required this.bearing});
  final double bearing;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: bearing * math.pi / 180,
        child: CustomPaint(painter: _ChevronPainter()),
      );
}

/// Pijlpunt die naar boven (noord) wijst; wordt gedraaid naar de looprichting.
class _ChevronPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.22, h * 0.70)
      ..lineTo(w * 0.5, h * 0.30)
      ..lineTo(w * 0.78, h * 0.70);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _KmBadge extends StatelessWidget {
  const _KmBadge(this.km);
  final int km;

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: RwColors.background,
          shape: BoxShape.circle,
          border: Border.all(color: RwColors.text, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
        ),
        child: Text(
          '$km',
          style: const TextStyle(
            fontFamily: RwFonts.display,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            color: RwColors.text,
            height: 1,
          ),
        ),
      );
}

class _Pin extends StatelessWidget {
  const _Pin({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: RwColors.background, width: 2.5),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
        ),
        child: Icon(icon, size: 17, color: RwColors.accentDark),
      );
}

class _HighlightDot extends StatelessWidget {
  const _HighlightDot();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: RwColors.accent, width: 5),
          boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 6)],
        ),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: RwColors.background.withValues(alpha: 0.88),
          shape: const CircleBorder(side: BorderSide(color: RwColors.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(9), child: Icon(icon, size: 20, color: RwColors.text)),
          ),
        ),
      );
}

class _LayerToggle extends StatelessWidget {
  const _LayerToggle({required this.layer, required this.onChanged});
  final MapLayer layer;
  final ValueChanged<MapLayer> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(MapLayer l, IconData icon, String label) {
      final on = layer == l;
      return Semantics(
        button: true,
        selected: on,
        child: GestureDetector(
          onTap: () => onChanged(l),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: on ? RwColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: on ? RwColors.accentDark : RwColors.muted),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? RwColors.accentDark : RwColors.text),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: RwColors.background.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: RwColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip(MapLayer.kaart, Icons.map_outlined, 'Kaart'),
          chip(MapLayer.satelliet, Icons.satellite_alt_outlined, 'Satelliet'),
        ],
      ),
    );
  }
}

/// Pijl in de richting waar de wind naartoe waait, met de snelheid.
class _WindBadge extends StatelessWidget {
  const _WindBadge({required this.fromDegrees, required this.speed, required this.compact});
  final double fromDegrees;
  final double speed;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
        decoration: BoxDecoration(
          color: RwColors.background.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: RwColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: (fromDegrees + 180) * math.pi / 180,
              child: const Icon(Icons.navigation, size: 16, color: RwColors.text),
            ),
            const SizedBox(width: 5),
            Text(
              compact ? '${speed.round()}' : '${speed.round()} km/u ${Fmt.compass(fromDegrees)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: RwColors.text),
            ),
          ],
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.windColored, required this.compact});
  final bool windColored;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 14, height: 4, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 10.5, color: RwColors.text, fontWeight: FontWeight.w600)),
          ],
        );

    final items = windColored
        ? [
            item(RwColors.danger, 'tegenwind'),
            item(RwColors.accent, 'zijwind'),
            item(RwColors.good, 'wind mee'),
          ]
        : [item(RwColors.accent, compact ? 'weinig wind' : 'weinig wind: elke richting is goed')];

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: RwColors.background.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: RwColors.border),
        ),
        child: Wrap(spacing: 9, children: items),
      ),
    );
  }
}

/// Blauwe stip op je eigen locatie (alleen als je daar toestemming voor gaf).
class _MyLocationLayer extends StatefulWidget {
  const _MyLocationLayer();

  @override
  State<_MyLocationLayer> createState() => _MyLocationLayerState();
}

class _MyLocationLayerState extends State<_MyLocationLayer> {
  StreamSubscription<Position>? _sub;
  Position? _pos;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final last = await Geolocator.getLastKnownPosition();
      if (mounted && last != null) setState(() => _pos = last);
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen((p) {
        if (mounted) setState(() => _pos = p);
      }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pos;
    if (p == null) return const SizedBox.shrink();
    final point = ll.LatLng(p.latitude, p.longitude);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (p.accuracy > 0 && p.accuracy < 200)
          CircleLayer(circles: [
            CircleMarker(
              point: point,
              radius: p.accuracy,
              useRadiusInMeter: true,
              color: const Color(0xFF4C8DFF).withValues(alpha: 0.15),
              borderColor: const Color(0xFF4C8DFF).withValues(alpha: 0.4),
              borderStrokeWidth: 1,
            ),
          ]),
        MarkerLayer(markers: [
          Marker(
            point: point,
            width: 20,
            height: 20,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF4C8DFF),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
              ),
            ),
          ),
        ]),
      ],
    );
  }
}

/// Rond icoontje voor een watertappunt of toilet.
class PoiIcon extends StatelessWidget {
  const PoiIcon(this.kind, {super.key, this.size = 26});
  final PoiKind kind;
  final double size;

  static const waterColor = Color(0xFF38BDF8);
  static const toiletColor = Color(0xFFA78BFA);

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: kind == PoiKind.water ? waterColor : toiletColor,
          shape: BoxShape.circle,
          border: Border.all(color: RwColors.background, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
        ),
        child: Icon(
          kind == PoiKind.water ? Icons.water_drop : Icons.wc,
          size: size * 0.55,
          color: RwColors.background,
        ),
      );
}
