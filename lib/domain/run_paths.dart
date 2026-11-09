// Looppaden-laag op de kaart: voet- en fietspaden, onverharde paden en bospaden uit OpenStreetMap,
// in goud over de donkere kaart (vergelijkbaar met de warmtekaart van Strava, maar met open kaartdata:
// het zijn paden waar je kúnt lopen, niet waar anderen gelopen hebben).

import 'dart:convert';

import 'geo.dart';

enum RunPathKind {
  /// Voetpad, voetgangersgebied (verhard).
  foot,

  /// Fietspad (vaak ook prima om te lopen).
  cycle,

  /// Onverhard: bospad, zandpad, veldweg.
  trail,
}

class RunPath {
  const RunPath(this.kind, this.points);
  final RunPathKind kind;
  final List<LatLng> points;
}

/// Grootte van een vak (graden). Paden worden per vak opgehaald en bewaard, zodat een kleine verschuiving
/// niet meteen een nieuwe vraag naar Overpass kost.
const runPathCell = 0.03;

/// Het vak waar een punt in valt (linksonder), als sleutel.
({double s, double w}) runPathCellOf(LatLng p) =>
    (s: (p.lat / runPathCell).floor() * runPathCell, w: (p.lon / runPathCell).floor() * runPathCell);

String runPathCellKey(LatLng p) {
  final c = runPathCellOf(p);
  return 'paths_${c.s.toStringAsFixed(2)}_${c.w.toStringAsFixed(2)}';
}

/// Overpass-vraag voor één vak met een rand van een halve vakbreedte eromheen
/// (zo loopt de laag door als je bij de rand van een vak staat). Stoepen (footway=sidewalk) niet:
/// die liggen langs elke straat en maken de kaart onrustig.
String runPathsQuery(LatLng p) {
  final c = runPathCellOf(p);
  const m = runPathCell / 2;
  final bbox = [c.s - m, c.w - m, c.s + runPathCell + m, c.w + runPathCell + m].map((v) => v.toStringAsFixed(4)).join(',');
  return '[out:json][timeout:25][maxsize:16777216];('
      'way["highway"~"^(footway|path|pedestrian|track|cycleway|bridleway)\$"]["footway"!="sidewalk"]["access"!~"^(private|no)\$"]($bbox);'
      ');out geom qt;';
}

const _unpaved = {'unpaved', 'ground', 'dirt', 'sand', 'grass', 'gravel', 'fine_gravel', 'compacted', 'earth', 'mud', 'woodchips', 'pebblestone'};

RunPathKind? runPathKind(Map<String, dynamic> tags) {
  final hw = tags['highway'];
  final surface = '${tags['surface'] ?? ''}';
  if (_unpaved.contains(surface)) return RunPathKind.trail;
  switch (hw) {
    case 'track' || 'bridleway':
      return RunPathKind.trail;
    case 'path':
      return surface.isEmpty ? RunPathKind.trail : RunPathKind.foot;
    case 'cycleway':
      return RunPathKind.cycle;
    case 'footway' || 'pedestrian':
      return RunPathKind.foot;
  }
  return null;
}

/// Leest het Overpass-antwoord tot paden. Hooguit [max] paden (de langste), zodat de kaart vlot blijft.
List<RunPath> parseRunPaths(String body, {int max = 3000}) {
  final elements = ((jsonDecode(body) as Map)['elements'] as List?) ?? const [];
  final out = <RunPath>[];
  for (final el in elements.cast<Map>()) {
    final geom = el['geometry'];
    if (geom is! List || geom.length < 2) continue;
    final kind = runPathKind(((el['tags'] as Map?) ?? const {}).cast<String, dynamic>());
    if (kind == null) continue;
    final pts = <LatLng>[];
    for (final g in geom.cast<Map>()) {
      final lat = g['lat'], lon = g['lon'];
      if (lat is num && lon is num) pts.add(LatLng(lat.toDouble(), lon.toDouble()));
    }
    if (pts.length >= 2) out.add(RunPath(kind, pts));
  }
  if (out.length > max) {
    double len(RunPath r) {
      var d = 0.0;
      for (var i = 1; i < r.points.length; i++) {
        d += distanceMeters(r.points[i - 1], r.points[i]);
      }
      return d;
    }

    final withLen = [for (final r in out) (r, len(r))]..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final x in withLen.take(max)) x.$1];
  }
  return out;
}

/// Compact bewaren (5 decimalen, ±1 m): [[soort, lat, lon, lat, lon, …], …].
String encodeRunPaths(List<RunPath> paths) => jsonEncode([
      for (final p in paths)
        [p.kind.index, for (final x in p.points) ...[(x.lat * 1e5).round(), (x.lon * 1e5).round()]],
    ]);

List<RunPath> decodeRunPaths(String s) {
  final out = <RunPath>[];
  for (final item in (jsonDecode(s) as List).cast<List>()) {
    final k = item[0] as int;
    if (k < 0 || k >= RunPathKind.values.length) continue;
    final pts = <LatLng>[];
    for (var i = 1; i + 1 < item.length; i += 2) {
      pts.add(LatLng((item[i] as num) / 1e5, (item[i + 1] as num) / 1e5));
    }
    if (pts.length >= 2) out.add(RunPath(RunPathKind.values[k], pts));
  }
  return out;
}
