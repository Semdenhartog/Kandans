import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/theme.dart';
import '../../domain/geo.dart';

/// Ondergrond van de kaart.
enum MapLayer { kaart, luchtfoto }

/// Gratis Nederlandse kaarten van PDOK (Kadaster), zonder sleutel.
/// Buiten Nederland blijft de ondergrond leeg; de route wordt wel getekend.
const _tiles = {
  MapLayer.kaart: 'https://service.pdok.nl/brt/achtergrondkaart/wmts/v2_0/standaard/EPSG:3857/{z}/{x}/{y}.png',
  MapLayer.luchtfoto: 'https://service.pdok.nl/hwh/luchtfotorgb/wmts/v1_0/Actueel_orthoHR/EPSG:3857/{z}/{x}/{y}.jpeg',
};

/// Route op een echte kaart, met keuze tussen kaart en luchtfoto.
class RouteMap extends StatefulWidget {
  const RouteMap({
    super.key,
    required this.polyline,
    this.windFromDegrees,
    this.interactive = true,
    this.showLayerToggle = true,
    this.initialLayer = MapLayer.kaart,
  });

  final String polyline;
  final double? windFromDegrees;
  final bool interactive;
  final bool showLayerToggle;
  final MapLayer initialLayer;

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  late MapLayer _layer = widget.initialLayer;
  late List<ll.LatLng> _pts = _decode();

  List<ll.LatLng> _decode() => [for (final p in decodePolyline(widget.polyline)) ll.LatLng(p.lat, p.lon)];

  @override
  void didUpdateWidget(covariant RouteMap old) {
    super.didUpdateWidget(old);
    if (old.polyline != widget.polyline) _pts = _decode();
  }

  @override
  Widget build(BuildContext context) {
    if (_pts.length < 2) {
      return Container(
        decoration: BoxDecoration(color: RwColors.surfaceHigh, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: const Text('Geen route', style: TextStyle(color: RwColors.subtle)),
      );
    }
    final photo = _layer == MapLayer.luchtfoto;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          FlutterMap(
            key: ValueKey(widget.polyline),
            options: MapOptions(
              initialCameraFit: CameraFit.coordinates(coordinates: _pts, padding: const EdgeInsets.all(28)),
              backgroundColor: RwColors.surfaceHigh,
              maxZoom: 19,
              interactionOptions: InteractionOptions(
                flags: widget.interactive
                    ? InteractiveFlag.all & ~InteractiveFlag.rotate
                    : InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: _tiles[_layer]!,
                userAgentPackageName: 'nl.runwise.app',
                maxNativeZoom: 19,
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _pts,
                    strokeWidth: 4.5,
                    color: RwColors.accent,
                    borderStrokeWidth: 2,
                    borderColor: photo ? Colors.white : RwColors.accentDark,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(point: _pts.last, width: 14, height: 14, child: const _Dot(RwColors.danger)),
                  Marker(point: _pts.first, width: 18, height: 18, child: const _Dot(RwColors.text)),
                ],
              ),
            ],
          ),
          if (widget.windFromDegrees != null)
            Positioned(top: 8, right: 8, child: _WindBadge(widget.windFromDegrees!)),
          if (widget.showLayerToggle)
            Positioned(
              top: 8,
              left: 8,
              child: _LayerToggle(
                layer: _layer,
                onChanged: (l) => setState(() => _layer = l),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: Colors.black54,
              child: Text(
                photo ? 'Luchtfoto © Beeldmateriaal.nl / PDOK' : 'Kaart © Kadaster / PDOK',
                style: const TextStyle(fontSize: 9, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: RwColors.accentDark, width: 2),
        ),
      );
}

class _LayerToggle extends StatelessWidget {
  const _LayerToggle({required this.layer, required this.onChanged});
  final MapLayer layer;
  final ValueChanged<MapLayer> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(MapLayer l, String label) {
      final on = layer == l;
      return GestureDetector(
        onTap: () => onChanged(l),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: on ? RwColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: on ? RwColors.accentDark : RwColors.text,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: RwColors.background.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [chip(MapLayer.kaart, 'Kaart'), chip(MapLayer.luchtfoto, 'Satelliet')],
      ),
    );
  }
}

/// Pijl in de richting waar de wind naartoe waait.
class _WindBadge extends StatelessWidget {
  const _WindBadge(this.fromDegrees);
  final double fromDegrees;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: RwColors.background.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: Transform.rotate(
          angle: (fromDegrees + 180) * math.pi / 180,
          child: const Icon(Icons.arrow_upward, size: 20, color: RwColors.text),
        ),
      );
}
