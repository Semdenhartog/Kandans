import 'package:xml/xml.dart';

import '../data/models/models.dart';
import 'geo.dart';
import 'route_geometry.dart';

class GpxParseException implements Exception {
  GpxParseException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Zet een GPX-bestand om naar een [RunRoute] met punten per kilometer.
///
/// [estimatedPaceSecPerKm] wordt gebruikt om de verwachte duur te berekenen.
RunRoute parseGpx(
  String gpxText, {
  String? fallbackName,
  double estimatedPaceSecPerKm = 360,
}) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(gpxText);
  } catch (_) {
    throw GpxParseException('Dit lijkt geen geldig GPX-bestand.');
  }

  // Track-punten hebben voorkeur, anders route-punten.
  var nodes = doc.findAllElements('trkpt').toList();
  if (nodes.isEmpty) nodes = doc.findAllElements('rtept').toList();
  if (nodes.length < 2) {
    throw GpxParseException('Er staan te weinig punten in dit GPX-bestand.');
  }

  final raw = <LatLng>[];
  for (final n in nodes) {
    final lat = double.tryParse(n.getAttribute('lat') ?? '');
    final lon = double.tryParse(n.getAttribute('lon') ?? '');
    if (lat == null || lon == null) continue;
    final eleText = n.getElement('ele')?.innerText;
    raw.add(LatLng(lat, lon, eleText == null ? null : double.tryParse(eleText)));
  }
  if (raw.length < 2) {
    throw GpxParseException('Er staan te weinig geldige punten in dit GPX-bestand.');
  }

  final name = doc.findAllElements('name').map((e) => e.innerText.trim()).firstWhere(
        (n) => n.isNotEmpty,
        orElse: () => fallbackName ?? 'Nieuwe route',
      );
  return buildRoute(raw, name: name, source: 'gpx_upload', estimatedPaceSecPerKm: estimatedPaceSecPerKm);
}

/// Maakt een route (met punten per kilometer en looprichting) van een lijst GPS-punten.
/// Gebruikt voor GPX-bestanden en voor routes die RunWise zelf maakt.
RunRoute buildRoute(
  List<LatLng> raw, {
  required String name,
  required String source,
  double estimatedPaceSecPerKm = 360,
}) {
  if (raw.length < 2) {
    throw GpxParseException('Er staan te weinig punten in deze route.');
  }
  // Totale afstand en hoogtemeters (kleine schommelingen < 2 m negeren).
  var total = 0.0;
  var gain = 0.0;
  double? refEle = raw.first.ele;
  final cumulative = <double>[0];
  for (var i = 1; i < raw.length; i++) {
    total += distanceMeters(raw[i - 1], raw[i]);
    cumulative.add(total);
    final e = raw[i].ele;
    if (e != null) {
      if (refEle == null) {
        refEle = e;
      } else if (e - refEle >= 2) {
        gain += e - refEle;
        refEle = e;
      } else if (refEle - e >= 2) {
        refEle = e;
      }
    }
  }
  if (total < 200) {
    throw GpxParseException('Deze route is korter dan 200 meter.');
  }

  // Vereenvoudigde track (ongeveer elke 40 m een punt) voor de polyline.
  final simplified = <LatLng>[raw.first];
  var lastKept = 0.0;
  for (var i = 1; i < raw.length - 1; i++) {
    if (cumulative[i] - lastKept >= 40) {
      simplified.add(raw[i]);
      lastKept = cumulative[i];
    }
  }
  simplified.add(raw.last);

  // Punten per kilometer met looprichting (richting naar ~150 m verderop).
  final points = <RoutePoint>[];
  var nextKm = 0.0;
  for (var i = 0; i < raw.length; i++) {
    final isLast = i == raw.length - 1;
    if (cumulative[i] >= nextKm * 1000 || isLast) {
      var j = i + 1;
      while (j < raw.length - 1 && cumulative[j] - cumulative[i] < 150) {
        j++;
      }
      final double? bearing = isLast || j >= raw.length
          ? (points.isNotEmpty ? points.last.bearing : null)
          : bearingDegrees(raw[i], raw[j]);
      points.add(RoutePoint(
        latitude: raw[i].lat,
        longitude: raw[i].lon,
        elevation: raw[i].ele,
        kmMarker: cumulative[i] / 1000,
        bearing: bearing,
      ));
      nextKm = (cumulative[i] / 1000).floorToDouble() + 1;
      if (isLast) break;
    }
  }

  return RunRoute(
    name: name.length > 80 ? name.substring(0, 80) : name,
    source: source,
    distanceMeters: double.parse(total.toStringAsFixed(1)),
    elevationGainMeters: double.parse(gain.toStringAsFixed(1)),
    estimatedDurationSeconds: (total / 1000 * estimatedPaceSecPerKm).round(),
    startLatitude: raw.first.lat,
    startLongitude: raw.first.lon,
    polyline: encodePolyline(simplified),
    points: points,
    elevationProfile: sampleElevation(raw),
  );
}

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Maakt een GPX-bestand van een route, om op je horloge te volgen
/// (Garmin Connect, Coros, Suunto, Komoot). Als [profile] er is, krijgt elk
/// punt ook een hoogte.
String buildGpx(String name, List<LatLng> points, {List<ElevationSample> profile = const []}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="RunWise" xmlns="http://www.topografix.com/GPX/1/1">')
    ..writeln('  <metadata><name>${_xml(name)}</name></metadata>')
    ..writeln('  <trk>')
    ..writeln('    <name>${_xml(name)}</name>')
    ..writeln('    <type>running</type>')
    ..writeln('    <trkseg>');
  final track = RouteTrack(points);
  final scale = profile.isEmpty || track.length <= 0 ? 0.0 : profile.last.meters / track.length;
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    final ele = p.ele ?? (profile.isEmpty ? null : elevationAt(profile, track.cumulative[i] * scale));
    b.write('      <trkpt lat="${p.lat.toStringAsFixed(6)}" lon="${p.lon.toStringAsFixed(6)}">');
    if (ele != null) b.write('<ele>${ele.toStringAsFixed(1)}</ele>');
    b.writeln('</trkpt>');
  }
  b
    ..writeln('    </trkseg>')
    ..writeln('  </trk>')
    ..writeln('</gpx>');
  return b.toString();
}
