import 'dart:math' as math;

import 'geo.dart';

/// Het verloop van een run: per meetpunt de tijd (s), afstand (m) en eventueel
/// hoogte, hartslag en positie. Uit Strava.
class RunStreams {
  const RunStreams({required this.time, required this.distance, this.altitude, this.heartRate, this.positions});

  final List<double> time;
  final List<double> distance;
  final List<double>? altitude;
  final List<double>? heartRate;
  final List<LatLng>? positions;

  int get length => time.length;
  double get totalDistance => distance.isEmpty ? 0 : distance.last;
  double get totalTime => time.isEmpty ? 0 : time.last - time.first;

  static RunStreams? fromJson(Object? json) {
    if (json is! Map) return null;
    List<double>? nums(Object? v) => v is List ? [for (final x in v) (x as num?)?.toDouble() ?? 0] : null;
    final t = nums(json['t']), d = nums(json['d']);
    if (t == null || d == null || t.length < 2 || t.length != d.length) return null;
    List<double>? same(List<double>? v) => v != null && v.length == t.length ? v : null;
    List<LatLng>? pos;
    final ll = json['ll'];
    if (ll is List && ll.length == t.length) {
      pos = [
        for (final p in ll)
          if (p is List && p.length >= 2) LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()) else const LatLng(0, 0),
      ];
    }
    return RunStreams(time: t, distance: d, altitude: same(nums(json['alt'])), heartRate: same(nums(json['hr'])), positions: pos);
  }

  /// Waarde van [series] op afstand [m] (lineair tussen de meetpunten).
  double? valueAt(List<double> series, double m) {
    if (series.isEmpty) return null;
    if (m <= distance.first) return series.first;
    for (var i = 1; i < distance.length; i++) {
      if (distance[i] >= m) {
        final span = distance[i] - distance[i - 1];
        final f = span <= 0 ? 0.0 : (m - distance[i - 1]) / span;
        return series[i - 1] + (series[i] - series[i - 1]) * f;
      }
    }
    return series.last;
  }

  LatLng? positionAt(double m) {
    final p = positions;
    if (p == null || p.isEmpty) return null;
    var i = 0;
    while (i < distance.length - 1 && distance[i] < m) {
      i++;
    }
    return p[i];
  }
}

/// Eén kilometer (de laatste kan korter zijn).
class Split {
  const Split({
    required this.index,
    required this.meters,
    required this.seconds,
    this.heartRate,
    this.elevationGain,
    this.bearing,
  });

  /// 1 = eerste kilometer.
  final int index;
  final double meters;
  final double seconds;
  final double? heartRate;
  final double? elevationGain;

  /// Looprichting in deze kilometer (voor de wind), als er posities zijn.
  final double? bearing;

  double get paceSecPerKm => meters <= 0 ? 0 : seconds / (meters / 1000);
  bool get partial => meters < 990;
}

/// Tijden per kilometer. Een laatste stuk korter dan 100 m wordt bij de vorige km geteld.
List<Split> splitsOf(RunStreams s) {
  final total = s.totalDistance;
  if (total < 200) return const [];
  final marks = <double>[0];
  for (var k = 1000.0; k < total; k += 1000) {
    marks.add(k);
  }
  if (total - marks.last < 100 && marks.length > 1) marks.removeLast();
  marks.add(total);

  final out = <Split>[];
  for (var i = 1; i < marks.length; i++) {
    final a = marks[i - 1], b = marks[i];
    final t = (s.valueAt(s.time, b) ?? 0) - (s.valueAt(s.time, a) ?? 0);

    double? hr;
    if (s.heartRate != null) {
      var sum = 0.0, n = 0;
      for (var j = 0; j < s.length; j++) {
        if (s.distance[j] >= a && s.distance[j] <= b && s.heartRate![j] > 0) {
          sum += s.heartRate![j];
          n++;
        }
      }
      if (n > 0) hr = sum / n;
    }

    double? gain;
    if (s.altitude != null) {
      gain = 0;
      double? prev;
      for (var j = 0; j < s.length; j++) {
        if (s.distance[j] < a || s.distance[j] > b) continue;
        final e = s.altitude![j];
        if (prev != null && e > prev) gain = gain! + (e - prev);
        prev = e;
      }
    }

    double? bearing;
    final pa = s.positionAt(a), pb = s.positionAt(b);
    if (pa != null && pb != null && distanceMeters(pa, pb) > 50) bearing = bearingDegrees(pa, pb);

    out.add(Split(index: i, meters: b - a, seconds: t, heartRate: hr, elevationGain: gain, bearing: bearing));
  }
  return out;
}

/// Tempo (s/km) langs de run, gladgestreken over ~[window] meter, voor de grafiek.
/// Geeft (afstand, tempo) paren; onrealistische waarden (stilstaan) vallen weg.
List<({double meters, double pace})> paceSeries(RunStreams s, {double window = 250}) {
  final out = <({double meters, double pace})>[];
  var j = 0;
  for (var i = 0; i < s.length; i++) {
    while (j < i && s.distance[i] - s.distance[j] > window) {
      j++;
    }
    final dd = s.distance[i] - s.distance[j];
    final dt = s.time[i] - s.time[j];
    if (dd < window * 0.5 || dt <= 0) continue;
    final pace = dt / (dd / 1000);
    if (pace < 150 || pace > 1200) continue;
    out.add((meters: s.distance[i], pace: pace));
  }
  return out;
}

/// Snelste en langzaamste hele kilometer.
({Split? fastest, Split? slowest}) extremes(List<Split> splits) {
  final full = splits.where((x) => !x.partial).toList();
  if (full.isEmpty) return (fastest: null, slowest: null);
  return (
    fastest: full.reduce((a, b) => a.paceSecPerKm <= b.paceSecPerKm ? a : b),
    slowest: full.reduce((a, b) => a.paceSecPerKm >= b.paceSecPerKm ? a : b),
  );
}

/// Klein beetje rekenhulp voor de grafiek.
({double min, double max}) rangeOf(Iterable<double> v) {
  var lo = double.infinity, hi = -double.infinity;
  for (final x in v) {
    lo = math.min(lo, x);
    hi = math.max(hi, x);
  }
  return (min: lo, max: hi);
}
