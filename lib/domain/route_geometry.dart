import 'dart:math' as math;

import 'geo.dart';

/// Een punt van het hoogteprofiel: afstand vanaf de start en hoogte.
class ElevationSample {
  const ElevationSample(this.meters, this.ele);
  final double meters;
  final double ele;

  List<num> toJson() => [meters.round(), double.parse(ele.toStringAsFixed(1))];

  static List<ElevationSample> listFromJson(Object? json) {
    if (json is! List) return const [];
    final out = <ElevationSample>[];
    for (final e in json) {
      if (e is List && e.length >= 2 && e[0] is num && e[1] is num) {
        out.add(ElevationSample((e[0] as num).toDouble(), (e[1] as num).toDouble()));
      }
    }
    return out;
  }
}

/// Een track met opgetelde afstanden, zodat je punten op afstand kunt opzoeken.
class RouteTrack {
  RouteTrack._(this.points, this.cumulative);

  factory RouteTrack(List<LatLng> points) {
    final cum = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cum.add(cum.last + distanceMeters(points[i - 1], points[i]));
    }
    return RouteTrack._(points, cum);
  }

  final List<LatLng> points;
  final List<double> cumulative;

  double get length => cumulative.isEmpty ? 0 : cumulative.last;
  bool get isValid => points.length >= 2 && length > 0;

  /// Index van het stuk waar [meters] in valt.
  int _segmentAt(double meters) {
    var lo = 0, hi = cumulative.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (cumulative[mid] <= meters) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Punt op [meters] vanaf de start (geïnterpoleerd).
  LatLng at(double meters) {
    if (points.length == 1) return points.first;
    final m = meters.clamp(0, length).toDouble();
    final i = _segmentAt(m);
    if (i >= points.length - 1) return points.last;
    final segLen = cumulative[i + 1] - cumulative[i];
    final t = segLen <= 0 ? 0.0 : (m - cumulative[i]) / segLen;
    final a = points[i], b = points[i + 1];
    return LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
  }

  /// Looprichting rond [meters], gemeten over een stukje van [window] meter.
  double bearingAt(double meters, {double window = 40}) {
    final from = at(math.max(0, meters - window / 2));
    final to = at(math.min(length, meters + window / 2));
    return bearingDegrees(from, to);
  }

  RouteTrack reversed() => RouteTrack(points.reversed.toList());
}

/// Hoe de wind op een stuk route staat.
enum WindClass { head, side, tail, calm }

class WindSegment {
  const WindSegment(this.points, this.windClass);
  final List<LatLng> points;
  final WindClass windClass;
}

/// Onder deze windsnelheid (km/u) kleuren we niets: het maakt dan weinig uit.
const calmWindKmh = 8.0;

/// Klasse van de wind voor een looprichting. Tegenwind = je loopt de wind in.
WindClass classifyWind(double bearing, double windSpeedKmh, double windFromDegrees) {
  if (windSpeedKmh < calmWindKmh) return WindClass.calm;
  final c = math.cos((bearing - windFromDegrees) * math.pi / 180);
  if (c > 0.38) return WindClass.head;
  if (c < -0.38) return WindClass.tail;
  return WindClass.side;
}

/// Deelt de route op in stukken tegenwind, zijwind en wind mee.
/// Kijkt per stuk van ongeveer [chunk] meter, zodat kleine bochtjes niet flikkeren.
List<WindSegment> windSegments(
  RouteTrack track, {
  required double windSpeedKmh,
  required double? windFromDegrees,
  double chunk = 120,
}) {
  if (!track.isValid) return const [];
  if (windFromDegrees == null) return [WindSegment(track.points, WindClass.calm)];

  final out = <WindSegment>[];
  var current = <LatLng>[track.points.first];
  WindClass? currentClass;
  var start = 0.0;
  while (start < track.length) {
    final end = math.min(track.length, start + chunk);
    final cls = classifyWind(
      bearingDegrees(track.at(start), track.at(end)),
      windSpeedKmh,
      windFromDegrees,
    );
    // Alle trackpunten in dit stuk, plus het eindpunt.
    final pts = <LatLng>[];
    for (var i = 1; i < track.points.length; i++) {
      final m = track.cumulative[i];
      if (m > start && m < end) pts.add(track.points[i]);
    }
    pts.add(track.at(end));

    if (currentClass == null || cls == currentClass) {
      current.addAll(pts);
    } else {
      out.add(WindSegment(current, currentClass));
      current = [current.last, ...pts];
    }
    currentClass = cls;
    start = end;
  }
  out.add(WindSegment(current, currentClass ?? WindClass.calm));
  return out;
}

/// Plekken voor richtingspijltjes: elke [spacing] meter, niet vlak bij start of finish.
List<({LatLng point, double bearing})> arrowPositions(RouteTrack track, double spacing) {
  if (!track.isValid || spacing <= 0) return const [];
  final out = <({LatLng point, double bearing})>[];
  for (var m = spacing / 2; m < track.length - spacing * 0.3; m += spacing) {
    out.add((point: track.at(m), bearing: track.bearingAt(m)));
  }
  return out;
}

/// Kilometerbordjes: elke [everyKm] kilometer, niet op de finish zelf.
List<({LatLng point, int km})> kmPositions(RouteTrack track, {int everyKm = 1}) {
  if (!track.isValid) return const [];
  final out = <({LatLng point, int km})>[];
  for (var km = everyKm; km * 1000 < track.length - 150; km += everyKm) {
    out.add((point: track.at(km * 1000.0), km: km));
  }
  return out;
}

/// Kiest een rustige afstand tussen pijltjes en kilometerbordjes.
({double arrowSpacing, int kmEvery}) markerDensity(double lengthMeters, {bool compact = false}) {
  final km = lengthMeters / 1000;
  if (compact) {
    return (arrowSpacing: math.max(800.0, lengthMeters / 5), kmEvery: 0);
  }
  return (
    arrowSpacing: km <= 6 ? 400.0 : km <= 15 ? 700.0 : 1200.0,
    kmEvery: km <= 15 ? 1 : km <= 30 ? 2 : 5,
  );
}

/// Hoogteprofiel elke [step] meter, licht gladgestreken tegen GPS-ruis.
/// Leeg als minder dan de helft van de punten een hoogte heeft.
List<ElevationSample> sampleElevation(List<LatLng> raw, {double step = 50}) {
  if (raw.length < 2) return const [];
  final withEle = raw.where((p) => p.ele != null).length;
  if (withEle < raw.length / 2 || withEle < 2) return const [];

  final dist = <double>[0];
  for (var i = 1; i < raw.length; i++) {
    dist.add(dist.last + distanceMeters(raw[i - 1], raw[i]));
  }
  final total = dist.last;
  if (total <= 0) return const [];

  // Hoogte op afstand m, geïnterpoleerd tussen punten met een hoogte.
  final idx = [for (var i = 0; i < raw.length; i++) if (raw[i].ele != null) i];
  double eleAt(double m) {
    var k = 0;
    while (k < idx.length - 1 && dist[idx[k + 1]] < m) {
      k++;
    }
    if (k >= idx.length - 1) return raw[idx.last].ele!;
    final a = idx[k], b = idx[k + 1];
    final span = dist[b] - dist[a];
    if (m <= dist[a] || span <= 0) return raw[a].ele!;
    return raw[a].ele! + (raw[b].ele! - raw[a].ele!) * (m - dist[a]) / span;
  }

  final samples = <double>[];
  final positions = <double>[];
  for (var m = 0.0; m < total; m += step) {
    positions.add(m);
    samples.add(eleAt(m));
  }
  positions.add(total);
  samples.add(eleAt(total));

  // Voortschrijdend gemiddelde over 5 punten.
  final out = <ElevationSample>[];
  for (var i = 0; i < samples.length; i++) {
    final from = math.max(0, i - 2), to = math.min(samples.length - 1, i + 2);
    var sum = 0.0;
    for (var j = from; j <= to; j++) {
      sum += samples[j];
    }
    out.add(ElevationSample(positions[i], sum / (to - from + 1)));
  }
  return out;
}

/// Hoogste en laagste punt van een profiel.
({double min, double max}) elevationRange(List<ElevationSample> profile) {
  var lo = double.infinity, hi = -double.infinity;
  for (final s in profile) {
    lo = math.min(lo, s.ele);
    hi = math.max(hi, s.ele);
  }
  return (min: lo, max: hi);
}

/// Hoogte op [meters] in een profiel.
double? elevationAt(List<ElevationSample> profile, double meters) {
  if (profile.isEmpty) return null;
  if (meters <= profile.first.meters) return profile.first.ele;
  for (var i = 1; i < profile.length; i++) {
    final b = profile[i];
    if (b.meters >= meters) {
      final a = profile[i - 1];
      final span = b.meters - a.meters;
      return span <= 0 ? b.ele : a.ele + (b.ele - a.ele) * (meters - a.meters) / span;
    }
  }
  return profile.last.ele;
}

/// Hetzelfde profiel, maar gelopen in de andere richting.
List<ElevationSample> reverseProfile(List<ElevationSample> profile) {
  if (profile.isEmpty) return profile;
  final total = profile.last.meters;
  return [for (final s in profile.reversed) ElevationSample(total - s.meters, s.ele)];
}

/// Totaal aantal meters omhoog in een profiel (schommelingen < 1 m negeren).
double profileAscent(List<ElevationSample> profile) {
  if (profile.isEmpty) return 0;
  var gain = 0.0;
  var ref = profile.first.ele;
  for (final s in profile.skip(1)) {
    if (s.ele - ref >= 1) {
      gain += s.ele - ref;
      ref = s.ele;
    } else if (ref - s.ele >= 1) {
      ref = s.ele;
    }
  }
  return gain;
}
