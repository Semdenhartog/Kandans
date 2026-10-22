import 'dart:math' as math;

import 'geo.dart';

/// Eén GPS-meting tijdens het lopen.
class GpsFix {
  const GpsFix(this.point, this.time, {this.accuracy = 10, this.speed, this.altitude});
  final LatLng point;
  final DateTime time;

  /// Hoogte boven zeeniveau volgens de GPS (grof, wordt gladgestreken).
  final double? altitude;

  /// Nauwkeurigheid in meters.
  final double accuracy;

  /// Snelheid in m/s volgens de telefoon (kan ontbreken).
  final double? speed;
}

enum RecorderStatus { idle, running, paused, autoPaused, finished }

/// Eén meetpunt van de run: bewegende tijd, afstand, positie en eventueel hoogte en hartslag.
class RunSample {
  const RunSample(this.t, this.d, this.point, {this.alt, this.hr});
  final double t;
  final double d;
  final LatLng point;
  final double? alt;
  final int? hr;
}

/// Houdt een run bij: afstand, bewegende tijd, automatisch pauzeren en kilometertijden.
/// Bevat geen GPS of timers zelf, zodat het goed te testen is.
class RunRecording {
  RunRecording({this.autoPause = true, this.indoor = false});

  final bool autoPause;

  /// Loopband of binnen: geen GPS, alleen de klok. De afstand vul je na afloop in.
  final bool indoor;

  RecorderStatus status = RecorderStatus.idle;
  DateTime? startedAt;
  final List<LatLng> track = [];
  double distance = 0;

  /// Bewegende tijd in seconden (pauzes tellen niet mee).
  double movingSeconds = 0;

  /// Tijd (bewegend) waarop elke hele km werd bereikt.
  final List<double> kmTimes = [];

  /// Meetpunten om de paar seconden, voor tijden per km, grafiek en snelste stukken.
  final List<RunSample> samples = [];

  /// Huidige hartslag van een hartslagband (null = geen band).
  int? heartRate;
  int _hrSum = 0;
  int _hrCount = 0;

  /// Gemiddelde hartslag over de bewegende tijd.
  int? get averageHeartRate => _hrCount == 0 ? null : (_hrSum / _hrCount).round();

  GpsFix? _last;
  DateTime? _slowSince;
  final List<({double meters, double seconds})> _recent = [];

  // Grenzen: slechter dan 30 m nauwkeurig negeren; sneller dan 12 m/s (43 km/u) is een GPS-sprong.
  static const maxAccuracy = 30.0;
  static const maxSpeed = 12.0;
  static const pauseBelow = 0.6; // m/s
  static const pauseAfter = Duration(seconds: 8);
  static const resumeAbove = 1.2; // m/s
  static const jitterFactor = 0.4;

  /// Na zoveel sprongen achter elkaar vertrouwen we het vorige punt niet meer.
  static const maxJumpsInRow = 3;
  int _jumps = 0;

  void start(DateTime t) {
    status = RecorderStatus.running;
    startedAt = t;
  }

  void pause() {
    if (status == RecorderStatus.running || status == RecorderStatus.autoPaused) status = RecorderStatus.paused;
    _last = null;
    _jumps = 0;
  }

  void resume() {
    if (status == RecorderStatus.paused || status == RecorderStatus.autoPaused) status = RecorderStatus.running;
    _last = null;
    _slowSince = null;
    _jumps = 0;
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
      if (samples.isEmpty) samples.add(RunSample(movingSeconds, distance, fix.point, alt: fix.altitude, hr: heartRate));
      return null;
    }
    final dt = fix.time.difference(prev.time).inMilliseconds / 1000;
    if (dt <= 0) return null;
    final d = distanceMeters(prev.point, fix.point);
    final v = fix.speed ?? d / dt;
    if (d / dt > maxSpeed) {
      // Sprong: deze meting overslaan. Zijn er meerdere sprongen achter elkaar, dan was
      // waarschijnlijk het vórige punt fout (bijv. een slecht eerste punt). Dan opnieuw
      // beginnen vanaf het nieuwe punt, zonder de afstand ertussen mee te tellen.
      _jumps++;
      if (_jumps >= maxJumpsInRow) {
        _jumps = 0;
        _slowSince = null;
        // Nog niets afgelegd: het foute beginpunt ook uit het spoor halen.
        if (distance < 1) {
          track
            ..clear()
            ..add(fix.point);
          samples
            ..clear()
            ..add(RunSample(movingSeconds, distance, fix.point, alt: fix.altitude, hr: heartRate));
        }
        return null; // _last is al het nieuwe punt
      }
      _last = prev;
      return null;
    }
    _jumps = 0;

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

    // GPS-ruis: kleine verschuivingen binnen de meetonnauwkeurigheid nog niet meetellen,
    // maar optellen tot je echt verder bent. Zo loopt de afstand niet op als je stilstaat.
    final jitter = (math.max(prev.accuracy, fix.accuracy) * jitterFactor).clamp(1.0, 8.0);
    if (d < jitter) {
      if (dt < 10) {
        _last = prev;
        return null;
      }
      // Al 10 s binnen de ruis: nieuw beginpunt, geen afstand. Zonder autopauze loopt de klok door.
      if (!autoPause) movingSeconds += dt;
      return null;
    }

    distance += d;
    movingSeconds += dt;
    final hr = heartRate;
    if (hr != null && hr > 30 && hr < 240) {
      _hrSum += hr;
      _hrCount++;
    }
    if (samples.isEmpty || movingSeconds - samples.last.t >= 3) {
      samples.add(RunSample(movingSeconds, distance, fix.point, alt: fix.altitude, hr: hr));
    }
    // Punt bewaren zodra je minstens 3 m van het vorige bewaarde punt bent.
    if (track.isEmpty || distanceMeters(track.last, fix.point) >= 3) track.add(fix.point);
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

  /// Loopband-snelheid (km/u) zoals op het display van de band; null = onbekend (alleen de klok).
  double? treadmillKmh;

  /// Loopband: de klok loopt door zolang je niet op pauze staat. Met een snelheid telt ook de afstand mee.
  /// Geeft een nieuwe hele km terug als die net is bereikt.
  int? tick(double seconds) {
    if (!indoor || status != RecorderStatus.running) return null;
    movingSeconds += seconds;
    final hr = heartRate;
    if (hr != null && hr > 30 && hr < 240) {
      _hrSum += hr;
      _hrCount++;
    }
    final kmh = treadmillKmh;
    if (kmh == null || kmh <= 0) return null;
    final d = kmh / 3.6 * seconds;
    distance += d;
    _recent.add((meters: d, seconds: seconds));
    while (_recent.length > 1 && _recent.fold<double>(0, (a, r) => a + r.meters) - _recent.first.meters > 300) {
      _recent.removeAt(0);
    }
    if (samples.isEmpty || movingSeconds - samples.last.t >= 3) {
      samples.add(RunSample(movingSeconds, distance, const LatLng(0, 0), hr: hr));
    }
    final km = (distance / 1000).floor();
    if (km > kmTimes.length) {
      final over = distance - km * 1000;
      kmTimes.add(movingSeconds - (d > 0 ? seconds * over / d : 0));
      return km;
    }
    return null;
  }

  /// Loopband: afstand na afloop invullen. Wijkt die af van de schatting, dan schalen we het verloop mee
  /// (zodat de tijden per km kloppen met de afstand van de band).
  void setIndoorDistance(double meters) {
    if (!indoor) return;
    if (distance > 100 && meters > 0 && samples.isNotEmpty) {
      final f = meters / distance;
      for (var i = 0; i < samples.length; i++) {
        final x = samples[i];
        samples[i] = RunSample(x.t, x.d * f, x.point, alt: x.alt, hr: x.hr);
      }
    }
    distance = meters;
  }

  /// Tussenstand om op te slaan, zodat een run niet verloren gaat als de app wordt afgesloten.
  Map<String, dynamic> toSnapshot() => {
        'v': 1,
        'indoor': indoor,
        if (treadmillKmh != null) 'tm': treadmillKmh,
        'auto': autoPause,
        'started': startedAt?.toIso8601String(),
        'dist': distance,
        'moving': movingSeconds,
        'km': kmTimes,
        'hrSum': _hrSum,
        'hrN': _hrCount,
        'track': [for (final p in track) [p.lat, p.lon]],
        'samples': [
          for (final x in samples) [x.t, x.d, x.point.lat, x.point.lon, x.alt, x.hr],
        ],
        'saved': DateTime.now().toIso8601String(),
      };

  /// Een onderbroken run terughalen. Staat daarna op pauze.
  static RunRecording? fromSnapshot(Object? j) {
    if (j is! Map || j['v'] != 1) return null;
    try {
      final r = RunRecording(autoPause: j['auto'] as bool? ?? true, indoor: j['indoor'] as bool? ?? false);
      r.startedAt = j['started'] == null ? null : DateTime.parse(j['started'] as String);
      r.treadmillKmh = (j['tm'] as num?)?.toDouble();
      r.distance = (j['dist'] as num).toDouble();
      r.movingSeconds = (j['moving'] as num).toDouble();
      r.kmTimes.addAll([for (final k in j['km'] as List) (k as num).toDouble()]);
      r._hrSum = (j['hrSum'] as num?)?.toInt() ?? 0;
      r._hrCount = (j['hrN'] as num?)?.toInt() ?? 0;
      for (final p in j['track'] as List) {
        r.track.add(LatLng(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()));
      }
      for (final x in j['samples'] as List) {
        final l = x as List;
        r.samples.add(RunSample(
          (l[0] as num).toDouble(),
          (l[1] as num).toDouble(),
          LatLng((l[2] as num).toDouble(), (l[3] as num).toDouble()),
          alt: (l[4] as num?)?.toDouble(),
          hr: (l[5] as num?)?.toInt(),
        ));
      }
      r.status = RecorderStatus.paused;
      return r;
    } catch (_) {
      return null;
    }
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

  /// Het verloop om op te slaan, in dezelfde vorm als bij Strava (t, d, alt, hr, ll).
  /// Hoogte wordt gladgestreken (GPS-hoogte springt), ontbrekende waarden aangevuld.
  Map<String, dynamic>? streamsJson() {
    if (samples.length < 2) return null;
    final t = [for (final s in samples) double.parse(s.t.toStringAsFixed(1))];
    final d = [for (final s in samples) double.parse(s.d.toStringAsFixed(1))];
    final ll = [
      for (final s in samples) [double.parse(s.point.lat.toStringAsFixed(6)), double.parse(s.point.lon.toStringAsFixed(6))],
    ];
    List<double>? fill(List<double?> v) {
      if (v.every((x) => x == null)) return null;
      final out = <double>[];
      double? last = v.firstWhere((x) => x != null);
      for (final x in v) {
        last = x ?? last;
        out.add(last!);
      }
      return out;
    }

    final alt = fill([for (final s in samples) s.alt]);
    List<double>? smooth(List<double>? v, int w) {
      if (v == null) return null;
      return [
        for (var i = 0; i < v.length; i++)
          () {
            final a = math.max(0, i - w), b = math.min(v.length - 1, i + w);
            var sum = 0.0;
            for (var j = a; j <= b; j++) {
              sum += v[j];
            }
            return double.parse((sum / (b - a + 1)).toStringAsFixed(1));
          }(),
      ];
    }

    final hr = fill([for (final s in samples) s.hr?.toDouble()]);
    return {
      't': t,
      'd': d,
      if (!indoor) 'll': ll,
      if (alt != null) 'alt': smooth(alt, 3),
      if (hr != null) 'hr': hr,
      'src': indoor ? 'loopband' : 'runwise',
    };
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
