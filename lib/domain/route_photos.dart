import 'dart:convert';
import 'dart:math' as math;

import 'geo.dart';
import 'route_geometry.dart';

/// Een plek op de route waar we een straatfoto zoeken.
class PhotoSample {
  const PhotoSample(this.meters, this.point, this.bearing);
  final double meters;
  final LatLng point;

  /// Looprichting op dat punt (graden), zodat de foto vooruit kijkt.
  final double bearing;
}

/// Gelijkmatig verdeelde punten langs de route (niet precies op de start).
List<PhotoSample> photoSamples(RouteTrack t, {double every = 500, int max = 16, int min = 2}) {
  if (!t.isValid) return const [];
  final n = (t.length / every).round().clamp(min, max);
  return [
    for (var i = 0; i < n; i++)
      () {
        final m = (i + 0.5) * t.length / n;
        final a = t.at(math.max(0, m - 15)), b = t.at(math.min(t.length, m + 15));
        return PhotoSample(m, t.at(m), bearingDegrees(a, b));
      }(),
  ];
}

enum PhotoSource { street, landmark }

/// Een foto langs de route: een straatfoto (Mapillary) of een bezienswaardigheid (Wikipedia).
class RoutePhoto {
  const RoutePhoto({
    required this.source,
    required this.url,
    required this.thumb,
    required this.point,
    required this.meters,
    this.title,
    this.description,
    this.creator,
    this.capturedAt,
    this.link,
  });

  final PhotoSource source;
  final String url;
  final String thumb;
  final LatLng point;

  /// Afstand vanaf de start van de route.
  final double meters;
  final String? title;
  final String? description;
  final String? creator;
  final DateTime? capturedAt;

  /// Pagina met meer uitleg en de licentie.
  final String? link;

  String get credit => switch (source) {
        PhotoSource.street => 'Foto ${creator == null ? '' : '$creator '}via Mapillary · CC BY-SA 4.0',
        PhotoSource.landmark => 'Foto via Wikipedia / Wikimedia Commons',
      };
}

/// Antwoord van de server-functie street-photos.
List<RoutePhoto> parseStreetPhotos(Object? data, List<PhotoSample> samples) {
  final list = data is Map ? data['photos'] : null;
  if (list is! List) return const [];
  final out = <RoutePhoto>[];
  for (final p in list) {
    if (p is! Map) continue;
    final i = (p['index'] as num?)?.toInt();
    final url = p['url'] as String?;
    final lat = (p['lat'] as num?)?.toDouble(), lon = (p['lon'] as num?)?.toDouble();
    if (i == null || i < 0 || i >= samples.length || url == null || lat == null || lon == null) continue;
    final ts = (p['captured_at'] as num?)?.toInt();
    out.add(RoutePhoto(
      source: PhotoSource.street,
      url: url,
      thumb: (p['thumb'] as String?) ?? url,
      point: LatLng(lat, lon),
      meters: samples[i].meters,
      creator: p['creator'] as String?,
      capturedAt: ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts),
      link: p['id'] == null ? null : 'https://www.mapillary.com/app/?pKey=${p['id']}',
    ));
  }
  out.sort((a, b) => a.meters.compareTo(b.meters));
  return out;
}

/// Vakje om de route heen (zuid, west, noord, oost) met wat marge.
({double south, double west, double north, double east}) routeBounds(List<LatLng> pts, {double marginM = 200}) {
  var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
  for (final p in pts) {
    s = math.min(s, p.lat);
    n = math.max(n, p.lat);
    w = math.min(w, p.lon);
    e = math.max(e, p.lon);
  }
  final dLat = marginM / 110540;
  final dLon = marginM / (111320 * math.cos(((s + n) / 2) * math.pi / 180));
  return (south: s - dLat, west: w - dLon, north: n + dLat, east: e + dLon);
}

/// Dichtstbijzijnde plek op de route: afstand vanaf de start en hoe ver ernaast.
({double meters, double off}) projectOnTrack(RouteTrack t, LatLng p) {
  var best = double.infinity, at = 0.0;
  // Per stukje de loodrechte afstand (vlakke benadering, ruim nauwkeurig genoeg).
  final cosLat = math.cos(p.lat * math.pi / 180);
  for (var i = 0; i < t.points.length - 1; i++) {
    final a = t.points[i], b = t.points[i + 1];
    final ax = a.lon * 111320 * cosLat, ay = a.lat * 110540;
    final bx = b.lon * 111320 * cosLat, by = b.lat * 110540;
    final px = p.lon * 111320 * cosLat, py = p.lat * 110540;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final f = len2 <= 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
    final qx = ax + f * dx, qy = ay + f * dy;
    final d = math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy));
    if (d < best) {
      best = d;
      at = t.cumulative[i] + f * (t.cumulative[i + 1] - t.cumulative[i]);
    }
  }
  return (meters: at, off: best);
}

/// Wikipedia-artikelen met een foto, binnen [maxOff] meter van de route.
List<RoutePhoto> parseWikipediaLandmarks(String body, RouteTrack t, {double maxOff = 150, String lang = 'nl'}) {
  final raw = (jsonDecode(body) as Map)['query']?['pages'];
  // formatversion=2 geeft een lijst, de oude vorm een map.
  final Iterable<Object?> pages = raw is Map ? raw.values : (raw is List ? raw : const []);
  final out = <RoutePhoto>[];
  for (final page in pages) {
    if (page is! Map) continue;
    final thumb = page['thumbnail']?['source'] as String?;
    final coords = page['coordinates'];
    if (thumb == null || coords is! List || coords.isEmpty) continue;
    final c = coords.first as Map;
    final p = LatLng((c['lat'] as num).toDouble(), (c['lon'] as num).toDouble());
    final pr = projectOnTrack(t, p);
    if (pr.off > maxOff) continue;
    final title = page['title'] as String? ?? '';
    out.add(RoutePhoto(
      source: PhotoSource.landmark,
      url: thumb,
      thumb: thumb,
      point: p,
      meters: pr.meters,
      title: title,
      description: page['description'] as String?,
      link: 'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
    ));
  }
  out.sort((a, b) => a.meters.compareTo(b.meters));
  return out;
}

/// Straatfoto's en bezienswaardigheden samen, op volgorde langs de route.
/// Een straatfoto vlak bij een bezienswaardigheid laten we weg (dubbel).
List<RoutePhoto> mergeRoutePhotos(List<RoutePhoto> street, List<RoutePhoto> landmarks) {
  final out = [
    ...landmarks,
    for (final s in street)
      if (!landmarks.any((l) => (l.meters - s.meters).abs() < 120)) s,
  ]..sort((a, b) => a.meters.compareTo(b.meters));
  return out;
}
