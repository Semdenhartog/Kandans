import 'dart:math' as math;

/// Eenvoudig coördinatenpunt.
class LatLng {
  const LatLng(this.lat, this.lon, [this.ele]);
  final double lat;
  final double lon;
  final double? ele;
}

const _earthRadiusM = 6371000.0;

double _rad(double deg) => deg * math.pi / 180;
double _deg(double rad) => rad * 180 / math.pi;

/// Afstand in meters tussen twee punten (haversine).
double distanceMeters(LatLng a, LatLng b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

/// Looprichting van a naar b in graden (0 = noord, 90 = oost).
double bearingDegrees(LatLng a, LatLng b) {
  final lat1 = _rad(a.lat);
  final lat2 = _rad(b.lat);
  final dLon = _rad(b.lon - a.lon);
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

/// Encodeert punten als Google-polyline (compacte tekst).
String encodePolyline(List<LatLng> points) {
  final out = StringBuffer();
  var prevLat = 0, prevLon = 0;
  void enc(int v) {
    var value = v < 0 ? ~(v << 1) : (v << 1);
    while (value >= 0x20) {
      out.writeCharCode((0x20 | (value & 0x1f)) + 63);
      value >>= 5;
    }
    out.writeCharCode(value + 63);
  }

  for (final p in points) {
    final lat = (p.lat * 1e5).round();
    final lon = (p.lon * 1e5).round();
    enc(lat - prevLat);
    enc(lon - prevLon);
    prevLat = lat;
    prevLon = lon;
  }
  return out.toString();
}

/// Decodeert een Google-polyline. Geeft een lege lijst bij ongeldige invoer.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0, lat = 0, lon = 0;
  try {
    while (index < encoded.length) {
      for (var coord = 0; coord < 2; coord++) {
        var shift = 0, result = 0, b = 0;
        do {
          b = encoded.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20);
        final delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
        if (coord == 0) {
          lat += delta;
        } else {
          lon += delta;
        }
      }
      points.add(LatLng(lat / 1e5, lon / 1e5));
    }
  } catch (_) {
    return const [];
  }
  return points;
}

/// Looprichtingen langs een track, met gewicht = lengte van het stuk.
/// Stukken korter dan [minSegment] meter worden samengevoegd.
List<({double bearing, double meters, double startKm})> trackSegments(
  List<LatLng> track, {
  double minSegment = 80,
}) {
  final segments = <({double bearing, double meters, double startKm})>[];
  if (track.length < 2) return segments;
  var anchor = track.first;
  var travelled = 0.0;
  for (var i = 1; i < track.length; i++) {
    final d = distanceMeters(anchor, track[i]);
    if (d >= minSegment || i == track.length - 1) {
      if (d > 1) {
        segments.add((
          bearing: bearingDegrees(anchor, track[i]),
          meters: d,
          startKm: travelled / 1000,
        ));
      }
      travelled += d;
      anchor = track[i];
    }
  }
  return segments;
}
