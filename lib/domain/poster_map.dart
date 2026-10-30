import 'dart:convert';
import 'dart:math' as math;

import 'geo.dart';

/// Soort lijn op de achtergrondkaart van een poster.
enum MapLineKind { major, minor, path, water, waterArea, rail }

/// Eén straat, pad, rivier of meer uit OpenStreetMap, als lijn.
class MapLine {
  const MapLine(this.kind, this.points);
  final MapLineKind kind;
  final List<LatLng> points;
}

/// Kader rond de route, iets ruimer en ongeveer in de vorm van het kaartvlak op de poster (breedte/hoogte ≈ [aspect]),
/// zodat de kaart het hele vlak vult en niet alleen de route.
({double s, double w, double n, double e}) posterMapBounds(List<LatLng> track, {double aspect = 0.9, double margin = 0.18}) {
  var s = track.first.lat, n = s, w = track.first.lon, e = w;
  for (final p in track) {
    s = math.min(s, p.lat);
    n = math.max(n, p.lat);
    w = math.min(w, p.lon);
    e = math.max(e, p.lon);
  }
  final lonScale = math.cos((s + n) / 2 * math.pi / 180);
  var height = math.max(n - s, 0.002);
  var width = math.max((e - w) * lonScale, 0.002);
  if (width / height < aspect) {
    width = height * aspect;
  } else {
    height = width / aspect;
  }
  height *= 1 + margin * 2;
  width *= 1 + margin * 2;
  final cLat = (s + n) / 2, cLon = (w + e) / 2;
  return (s: cLat - height / 2, n: cLat + height / 2, w: cLon - width / lonScale / 2, e: cLon + width / lonScale / 2);
}

/// Overpass-vraag voor de kaart onder een poster. Bij een groot gebied alleen de grotere wegen,
/// anders wordt het antwoord te groot en de poster te druk.
String posterMapQuery(List<LatLng> track) {
  final b = posterMapBounds(track);
  final diag = distanceMeters(LatLng(b.s, b.w), LatLng(b.n, b.e));
  final roads = diag < 7000
      ? 'motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|pedestrian|cycleway|footway|path|track|service'
      : diag < 20000
          ? 'motorway|trunk|primary|secondary|tertiary|unclassified|residential'
          : 'motorway|trunk|primary|secondary|tertiary';
  final bbox = [b.s, b.w, b.n, b.e].map((v) => v.toStringAsFixed(5)).join(',');
  return '[out:json][timeout:25][maxsize:33554432];('
      'way["highway"~"^($roads)\$"]($bbox);'
      'way["waterway"~"^(river|canal|stream)\$"]($bbox);'
      'way["natural"="water"]($bbox);'
      'way["railway"="rail"]($bbox);'
      ');out geom qt;';
}

/// Leest het Overpass-antwoord tot kaartlijnen.
List<MapLine> parsePosterMap(String body) {
  final elements = ((jsonDecode(body) as Map)['elements'] as List?) ?? const [];
  final out = <MapLine>[];
  for (final el in elements.cast<Map>()) {
    final geom = el['geometry'];
    if (geom is! List || geom.length < 2) continue;
    final tags = ((el['tags'] as Map?) ?? const {}).cast<String, dynamic>();
    final kind = posterLineKind(tags);
    if (kind == null) continue;
    final pts = <LatLng>[];
    for (final g in geom.cast<Map>()) {
      final lat = g['lat'], lon = g['lon'];
      if (lat is num && lon is num) pts.add(LatLng(lat.toDouble(), lon.toDouble()));
    }
    if (pts.length >= 2) out.add(MapLine(kind, pts));
  }
  // Water en kleine paden eerst tekenen, grote wegen bovenop.
  out.sort((a, b) => _order(a.kind).compareTo(_order(b.kind)));
  return out;
}

int _order(MapLineKind k) => switch (k) {
      MapLineKind.waterArea => 0,
      MapLineKind.water => 1,
      MapLineKind.path => 2,
      MapLineKind.rail => 3,
      MapLineKind.minor => 4,
      MapLineKind.major => 5,
    };

MapLineKind? posterLineKind(Map<String, dynamic> tags) {
  if (tags['natural'] == 'water') return MapLineKind.waterArea;
  if (tags['waterway'] != null) return MapLineKind.water;
  if (tags['railway'] == 'rail') return MapLineKind.rail;
  final h = tags['highway'];
  if (h == null) return null;
  const major = {'motorway', 'trunk', 'primary', 'secondary'};
  const minor = {'tertiary', 'unclassified', 'residential', 'living_street', 'pedestrian'};
  if (major.contains(h)) return MapLineKind.major;
  if (minor.contains(h)) return MapLineKind.minor;
  return MapLineKind.path;
}

/// Compact bewaren (5 decimalen ≈ 1 m), zodat de opslag klein blijft.
String encodePosterMap(List<MapLine> lines) => jsonEncode([
      for (final l in lines)
        [
          l.kind.index,
          [for (final p in l.points) ...[(p.lat * 1e5).round(), (p.lon * 1e5).round()]],
        ],
    ]);

List<MapLine> decodePosterMap(String text) {
  final out = <MapLine>[];
  for (final item in (jsonDecode(text) as List).cast<List>()) {
    final kind = MapLineKind.values[item[0] as int];
    final c = (item[1] as List).cast<num>();
    out.add(MapLine(kind, [for (var i = 0; i + 1 < c.length; i += 2) LatLng(c[i] / 1e5, c[i + 1] / 1e5)]));
  }
  return out;
}
