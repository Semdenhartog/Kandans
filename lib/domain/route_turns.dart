import 'dart:math' as math;

import 'geo.dart';
import 'route_geometry.dart';

/// Soort afslag, zoals een navigatie-app hem noemt.
enum TurnKind { slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn }

extension TurnKindText on TurnKind {
  bool get isLeft => this == TurnKind.slightLeft || this == TurnKind.left || this == TurnKind.sharpLeft;

  /// Korte opdracht, bijv. "Linksaf".
  String get label => switch (this) {
        TurnKind.slightLeft => 'Houd links',
        TurnKind.left => 'Linksaf',
        TurnKind.sharpLeft => 'Scherp linksaf',
        TurnKind.slightRight => 'Houd rechts',
        TurnKind.right => 'Rechtsaf',
        TurnKind.sharpRight => 'Scherp rechtsaf',
        TurnKind.uTurn => 'Keer om',
      };

  /// Pijl als teken (voor meldingen, die op je horloge verschijnen).
  String get arrow => switch (this) {
        TurnKind.slightLeft => '↖',
        TurnKind.left => '←',
        TurnKind.sharpLeft => '↙',
        TurnKind.slightRight => '↗',
        TurnKind.right => '→',
        TurnKind.sharpRight => '↘',
        TurnKind.uTurn => '↶',
      };

  /// Draaiing van de pijl op het scherm in graden (0 = rechtdoor, + = rechts).
  double get screenAngle => switch (this) {
        TurnKind.slightLeft => -45,
        TurnKind.left => -90,
        TurnKind.sharpLeft => -135,
        TurnKind.slightRight => 45,
        TurnKind.right => 90,
        TurnKind.sharpRight => 135,
        TurnKind.uTurn => 180,
      };
}

/// Een afslag op een route.
class RouteTurn {
  const RouteTurn({required this.meters, required this.point, required this.kind, required this.angle});

  /// Afstand vanaf de start.
  final double meters;
  final LatLng point;
  final TurnKind kind;

  /// Hoeveel graden je draait: + = rechts, - = links.
  final double angle;

  @override
  String toString() => 'RouteTurn(${meters.round()} m, ${kind.label}, ${angle.round()}°)';
}

/// Verschil tussen twee kompasrichtingen, van -180 tot 180 (+ = met de klok mee = rechts).
double headingChange(double from, double to) {
  var d = (to - from) % 360;
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;
  return d;
}

TurnKind classifyTurn(double angle) {
  final a = angle.abs();
  if (a >= 150) return TurnKind.uTurn;
  final right = angle > 0;
  if (a < 60) return right ? TurnKind.slightRight : TurnKind.slightLeft;
  if (a < 125) return right ? TurnKind.right : TurnKind.left;
  return right ? TurnKind.sharpRight : TurnKind.sharpLeft;
}

/// Zoekt de afslagen in een route.
///
/// 1. We leggen elke [step] meter een punt en strijken de lijn licht glad (±15 m),
///    zodat GPS-ruis in een opgenomen route geen nep-afslagen geeft.
/// 2. Per punt kijken we hoe de looprichting verandert tussen het stuk vóór en ná dat punt
///    (elk [window] meter). Wordt dat samen meer dan [minAngle] graden, dan is het een afslag.
///    Gewone bochten in de weg tellen niet: die draaien geleidelijk.
/// 3. Afslagen vlak achter elkaar ([minGap] m) voegen we samen of laten we weg (even oversteken).
List<RouteTurn> detectTurns(
  RouteTrack track, {
  double step = 5,
  double window = 25,
  double minAngle = 35,
  double minGap = 40,
  double edge = 30,
  int smoothHalf = 3,
}) {
  if (!track.isValid || track.length < window * 2 + edge * 2) return const [];

  // 1) Gelijkmatig verdeelde, gladgestreken punten. Punt i ligt op i * step meter van de originele route.
  final n = (track.length / step).floor() + 1;
  final even = [for (var i = 0; i < n; i++) track.at(i * step)];
  final smooth = <LatLng>[];
  for (var i = 0; i < n; i++) {
    final a = math.max(0, i - smoothHalf), b = math.min(n - 1, i + smoothHalf);
    var lat = 0.0, lon = 0.0;
    for (var j = a; j <= b; j++) {
      lat += even[j].lat;
      lon += even[j].lon;
    }
    smooth.add(LatLng(lat / (b - a + 1), lon / (b - a + 1)));
  }
  final st = RouteTrack(smooth);
  if (!st.isValid) return const [];
  // Afstand op de gladde lijn terugrekenen naar de originele route.
  double original(double m) {
    var lo = 0, hi = st.cumulative.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (st.cumulative[mid] <= m) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final i = (m - st.cumulative[lo]).abs() <= (st.cumulative[hi] - m).abs() ? lo : hi;
    return math.min(track.length, i * step);
  }

  // 2) Draaiing per meetpunt.
  final samples = <({double m, double angle})>[];
  final margin = math.max(window, edge);
  for (var m = margin; m <= st.length - margin; m += step) {
    final from = st.at(m - window), here = st.at(m), to = st.at(m + window);
    if (distanceMeters(from, here) < window * 0.4) continue; // Stilstand in het spoor.
    samples.add((m: m, angle: headingChange(bearingDegrees(from, here), bearingDegrees(here, to))));
  }

  // Groepjes punten achter elkaar die dezelfde kant op draaien: één afslag.
  final startAt = minAngle * 0.6;
  final raw = <RouteTurn>[];
  var i = 0;
  while (i < samples.length) {
    if (samples[i].angle.abs() < startAt) {
      i++;
      continue;
    }
    final sign = samples[i].angle.sign;
    var best = samples[i];
    var j = i;
    while (j < samples.length && samples[j].angle.abs() >= startAt * 0.8 && samples[j].angle.sign == sign) {
      if (samples[j].angle.abs() > best.angle.abs()) best = samples[j];
      j++;
    }
    // Hoeveel je in totaal draait: richting vóór de groep tegenover richting ná de groep.
    final from = samples[i].m, to = samples[j - 1].m;
    var angle = headingChange(
      bearingDegrees(st.at(math.max(0, from - window)), st.at(from)),
      bearingDegrees(st.at(to), st.at(math.min(st.length, to + window))),
    );
    if (angle.sign != sign || angle.abs() < best.angle.abs()) angle = best.angle;
    if (angle.abs() >= minAngle) {
      final m = original(best.m);
      raw.add(RouteTurn(meters: m, point: track.at(m), kind: classifyTurn(angle), angle: angle));
    }
    i = math.max(j, i + 1);
  }

  // 3) Afslagen vlak achter elkaar samenvoegen.
  final out = <RouteTurn>[];
  for (final t in raw) {
    if (out.isNotEmpty && t.meters - out.last.meters < minGap) {
      final prev = out.removeLast();
      final sum = prev.angle + t.angle;
      if (prev.angle.sign != t.angle.sign && sum.abs() < minAngle) {
        continue; // Links-rechts verspringen (bijv. even oversteken): geen afslag.
      }
      if (prev.angle.sign == t.angle.sign) {
        // Twee halve bochten = één echte afslag.
        final angle = sum.clamp(-179.0, 179.0).toDouble();
        out.add(RouteTurn(meters: prev.meters, point: prev.point, kind: classifyTurn(angle), angle: angle));
      } else {
        out.add(prev.angle.abs() >= t.angle.abs() ? prev : t);
      }
      continue;
    }
    out.add(t);
  }
  return out;
}

/// Tekst om uit te spreken, bijv. "Over 100 meter rechtsaf".
String turnSpeech(RouteTurn t, {double? inMeters}) {
  final what = switch (t.kind) {
    TurnKind.uTurn => 'omkeren',
    TurnKind.slightLeft => 'links aanhouden',
    TurnKind.slightRight => 'rechts aanhouden',
    _ => t.kind.label.toLowerCase(),
  };
  if (inMeters == null || inMeters < 25) return t.kind.label;
  final rounded = inMeters >= 150 ? (inMeters / 50).round() * 50 : (inMeters / 10).round() * 10;
  return 'Over $rounded meter $what';
}

/// Volgt de afslagen terwijl je loopt en zegt wanneer er iets gemeld moet worden.
class TurnGuide {
  TurnGuide(this.turns, {this.early = 120, this.now = 20});
  final List<RouteTurn> turns;

  /// Vooraankondiging op ongeveer zoveel meter.
  final double early;

  /// "Nu linksaf" binnen zoveel meter.
  final double now;

  int _next = 0;
  bool _earlySaid = false;

  /// Eerstvolgende afslag (of null als je ze allemaal gehad hebt).
  RouteTurn? get next => _next < turns.length ? turns[_next] : null;

  /// Meters tot de volgende afslag bij [progress] meter op de route.
  double? distanceTo(double progress) => next == null ? null : (next!.meters - progress);

  /// Verwerkt je voortgang op de route. Geeft een melding als er een moment is.
  ({RouteTurn turn, String text, bool atTurn})? update(double progress) {
    // Afslagen die je al voorbij bent overslaan (bijv. na een stukje afsnijden).
    while (next != null && progress > next!.meters + 15) {
      _next++;
      _earlySaid = false;
    }
    final t = next;
    if (t == null) return null;
    final d = t.meters - progress;
    if (d <= now) {
      _next++;
      _earlySaid = false;
      return (turn: t, text: turnSpeech(t), atTurn: true);
    }
    if (!_earlySaid && d <= early && d > now * 2.5) {
      _earlySaid = true;
      return (turn: t, text: turnSpeech(t, inMeters: d), atTurn: false);
    }
    return null;
  }
}
