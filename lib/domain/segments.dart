import 'dart:math' as math;

import 'geo.dart';

/// Eigen segmenten: stukken die je vaak loopt (de dijk, de bosweg) worden vanzelf herkend,
/// met per stuk je beste tijd. Alleen op runs met een eigen GPS-verloop (Kadans-opnames).

class SegTrack {
  const SegTrack(this.id, this.date, this.points, this.time, this.distance);
  final String id;
  final DateTime date;
  final List<LatLng> points;
  final List<double> time;
  final List<double> distance;
}

class Segment {
  const Segment({required this.id, required this.start, required this.end, required this.length, required this.heading, this.name});
  final String id;
  final LatLng start, end;
  final double length;

  /// Kompasrichting van begin naar eind (graden).
  final double heading;
  final String? name;

  Segment named(String? n) => Segment(id: id, start: start, end: end, length: length, heading: heading, name: n);

  Map<String, dynamic> toJson() => {
        'id': id,
        's': [start.lat, start.lon],
        'e': [end.lat, end.lon],
        'l': length,
        'h': heading,
        if (name != null) 'n': name,
      };

  static Segment? fromJson(Map<String, dynamic> j) {
    try {
      final s = (j['s'] as List).cast<num>(), e = (j['e'] as List).cast<num>();
      return Segment(
        id: j['id'] as String,
        start: LatLng(s[0].toDouble(), s[1].toDouble()),
        end: LatLng(e[0].toDouble(), e[1].toDouble()),
        length: (j['l'] as num).toDouble(),
        heading: (j['h'] as num).toDouble(),
        name: j['n'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

typedef _Cell = (int, int);
_Cell _cell(LatLng p) => ((p.lat / 0.0009).floor(), (p.lon / 0.0014).floor()); // ± 100 m

/// Punten om de ~25 m (index in de originele lijsten).
List<int> _resample(SegTrack r, {double every = 25}) {
  final out = <int>[];
  var next = 0.0;
  for (var i = 0; i < r.points.length && i < r.distance.length; i++) {
    if (r.distance[i] >= next) {
      out.add(i);
      next = r.distance[i] + every;
    }
  }
  return out;
}

/// Zoekt stukken van [minLen]–[maxLen] meter die in minstens [minRuns] verschillende runs voorkomen.
List<Segment> findSegments(List<SegTrack> runs, {int minRuns = 3, double minLen = 600, double maxLen = 2500, int max = 8}) {
  if (runs.length < minRuns) return const [];
  final cellRuns = <_Cell, int>{};
  for (final r in runs) {
    final cells = {for (final i in _resample(r)) _cell(r.points[i])};
    for (final c in cells) {
      cellRuns[c] = (cellRuns[c] ?? 0) + 1;
    }
  }
  final sorted = [...runs]..sort((a, b) => b.date.compareTo(a.date));
  final found = <Segment>[];
  for (final r in sorted) {
    final idx = _resample(r);
    var startK = -1;
    void close(int endK) {
      if (startK < 0) return;
      var a = idx[startK];
      final b = idx[endK];
      // Lange stukken in delen van hooguit maxLen.
      while (r.distance[b] - r.distance[a] >= minLen) {
        var e = a;
        for (final i in idx) {
          if (i > a && i <= b && r.distance[i] - r.distance[a] <= maxLen) e = i;
        }
        final len = r.distance[e] - r.distance[a];
        if (len < minLen) break;
        final s = r.points[a], en = r.points[e];
        final dup = found.any((f) =>
            (distanceMeters(f.start, s) < 150 && distanceMeters(f.end, en) < 150) ||
            (distanceMeters(f.start, s) < 300 && (f.heading - bearingDegrees(s, en)).abs() % 360 < 30 && (f.length - len).abs() < 400));
        if (!dup && found.length < max) {
          found.add(Segment(
            id: '${s.lat.toStringAsFixed(4)},${s.lon.toStringAsFixed(4)}>${en.lat.toStringAsFixed(4)},${en.lon.toStringAsFixed(4)}',
            start: s,
            end: en,
            length: len,
            heading: bearingDegrees(s, en),
          ));
        }
        a = e;
      }
      startK = -1;
    }

    for (var k = 0; k < idx.length; k++) {
      final often = (cellRuns[_cell(r.points[idx[k]])] ?? 0) >= minRuns;
      if (often && startK < 0) startK = k;
      if (!often && startK >= 0) close(k - 1);
    }
    if (startK >= 0) close(idx.length - 1);
    if (found.length >= max) break;
  }
  return found;
}

/// Snelste tijd (seconden) over dit stuk in deze run, of null als je het niet liep.
double? effortTime(SegTrack r, Segment s, {double near = 40}) {
  final n = math.min(r.points.length, math.min(r.time.length, r.distance.length));
  double? best;
  for (var i = 0; i < n; i++) {
    if (distanceMeters(r.points[i], s.start) > near) continue;
    for (var j = i + 1; j < n; j++) {
      final dd = r.distance[j] - r.distance[i];
      if (dd > s.length * 1.2) break;
      if (dd < s.length * 0.85) continue;
      if (distanceMeters(r.points[j], s.end) <= near) {
        final t = r.time[j] - r.time[i];
        if (t > 0 && (best == null || t < best)) best = t;
        break;
      }
    }
  }
  return best;
}

/// Naam als je er zelf geen gaf: richting en lengte.
String segmentLabel(Segment s, String Function(double) compass) =>
    s.name ?? 'Stuk ${compass(s.heading)} · ${(s.length / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
