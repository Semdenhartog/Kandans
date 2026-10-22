import 'dart:math' as math;

import 'geo.dart';
import 'route_geometry.dart';
import 'route_photos.dart' show projectOnTrack;
import 'run_recorder.dart';
import 'run_streams.dart';

/// Hoe vaak de stem iets zegt.
enum CueEvery {
  halfKm('Elke 500 m', meters: 500),
  km('Elke kilometer', meters: 1000),
  twoKm('Elke 2 km', meters: 2000),
  fiveMin('Elke 5 minuten', seconds: 300),
  tenMin('Elke 10 minuten', seconds: 600);

  const CueEvery(this.label, {this.meters, this.seconds});
  final String label;
  final int? meters;
  final int? seconds;
}

/// Wat de stemcoach zegt en hoe vaak.
class CueSettings {
  const CueSettings({
    this.every = CueEvery.km,
    this.lap = true,
    this.average = true,
    this.total = true,
    this.heartRate = true,
    this.fuel = false,
  });

  final CueEvery every;

  /// Herinneringen om te drinken en (bij lange runs) een gel te nemen.
  final bool fuel;

  /// Tempo van het laatste stuk.
  final bool lap;
  final bool average;
  final bool total;
  final bool heartRate;

  CueSettings copyWith({CueEvery? every, bool? lap, bool? average, bool? total, bool? heartRate, bool? fuel}) => CueSettings(
        every: every ?? this.every,
        lap: lap ?? this.lap,
        average: average ?? this.average,
        total: total ?? this.total,
        heartRate: heartRate ?? this.heartRate,
        fuel: fuel ?? this.fuel,
      );

  Map<String, dynamic> toJson() => {'e': every.name, 'l': lap, 'a': average, 't': total, 'h': heartRate, 'f': fuel};

  static CueSettings fromJson(Object? j) {
    if (j is! Map) return const CueSettings();
    return CueSettings(
      every: CueEvery.values.where((e) => e.name == j['e']).firstOrNull ?? CueEvery.km,
      lap: j['l'] as bool? ?? true,
      average: j['a'] as bool? ?? true,
      total: j['t'] as bool? ?? true,
      heartRate: j['h'] as bool? ?? true,
      fuel: j['f'] as bool? ?? false,
    );
  }
}

/// Drink- en gelherinneringen voor lange runs (zoals Garmin en Coros):
/// drinken elke 20 minuten vanaf 25 minuten, een gel elke 35 minuten vanaf 45 minuten.
class FuelReminder {
  FuelReminder({this.drinkFirst = 25, this.drinkEvery = 20, this.gelFirst = 45, this.gelEvery = 35});
  final int drinkFirst, drinkEvery, gelFirst, gelEvery;
  int _drinks = 0, _gels = 0;

  String? update(double movingSeconds) {
    final min = movingSeconds / 60;
    final drinkDue = min >= drinkFirst + _drinks * drinkEvery;
    final gelDue = min >= gelFirst + _gels * gelEvery;
    if (gelDue) {
      _gels++;
      if (drinkDue) _drinks++;
      return 'Tijd voor een gel of iets zoets, met een paar slokken water.';
    }
    if (drinkDue) {
      _drinks++;
      return 'Tijd om even te drinken.';
    }
    return null;
  }
}

String _km(double m) {
  final km = m / 1000;
  final t = km.toStringAsFixed(km >= 10 ? 1 : 2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return '${t.replaceAll('.', ',')} kilometer';
}

/// Houdt bij wanneer de volgende melding moet komen (op afstand of op tijd).
class CueScheduler {
  CueScheduler(this.settings);
  final CueSettings settings;
  int _done = 0;
  double _lastT = 0, _lastD = 0;

  /// Geeft de tekst als het tijd is voor een melding.
  String? update(RunRecording r, {int? heartRate}) {
    final every = settings.every;
    final n = every.meters != null ? (r.distance / every.meters!).floor() : (r.movingSeconds / every.seconds!).floor();
    if (n <= _done || n == 0) return null;
    _done = n;
    final lapT = r.movingSeconds - _lastT, lapD = r.distance - _lastD;
    _lastT = r.movingSeconds;
    _lastD = r.distance;
    final parts = <String>[
      every.meters != null ? '${_km(n * every.meters!.toDouble())}.' : '${n * every.seconds! ~/ 60} minuten.',
      // Op de loopband staan afstand en tempo al op het display: dan alleen tijd (en hartslag).
      if (every.seconds != null && !r.indoor) 'Afstand ${_km(r.distance)}.',
      if (settings.lap && lapD > 50 && !r.indoor) 'Dit stuk ${spokenPace(lapT / (lapD / 1000))} per kilometer.',
      if (settings.average && r.averagePace > 0 && !r.indoor) 'Gemiddeld ${spokenPace(r.averagePace)}.',
      if (settings.total && every.meters != null) 'Totale tijd ${spokenDuration(r.movingSeconds)}.',
      if (settings.heartRate && heartRate != null) 'Hartslag $heartRate.',
    ];
    return parts.join(' ');
  }
}

/// Doeltempo-coach: zegt het als je duidelijk te snel of te langzaam gaat.
class PaceCoach {
  PaceCoach(this.targetSecPerKm, {this.tolerance = 15, this.holdSeconds = 20, this.quietSeconds = 60});

  final double targetSecPerKm;

  /// Hoeveel seconden per km je ernaast mag zitten.
  final double tolerance;

  /// Zo lang moet je ernaast zitten voordat de coach iets zegt.
  final double holdSeconds;

  /// Daarna minstens zo lang stil.
  final double quietSeconds;

  double? _offSince;
  double _lastSaid = -1e9;
  int _lastDir = 0;

  /// [t] = bewegende tijd, [pace] = tempo van het laatste stuk (s/km, 0 = onbekend).
  String? update(double t, double pace) {
    if (pace <= 0) {
      _offSince = null;
      return null;
    }
    final diff = pace - targetSecPerKm;
    final dir = diff > tolerance ? 1 : (diff < -tolerance ? -1 : 0);
    if (dir == 0) {
      // Terug op tempo na een waarschuwing: één keer bevestigen.
      if (_lastDir != 0 && t - _lastSaid > 10) {
        _lastDir = 0;
        _offSince = null;
        _lastSaid = t;
        return 'Mooi, je zit weer op tempo.';
      }
      _offSince = null;
      return null;
    }
    _offSince ??= t;
    if (t - _offSince! < holdSeconds || t - _lastSaid < quietSeconds) return null;
    _lastSaid = t;
    _lastDir = dir;
    return dir > 0
        ? 'Iets sneller. Je loopt ${spokenPace(pace)}, je doel is ${spokenPace(targetSecPerKm)}.'
        : 'Rustiger aan. Je loopt ${spokenPace(pace)}, je doel is ${spokenPace(targetSecPerKm)}.';
  }
}

/// Route volgen tijdens het lopen: waar ben je op de route en ben je ervan af?
class RouteFollower {
  RouteFollower(this.track, {this.offAfter = 45, this.backWithin = 25});
  final RouteTrack track;

  /// Verder dan zoveel meter van de route = eraf (na 3 metingen achter elkaar).
  final double offAfter;
  final double backWithin;

  double progress = 0;
  bool offRoute = false;
  int _offCount = 0;
  bool _nearFinishSaid = false;

  double get remaining => (track.length - progress).clamp(0, double.infinity).toDouble();

  /// Verwerkt je positie. Geeft een tekst voor de stem als er iets verandert.
  String? update(LatLng p) {
    if (!track.isValid) return null;
    final pr = projectOnTrack(track, p);
    // Vooruitgang alleen vooruit (een stukje terug telt niet), en niet verspringen naar het einde van een rondje.
    if (pr.off < backWithin * 2 && pr.meters > progress - 150 && pr.meters < progress + 400) {
      progress = math.max(progress, pr.meters);
    }
    if (!offRoute) {
      _offCount = pr.off > offAfter ? _offCount + 1 : 0;
      if (_offCount >= 3) {
        offRoute = true;
        return 'Let op, je bent van je route af.';
      }
    } else if (pr.off < backWithin) {
      offRoute = false;
      _offCount = 0;
      return 'Je bent weer op je route.';
    }
    if (!_nearFinishSaid && track.length > 1000 && remaining < 300 && progress > track.length * 0.7) {
      _nearFinishSaid = true;
      return 'Nog 300 meter tot het einde van je route.';
    }
    return null;
  }
}

/// Race tegen je eigen record op een route (zoals Apple's Race Route): hoeveel seconden je
/// voor of achter ligt op je snelste keer, op hetzelfde punt van de route.
class GhostRace {
  GhostRace(this.best, {this.every = 1000});

  /// Verloop van je snelste run op deze route.
  final RunStreams best;
  final double every;
  int _said = 0;

  /// Tijd die je record nodig had tot [meters] op de route.
  double? bestTimeAt(double meters) {
    if (meters <= 0 || meters > best.totalDistance) return null;
    return best.valueAt(best.time, meters);
  }

  /// Seconden achter (positief) of voor (negatief) op je record.
  double? delta(double progress, double movingSeconds) {
    final t = bestTimeAt(progress);
    return t == null ? null : movingSeconds - t;
  }

  /// Elke kilometer van de route: zeg hoe je ervoor staat.
  String? update(double progress, double movingSeconds) {
    final n = (progress / every).floor();
    if (n <= _said || n == 0) return null;
    _said = n;
    final d = delta(progress, movingSeconds);
    if (d == null) return null;
    final s = d.abs().round();
    if (s < 3) return 'Je loopt precies gelijk met je record.';
    return d < 0 ? 'Je ligt $s seconden voor op je record. Hou vast!' : 'Je ligt $s seconden achter op je record.';
  }
}
