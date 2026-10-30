import 'dart:math' as math;

import 'geo.dart';
import 'run_trim.dart';

/// Een stuk van een run waar de GPS onmogelijk hard ging (een "sprong").
class GpsSpike {
  const GpsSpike({
    required this.from,
    required this.to,
    required this.extraMeters,
    required this.atMeters,
    required this.peakKmh,
  });

  /// Meetpunten: [from] is het laatste goede punt vóór de sprong, [to] het eerste goede erna.
  final int from;
  final int to;

  /// Zoveel meter telt de run te veel door deze sprong.
  final double extraMeters;

  /// Waar in de run (meters vanaf de start).
  final double atMeters;

  /// Hoogste snelheid in dit stuk (km/u).
  final double peakKmh;
}

List<double>? _nums(Object? v) => v is List ? [for (final x in v) (x as num?)?.toDouble() ?? 0] : null;

List<LatLng?>? _positions(Object? ll, int n) {
  if (ll is! List || ll.length != n) return null;
  return [
    for (final p in ll)
      if (p is List && p.length >= 2) LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()) else null,
  ];
}

/// Mediane snelheid (m/s) over stukjes met beweging; je "gewone" tempo in deze run.
double _medianSpeed(List<double> t, List<double> d) {
  final v = <double>[];
  for (var i = 1; i < t.length; i++) {
    final dt = t[i] - t[i - 1];
    final dd = d[i] - d[i - 1];
    if (dt > 0 && dd > 0) v.add(dd / dt);
  }
  if (v.isEmpty) return 2.8;
  v.sort();
  return v[v.length ~/ 2];
}

/// Zoekt GPS-sprongen: stukjes sneller dan [maxSpeed] m/s (standaard 25 km/u, of bijna
/// het dubbele van je gewone tempo als je echt zo snel loopt). Kleine uitschieters
/// (samen minder dan [minExtra] meter te veel) tellen niet.
List<GpsSpike> findGpsSpikes(Map<String, dynamic> streams, {double maxSpeed = 7.0, double minExtra = 15}) {
  final t = _nums(streams['t']);
  final d = _nums(streams['d']);
  if (t == null || d == null || t.length != d.length || t.length < 3) return const [];
  final n = t.length;
  final median = _medianSpeed(t, d);
  final limit = math.max(maxSpeed, median * 1.8);

  bool bad(int i) {
    final dt = t[i] - t[i - 1];
    final dd = d[i] - d[i - 1];
    if (dd <= 0) return false;
    if (dt <= 0) return dd > 5; // afstand zonder tijd: altijd fout
    return dd / dt > limit;
  }

  final spikes = <GpsSpike>[];
  var i = 1;
  while (i < n) {
    if (!bad(i)) {
      i++;
      continue;
    }
    final start = i - 1;
    var end = i;
    var peak = 0.0;
    while (end < n && bad(end)) {
      final dt = t[end] - t[end - 1];
      final dd = d[end] - d[end - 1];
      peak = math.max(peak, dt <= 0 ? 99 : dd / dt * 3.6);
      end++;
    }
    // [start] = laatste goede punt; stuk [end] is weer goed, dus punt end-1 is het eerste goede punt erna.
    final to = end - 1;
    final fixed = _fixedSpan(t, d, _positions(streams['ll'], n), start, to, median, limit);
    final extra = (d[to] - d[start]) - fixed;
    if (extra >= minExtra) {
      spikes.add(GpsSpike(from: start, to: to, extraMeters: extra, atMeters: d[start], peakKmh: math.min(peak, 199)));
    }
    i = end + 1;
  }
  return spikes;
}

/// Hoe ver je echt liep tussen [a] en [b]: in een rechte lijn tussen de goede punten,
/// maar nooit sneller dan je gewone tempo als die lijn zelf ook onmogelijk is.
double _fixedSpan(List<double> t, List<double> d, List<LatLng?>? ll, int a, int b, double median, double limit) {
  final dt = math.max(0.0, t[b] - t[a]);
  final pa = ll?[a], pb = ll?[b];
  if (pa != null && pb != null) {
    final straight = distanceMeters(pa, pb);
    if (dt > 0 && straight / dt <= limit) return straight;
  }
  return median * dt;
}

/// Haalt de gekozen sprongen eruit: punten in de sprong komen op een rechte lijn tussen
/// de goede punten, en de afstand telt vanaf daar door zonder de sprong.
/// Tijd blijft gelijk. Null als er niets te herstellen viel.
TrimmedRun? removeGpsSpikes(Map<String, dynamic> streams, List<GpsSpike> spikes) {
  final t = _nums(streams['t']);
  final d = _nums(streams['d']);
  if (t == null || d == null || t.length != d.length || spikes.isEmpty) return null;
  final n = t.length;
  final ll = _positions(streams['ll'], n);
  final median = _medianSpeed(t, d);
  final limit = math.max(7.0, median * 1.8);

  final newD = [...d];
  final newLl = ll == null ? null : [...ll];
  var shift = 0.0; // hoeveel meter er al af is vóór dit punt
  var s = 0;
  final sorted = [...spikes]..sort((x, y) => x.from.compareTo(y.from));
  for (var i = 0; i < n; i++) {
    newD[i] = d[i] - shift;
    if (s < sorted.length && i == sorted[s].from) {
      final sp = sorted[s];
      final a = sp.from, b = sp.to;
      final span = _fixedSpan(t, d, ll, a, b, median, limit);
      final total = (t[b] - t[a]) <= 0 ? 1.0 : t[b] - t[a];
      for (var j = a + 1; j <= b; j++) {
        final f = ((t[j] - t[a]) / total).clamp(0.0, 1.0);
        newD[j] = newD[a] + span * f;
        if (newLl != null && ll![a] != null && ll[b] != null && j < b) {
          newLl[j] = LatLng(ll[a]!.lat + (ll[b]!.lat - ll[a]!.lat) * f, ll[a]!.lon + (ll[b]!.lon - ll[a]!.lon) * f);
        }
      }
      shift = d[b] - newD[b];
      s++;
      i = b - 1; // punt b opnieuw bekijken: daar kan direct de volgende sprong beginnen
    }
  }

  final out = <String, dynamic>{...streams};
  out['d'] = [for (final x in newD) double.parse(x.toStringAsFixed(1))];
  if (newLl != null && streams['ll'] is List) {
    final orig = streams['ll'] as List;
    out['ll'] = [
      for (var i = 0; i < n; i++)
        newLl[i] == null
            ? orig[i]
            : [double.parse(newLl[i]!.lat.toStringAsFixed(6)), double.parse(newLl[i]!.lon.toStringAsFixed(6))],
    ];
  }
  // Via trimRun (hele run) komen afstand, tijd, gem. hartslag en het spoor in dezelfde vorm als bij bijsnijden.
  return trimRun(out, 0, n - 1);
}
