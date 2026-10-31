import 'dart:math' as math;

import 'geo.dart';
import 'route_geometry.dart';
import 'route_photos.dart' show projectOnTrack;
import 'run_helpers.dart' show directionWords;
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

/// Hoe de stemcoach klinkt.
enum CoachStyle {
  calm('Rustig', 'Alleen de cijfers, vriendelijk gezegd'),
  motivating('Motiverend', 'Met een aanmoediging erbij'),
  short('Kort', 'Alleen afstand en tempo van het laatste stuk');

  const CoachStyle(this.label, this.description);
  final String label;
  final String description;
}

/// Aanmoedigingen voor de motiverende stem (wisselen per melding).
const motivatingLines = [
  'Lekker bezig!',
  'Je loopt sterk.',
  'Mooi ritme, hou vast.',
  'Ontspan je schouders en blijf soepel.',
  'Elke kilometer telt. Ga zo door!',
  'Dit doe je goed.',
];

/// Wat de stemcoach zegt en hoe vaak.
class CueSettings {
  const CueSettings({
    this.every = CueEvery.km,
    this.lap = true,
    this.average = true,
    this.total = true,
    this.heartRate = true,
    this.fuel = false,
    this.style = CoachStyle.calm,
    this.compare = true,
    this.finish = true,
  });

  final CueEvery every;

  /// Hoe de stem klinkt.
  final CoachStyle style;

  /// Vergelijken met het vorige stuk ("6 seconden sneller dan de vorige").
  final bool compare;

  /// Verwachte eindtijd noemen als Kadans weet hoe ver je nog moet (route of heen-en-terug).
  final bool finish;

  /// Herinneringen om te drinken en (bij lange runs) een gel te nemen.
  final bool fuel;

  /// Tempo van het laatste stuk.
  final bool lap;
  final bool average;
  final bool total;
  final bool heartRate;

  CueSettings copyWith({
    CueEvery? every,
    bool? lap,
    bool? average,
    bool? total,
    bool? heartRate,
    bool? fuel,
    CoachStyle? style,
    bool? compare,
    bool? finish,
  }) =>
      CueSettings(
        every: every ?? this.every,
        lap: lap ?? this.lap,
        average: average ?? this.average,
        total: total ?? this.total,
        heartRate: heartRate ?? this.heartRate,
        fuel: fuel ?? this.fuel,
        style: style ?? this.style,
        compare: compare ?? this.compare,
        finish: finish ?? this.finish,
      );

  Map<String, dynamic> toJson() => {
        'e': every.name,
        'l': lap,
        'a': average,
        't': total,
        'h': heartRate,
        'f': fuel,
        's': style.name,
        'c': compare,
        'fi': finish,
      };

  static CueSettings fromJson(Object? j) {
    if (j is! Map) return const CueSettings();
    return CueSettings(
      every: CueEvery.values.where((e) => e.name == j['e']).firstOrNull ?? CueEvery.km,
      lap: j['l'] as bool? ?? true,
      average: j['a'] as bool? ?? true,
      total: j['t'] as bool? ?? true,
      heartRate: j['h'] as bool? ?? true,
      fuel: j['f'] as bool? ?? false,
      style: CoachStyle.values.where((e) => e.name == j['s']).firstOrNull ?? CoachStyle.calm,
      compare: j['c'] as bool? ?? true,
      finish: j['fi'] as bool? ?? true,
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
  double? _prevLapPace;

  /// Geeft de tekst als het tijd is voor een melding.
  /// [remainingMeters] = hoeveel je nog moet (route of heen-en-terug), voor de verwachte eindtijd.
  String? update(RunRecording r, {int? heartRate, double? remainingMeters}) {
    final every = settings.every;
    final n = every.meters != null ? (r.distance / every.meters!).floor() : (r.movingSeconds / every.seconds!).floor();
    if (n <= _done || n == 0) return null;
    _done = n;
    final lapT = r.movingSeconds - _lastT, lapD = r.distance - _lastD;
    _lastT = r.movingSeconds;
    _lastD = r.distance;
    final lapPace = lapD > 50 && !r.indoor ? lapT / (lapD / 1000) : null;
    final prev = _prevLapPace;
    _prevLapPace = lapPace;
    final head = every.meters != null ? '${_km(n * every.meters!.toDouble())}.' : '${n * every.seconds! ~/ 60} minuten.';
    if (settings.style == CoachStyle.short) {
      return [
        head,
        if (lapPace != null) '${spokenPace(lapPace)}.',
        if (every.seconds != null && !r.indoor) '${_km(r.distance)}.',
      ].join(' ');
    }
    String? compare;
    if (settings.compare && lapPace != null && prev != null && settings.lap) {
      final d = (lapPace - prev).round();
      compare = d.abs() < 3
          ? 'Even snel als het vorige stuk.'
          : d < 0
              ? '${d.abs()} seconden sneller dan het vorige stuk.'
              : '${d.abs()} seconden langzamer dan het vorige stuk.';
    }
    String? finish;
    final rem = remainingMeters;
    if (settings.finish && rem != null && rem > 300 && r.averagePace > 0 && !r.indoor) {
      final eta = r.movingSeconds + rem / 1000 * r.averagePace;
      finish = 'Met dit tempo ben je klaar na ${spokenDuration(eta)}.';
    }
    final parts = <String>[
      head,
      // Op de loopband staan afstand en tempo al op het display: dan alleen tijd (en hartslag).
      if (every.seconds != null && !r.indoor) 'Afstand ${_km(r.distance)}.',
      if (settings.lap && lapPace != null) 'Dit stuk ${spokenPace(lapPace)} per kilometer.',
      if (compare != null) compare,
      if (settings.average && r.averagePace > 0 && !r.indoor) 'Gemiddeld ${spokenPace(r.averagePace)}.',
      if (settings.total && every.meters != null) 'Totale tijd ${spokenDuration(r.movingSeconds)}.',
      if (settings.heartRate && heartRate != null) 'Hartslag $heartRate.',
      if (finish != null) finish,
      if (settings.style == CoachStyle.motivating) motivatingLines[(n - 1) % motivatingLines.length],
    ];
    return parts.join(' ');
  }
}

/// Recordjacht en mijlpalen onderweg: "houd dit tempo vast en je loopt een nieuw 5 km-record",
/// "nieuw record!" en "dit is nu je langste run ooit".
class RecordHunt {
  RecordHunt({required this.bests, this.longestBefore = 0, this.labels = const {}});

  /// Je snelste tijd per afstand (meters → seconden), van vóór deze run.
  final Map<int, double> bests;

  /// Je langste run tot nu toe (meters).
  final double longestBefore;

  /// Naam per afstand ("5 km"); anders "5000 meter".
  final Map<int, String> labels;

  final _hinted = <int>{};
  final _done = <int>{};
  bool _longestSaid = false;

  String _label(int m) => labels[m] ?? (m % 1000 == 0 ? '${m ~/ 1000} km' : '$m meter');

  /// [pace] = tempo van het laatste stuk (s/km), om de eindtijd te schatten.
  String? update(double distance, double moving, double pace) {
    if (!_longestSaid && longestBefore >= 3000 && distance > longestBefore + 20) {
      _longestSaid = true;
      return 'Dit is nu je langste run ooit! Nog nooit liep je zo ver.';
    }
    final keys = bests.keys.toList()..sort();
    for (final m in keys) {
      if (m < 1000) continue;
      final best = bests[m]!;
      if (distance >= m && !_done.contains(m)) {
        _done.add(m);
        // Alleen als het hele stuk vanaf de start sneller was (een snel middenstuk zie je na afloop).
        if (moving + 0.5 < best) {
          return 'Nieuw record op de ${_label(m)}! ${spokenDuration(moving)}. Wat een run!';
        }
        continue;
      }
      if (_hinted.contains(m) || distance < m * 0.6 || distance >= m || pace <= 0) continue;
      final projected = moving + (m - distance) / 1000 * pace;
      if (projected + 2 < best) {
        _hinted.add(m);
        return 'Houd dit tempo vast en je loopt een nieuw ${_label(m)}-record: rond ${spokenDuration(projected)}.';
      }
    }
    return null;
  }
}

/// Heen en terug op tijd: halverwege zegt Kadans "draai om".
class Turnaround {
  Turnaround(this.totalSeconds);
  final double totalSeconds;
  bool _said = false;
  bool _almost = false;

  String? update(double moving) {
    final half = totalSeconds / 2;
    if (!_almost && moving >= half - 60 && moving < half) {
      _almost = true;
      return 'Over een minuut ben je halverwege.';
    }
    if (!_said && moving >= half) {
      _said = true;
      _almost = true;
      return 'Halverwege! Draai nu om, dan ben je na ${spokenDuration(totalSeconds)} weer terug.';
    }
    return null;
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

/// Kompasrichting in gewone woorden ("naar het noordoosten").
String compassWords(double bearing) {
  const names = ['noorden', 'noordoosten', 'oosten', 'zuidoosten', 'zuiden', 'zuidwesten', 'westen', 'noordwesten'];
  final i = (((bearing % 360) + 22.5) ~/ 45) % 8;
  return 'naar het ${names[i]}';
}

/// Windrichting in woorden ("uit het zuidwesten").
String windFromWords(double degrees) => compassWords(degrees).replaceFirst('naar', 'uit');

/// Korte briefing bij de start: temperatuur, wind en waar je tegenwind hebt op je route.
String startBriefing({
  required double temperature,
  double? feelsLike,
  required double windKmh,
  double? windFrom,
  double? rainChance,
  double? firstHalfHead,
  double? secondHalfHead,
}) {
  final t = temperature.round();
  final parts = <String>[
    feelsLike != null && (feelsLike - temperature).abs() >= 2
        ? 'Het is $t graden, het voelt als ${feelsLike.round()}.'
        : 'Het is $t graden.',
  ];
  if (windKmh >= 8 && windFrom != null) {
    parts.add('Wind ${windKmh.round()} kilometer per uur ${windFromWords(windFrom)}.');
    final a = firstHalfHead, b = secondHalfHead;
    if (a != null && b != null) {
      if (a > 4 && a - b > 3) {
        parts.add('De eerste helft heb je tegenwind, op de terugweg helpt de wind je.');
      } else if (b > 4 && b - a > 3) {
        parts.add('De tweede helft heb je tegenwind. Houd wat over voor het eind.');
      }
    }
  } else {
    parts.add('Er staat bijna geen wind.');
  }
  if (rainChance != null && rainChance >= 50) parts.add('Kans op regen: ${rainChance.round()} procent.');
  return parts.join(' ');
}

/// Afstand voor de stem: tot 100 m op 10 m, daarboven op 50 m.
String spokenMeters(double m) {
  if (m >= 1000) return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} kilometer';
  final r = m >= 100 ? (m / 50).round() * 50 : math.max(10, (m / 10).round() * 10);
  return '$r meter';
}

/// Waar de route ligt vanaf waar je nu bent.
class WayToRoute {
  const WayToRoute({required this.meters, required this.bearing, this.relative});

  /// Afstand tot het dichtstbijzijnde punt van de route.
  final double meters;

  /// Kompasrichting naar de route (0 = noord).
  final double bearing;

  /// Ten opzichte van je looprichting (0 = recht voor je, 90 = rechts). Null = je staat stil.
  final double? relative;

  String get words => relative != null ? directionWords(relative!) : compassWords(bearing);
}

/// Route volgen tijdens het lopen: waar ben je op de route en ben je ervan af?
///
/// - Je mag overal op de route beginnen: Kadans pakt de route op waar je erop komt.
///   Bij een rondje draait de route mee, zodat je toch het hele rondje loopt.
/// - Sta je nog niet op de route, of ben je eraf, dan zegt Kadans welke kant je op moet.
class RouteFollower {
  RouteFollower(RouteTrack track, {this.offAfter = 45, this.backWithin = 25, this.repeatSeconds = 30})
      : _track = track,
        original = track;

  /// De route zoals hij gemaakt is.
  final RouteTrack original;
  RouteTrack _track;

  /// De route zoals je hem nu volgt (bij een rondje kan het begin verschoven zijn).
  RouteTrack get track => _track;

  /// Verder dan zoveel meter van de route = eraf (na 3 metingen achter elkaar).
  final double offAfter;
  final double backWithin;

  /// Zo vaak (seconden) herhaalt de stem waar de route ligt als je ernaast loopt.
  final double repeatSeconds;

  double progress = 0;
  bool offRoute = false;

  /// Nog niet op de route geweest (je loopt ernaartoe).
  bool approaching = true;

  /// Wordt true als de route een nieuw begin kreeg (de recorder rekent dan de afslagen opnieuw uit).
  bool rebased = false;

  /// Op hoeveel meter van het oorspronkelijke begin je de route oppakte.
  double joinedAt = 0;

  /// Waar de route ligt (alleen als je er nog niet op bent of ervan af bent).
  WayToRoute? way;

  int _offCount = 0;
  bool _nearFinishSaid = false;
  LatLng? _last;
  double? _heading;
  double? _lastWaySaid;
  double _clock = 0;

  double get remaining => (track.length - progress).clamp(0, double.infinity).toDouble();

  /// Begin en eind liggen vlak bij elkaar: een rondje.
  bool get isLoop => original.isValid && distanceMeters(original.points.first, original.points.last) < 120;

  void _trackHeading(LatLng p) {
    final last = _last;
    if (last == null) {
      _last = p;
      return;
    }
    if (distanceMeters(last, p) >= 12) {
      _heading = bearingDegrees(last, p);
      _last = p;
    }
  }

  WayToRoute _wayFrom(LatLng p, RouteTrack t, double meters, double off) {
    final target = t.at(meters);
    final b = bearingDegrees(p, target);
    double? rel;
    if (_heading != null) {
      rel = (b - _heading!) % 360;
      if (rel < 0) rel += 360;
    }
    return WayToRoute(meters: off, bearing: b, relative: rel);
  }

  /// Draai een rondje zo dat het begint op [m] meter.
  RouteTrack _rotated(double m) {
    final t = original;
    final pts = <LatLng>[t.at(m)];
    for (var i = 0; i < t.points.length; i++) {
      if (t.cumulative[i] > m) pts.add(t.points[i]);
    }
    for (var i = 1; i < t.points.length; i++) {
      if (t.cumulative[i] <= m) pts.add(t.points[i]);
    }
    pts.add(t.at(m));
    return RouteTrack(pts);
  }

  /// Verwerkt je positie. Geeft een tekst voor de stem als er iets verandert.
  /// [seconds] = tijd sinds de start (voor het herhalen van "de route ligt …").
  String? update(LatLng p, {double? seconds}) {
    if (!track.isValid) return null;
    _clock = seconds ?? _clock + 3;
    _trackHeading(p);

    if (approaching) {
      // Vlak bij het begin? Dan gewoon vanaf het begin.
      final startOff = distanceMeters(p, original.points.first);
      final pr = projectOnTrack(original, p);
      final joinNearStart = startOff <= backWithin * 1.6;
      if (joinNearStart || pr.off <= backWithin) {
        approaching = false;
        way = null;
        final at = joinNearStart ? 0.0 : pr.meters;
        if (at > 50 && (original.length - at) > 50) {
          joinedAt = at;
          if (isLoop) {
            _track = _rotated(at);
            rebased = true;
            progress = 0;
          } else {
            progress = at;
          }
          // Alleen iets zeggen als je eerst naar de route toe moest lopen of halverwege instapt.
          return isLoop
              ? 'Je bent op je route. Je loopt het hele rondje vanaf hier.'
              : 'Je bent op je route. Nog ${spokenMeters(remaining)}.';
        }
        return _lastWaySaid != null ? 'Je bent op je route. Veel plezier.' : null;
      }
      way = _wayFrom(p, original, pr.meters, pr.off);
      if (_lastWaySaid == null || _clock - _lastWaySaid! >= repeatSeconds * 1.5) {
        final first = _lastWaySaid == null;
        _lastWaySaid = _clock;
        return first
            ? 'Je route ligt ${spokenMeters(pr.off)} ${way!.words}. Loop daarheen, dan begint de begeleiding.'
            : 'Je route ligt nog ${spokenMeters(pr.off)} ${way!.words}.';
      }
      return null;
    }

    final pr = projectOnTrack(track, p);
    // Vooruitgang alleen vooruit (een stukje terug telt niet), en niet verspringen naar het einde van een rondje.
    if (pr.off < backWithin * 2 && pr.meters > progress - 150 && pr.meters < progress + 400) {
      progress = math.max(progress, pr.meters);
    }
    if (!offRoute) {
      _offCount = pr.off > offAfter ? _offCount + 1 : 0;
      if (_offCount >= 3) {
        offRoute = true;
        // Terug naar het punt waar je eraf ging (of verderop als dat dichterbij is).
        way = _wayFrom(p, track, pr.meters, pr.off);
        _lastWaySaid = _clock;
        return 'Let op, je bent van je route af. De route ligt ${spokenMeters(pr.off)} ${way!.words}.';
      }
    } else if (pr.off < backWithin) {
      offRoute = false;
      _offCount = 0;
      way = null;
      // Weer op de route: verder tellen vanaf waar je erop kwam (als dat vooruit is).
      if (pr.meters > progress && pr.meters < progress + 1500) progress = pr.meters;
      return 'Je bent weer op je route.';
    } else {
      way = _wayFrom(p, track, pr.meters, pr.off);
      if (_lastWaySaid == null || _clock - _lastWaySaid! >= repeatSeconds) {
        _lastWaySaid = _clock;
        return 'De route ligt ${spokenMeters(pr.off)} ${way!.words}.';
      }
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

  /// Hoe ver je record was na [seconds] seconden (voor de ghost-loper op de kaart).
  double? distanceAt(double seconds) {
    final t = best.time, d = best.distance;
    if (t.isEmpty || seconds <= 0) return null;
    if (seconds >= t.last) return d.last;
    var lo = 0, hi = t.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (t[mid] <= seconds) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = t[hi] - t[lo];
    final f = span <= 0 ? 0.0 : (seconds - t[lo]) / span;
    return d[lo] + (d[hi] - d[lo]) * f;
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
