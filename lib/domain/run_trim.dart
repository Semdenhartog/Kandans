import 'geo.dart';

/// Resultaat van een bijgesneden run.
class TrimmedRun {
  const TrimmedRun({
    required this.streams,
    required this.distanceMeters,
    required this.movingSeconds,
    required this.startOffsetSeconds,
    required this.track,
    this.averageHeartRate,
  });

  /// Het nieuwe verloop (zelfde vorm als het origineel, t en d beginnen bij 0).
  final Map<String, dynamic> streams;
  final double distanceMeters;
  final int movingSeconds;

  /// Hoeveel (bewegende) seconden er aan het begin af zijn; om de starttijd op te schuiven.
  final double startOffsetSeconds;

  /// Spoor om als polyline op te slaan (punt om de ~20 m). Leeg zonder posities.
  final List<LatLng> track;
  final int? averageHeartRate;
}

/// Snijdt een opgenomen run bij tot de meetpunten [from] t/m [to].
///
/// Alle reeksen in [streams] met dezelfde lengte als `t` worden mee gesneden (ook
/// reeksen die later zijn toegevoegd, zoals een verbeterde hoogte). Null als er na het
/// snijden te weinig over is.
TrimmedRun? trimRun(Map<String, dynamic> streams, int from, int to) {
  final t = _nums(streams['t']);
  final d = _nums(streams['d']);
  if (t == null || d == null || t.length != d.length || t.length < 2) return null;
  final n = t.length;
  if (from < 0) from = 0;
  if (to > n - 1) to = n - 1;
  if (to - from < 1) return null;

  final t0 = t[from], d0 = d[from];
  final out = <String, dynamic>{};
  for (final e in streams.entries) {
    final v = e.value;
    if (e.key == 't') {
      out['t'] = [for (var i = from; i <= to; i++) _round1(t[i] - t0)];
    } else if (e.key == 'd') {
      out['d'] = [for (var i = from; i <= to; i++) _round1(d[i] - d0)];
    } else if (v is List && v.length == n) {
      out[e.key] = v.sublist(from, to + 1);
    } else {
      out[e.key] = v;
    }
  }

  final distance = d[to] - d0;
  final seconds = (t[to] - t0).round();
  if (distance < 0 || seconds <= 0) return null;

  final hr = _nums(streams['hr']);
  int? avgHr;
  if (hr != null && hr.length == n) {
    var sum = 0.0, count = 0;
    for (var i = from; i <= to; i++) {
      if (hr[i] > 30 && hr[i] < 240) {
        sum += hr[i];
        count++;
      }
    }
    if (count > 0) avgHr = (sum / count).round();
  }

  final track = <LatLng>[];
  final ll = streams['ll'];
  if (ll is List && ll.length == n) {
    for (var i = from; i <= to; i++) {
      final p = ll[i];
      if (p is! List || p.length < 2) continue;
      final pt = LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble());
      if (track.isEmpty || distanceMeters(track.last, pt) >= 20 || i == to) track.add(pt);
    }
  }

  return TrimmedRun(
    streams: out,
    distanceMeters: _round1(distance),
    movingSeconds: seconds,
    startOffsetSeconds: t0 - t.first,
    track: track,
    averageHeartRate: avgHr,
  );
}

/// Index van het meetpunt dat het dichtst bij [meters] ligt.
int indexAtDistance(List<double> d, double meters) {
  if (d.isEmpty) return 0;
  var best = 0;
  var bestDiff = double.infinity;
  for (var i = 0; i < d.length; i++) {
    final diff = (d[i] - meters).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = i;
    }
  }
  return best;
}

List<double>? _nums(Object? v) => v is List ? [for (final x in v) (x as num?)?.toDouble() ?? 0] : null;
double _round1(double x) => double.parse(x.toStringAsFixed(1));
