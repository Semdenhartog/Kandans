import 'dart:convert';
import 'dart:math' as math;

import 'geo.dart';
import 'route_geometry.dart';

/// Straatverlichting langs een route, uit OpenStreetMap (tag "lit" op wegen en paden).

/// Punten om de [every] meter langs de route (voor een korte Overpass-vraag).
List<LatLng> sampleTrack(RouteTrack t, {double every = 120, int max = 110}) {
  if (!t.isValid) return const [];
  final step = math.max(every, t.length / max);
  return [for (var m = 0.0; m <= t.length; m += step) t.at(m)];
}

/// Overpass-vraag: alle wegen en paden binnen 20 m van de route, met hun vorm.
/// Lichter dan voorheen (minder punten, kleinere straal), zodat de server sneller antwoordt.
String litQuery(List<LatLng> samples) {
  final coords = samples.map((p) => '${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)}').join(',');
  return '[out:json][timeout:20];way["highway"](around:20,$coords);out tags geom 1500;';
}

class LitWay {
  const LitWay(this.points, this.lit);
  final List<LatLng> points;

  /// true = verlicht, false = niet verlicht, null = onbekend.
  final bool? lit;
}

List<LitWay> parseLitWays(String body) {
  final elements = ((jsonDecode(body) as Map)['elements'] as List?) ?? const [];
  final out = <LitWay>[];
  for (final el in elements.cast<Map>()) {
    final geom = el['geometry'];
    if (geom is! List || geom.length < 2) continue;
    final tags = ((el['tags'] as Map?) ?? const {}).cast<String, dynamic>();
    final v = tags['lit'];
    final bool? lit = switch (v) {
      'yes' || '24/7' || 'automatic' || 'limited' || 'interval' || 'sunset-sunrise' || 'dusk-dawn' => true,
      'no' || 'disused' => false,
      _ => null,
    };
    out.add(LitWay([
      for (final g in geom.cast<Map>())
        if (g['lat'] is num && g['lon'] is num) LatLng((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()),
    ], lit));
  }
  return out;
}

double _toSegment(LatLng p, LatLng a, LatLng b) {
  final cosLat = math.cos(p.lat * math.pi / 180);
  final ax = a.lon * 111320 * cosLat, ay = a.lat * 110540;
  final bx = b.lon * 111320 * cosLat, by = b.lat * 110540;
  final px = p.lon * 111320 * cosLat, py = p.lat * 110540;
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final f = len2 <= 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
  final qx = ax + f * dx, qy = ay + f * dy;
  return math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy));
}

/// Meters van de route die verlicht, onverlicht of onbekend zijn. Per stukje telt de dichtstbijzijnde weg.
({double lit, double unlit, double unknown}) lightingAlong(RouteTrack track, List<LitWay> ways, {double maxOff = 25}) {
  var lit = 0.0, unlit = 0.0, unknown = 0.0;
  if (!track.isValid) return (lit: 0, unlit: 0, unknown: 0);
  const step = 40.0;
  for (var m = step / 2; m < track.length; m += step) {
    final p = track.at(m);
    final seg = math.min(step, track.length - (m - step / 2));
    var best = double.infinity;
    bool? value;
    for (final w in ways) {
      for (var i = 0; i < w.points.length - 1; i++) {
        final d = _toSegment(p, w.points[i], w.points[i + 1]);
        // Bij twee even dichte wegen telt de verlichte (bijv. fietspad naast de weg).
        if (d < best - 3 || (d <= best + 3 && w.lit == true && value != true)) {
          if (d < best) best = d;
          value = w.lit;
        }
      }
    }
    if (best > maxOff || value == null) {
      unknown += seg;
    } else if (value) {
      lit += seg;
    } else {
      unlit += seg;
    }
  }
  return (lit: lit, unlit: unlit, unknown: unknown);
}
