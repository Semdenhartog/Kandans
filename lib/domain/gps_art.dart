import 'dart:math' as math;

import 'geo.dart';

/// GPS-kunst: een vorm op echte paden rond je huis. De vorm gaat als tussenpunten naar de routeplanner.
enum ArtShape {
  heart('Hartje'),
  star('Ster'),
  diamond('Ruit'),
  circle('Cirkel'),
  arrow('Pijl'),
  letterK('Letter K');

  const ArtShape(this.label);
  final String label;
}

/// Vorm in eenheden (x = oost, y = noord), ongeveer tussen -1 en 1. Gesloten: eindigt waar hij begon.
List<(double, double)> artUnitShape(ArtShape s) {
  switch (s) {
    case ArtShape.heart:
      // Klassieke hartkromme, onderste punt eerst.
      return [
        for (var i = 0; i <= 16; i++)
          () {
            final t = math.pi * 2 * i / 16 + math.pi;
            final x = 16 * math.pow(math.sin(t), 3);
            final y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t);
            return (x / 17, y / 17);
          }(),
      ];
    case ArtShape.star:
      return [
        for (var i = 0; i <= 10; i++)
          () {
            final a = math.pi / 2 + math.pi * 2 * i / 10;
            final r = i.isEven ? 1.0 : 0.42;
            return (r * math.cos(a), r * math.sin(a));
          }(),
      ];
    case ArtShape.diamond:
      return const [(0.0, -1.0), (0.7, 0.0), (0.0, 1.0), (-0.7, 0.0), (0.0, -1.0)];
    case ArtShape.circle:
      return [
        for (var i = 0; i <= 12; i++) (math.cos(math.pi * 2 * i / 12), math.sin(math.pi * 2 * i / 12)),
      ];
    case ArtShape.arrow:
      return const [(-0.25, -1.0), (-0.25, 0.2), (-0.7, 0.2), (0.0, 1.0), (0.7, 0.2), (0.25, 0.2), (0.25, -1.0), (-0.25, -1.0)];
    case ArtShape.letterK:
      // Één doorlopende lijn: omhoog, terug naar het midden, schuin omhoog, terug, schuin omlaag, terug naar start.
      return const [(-0.6, -1.0), (-0.6, 1.0), (-0.6, 0.0), (0.6, 1.0), (-0.6, 0.0), (0.6, -1.0), (-0.6, 0.0), (-0.6, -1.0)];
  }
}

double _unitLength(List<(double, double)> u) {
  var m = 0.0;
  for (var i = 1; i < u.length; i++) {
    final dx = u[i].$1 - u[i - 1].$1, dy = u[i].$2 - u[i - 1].$2;
    m += math.sqrt(dx * dx + dy * dy);
  }
  return m;
}

/// Wegen lopen niet recht: de echte route wordt ongeveer zoveel langer dan de getekende vorm.
const artRoadFactor = 1.25;

/// Tussenpunten voor een vorm van ongeveer [targetMeters] rond [center].
List<LatLng> artWaypoints(ArtShape s, LatLng center, double targetMeters) {
  final u = artUnitShape(s);
  final scale = targetMeters / artRoadFactor / _unitLength(u); // meter per eenheid
  final mLat = 111320.0, mLon = 111320.0 * math.cos(center.lat * math.pi / 180);
  final pts = [for (final (x, y) in u) LatLng(center.lat + y * scale / mLat, center.lon + x * scale / mLon)];
  // Dubbele opeenvolgende punten weg (de routeplanner heeft er niets aan).
  final out = <LatLng>[];
  for (final p in pts) {
    if (out.isEmpty || distanceMeters(out.last, p) > 5) out.add(p);
  }
  return out;
}

double _toSegment(LatLng p, LatLng a, LatLng b) {
  final mLon = math.cos(p.lat * math.pi / 180);
  final ax = a.lon * mLon, ay = a.lat, bx = b.lon * mLon, by = b.lat, px = p.lon * mLon, py = p.lat;
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy)) * 111320;
}

/// Hoe goed de gelopen of geplande route de vorm volgt (0–100).
/// Vergelijkt hoe ver de routepunten gemiddeld van de vorm liggen met de grootte van de vorm.
int artFidelity(List<LatLng> route, List<LatLng> shape) {
  if (route.length < 2 || shape.length < 2) return 0;
  var minLat = shape.first.lat, maxLat = minLat, minLon = shape.first.lon, maxLon = minLon;
  for (final p in shape) {
    minLat = math.min(minLat, p.lat);
    maxLat = math.max(maxLat, p.lat);
    minLon = math.min(minLon, p.lon);
    maxLon = math.max(maxLon, p.lon);
  }
  final size = distanceMeters(LatLng(minLat, minLon), LatLng(maxLat, maxLon));
  if (size <= 0) return 0;
  var sum = 0.0;
  final step = math.max(1, route.length ~/ 200);
  var n = 0;
  for (var i = 0; i < route.length; i += step) {
    var best = double.infinity;
    for (var j = 1; j < shape.length; j++) {
      best = math.min(best, _toSegment(route[i], shape[j - 1], shape[j]));
    }
    sum += best;
    n++;
  }
  final mean = sum / n;
  return ((1 - mean / (size * 0.15)) * 100).clamp(0, 100).round();
}
