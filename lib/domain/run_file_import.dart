import 'package:xml/xml.dart';

import 'geo.dart';

class RunFileException implements Exception {
  RunFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Een run uit een GPX- of TCX-bestand (van een horloge of een andere app).
class ImportedRun {
  ImportedRun({
    required this.start,
    required this.distanceMeters,
    required this.movingSeconds,
    required this.track,
    required this.streams,
    this.averageHeartRate,
    this.elevationGain,
    this.name,
  });

  final DateTime start;
  final double distanceMeters;
  final int movingSeconds;
  final List<LatLng> track;

  /// In dezelfde vorm als eigen opnames (t, d, ll, alt, hr).
  final Map<String, dynamic> streams;
  final int? averageHeartRate;
  final double? elevationGain;
  final String? name;
}

class _Pt {
  _Pt(this.time, this.point, {this.ele, this.hr, this.dist});
  final DateTime time;
  final LatLng? point;
  final double? ele;
  final int? hr;
  final double? dist;
}

String? _child(XmlElement e, String local) =>
    e.descendants.whereType<XmlElement>().where((c) => c.name.local == local).map((c) => c.innerText.trim()).firstOrNull;

/// Leest GPX of TCX (herkent het zelf). Gooit [RunFileException] met een begrijpelijke melding.
ImportedRun parseRunFile(String text) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } catch (_) {
    throw RunFileException('Dit bestand kon niet worden gelezen. Kies een .gpx- of .tcx-bestand.');
  }
  final root = doc.rootElement.name.local;
  final pts = <_Pt>[];
  String? name;
  if (root == 'gpx') {
    name = _child(doc.rootElement, 'name');
    for (final e in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'trkpt')) {
      final t = _child(e, 'time');
      final lat = double.tryParse(e.getAttribute('lat') ?? ''), lon = double.tryParse(e.getAttribute('lon') ?? '');
      if (t == null || lat == null || lon == null) continue;
      final time = DateTime.tryParse(t);
      if (time == null) continue;
      pts.add(_Pt(time, LatLng(lat, lon),
          ele: double.tryParse(_child(e, 'ele') ?? ''), hr: int.tryParse(_child(e, 'hr') ?? '')));
    }
  } else if (root == 'TrainingCenterDatabase') {
    final sport = doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Activity').firstOrNull?.getAttribute('Sport');
    if (sport != null && sport.toLowerCase() != 'running') {
      throw RunFileException('Dit is geen hardloopactiviteit ($sport).');
    }
    for (final e in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Trackpoint')) {
      final time = DateTime.tryParse(_child(e, 'Time') ?? '');
      if (time == null) continue;
      final lat = double.tryParse(_child(e, 'LatitudeDegrees') ?? ''), lon = double.tryParse(_child(e, 'LongitudeDegrees') ?? '');
      final hrEl = e.descendants.whereType<XmlElement>().where((c) => c.name.local == 'HeartRateBpm').firstOrNull;
      pts.add(_Pt(
        time,
        lat == null || lon == null ? null : LatLng(lat, lon),
        ele: double.tryParse(_child(e, 'AltitudeMeters') ?? ''),
        hr: hrEl == null ? null : int.tryParse(_child(hrEl, 'Value') ?? ''),
        dist: double.tryParse(_child(e, 'DistanceMeters') ?? ''),
      ));
    }
  } else {
    throw RunFileException('Onbekend bestand. Kies een .gpx- of .tcx-bestand.');
  }
  pts.sort((a, b) => a.time.compareTo(b.time));
  if (pts.length < 10) throw RunFileException('Er staan te weinig meetpunten met tijd in dit bestand.');

  // Afstand: uit het bestand (TCX) of zelf rekenen. Bewegende tijd: stukken waarin je echt beweegt.
  final t = <double>[], d = <double>[], alt = <double?>[], hr = <int?>[];
  final ll = <List<double>>[];
  var dist = 0.0, moving = 0.0, gain = 0.0;
  double? refEle;
  final t0 = pts.first.time;
  LatLng? lastPos;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    if (i > 0) {
      final dt = p.time.difference(pts[i - 1].time).inMilliseconds / 1000;
      double step;
      if (p.dist != null && pts[i - 1].dist != null) {
        step = (p.dist! - pts[i - 1].dist!).clamp(0, double.infinity).toDouble();
      } else if (p.point != null && lastPos != null) {
        step = distanceMeters(lastPos, p.point!);
      } else {
        step = 0;
      }
      if (dt > 0 && step / dt <= 12) {
        dist += step;
        if (dt <= 30 && step / dt >= 0.5) moving += dt;
      }
    }
    if (p.point != null) lastPos = p.point;
    final e = p.ele;
    if (e != null) {
      if (refEle == null) {
        refEle = e;
      } else if (e - refEle > 2) {
        gain += e - refEle;
        refEle = e;
      } else if (refEle - e > 2) {
        refEle = e;
      }
    }
    t.add(double.parse(moving.toStringAsFixed(1)));
    d.add(double.parse(dist.toStringAsFixed(1)));
    alt.add(e);
    hr.add(p.hr);
    final pos = p.point ?? lastPos;
    ll.add(pos == null ? [0, 0] : [double.parse(pos.lat.toStringAsFixed(6)), double.parse(pos.lon.toStringAsFixed(6))]);
  }
  if (dist < 200) throw RunFileException('Deze run is korter dan 200 meter.');

  List<double>? fill(List<num?> v) {
    if (v.every((x) => x == null)) return null;
    num? last = v.firstWhere((x) => x != null);
    return [for (final x in v) (last = x ?? last)!.toDouble()];
  }

  final hrs = [for (final x in hr) if (x != null && x > 30) x];
  final track = [for (final p in pts) if (p.point != null) p.point!];
  // Spoor uitdunnen tot een punt om de ~15 m.
  final thin = <LatLng>[];
  for (final p in track) {
    if (thin.isEmpty || distanceMeters(thin.last, p) >= 15) thin.add(p);
  }
  if (track.isNotEmpty && thin.last != track.last) thin.add(track.last);

  return ImportedRun(
    start: t0,
    distanceMeters: dist,
    movingSeconds: moving.round() > 0 ? moving.round() : pts.last.time.difference(t0).inSeconds,
    track: thin,
    streams: {
      't': t,
      'd': d,
      if (track.isNotEmpty) 'll': ll,
      if (fill(alt) case final a?) 'alt': a,
      if (fill(hr) case final h?) 'hr': h,
      'src': 'import',
    },
    averageHeartRate: hrs.isEmpty ? null : (hrs.reduce((a, b) => a + b) / hrs.length).round(),
    elevationGain: alt.every((x) => x == null) ? null : gain,
    name: name,
  );
}
