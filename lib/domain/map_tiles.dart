import 'dart:math' as math;

import 'geo.dart';

/// Kaarttegel in het gewone web-schema (zoom, x, y).
class TileId {
  const TileId(this.z, this.x, this.y);
  final int z, x, y;

  @override
  bool operator ==(Object o) => o is TileId && o.z == z && o.x == x && o.y == y;
  @override
  int get hashCode => Object.hash(z, x, y);
  @override
  String toString() => '$z/$x/$y';
}

/// Gratis PDOK-kaart (grijs). Zelfde adres als in `route_map.dart`, zodat opgeslagen tegels daar gevonden worden.
const pdokGreyTiles = 'https://service.pdok.nl/brt/achtergrondkaart/wmts/v2_0/grijs/EPSG:3857/{z}/{x}/{y}.png';

String tileUrl(String template, TileId t) =>
    template.replaceAll('{z}', '${t.z}').replaceAll('{x}', '${t.x}').replaceAll('{y}', '${t.y}');

int tileX(double lon, int z) => ((lon + 180) / 360 * (1 << z)).floor().clamp(0, (1 << z) - 1);

int tileY(double lat, int z) {
  final r = lat * math.pi / 180;
  final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * (1 << z);
  return y.floor().clamp(0, (1 << z) - 1);
}

/// PDOK dekt alleen Nederland; daarbuiten is een offline kaart zinloos.
bool inNetherlands(LatLng p) => p.lat >= 50.7 && p.lat <= 53.7 && p.lon >= 3.2 && p.lon <= 7.3;

/// Welke tegels nodig zijn om een route (met [bufferMeters] eromheen) offline te kunnen bekijken.
class TilePlan {
  const TilePlan(this.tiles, this.maxZoom);
  final List<TileId> tiles;
  final int maxZoom;
}

/// Tegels van [minZoom] tot en met [maxZoom] langs de route. Zijn het er meer dan [maxTiles], dan
/// wordt het hoogste zoomniveau weggelaten tot het past. Null als het ook op [minZoom] niet past.
TilePlan? tilePlanForTrack(
  List<LatLng> track, {
  int minZoom = 13,
  int maxZoom = 17,
  double bufferMeters = 500,
  int maxTiles = 3000,
}) {
  if (track.length < 2) return null;
  final pts = _densify(track, 100);
  for (var top = maxZoom; top >= minZoom; top--) {
    final set = <TileId>{};
    for (var z = minZoom; z <= top; z++) {
      for (final p in pts) {
        final dLat = bufferMeters / 111320;
        final dLon = bufferMeters / (111320 * math.cos(p.lat * math.pi / 180));
        final x0 = tileX(p.lon - dLon, z), x1 = tileX(p.lon + dLon, z);
        final y0 = tileY(p.lat + dLat, z), y1 = tileY(p.lat - dLat, z);
        for (var x = x0; x <= x1; x++) {
          for (var y = y0; y <= y1; y++) {
            set.add(TileId(z, x, y));
          }
        }
        if (set.length > maxTiles * 2) break; // veel te groot: niet verder rekenen
      }
    }
    if (set.length <= maxTiles) return TilePlan(set.toList(), top);
  }
  return null;
}

List<LatLng> _densify(List<LatLng> track, double every) {
  final out = <LatLng>[track.first];
  for (var i = 1; i < track.length; i++) {
    final a = track[i - 1], b = track[i];
    final d = distanceMeters(a, b);
    final n = (d / every).floor();
    for (var k = 1; k <= n; k++) {
      final f = k * every / d;
      out.add(LatLng(a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f));
    }
    out.add(b);
  }
  return out;
}

/// Grove schatting van de grootte in bytes (een grijze PDOK-tegel is gemiddeld zo'n 15 kB).
int estimateTileBytes(int tiles) => tiles * 15 * 1024;
