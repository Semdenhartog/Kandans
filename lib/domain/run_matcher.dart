import 'dart:math' as math;

import 'geo.dart';
import 'route_geometry.dart';

/// Punten om de [step] meter langs een track (inclusief begin en eind).
List<LatLng> resample(List<LatLng> track, {double step = 25}) {
  final t = RouteTrack(track);
  if (!t.isValid) return track;
  return [for (var m = 0.0; m < t.length; m += step) t.at(m), track.last];
}

/// Rooster om snel te zoeken of er een punt in de buurt ligt.
class _Grid {
  _Grid(List<LatLng> points, this.radius) {
    if (points.isEmpty) return;
    final lat0 = points.first.lat;
    _latCell = radius / 110540;
    _lonCell = radius / (111320 * math.cos(lat0 * math.pi / 180));
    for (final p in points) {
      _cells.putIfAbsent(_key(_cx(p), _cy(p)), () => []).add(p);
    }
  }

  final double radius;
  late final double _latCell;
  late final double _lonCell;
  final _cells = <int, List<LatLng>>{};

  int _cx(LatLng p) => (p.lon / _lonCell).floor();
  int _cy(LatLng p) => (p.lat / _latCell).floor();
  static int _key(int x, int y) => x * 1000003 + y;

  bool near(LatLng p) {
    if (_cells.isEmpty) return false;
    final x = _cx(p), y = _cy(p);
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final cell = _cells[_key(x + dx, y + dy)];
        if (cell == null) continue;
        for (final q in cell) {
          if (distanceMeters(p, q) <= radius) return true;
        }
      }
    }
    return false;
  }
}

/// Deel van [points] dat binnen [grid] valt.
double _coverage(List<LatLng> points, _Grid grid) {
  if (points.isEmpty) return 0;
  var hit = 0;
  for (final p in points) {
    if (grid.near(p)) hit++;
  }
  return hit / points.length;
}

/// Een route om tegen te vergelijken, eenmalig voorbereid.
class MatchableRoute {
  MatchableRoute(this.id, List<LatLng> track, {double tolerance = 75})
      : length = RouteTrack(track).length,
        _points = resample(track),
        _grid = _Grid(resample(track), tolerance) {
    if (track.isNotEmpty) {
      var s = track.first.lat, n = s, w = track.first.lon, e = w;
      for (final p in track) {
        s = math.min(s, p.lat);
        n = math.max(n, p.lat);
        w = math.min(w, p.lon);
        e = math.max(e, p.lon);
      }
      bbox = (s: s, w: w, n: n, e: e);
    }
  }

  final String id;
  final double length;
  final List<LatLng> _points;
  final _Grid _grid;
  ({double s, double w, double n, double e})? bbox;
}

/// Uitkomst van een vergelijking.
class RouteMatch {
  const RouteMatch(this.routeId, this.runCoverage, this.routeCoverage);
  final String routeId;

  /// Deel van je run dat over de route liep.
  final double runCoverage;

  /// Deel van de route dat je hebt gelopen.
  final double routeCoverage;

  double get score => math.min(runCoverage, routeCoverage);
}

/// Zoekt de route waar deze run op gelopen is. Null als geen route goed genoeg past:
/// minstens [minCoverage] van de run moet op de route liggen én andersom.
/// De looprichting en het startpunt maken niet uit.
RouteMatch? matchRun(List<LatLng> runTrack, List<MatchableRoute> routes, {double minCoverage = 0.85, double tolerance = 75}) {
  if (runTrack.length < 2 || routes.isEmpty) return null;
  final runLen = RouteTrack(runTrack).length;
  if (runLen < 500) return null;
  final runPts = resample(runTrack);
  final runGrid = _Grid(runPts, tolerance);

  // Kader van de run, met wat marge.
  var s = runTrack.first.lat, n = s, w = runTrack.first.lon, e = w;
  for (final p in runTrack) {
    s = math.min(s, p.lat);
    n = math.max(n, p.lat);
    w = math.min(w, p.lon);
    e = math.max(e, p.lon);
  }
  const pad = 0.003;

  RouteMatch? best;
  for (final r in routes) {
    if (r.length <= 0) continue;
    final ratio = runLen / r.length;
    if (ratio < 0.8 || ratio > 1.25) continue;
    final b = r.bbox;
    if (b == null || b.n < s - pad || b.s > n + pad || b.e < w - pad || b.w > e + pad) continue;
    final runCov = _coverage(runPts, r._grid);
    if (runCov < minCoverage) continue;
    final routeCov = _coverage(r._points, runGrid);
    if (routeCov < minCoverage) continue;
    final m = RouteMatch(r.id, runCov, routeCov);
    if (best == null || m.score > best.score) best = m;
  }
  return best;
}
