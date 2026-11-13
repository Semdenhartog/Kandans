import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect;

import 'geo.dart';

/// Stijlen van de bewegende routevideo (ontwerp: canvas "Animaties voor in de app").
enum RouteAnimStyle { draw, comet, km, pace, echo }

/// Beelden per seconde van de video.
const routeAnimFps = 24;

extension RouteAnimStyleX on RouteAnimStyle {
  /// Lengte van de video in seconden. Komeet en echo lopen naadloos rond.
  double get seconds => switch (this) {
        RouteAnimStyle.draw => 8.0,
        RouteAnimStyle.comet => 6.0,
        RouteAnimStyle.km => 8.0,
        RouteAnimStyle.pace => 8.0,
        RouteAnimStyle.echo => 7.2,
      };

  int get frames => (seconds * routeAnimFps).round();
}

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

double smoothstep(double u) {
  final t = clamp01(u);
  return t * t * (3 - 2 * t);
}

/// Rustig begin, snel in het midden, rustig einde.
double easeInOut(double u) {
  final t = clamp01(u);
  return t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
}

/// Hoeveel van de route al getekend is (0..1) op tijdstip [t] seconden.
double routeProgress(RouteAnimStyle style, double t) {
  switch (style) {
    case RouteAnimStyle.draw:
    case RouteAnimStyle.pace:
      return easeInOut((t - 0.5) / 4.5);
    case RouteAnimStyle.km:
      return clamp01((t - 0.5) / 5.0);
    case RouteAnimStyle.comet:
    case RouteAnimStyle.echo:
      return 1.0;
  }
}

/// "47:58" of "1:05:12".
String formatAnimTime(num seconds) {
  final s = seconds.round() < 0 ? 0 : seconds.round();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final r = s % 60;
  final rr = r.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$rr' : '$m:$rr';
}

/// "8,2 km" (met komma, zoals de rest van Kadans in het Nederlands).
String formatAnimKm(double meters, {String decimal = ','}) =>
    '${(meters / 1000).toStringAsFixed(1).replaceAll('.', decimal)} km';

/// Route als vloeiende lijn in een vak, op vaste afstand van elkaar (stap in beeldpunten).
class RoutePath {
  RoutePath._(this.points, this.cum);

  final List<Offset> points;

  /// Afgelegde afstand (beeldpunten) bij elk punt; cum.first == 0.
  final List<double> cum;

  double get length => cum.last;

  /// Past [track] in [box] (verhouding blijft kloppen), maakt de lijn glad. Null bij te weinig route.
  static RoutePath? fit(List<LatLng> track, Rect box, {double step = 2, double smoothSigma = 7}) {
    if (track.length < 2) return null;
    var latSum = 0.0;
    for (final p in track) {
      latSum += p.lat;
    }
    final lonScale = math.cos(latSum / track.length * math.pi / 180);
    final xs = [for (final p in track) p.lon * lonScale];
    final ys = [for (final p in track) -p.lat];
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final w = math.max(maxX - minX, 1e-9), h = math.max(maxY - minY, 1e-9);
    final scale = math.min(box.width / w, box.height / h);
    final ox = box.left + (box.width - w * scale) / 2;
    final oy = box.top + (box.height - h * scale) / 2;
    final raw = [for (var i = 0; i < xs.length; i++) Offset(ox + (xs[i] - minX) * scale, oy + (ys[i] - minY) * scale)];

    final dense = _resample(raw, step);
    if (dense.length < 3) return null;
    // Gladstrijken met een gewogen gemiddelde (Gauss) over buurpunten; begin en eind blijven op hun plek.
    final r = (smoothSigma * 3).ceil();
    final weights = [for (var i = -r; i <= r; i++) math.exp(-0.5 * (i / smoothSigma) * (i / smoothSigma))];
    final sm = <Offset>[];
    for (var i = 0; i < dense.length; i++) {
      var sx = 0.0, sy = 0.0, sw = 0.0;
      for (var k = -r; k <= r; k++) {
        final j = i + k;
        if (j < 0 || j >= dense.length) continue;
        final wgt = weights[k + r];
        sx += dense[j].dx * wgt;
        sy += dense[j].dy * wgt;
        sw += wgt;
      }
      sm.add(Offset(sx / sw, sy / sw));
    }
    sm[0] = dense.first;
    sm[sm.length - 1] = dense.last;
    final fin = _resample(sm, step);
    if (fin.length < 3) return null;
    final cum = <double>[0];
    for (var i = 1; i < fin.length; i++) {
      cum.add(cum.last + (fin[i] - fin[i - 1]).distance);
    }
    if (cum.last < 10) return null;
    return RoutePath._(fin, cum);
  }

  static List<Offset> _resample(List<Offset> pts, double step) {
    final cum = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum.last + (pts[i] - pts[i - 1]).distance);
    }
    final total = cum.last;
    if (total <= 0) return [pts.first];
    final out = <Offset>[];
    var j = 0;
    for (var d = 0.0; d < total; d += step) {
      while (j < cum.length - 2 && cum[j + 1] < d) {
        j++;
      }
      final seg = cum[j + 1] - cum[j];
      final f = seg <= 0 ? 0.0 : (d - cum[j]) / seg;
      out.add(Offset.lerp(pts[j], pts[j + 1], f)!);
    }
    out.add(pts.last);
    return out;
  }

  /// Laatste punt-index dat hoogstens op afstand [d] ligt.
  int indexAt(double d) {
    var lo = 0, hi = cum.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cum[mid] <= d) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  Offset pointAt(double d) {
    final dd = d < 0 ? 0.0 : (d > length ? length : d);
    final i = indexAt(dd);
    if (i >= points.length - 1) return points.last;
    final seg = cum[i + 1] - cum[i];
    return Offset.lerp(points[i], points[i + 1], seg <= 0 ? 0 : (dd - cum[i]) / seg)!;
  }

  /// Punten tussen afstand [from] en [to] (met nauwkeurige uiteinden).
  List<Offset> slice(double from, double to) {
    final a = from < 0 ? 0.0 : from;
    final b = to > length ? length : to;
    if (b <= a) return const [];
    final out = <Offset>[pointAt(a)];
    for (var i = indexAt(a) + 1; i < points.length && cum[i] < b; i++) {
      out.add(points[i]);
    }
    out.add(pointAt(b));
    return out;
  }
}

/// Stuk van de route (0..1 van de lijn) met een kleur, voor de tempo-stijl.
typedef PaceSpan = ({double from, double to, Color color});

/// Zet gekleurde stukken van de hele run om naar stukken op de getoonde lijn.
///
/// [full] is de hele track, [shown] de track zonder privacyzone (een deel van [full]); [segments] komen uit
/// `coloredRunSegments`. Stukken buiten de getoonde lijn vallen weg.
List<PaceSpan> paceSpansFor(
  List<LatLng> full,
  List<LatLng> shown,
  List<({List<LatLng> points, Color color})> segments,
) {
  if (full.length < 2 || shown.length < 2 || segments.isEmpty) return const [];
  double lenOf(List<LatLng> p) {
    var s = 0.0;
    for (var i = 1; i < p.length; i++) {
      s += distanceMeters(p[i - 1], p[i]);
    }
    return s;
  }

  final fullLen = lenOf(full);
  final shownLen = lenOf(shown);
  if (fullLen <= 0 || shownLen <= 0) return const [];
  final startIdx = math.max(0, full.indexOf(shown.first));
  final trimStart = lenOf(full.sublist(0, startIdx + 1));
  final segLens = [for (final s in segments) lenOf(s.points)];
  final segTotal = segLens.fold<double>(0, (a, b) => a + b);
  if (segTotal <= 0) return const [];
  final k = fullLen / segTotal;
  final out = <PaceSpan>[];
  var acc = 0.0;
  for (var i = 0; i < segments.length; i++) {
    final d0 = acc * k - trimStart, d1 = (acc + segLens[i]) * k - trimStart;
    acc += segLens[i];
    final f0 = clamp01(d0 / shownLen), f1 = clamp01(d1 / shownLen);
    if (f1 > f0) out.add((from: f0, to: f1, color: segments[i].color));
  }
  return out;
}

/// Voegt stukken samen tot hooguit [maxBands] banden (snellere tekening).
List<PaceSpan> mergePaceSpans(List<PaceSpan> spans, {int maxBands = 24}) {
  if (spans.length <= maxBands) return spans;
  final per = (spans.length / maxBands).ceil();
  final out = <PaceSpan>[];
  for (var i = 0; i < spans.length; i += per) {
    final part = spans.sublist(i, math.min(i + per, spans.length));
    var r = 0.0, g = 0.0, b = 0.0;
    for (final s in part) {
      r += s.color.r;
      g += s.color.g;
      b += s.color.b;
    }
    final n = part.length;
    out.add((from: part.first.from, to: part.last.to, color: Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n)));
  }
  return out;
}

/// Meters langs een lijn van punten.
double trackMeters(List<LatLng> p) {
  var s = 0.0;
  for (var i = 1; i < p.length; i++) {
    s += distanceMeters(p[i - 1], p[i]);
  }
  return s;
}
