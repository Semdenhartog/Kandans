import 'dart:convert';
import 'dart:math' as math;

import 'geo.dart';
import 'route_geometry.dart';

/// Soort voorziening langs de route.
enum PoiKind { water, toilet }

/// Een watertappunt of toilet langs de route (uit OpenStreetMap).
class RoutePoi {
  const RoutePoi({
    required this.kind,
    required this.point,
    required this.alongMeters,
    required this.offsetMeters,
    this.name,
    this.fee = false,
    this.seasonal = false,
  });

  final PoiKind kind;
  final LatLng point;

  /// Na hoeveel meter vanaf de start je erlangs komt.
  final double alongMeters;

  /// Hoe ver het van de route af ligt.
  final double offsetMeters;
  final String? name;
  final bool fee;

  /// Alleen in een deel van het jaar open (bijv. 's winters afgesloten).
  final bool seasonal;

  String get label => switch (kind) {
        PoiKind.water => 'Watertappunt',
        PoiKind.toilet => fee ? 'Toilet (betaald)' : 'Toilet',
      };
}

/// Ruw punt uit OpenStreetMap, nog niet aan de route gekoppeld.
class OsmPoi {
  const OsmPoi(this.kind, this.point, {this.name, this.fee = false, this.seasonal = false});
  final PoiKind kind;
  final LatLng point;
  final String? name;
  final bool fee;
  final bool seasonal;
}

/// Overpass-zoekopdracht voor water en toiletten binnen een rechthoek.
String overpassQuery(List<LatLng> track, {double padDegrees = 0.003}) {
  var s = track.first.lat, n = s, w = track.first.lon, e = w;
  for (final p in track) {
    s = math.min(s, p.lat);
    n = math.max(n, p.lat);
    w = math.min(w, p.lon);
    e = math.max(e, p.lon);
  }
  final bbox = [s - padDegrees, w - padDegrees, n + padDegrees, e + padDegrees].map((v) => v.toStringAsFixed(5)).join(',');
  return '[out:json][timeout:20];('
      'node["amenity"="drinking_water"]($bbox);'
      'node["amenity"="water_point"]($bbox);'
      'node["drinking_water"="yes"]["amenity"!="toilets"]($bbox);'
      'node["amenity"="toilets"]($bbox);'
      ');out body 300;';
}

/// Leest het Overpass-antwoord. Privé of afgesloten voorzieningen vallen af.
List<OsmPoi> parseOverpass(String body) {
  final elements = ((jsonDecode(body) as Map)['elements'] as List?) ?? const [];
  final out = <OsmPoi>[];
  for (final el in elements.cast<Map>()) {
    final lat = el['lat'], lon = el['lon'];
    if (lat is! num || lon is! num) continue;
    final tags = ((el['tags'] as Map?) ?? const {}).cast<String, dynamic>();
    final access = tags['access'];
    if (access == 'private' || access == 'no' || access == 'customers') continue;
    if (tags['drinking_water'] == 'no') continue;
    final amenity = tags['amenity'];
    final kind = amenity == 'toilets' ? PoiKind.toilet : PoiKind.water;
    out.add(OsmPoi(
      kind,
      LatLng(lat.toDouble(), lon.toDouble()),
      name: tags['name'] as String?,
      fee: tags['fee'] == 'yes',
      seasonal: tags['seasonal'] != null && tags['seasonal'] != 'no',
    ));
  }
  return out;
}

/// Afstand (m) van punt p tot het lijnstuk a-b, plus de positie (0..1) op dat stuk.
({double meters, double t}) _toSegment(LatLng p, LatLng a, LatLng b) {
  // Lokale platte projectie in meters rond punt a.
  final k = math.cos(a.lat * math.pi / 180) * 111320;
  final ax = 0.0, ay = 0.0;
  final bx = (b.lon - a.lon) * k, by = (b.lat - a.lat) * 110540;
  final px = (p.lon - a.lon) * k, py = (p.lat - a.lat) * 110540;
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return (meters: math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy)), t: t);
}

/// Houdt alleen voorzieningen binnen [maxOffset] meter van de route, op volgorde langs de route.
/// Dubbele punten (bijv. twee kranen naast elkaar) worden samengevoegd.
List<RoutePoi> poisAlongRoute(List<OsmPoi> pois, RouteTrack track, {double maxOffset = 150}) {
  if (!track.isValid) return const [];
  final out = <RoutePoi>[];
  for (final poi in pois) {
    var best = double.infinity, along = 0.0;
    for (var i = 0; i < track.points.length - 1; i++) {
      final r = _toSegment(poi.point, track.points[i], track.points[i + 1]);
      if (r.meters < best) {
        best = r.meters;
        along = track.cumulative[i] + r.t * (track.cumulative[i + 1] - track.cumulative[i]);
      }
    }
    if (best > maxOffset) continue;
    final dup = out.any((o) => o.kind == poi.kind && distanceMeters(o.point, poi.point) < 40);
    if (dup) continue;
    out.add(RoutePoi(
      kind: poi.kind,
      point: poi.point,
      alongMeters: along,
      offsetMeters: best,
      name: poi.name,
      fee: poi.fee,
      seasonal: poi.seasonal,
    ));
  }
  out.sort((a, b) => a.alongMeters.compareTo(b.alongMeters));
  return out;
}
