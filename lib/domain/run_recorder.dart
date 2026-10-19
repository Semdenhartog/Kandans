import 'dart:math' as math;

import 'geo.dart';

/// Eén GPS-meting tijdens het lopen.
class GpsFix {
  const GpsFix(this.point, this.time, {this.accuracy = 10, this.speed});
  final LatLng point;
  final DateTime time;

  /// Nauwkeurigheid in meters.
  final double accuracy;

  /// Snelheid in m/s volgens de telefoon (kan ontbreken).
  final double? speed;
}

enum RecorderStatus { idle, running, paused, autoPaused, finished }

/// Houdt een run bij: afstand, bewegende tijd, automatisch pauzeren en kilometertijden.
/// Bevat geen GPS of timers zelf, zodat het goed te testen is.
class RunRecording {
  RunRecording({this.autoPause = true});

  final bool autoPause;

  RecorderStatus status = RecorderStatus.idle;
  DateTime? startedAt;
  final List<LatLng> track = [];
  double distance = 0;

  /// Bewegende tijd in seconden (pauzes tellen niet mee).
  double movingSeconds = 0;

  /// Tijd (bewegend) waarop elke hele km werd bereikt.
  final List<double> kmTimes = [];

  GpsFix? _last;
  DateTime? _slowSince;
  final List<({double meters, double seconds})> _recent = [];

  // Grenzen: slechter dan 30 m nauwkeurig negeren; sneller dan 12 m/s (43 km/u) is een GPS-sprong.
  static const maxAccuracy = 30.0;
  static const maxSpeed = 12.0;
  static const pauseBelow = 0.6; // m/s
  static const pauseAfter = Duration(seconds: 8);
  static const resumeAbove = 1.2; // m/s

  void start(DateTime t) {
    status = RecorderStatus.running;
    startedAt = t;
  }

  void pause() {
    if (status == RecorderStatus.running || status == RecorderStatus.autoPaused) status = RecorderStatus.paused;
    _last = null;
  }

  void resume() {
    if (status == RecorderStatus.paused || status == RecorderStatus.autoPaused) status = RecorderStatus.running;
    _last = null;
    _slowSince = null;
  }

  void finish() => status = RecorderStatus.finished;

  bool get isActive => status == RecorderStatus.running || status == RecorderStatus.autoPaused;

  /// Verwerkt een meting. Geeft een nieuwe hele km terug als die net is bereikt.
  int? add(GpsFix fix) {
    if (!isActive || fix.accuracy > maxAccuracy) return null;
    final prev = _last;
    _last = fix;
    if (prev == null) {
      if (track.isEmpty) track.add(fix.point);
      return null;
    }
    final dt = fix.time.difference(prev.time).inMilliseconds / 1000;
    if (dt <= 0) return null;
    final d = distanceMeters(prev.point, fix.point);
    final v = fix.speed ?? d / dt;
    if (d / dt > maxSpeed) {
      _last = prev; // sprong: deze meting overslaan
      return null;
    }

    // Automatisch pauzeren bij stilstaan (stoplicht), en weer verder bij lopen.
    if (autoPause) {
      if (v < pauseBelow) {
        _slowSince ??= prev.time;
        if (status == RecorderStatus.running && fix.time.difference(_slowSince!) >= pauseAfter) {
          status = RecorderStatus.autoPaused;
        }
      } else {
        _slowSince = null;
        if (status == RecorderStatus.autoPaused && v >= resumeAbove) status = RecorderStatus.running;
      }
      if (status == RecorderStatus.autoPaused) return null;
    }

    distance += d;
    movingSeconds += dt;
    if (d >= 3) track.add(fix.point);
    _recent.add((meters: d, seconds: dt));
    var sum = 0.0;
    for (var i = _recent.length - 1; i >= 0; i--) {
      sum += _recent[i].meters;
      if (sum > 300) {
        _recent.removeRange(0, i);
        break;
      }
    }

    final km = (distance / 1000).floor();
    if (km > kmTimes.length) {
      // Precies op de km-grens schatten.
      final over = distance - km * 1000;
      final tAtKm = movingSeconds - (d > 0 ? dt * over / d : 0);
      kmTimes.add(tAtKm);
      return km;
    }
    return null;
  }

  /// Gemiddeld tempo (s/km).
  double get averagePace => distance < 50 ? 0 : movingSeconds / (distance / 1000);

  /// Tempo over de laatste ~300 m (s/km).
  double get currentPace {
    var m = 0.0, s = 0.0;
    for (final r in _recent) {
      m += r.meters;
      s += r.seconds;
    }
    return m < 50 ? 0 : s / (m / 1000);
  }

  /// Tijd van de laatste hele km (s).
  double? get lastKmSeconds {
    if (kmTimes.isEmpty) return null;
    return kmTimes.length == 1 ? kmTimes.first : kmTimes.last - kmTimes[kmTimes.length - 2];
  }

  /// Vereenvoudigde track (punt om de ~20 m) om op te slaan.
  List<LatLng> simplifiedTrack({double every = 20}) {
    if (track.length < 3) return List.of(track);
    final out = <LatLng>[track.first];
    for (final p in track.skip(1)) {
      if (distanceMeters(out.last, p) >= every) out.add(p);
    }
    if (out.last != track.last) out.add(track.last);
    return out;
  }
}

/// "5 minuten 12" voor de stem.
String spokenPace(double secPerKm) {
  if (secPerKm <= 0 || secPerKm.isInfinite || secPerKm.isNaN) return 'onbekend';
  final t = secPerKm.round();
  final m = t ~/ 60, s = t % 60;
  return s == 0 ? '$m minuten' : '$m minuten $s';
}

/// "1 uur 4 minuten" of "23 minuten 40" voor de stem.
String spokenDuration(double seconds) {
  final t = seconds.round();
  final h = t ~/ 3600, m = (t % 3600) ~/ 60, s = t % 60;
  if (h > 0) return '$h uur $m minuten';
  return s == 0 ? '$m minuten' : '$m minuten $s';
}

/// Wat de stemcoach zegt bij elke kilometer.
String kmAnnouncement(RunRecording r, int km) {
  final lap = r.lastKmSeconds;
  return [
    'Kilometer $km.',
    if (lap != null) 'Deze kilometer in ${spokenPace(lap)}.',
    'Gemiddeld ${spokenPace(r.averagePace)} per kilometer.',
    'Totale tijd ${spokenDuration(r.movingSeconds)}.',
  ].join(' ');
}

double clampPace(double p) => math.min(math.max(p, 0), 3600);
