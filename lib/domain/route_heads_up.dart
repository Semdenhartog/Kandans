import 'dart:math' as math;

import 'poi.dart';
import 'route_geometry.dart';

/// Een klim op de route.
class RouteClimb {
  const RouteClimb({required this.startMeters, required this.lengthMeters, required this.gainMeters});
  final double startMeters;
  final double lengthMeters;
  final double gainMeters;

  /// Gemiddeld stijgingspercentage.
  double get grade => lengthMeters <= 0 ? 0 : gainMeters / lengthMeters * 100;
}

/// Zoekt klimmetjes in een hoogteprofiel: minstens [minGain] meter omhoog met gemiddeld
/// minstens [minGrade] procent. Kleine dipjes onderweg (< [dip] m) horen bij dezelfde klim.
/// [trackLength] zet de afstanden van het profiel om naar meters op de route.
List<RouteClimb> detectClimbs(
  List<ElevationSample> profile, {
  double? trackLength,
  double minGain = 12,
  double minGrade = 3,
  double dip = 3,
  double maxFlat = 250,
}) {
  if (profile.length < 3) return const [];
  final scale = trackLength == null || profile.last.meters <= 0 ? 1.0 : trackLength / profile.last.meters;
  final out = <RouteClimb>[];
  var i = 0;
  while (i < profile.length - 1) {
    // Begin bij een dal.
    if (profile[i + 1].ele <= profile[i].ele) {
      i++;
      continue;
    }
    final start = i;
    var top = i;
    var j = i + 1;
    while (j < profile.length) {
      if (profile[j].ele > profile[top].ele) top = j;
      if (profile[top].ele - profile[j].ele > dip) break;
      // Lang vlak na de top: de klim is voorbij.
      if (profile[j].meters - profile[top].meters > maxFlat) break;
      j++;
    }
    final gain = profile[top].ele - profile[start].ele;
    final len = (profile[top].meters - profile[start].meters) * scale;
    if (gain >= minGain && len > 0 && gain / len * 100 >= minGrade) {
      out.add(RouteClimb(startMeters: profile[start].meters * scale, lengthMeters: len, gainMeters: gain));
    }
    i = math.max(top, i + 1);
  }
  return out;
}

/// Aankondigingen vooruit op je route: klimmetjes, drinkwater en toiletten.
class RouteHeadsUp {
  RouteHeadsUp(List<({double meters, String text})> events, {this.lead = 150})
      : _events = [...events]..sort((a, b) => a.meters.compareTo(b.meters));

  factory RouteHeadsUp.build({
    List<RouteClimb> climbs = const [],
    List<RoutePoi> pois = const [],
    double lead = 150,
  }) {
    final ev = <({double meters, String text})>[];
    for (final c in climbs) {
      final steep = c.grade >= 6 ? ' Kleine passen en houd je inspanning gelijk.' : ' Rustig aan, korte passen.';
      ev.add((
        meters: c.startMeters,
        text: 'Over ${lead.round()} meter een klim van ${c.gainMeters.round()} meter, '
            '${c.lengthMeters >= 1000 ? '${(c.lengthMeters / 1000).toStringAsFixed(1).replaceAll('.', ',')} kilometer' : '${(c.lengthMeters / 50).round() * 50} meter'} lang.$steep',
      ));
    }
    // Alleen voorzieningen vlak bij de route, en niet twee keer hetzelfde soort kort na elkaar.
    final last = <PoiKind, double>{};
    for (final p in [...pois]..sort((a, b) => a.alongMeters.compareTo(b.alongMeters))) {
      if (p.offsetMeters > 80) continue;
      final prev = last[p.kind];
      if (prev != null && p.alongMeters - prev < 1500) continue;
      last[p.kind] = p.alongMeters;
      final side = p.offsetMeters < 15 ? 'aan de route' : '${(p.offsetMeters / 10).round() * 10} meter van de route';
      ev.add((
        meters: p.alongMeters,
        text: 'Over ${lead.round()} meter ${p.kind == PoiKind.water ? 'een watertappunt' : 'een toilet'}, $side.',
      ));
    }
    return RouteHeadsUp(ev, lead: lead);
  }

  final List<({double meters, String text})> _events;
  final double lead;
  int _next = 0;

  int get count => _events.length;

  /// Geeft een tekst als je ongeveer [lead] meter voor iets bent.
  String? update(double progress) {
    while (_next < _events.length && _events[_next].meters < progress + lead * 0.3) {
      // Al te dichtbij of voorbij om nog aan te kondigen: overslaan.
      _next++;
    }
    if (_next >= _events.length) return null;
    final e = _events[_next];
    if (e.meters - progress <= lead) {
      _next++;
      return e.text;
    }
    return null;
  }
}

/// Eén keer melden hoeveel daglicht je nog hebt, ongeveer [before] voor zonsondergang.
class DaylightWarner {
  DaylightWarner(this.sunset, {this.before = const Duration(minutes: 20)});
  final DateTime? sunset;
  final Duration before;
  bool _said = false;

  String? update(DateTime now) {
    final s = sunset;
    if (_said || s == null) return null;
    final left = s.difference(now);
    if (left <= before && left > Duration.zero) {
      _said = true;
      final min = left.inMinutes;
      return min <= 1
          ? 'De zon gaat nu onder. Zet je lampje aan.'
          : 'Nog $min minuten daglicht. Zorg dat je gezien wordt.';
    }
    return null;
  }
}
