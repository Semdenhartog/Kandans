import 'dart:math' as math;

import 'beginner_plan.dart';
import 'intervals.dart';
import 'training_plan.dart';

/// Schema op maat: een uitgebreid hardloopschema naar de wensen van de loper.
/// Alles wordt op de telefoon berekend (geen AI). Zie docs/schema-op-maat-100-vragen.md.

enum PlanGoal {
  beginnen('Beginnen', 'Van nul naar 30 minuten lopen', null, 9, 6),
  terugkomen('Terugkomen', 'Na een blessure of pauze', null, 6, 4),
  fit('Fit blijven', 'Fitter worden, zonder wedstrijd', null, 10, 6),
  sneller('Sneller worden', 'Sneller op 5 en 10 km, zonder wedstrijd', null, 10, 6),
  k5('5 km', 'Naar een 5 km', 5000, 8, 6),
  k10('10 km', 'Naar een 10 km', 10000, 10, 6),
  k15('15 km', 'Naar een 15 km of 10 Engelse mijl', 15000, 12, 8),
  halve('Halve marathon', '21,1 km', 21097.5, 14, 10),
  marathon('Marathon', '42,2 km', 42195, 18, 14);

  const PlanGoal(this.label, this.subtitle, this.meters, this.defaultWeeks, this.minWeeks);
  final String label;
  final String subtitle;
  final double? meters;
  final int defaultWeeks;
  final int minWeeks;

  bool get isRace => meters != null;
  bool get isStarter => this == beginnen || this == terugkomen;
}

enum Ambition {
  rustig('Rustig', 'Lekker lopen, weinig druk', 0.85),
  gebalanceerd('Gebalanceerd', 'Stevig maar haalbaar', 1.0),
  ambitieus('Ambitieus', 'Het maximale eruit halen', 1.15);

  const Ambition(this.label, this.subtitle, this.factor);
  final String label;
  final String subtitle;
  final double factor;
}

enum Terrain {
  vlak('Vlak'),
  heuvels('Heuvelachtig'),
  trail('Trail');

  const Terrain(this.label);
  final String label;
}

enum PlanPhase {
  start('Start', 'Wennen aan het lopen'),
  basis('Basis', 'Rustige kilometers, sterke basis'),
  opbouw('Opbouw', 'Meer omvang, eerste snelle trainingen'),
  piek('Piek', 'Wedstrijdspecifiek, de zwaarste weken'),
  afbouw('Afbouw', 'Minder volume, fris aan de start'),
  herstel('Herstel', 'Bijkomen na de wedstrijd'),
  vrij('Vrij', 'Week zonder lopen');

  const PlanPhase(this.label, this.subtitle);
  final String label;
  final String subtitle;
}

enum ExtraKind {
  kracht('Kracht'),
  cross('Crosstraining'),
  mobiliteit('Mobiliteit'),
  rust('Rust');

  const ExtraKind(this.label);
  final String label;
}

/// Wat de loper wil.
class PlanWishes {
  const PlanWishes({
    this.goal = PlanGoal.k10,
    this.raceDate,
    this.raceName,
    this.weeks = 10,
    this.goalTimeSeconds,
    this.recent5kSeconds,
    this.weeklyKm = 15,
    this.longestKm = 8,
    this.runDays = const [2, 4, 7],
    this.longRunDay = 7,
    this.maxWeekdayMinutes = 60,
    this.ambition = Ambition.gebalanceerd,
    this.strengthPerWeek = 1,
    this.cross = false,
    this.injuryProne = false,
    this.over50 = false,
    this.terrain = Terrain.vlak,
    this.treadmill = false,
    this.inMinutes = false,
    this.skipWeeks = const {},
    this.testRace = false,
    this.name,
  });

  final PlanGoal goal;
  final DateTime? raceDate;
  final String? raceName;

  /// Duur zonder wedstrijd(datum).
  final int weeks;
  final int? goalTimeSeconds;
  final int? recent5kSeconds;
  final double weeklyKm;
  final double longestKm;

  /// 1 = maandag … 7 = zondag.
  final List<int> runDays;
  final int longRunDay;
  final int maxWeekdayMinutes;
  final Ambition ambition;
  final int strengthPerWeek;
  final bool cross;
  final bool injuryProne;
  final bool over50;
  final Terrain terrain;
  final bool treadmill;
  final bool inMinutes;

  /// Weeknummers (1 = eerste) zonder lopen, bijvoorbeeld vakantie.
  final Set<int> skipWeeks;
  final bool testRace;
  final String? name;

  PlanWishes copyWith({
    PlanGoal? goal,
    DateTime? raceDate,
    bool clearRace = false,
    String? raceName,
    int? weeks,
    int? goalTimeSeconds,
    bool clearGoalTime = false,
    int? recent5kSeconds,
    bool clear5k = false,
    double? weeklyKm,
    double? longestKm,
    List<int>? runDays,
    int? longRunDay,
    int? maxWeekdayMinutes,
    Ambition? ambition,
    int? strengthPerWeek,
    bool? cross,
    bool? injuryProne,
    bool? over50,
    Terrain? terrain,
    bool? treadmill,
    bool? inMinutes,
    Set<int>? skipWeeks,
    bool? testRace,
    String? name,
  }) =>
      PlanWishes(
        goal: goal ?? this.goal,
        raceDate: clearRace ? null : raceDate ?? this.raceDate,
        raceName: clearRace ? null : raceName ?? this.raceName,
        weeks: weeks ?? this.weeks,
        goalTimeSeconds: clearGoalTime ? null : goalTimeSeconds ?? this.goalTimeSeconds,
        recent5kSeconds: clear5k ? null : recent5kSeconds ?? this.recent5kSeconds,
        weeklyKm: weeklyKm ?? this.weeklyKm,
        longestKm: longestKm ?? this.longestKm,
        runDays: runDays ?? this.runDays,
        longRunDay: longRunDay ?? this.longRunDay,
        maxWeekdayMinutes: maxWeekdayMinutes ?? this.maxWeekdayMinutes,
        ambition: ambition ?? this.ambition,
        strengthPerWeek: strengthPerWeek ?? this.strengthPerWeek,
        cross: cross ?? this.cross,
        injuryProne: injuryProne ?? this.injuryProne,
        over50: over50 ?? this.over50,
        terrain: terrain ?? this.terrain,
        treadmill: treadmill ?? this.treadmill,
        inMinutes: inMinutes ?? this.inMinutes,
        skipWeeks: skipWeeks ?? this.skipWeeks,
        testRace: testRace ?? this.testRace,
        name: name ?? this.name,
      );

  Map<String, dynamic> toJson() => {
        'goal': goal.name,
        if (raceDate != null) 'race': raceDate!.toIso8601String(),
        if (raceName != null) 'raceName': raceName,
        'weeks': weeks,
        if (goalTimeSeconds != null) 'goalTime': goalTimeSeconds,
        if (recent5kSeconds != null) 't5k': recent5kSeconds,
        'km': weeklyKm,
        'longest': longestKm,
        'days': runDays,
        'long': longRunDay,
        'max': maxWeekdayMinutes,
        'amb': ambition.name,
        'str': strengthPerWeek,
        'cross': cross,
        'inj': injuryProne,
        'o50': over50,
        'ter': terrain.name,
        'tm': treadmill,
        'min': inMinutes,
        'skip': skipWeeks.toList(),
        'test': testRace,
        if (name != null) 'name': name,
      };

  static PlanWishes? fromJson(Object? j) {
    if (j is! Map) return null;
    T byName<T extends Enum>(List<T> values, Object? v, T fallback) => values.where((e) => e.name == v).firstOrNull ?? fallback;
    try {
      return PlanWishes(
        goal: byName(PlanGoal.values, j['goal'], PlanGoal.k10),
        raceDate: j['race'] == null ? null : DateTime.parse(j['race'] as String),
        raceName: j['raceName'] as String?,
        weeks: (j['weeks'] as num?)?.toInt() ?? 10,
        goalTimeSeconds: (j['goalTime'] as num?)?.toInt(),
        recent5kSeconds: (j['t5k'] as num?)?.toInt(),
        weeklyKm: (j['km'] as num?)?.toDouble() ?? 15,
        longestKm: (j['longest'] as num?)?.toDouble() ?? 8,
        runDays: [for (final d in (j['days'] as List? ?? const [2, 4, 7])) (d as num).toInt()],
        longRunDay: (j['long'] as num?)?.toInt() ?? 7,
        maxWeekdayMinutes: (j['max'] as num?)?.toInt() ?? 60,
        ambition: byName(Ambition.values, j['amb'], Ambition.gebalanceerd),
        strengthPerWeek: (j['str'] as num?)?.toInt() ?? 1,
        cross: j['cross'] == true,
        injuryProne: j['inj'] == true,
        over50: j['o50'] == true,
        terrain: byName(Terrain.values, j['ter'], Terrain.vlak),
        treadmill: j['tm'] == true,
        inMinutes: j['min'] == true,
        skipWeeks: {for (final w in (j['skip'] as List? ?? const [])) (w as num).toInt()},
        testRace: j['test'] == true,
        name: j['name'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Een looptraining met uitleg (de sessie zelf gaat ook in je plan).
class PlanItem {
  const PlanItem({required this.session, required this.rpe, required this.why, required this.parts, required this.minutes, this.key = false});
  final PlanSession session;

  /// Zwaarte 1–10.
  final int rpe;
  final String why;

  /// Inlopen / kern / uitlopen (en tips).
  final List<String> parts;
  final int minutes;

  /// Sleuteltraining van de week.
  final bool key;
}

class PlanExtra {
  const PlanExtra({required this.date, required this.kind, required this.title, required this.description, this.minutes = 0});
  final DateTime date;
  final ExtraKind kind;
  final String title;
  final String description;
  final int minutes;
}

class PlanWeek {
  PlanWeek({required this.number, required this.start, required this.phase, required this.focus, required this.recovery});
  final int number;
  final DateTime start;
  final PlanPhase phase;
  final String focus;
  final bool recovery;
  final List<PlanItem> items = [];
  final List<PlanExtra> extras = [];

  double get km => items.where((i) => i.session.kind != SessionKind.race).fold(0.0, (s, i) => s + (i.session.distanceMeters ?? i.minutes * 60 / 390 * 1000)) / 1000;
  int get minutes => items.fold(0, (s, i) => s + i.minutes) + extras.fold(0, (s, e) => s + e.minutes);
}

class PaceZone {
  const PaceZone(this.name, this.from, this.to, this.rpe, this.text);
  final String name;

  /// s/km.
  final double from;
  final double to;
  final String rpe;
  final String text;
}

class CustomPlan {
  CustomPlan({required this.wishes, required this.start, required this.weeks, required this.paces, this.predictedSeconds, this.goalCheck,
      this.warnings = const [], this.raceDate, this.paceIsEstimate = true});
  final PlanWishes wishes;
  final DateTime start;
  final List<PlanWeek> weeks;
  final List<PaceZone> paces;
  final int? predictedSeconds;

  /// "haalbaar", "ambitieus" of "erg ambitieus" (alleen met doeltijd).
  final String? goalCheck;
  final List<String> warnings;
  final List<String> raceDay = [];
  final DateTime? raceDate;
  final bool paceIsEstimate;

  /// Alle looptrainingen, voor je plan in de app.
  List<PlanSession> get runSessions => [for (final w in weeks) for (final i in w.items) i.session];
  double get peakKm => weeks.fold(0.0, (m, w) => math.max(m, w.km));
  int get keyCount => weeks.fold(0, (s, w) => s + w.items.where((i) => i.key).length);
  double get totalKm => weeks.fold(0.0, (s, w) => s + w.km);
}

// ---------------------------------------------------------------- hulpjes

String fmtPace(double s) {
  final t = s.round();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

String fmtTime(int s) {
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}' : '$m:${r.toString().padLeft(2, '0')}';
}

String _km(double km) => km.toStringAsFixed(km.roundToDouble() == km ? 0 : 1).replaceAll('.', ',');
double _half(double km) => math.max(3, (km * 2).round() / 2);
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Voorspelde tijd (s) op [meters], vanuit drempeltempo (Riegel, via een 5 km-equivalent).
int predictSeconds(double thresholdPace, double meters) {
  final t5 = thresholdPace * 0.95 * 5;
  return (t5 * math.pow(meters / 5000, 1.06)).round();
}

/// Drempeltempo uit een 5 km-tijd.
double thresholdFrom5k(int seconds) => seconds / 5 * 1.053;

/// Maakt het schema. [thresholdPace] uit je runs (s/km), of null als er te weinig runs zijn.
CustomPlan buildCustomPlan(PlanWishes w, {required DateTime start, double? thresholdPace}) {
  final day0 = _day(start);
  final monday0 = day0.subtract(Duration(days: day0.weekday - 1));
  final race = w.goal.isRace && w.raceDate != null ? _day(w.raceDate!) : null;
  final warnings = <String>[];
  final days = ([...w.runDays.toSet()]..sort());
  if (days.isEmpty) days.addAll([2, 4, 7]);
  final longDay = days.contains(w.longRunDay) ? w.longRunDay : days.last;

  // Tempo's.
  final fromRace = w.recent5kSeconds != null && w.recent5kSeconds! > 600;
  final t = fromRace ? thresholdFrom5k(w.recent5kSeconds!) : (thresholdPace ?? 345);
  final paceIsEstimate = !fromRace && thresholdPace == null;
  final goalPace = w.goalTimeSeconds != null && w.goal.meters != null ? w.goalTimeSeconds! / (w.goal.meters! / 1000) : null;
  final easyFrom = t * 1.22, easyTo = t * 1.36;
  final easy = (easyFrom + easyTo) / 2;
  final long = t * 1.3;
  final tempo = t;
  final interval = t * 0.94;
  final racePace = goalPace ?? (w.goal.meters == null ? t * 0.97 : predictSeconds(t, w.goal.meters!) / (w.goal.meters! / 1000));
  final paces = <PaceZone>[
    PaceZone('Rustig', easyFrom, easyTo, '3–4', 'Praattempo. Het grootste deel van je kilometers.'),
    PaceZone('Lang', long - 10, long + 15, '4–5', 'Lange duurloop: ontspannen, de laatste km mag iets sneller.'),
    PaceZone('Tempo', tempo - 5, tempo + 5, '7', 'Comfortabel zwaar: je kunt nog losse woorden zeggen.'),
    PaceZone('Interval', interval - 6, interval + 4, '8', 'Snel maar gecontroleerd, ongeveer je 5 km-tempo.'),
    PaceZone(w.goal.isRace ? 'Wedstrijd' : 'Doel', racePace - 3, racePace + 3, '9', w.goal.isRace ? 'Je doeltempo op de dag zelf.' : 'Snel tempo voor een testloop.'),
  ];

  int? predicted;
  String? goalCheck;
  if (w.goal.meters != null) {
    predicted = predictSeconds(t, w.goal.meters!);
    if (w.goalTimeSeconds != null) {
      final r = w.goalTimeSeconds! / predicted;
      goalCheck = r >= 0.97 ? 'haalbaar' : (r >= 0.92 ? 'ambitieus' : 'erg ambitieus');
      if (goalCheck == 'erg ambitieus') {
        warnings.add('Je doeltijd ${fmtTime(w.goalTimeSeconds!)} is erg ambitieus: op basis van je tempo verwachten we nu rond ${fmtTime(predicted)}. '
            'Het schema rekent met je doeltempo voor de snelle trainingen; voelt het te zwaar, loop ze dan iets rustiger.');
      }
    }
  }

  // Aantal weken.
  var nWeeks = race != null ? (race.difference(monday0).inDays ~/ 7) + 1 : w.weeks.clamp(4, 24);
  if (race != null && race.difference(day0).inDays < 7) {
    nWeeks = 1;
    warnings.add('Je wedstrijd is binnen een week. Er staat alleen nog een korte afbouw in.');
  } else if (nWeeks < w.goal.minWeeks) {
    warnings.add('${w.goal.label} in $nWeeks weken is kort; ${w.goal.defaultWeeks} weken is beter. Het schema bouwt daarom voorzichtig op.');
  }
  if (w.goal == PlanGoal.marathon && w.weeklyKm < 20) {
    warnings.add('Voor een marathon loop je nu nog weinig. Overweeg eerst een halve marathon; dit schema blijft voorzichtig.');
  }

  final plan = CustomPlan(
    wishes: w,
    start: day0,
    weeks: [],
    paces: paces,
    predictedSeconds: predicted,
    goalCheck: goalCheck,
    warnings: warnings,
    raceDate: race,
    paceIsEstimate: paceIsEstimate,
  );

  if (w.goal.isStarter) {
    _buildStarter(plan, w, day0, days, longDay);
    return plan;
  }

  // Omvang.
  final g = w.goal;
  final basePeak = switch (g) {
    PlanGoal.k5 => 30.0,
    PlanGoal.k10 => 40.0,
    PlanGoal.k15 => 45.0,
    PlanGoal.halve => 50.0,
    PlanGoal.marathon => 65.0,
    PlanGoal.sneller => 35.0,
    _ => 25.0,
  };
  final growth = w.injuryProne || w.over50 ? 1.07 : (w.ambition == Ambition.ambitieus ? 1.1 : 1.08);
  final every = w.injuryProne || w.over50 ? 3 : 4;
  final dayFactor = math.min(1.15, 0.55 + days.length * 0.11);
  final peak = math.max(w.weeklyKm, basePeak * w.ambition.factor * dayFactor);
  final longCap = switch (g) {
    PlanGoal.k5 => 12.0,
    PlanGoal.k10 => 16.0,
    PlanGoal.k15 => 18.0,
    PlanGoal.halve => 21.0,
    PlanGoal.marathon => 32.0,
    _ => 14.0,
  };
  final taperWeeks = switch (g) {
    PlanGoal.marathon => 3,
    PlanGoal.halve || PlanGoal.k15 => 2,
    PlanGoal.k5 || PlanGoal.k10 => 1,
    _ => 0,
  };
  var volume = math.max(w.weeklyKm, math.min(peak * 0.6, w.weeklyKm + 5));
  var longKm = math.max(4.0, math.min(w.longestKm + 1, longCap));
  var afterSkip = false;
  final quality = days.length >= 5 && w.ambition != Ambition.rustig && !w.injuryProne ? 2 : (days.length >= 2 ? 1 : 0);
  final testWeek = w.testRace && g.isRace && g.meters! >= 10000 && nWeeks >= 8 ? (nWeeks - taperWeeks - 2) : -1;

  for (var i = 0; i < nWeeks; i++) {
    final nr = i + 1;
    final weekStart = DateTime(monday0.year, monday0.month, monday0.day + i * 7);
    final left = nWeeks - i;
    final skip = w.skipWeeks.contains(nr) && left > 1;
    final taper = taperWeeks > 0 && left <= taperWeeks;
    final recovery = !taper && !skip && nr % every == 0 && left > taperWeeks + 1;
    final buildable = nWeeks - taperWeeks;
    final phase = skip
        ? PlanPhase.vrij
        : taper
            ? PlanPhase.afbouw
            : i < buildable * 0.35
                ? PlanPhase.basis
                : (g.isRace && i >= buildable * 0.7 ? PlanPhase.piek : PlanPhase.opbouw);

    double weekKm;
    if (skip) {
      weekKm = 0;
      afterSkip = true;
    } else if (taper) {
      final step = taperWeeks - left + 1; // 1..taperWeeks
      weekKm = volume * (taperWeeks == 1 ? 0.6 : (step == taperWeeks ? 0.5 : (step == 1 ? 0.8 : 0.65)));
    } else if (recovery) {
      weekKm = volume * 0.75;
    } else if (afterSkip) {
      weekKm = volume * 0.75;
      afterSkip = false;
    } else {
      if (i > 0) volume = math.min(peak, math.max(volume * growth, volume + (volume < 25 ? (w.injuryProne || w.over50 ? 1.5 : 2.5) : 0)));
      weekKm = volume;
    }

    final focus = _focus(phase, recovery, nr == nWeeks && g.isRace, g, w);
    final week = PlanWeek(number: nr, start: weekStart, phase: phase, focus: focus, recovery: recovery);
    plan.weeks.add(week);
    if (skip) {
      for (var d = 0; d < 7; d++) {
        if (d == 0 || d == 3) {
          week.extras.add(PlanExtra(
            date: DateTime(weekStart.year, weekStart.month, weekStart.day + d),
            kind: ExtraKind.rust,
            title: d == 0 ? 'Vrije week' : 'Blijf bewegen',
            description: d == 0 ? 'Geen looptrainingen. Geniet ervan.' : 'Wandelen, fietsen of zwemmen mag, zonder doel.',
          ));
        }
      }
      continue;
    }

    // Lange duurloop.
    if (!taper && !recovery) longKm = math.min(longCap, longKm + (phase == PlanPhase.basis ? 1 : 1.5));
    final thisLong = taper ? longKm * (left == 1 ? 0.0 : 0.65) : (recovery ? longKm * 0.75 : longKm);
    final longMax = weekKm * (days.length <= 2 ? 0.55 : (days.length == 3 ? 0.45 : 0.38));
    final longRun = _half(math.min(thisLong, math.max(longMax, 5.0)));

    final weekDays = <DateTime, int>{};
    for (final d in days) {
      final date = DateTime(weekStart.year, weekStart.month, weekStart.day + ((d - weekStart.weekday) % 7));
      if (race != null && !date.isBefore(race)) continue;
      if (date.isBefore(day0)) continue;
      weekDays[date] = d;
    }
    final sortedDates = weekDays.keys.toList()..sort();
    final longDate = sortedDates.where((x) => weekDays[x] == longDay).firstOrNull;
    // Kwaliteit: niet de dag na de lange duurloop, niet twee dagen achter elkaar.
    final cands = sortedDates.where((x) => x != longDate && (longDate == null || x.difference(longDate).inDays != 1)).toList();
    final qDates = <DateTime>[];
    final nQ = recovery ? math.min(1, quality) : quality;
    for (final c in cands) {
      if (qDates.length >= nQ) break;
      if (qDates.any((q) => (q.difference(c).inDays).abs() <= 1)) continue;
      if (left == 1 && race != null && race.difference(c).inDays <= 2) continue;
      qDates.add(c);
    }

    final easyDates = sortedDates.where((x) => x != longDate && !qDates.contains(x)).toList();
    final qKm = qDates.length * math.min(10.0, weekKm * 0.2);
    final rest = weekKm - (longDate == null || left == 1 && race != null ? 0 : longRun) - qKm;
    final easyKm = easyDates.isEmpty ? 0.0 : math.max((g.meters ?? 0) >= 10000 ? 4.0 : 3.0, rest / easyDates.length);
    var stridesGiven = false;

    for (final date in sortedDates) {
      if (date == longDate && !(left == 1 && race != null)) {
        week.items.add(_longRun(w, date, nr, longRun, long, phase, g));
      } else if (qDates.contains(date)) {
        final idx = qDates.indexOf(date);
        if (nr - 1 == testWeek && idx == 0) {
          week.items.add(_testRace(w, date, nr, racePace, g));
        } else {
          week.items.add(_quality(w, date, nr, phase, idx, i, left, g, tempo, interval, racePace));
        }
      } else {
        final strides = !stridesGiven && phase != PlanPhase.basis && !recovery;
        if (strides) stridesGiven = true;
        week.items.add(_easy(w, date, nr, left == 1 && race != null ? math.min(easyKm, 5.0) : easyKm, easy, strides, weekDays[date] != longDay));
      }
    }

    if (race != null && left == 1) {
      week.items.add(_race(w, race, nr, racePace, predicted));
    }
    week.items.sort((a, b) => a.session.date.compareTo(b.session.date));
    _extras(week, w, weekStart, sortedDates, longDate, phase, race, notBefore: day0);
  }

  // Herstelweek na de wedstrijd.
  if (race != null) {
    final ws = DateTime(race.year, race.month, race.day + 1);
    final week = PlanWeek(number: plan.weeks.length + 1, start: ws, phase: PlanPhase.herstel, focus: 'Herstel: korte, rustige runs. Voel je je nog moe, wandel dan. Daarna kies je een nieuw doel.', recovery: true);
    final herstelDagen = [
      for (var k = 2; k < 7; k++) DateTime(ws.year, ws.month, ws.day + k),
    ].where((x) => days.contains(x.weekday)).toList();
    final firstDays = <DateTime>[];
    for (final x in herstelDagen) {
      if (firstDays.length >= 2) break;
      if (firstDays.isNotEmpty && x.difference(firstDays.last).inDays < 2) continue;
      firstDays.add(x);
    }
    for (final (n, date) in firstDays.indexed) {
      final km = g.meters! >= 21000 ? 4.0 : 5.0;
      week.items.add(_easy(w, date, week.number, n == 0 ? km : km + 1, easy, false, true, why: 'Bloed laten stromen, niets meer. Hersteld = soepel en zonder pijn.'));
    }
    week.items.sort((a, b) => a.session.date.compareTo(b.session.date));
    plan.weeks.add(week);
    plan.raceDay.addAll(_raceDayPlan(w, racePace, predicted));
    final longest = plan.runSessions.where((s) => s.kind == SessionKind.long).fold<double>(0, (m, s) => math.max(m, (s.distanceMeters ?? 0) / 1000));
    final wanted = math.min(g.meters! / 1000 * 0.9, longCap);
    if (g.meters! >= 10000 && longest < wanted - 1) {
      warnings.add('Je langste duurloop komt in dit schema tot ${_km(longest)} km; voor een ${g.label} is ±${_km(wanted.roundToDouble())} km beter. '
          'Meer weken of een extra loopdag helpt.');
    }
  }
  return plan;
}

// ---------------------------------------------------------------- trainingen

int _min(double km, double pace) => (km * pace / 60).round();

String _dist(PlanWishes w, double km, double pace) => w.inMinutes ? '${_min(km, pace)} min' : '${_km(km)} km';

PlanItem _easy(PlanWishes w, DateTime date, int nr, double km, double pace, bool strides, bool weekday, {String? why}) {
  var k = _half(km);
  if (weekday) k = _half(math.min(k, w.maxWeekdayMinutes * 60 / pace));
  final mins = _min(k, pace) + (strides ? 3 : 0);
  return PlanItem(
    session: PlanSession(
      date: date,
      kind: SessionKind.easy,
      week: nr,
      title: 'Rustig ${_dist(w, k, pace)}${strides ? ' + versnellingen' : ''}',
      description: 'Ontspannen rond ${fmtPace(pace)} /km, praattempo.${strides ? ' Daarna 4–6 versnellingen van 20 seconden.' : ''}',
      distanceMeters: k * 1000,
      targetPace: pace,
    ),
    rpe: 3,
    why: why ?? (strides ? 'Basisconditie, en met de versnellingen houd je je benen snel en je pas soepel.' : 'Hier groeit je conditie: veel rustige kilometers, weinig belasting.'),
    parts: [
      'Begin de eerste 5 minuten extra rustig.',
      'Hele run rond ${fmtPace(pace)} /km, je kunt in zinnen praten.',
      if (strides) '4–6 × 20 s versnellen tot ±90%, rustig terugwandelen.',
    ],
    minutes: mins,
  );
}

PlanItem _longRun(PlanWishes w, DateTime date, int nr, double km, double pace, PlanPhase phase, PlanGoal g) {
  final mins = _min(km, pace);
  final finish = phase == PlanPhase.piek && g.meters != null && g.meters! >= 15000;
  final marathonBlocks = g == PlanGoal.marathon && phase == PlanPhase.piek && km >= 24;
  return PlanItem(
    session: PlanSession(
      date: date,
      kind: SessionKind.long,
      week: nr,
      title: 'Lange duurloop ${_dist(w, km, pace)}',
      description: marathonBlocks
          ? 'Rustig rond ${fmtPace(pace)} /km, met in het midden 2 × 5 km op marathontempo.'
          : 'Rustig rond ${fmtPace(pace)} /km.${finish ? ' De laatste 2–3 km op wedstrijdtempo als het goed voelt.' : ''}',
      distanceMeters: km * 1000,
      targetPace: pace,
    ),
    rpe: finish || marathonBlocks ? 6 : 4,
    key: true,
    why: 'Je belangrijkste training: uithoudingsvermogen, sterkere pezen en je lichaam leert vet verbranden.',
    parts: [
      'Eerste 2 km om in te komen, nog rustiger.',
      marathonBlocks ? 'Middenstuk: 2 × 5 km op marathontempo, daartussen 2 km rustig.' : 'Gelijkmatig rond ${fmtPace(pace)} /km.',
      if (finish) 'Laatste 2–3 km op wedstrijdtempo, alleen als het goed voelt.',
      if (mins >= 75) 'Langer dan 75 min: neem drinken mee en 30–60 g koolhydraten per uur (gel, sportdrank).',
      if (w.terrain != Terrain.vlak) 'Kies een route met hoogteverschil, zoals je wedstrijd.',
      'Na afloop 10 min mobiliteit: kuiten, hamstrings, heupbuigers en billen, 30 s per oefening.',
    ],
    minutes: mins,
  );
}

PlanItem _quality(PlanWishes w, DateTime date, int nr, PlanPhase phase, int idx, int i, int left, PlanGoal g, double tempo,
    double interval, double racePace) {
  final tm = w.treadmill ? 'Op de loopband: helling 1%, tempo op het scherm instellen.' : null;
  final hills = w.terrain != Terrain.vlak;
  // Basis: fartlek of heuvels.
  if (phase == PlanPhase.basis) {
    if (hills && idx == 0) {
      final reps = math.min(10, 6 + i ~/ 2);
      return _item(w, date, nr, SessionKind.interval, 'Heuvels $reps × 45 s', 'Heuvelsprints: $reps × 45 s stevig bergop, wandelend terug.',
          IntervalPlan.build(name: 'Heuvels $reps × 45 s', reps: reps, workSeconds: 45, restSeconds: 90), null, 7,
          'Kracht in je benen en een betere pas, met weinig klappen.', ['10 min rustig inlopen.', '$reps × 45 s krachtig bergop, korte passen, armen mee.', 'Rustig terugwandelen of dribbelen.', '10 min uitlopen.'], 35);
    }
    final reps = math.min(10, 6 + i ~/ 2);
    return _item(w, date, nr, SessionKind.interval, 'Fartlek $reps × 1 min', 'Spelen met tempo: $reps × 1 min vlot, 1 min rustig.',
        IntervalPlan.build(name: 'Fartlek $reps × 1 min', reps: reps, workSeconds: 60, restSeconds: 60), null, 6,
        'Lichte snelheidsprikkel zonder je te slopen; je went aan sneller lopen.', ['10 min rustig inlopen.', '$reps × 1 min vlot (zwaarte 7), 1 min rustig dribbelen.', '5 min uitlopen.', if (tm != null) tm], 30 + reps * 2);
  }
  final afbouw = phase == PlanPhase.afbouw;
  // Tempo (idx 0 in opbouw) of intervallen.
  final useTempo = (idx == 0 && phase == PlanPhase.opbouw && i.isEven) || (idx == 1 && phase != PlanPhase.piek);
  if (useTempo) {
    final blocks = afbouw ? '2 × 8 min' : (i < 8 ? '2 × 10 min' : (i < 12 ? '3 × 10 min' : '25 min aan één stuk'));
    final plan = switch (blocks) {
      '2 × 8 min' => IntervalPlan.build(name: 'Tempo 2 × 8 min', reps: 2, workSeconds: 480, restSeconds: 120),
      '2 × 10 min' => IntervalPlan.build(name: 'Tempo 2 × 10 min', reps: 2, workSeconds: 600, restSeconds: 120),
      '3 × 10 min' => IntervalPlan.build(name: 'Tempo 3 × 10 min', reps: 3, workSeconds: 600, restSeconds: 120),
      _ => IntervalPlan('Tempo 25 min', [
          const IntervalStep(StepKind.warmup, seconds: 600),
          const IntervalStep(StepKind.work, seconds: 1500),
          const IntervalStep(StepKind.cooldown, seconds: 300),
        ]),
    };
    return _item(w, date, nr, SessionKind.tempo, 'Tempoloop $blocks', '$blocks rond ${fmtPace(tempo)} /km, comfortabel zwaar.', plan, tempo, 7,
        'Je drempel omhoog: een hoger tempo langer volhouden. Dé training voor 10 km en verder.',
        ['10 min rustig inlopen + 3 versnellingen.', '$blocks rond ${fmtPace(tempo)} /km, 2 min rustig ertussen.', '5–10 min uitlopen.', if (tm != null) tm], 50);
  }
  // Intervallen per doel en fase.
  final (String name, IntervalPlan plan, double pace, String core) = switch (g) {
    PlanGoal.k5 || PlanGoal.sneller => phase == PlanPhase.piek
        ? ('${afbouw ? 4 : 6} × 800 m', IntervalPlan.build(name: '${afbouw ? 4 : 6} × 800 m', reps: afbouw ? 4 : 6, workMeters: 800, restSeconds: 120), racePace, '${afbouw ? 4 : 6} × 800 m op wedstrijdtempo, 2 min dribbelen.')
        : ('${afbouw ? 5 : 8} × 400 m', IntervalPlan.build(name: '${afbouw ? 5 : 8} × 400 m', reps: afbouw ? 5 : 8, workMeters: 400, restSeconds: 90), interval * 0.98, '${afbouw ? 5 : 8} × 400 m vlot, 90 s dribbelen.'),
    PlanGoal.k10 => phase == PlanPhase.piek
        ? ('${afbouw ? 2 : 3} × 2 km', IntervalPlan.build(name: '${afbouw ? 2 : 3} × 2 km', reps: afbouw ? 2 : 3, workMeters: 2000, restSeconds: 150), racePace, '${afbouw ? 2 : 3} × 2 km op wedstrijdtempo, 2,5 min rustig.')
        : ('${afbouw ? 3 : 5} × 1 km', IntervalPlan.build(name: '${afbouw ? 3 : 5} × 1 km', reps: afbouw ? 3 : 5, workMeters: 1000, restSeconds: 120), interval, '${afbouw ? 3 : 5} × 1 km rond ${fmtPace(interval)} /km, 2 min rustig.'),
    PlanGoal.k15 || PlanGoal.halve => phase == PlanPhase.piek
        ? ('${afbouw ? 2 : 3} × 3 km', IntervalPlan.build(name: '${afbouw ? 2 : 3} × 3 km', reps: afbouw ? 2 : 3, workMeters: 3000, restSeconds: 180), racePace, '${afbouw ? 2 : 3} × 3 km op wedstrijdtempo, 3 min rustig.')
        : ('${afbouw ? 3 : 5} × 6 min', IntervalPlan.build(name: '${afbouw ? 3 : 5} × 6 min', reps: afbouw ? 3 : 5, workSeconds: 360, restSeconds: 120), interval * 1.03, '${afbouw ? 3 : 5} × 6 min net onder je drempel, 2 min rustig.'),
    _ => phase == PlanPhase.piek
        ? ('${afbouw ? 2 : 3} × 4 km marathontempo', IntervalPlan.build(name: '${afbouw ? 2 : 3} × 4 km', reps: afbouw ? 2 : 3, workMeters: 4000, restSeconds: 120), racePace, '${afbouw ? 2 : 3} × 4 km op marathontempo, 2 min rustig.')
        : ('${afbouw ? 3 : 4} × 8 min', IntervalPlan.build(name: '${afbouw ? 3 : 4} × 8 min', reps: afbouw ? 3 : 4, workSeconds: 480, restSeconds: 120), tempo, '${afbouw ? 3 : 4} × 8 min op drempeltempo, 2 min rustig.'),
  };
  return _item(w, date, nr, SessionKind.interval, 'Intervallen $name', core, plan, pace, 8,
      phase == PlanPhase.piek ? 'Wedstrijdspecifiek: je lichaam went aan je doeltempo.' : 'Je zuurstofopname omhoog: hier word je sneller van.',
      ['10–15 min inlopen + 3 versnellingen.', core, '10 min uitlopen.', 'De stem in de app telt de blokken voor je af.', if (tm != null) tm], 55);
}

PlanItem _item(PlanWishes w, DateTime date, int nr, SessionKind kind, String title, String desc, IntervalPlan? plan, double? pace, int rpe,
        String why, List<String> parts, int minutes) =>
    PlanItem(
      session: PlanSession(date: date, kind: kind, week: nr, title: title, description: desc, intervals: plan, targetPace: pace),
      rpe: rpe,
      key: true,
      why: why,
      parts: parts,
      minutes: math.min(minutes, math.max(w.maxWeekdayMinutes, 30)),
    );

PlanItem _testRace(PlanWishes w, DateTime date, int nr, double racePace, PlanGoal g) {
  final km = g.meters! >= 21000 ? 10.0 : 5.0;
  return PlanItem(
    session: PlanSession(
      date: date,
      kind: SessionKind.tempo,
      week: nr,
      title: 'Testloop ${_km(km)} km',
      description: 'Een ${_km(km)} km voluit (of een echte loop in de buurt). Zo zie je waar je staat.',
      distanceMeters: km * 1000,
    ),
    rpe: 9,
    key: true,
    why: 'Generale repetitie: tempo, eten en schoenen testen, en je doeltijd bijstellen.',
    parts: ['15 min inlopen + 4 versnellingen.', '${_km(km)} km voluit, de eerste km rustig.', '10 min uitlopen.'],
    minutes: (km * racePace / 60).round() + 25,
  );
}

PlanItem _race(PlanWishes w, DateTime date, int nr, double racePace, int? predicted) {
  final m = w.goal.meters!;
  return PlanItem(
    session: PlanSession(
      date: date,
      kind: SessionKind.race,
      week: nr,
      title: w.raceName == null ? 'Wedstrijd: ${w.goal.label}' : w.raceName!,
      description: 'Doeltempo ${fmtPace(racePace)} /km. Start de eerste kilometer iets rustiger. Succes!',
      distanceMeters: m,
      targetPace: racePace,
    ),
    rpe: 10,
    key: true,
    why: 'Hier heb je voor getraind. Zie het wedstrijdplan.',
    parts: [m >= 21000 ? 'Kort inlopen: 5 min wandelen en dribbelen is genoeg.' : 'Inlopen: 10–15 min rustig en 3 versnellingen.', 'Eerste km iets rustiger dan ${fmtPace(racePace)} /km.', 'Laatste kwart: versnellen als het kan.'],
    minutes: (predicted ?? (m / 1000 * racePace)).round() ~/ 60,
  );
}

void _buildStarter(CustomPlan plan, PlanWishes w, DateTime day0, List<int> days, int longDay) {
  final program = w.goal == PlanGoal.beginnen ? BeginnerProgram.start : BeginnerProgram.comeback;
  final n = w.weeks.clamp(program.minWeeks, program.maxWeeks);
  final sessions = buildBeginnerPlan(program, start: day0, runDays: days, weeks: n);
  for (var i = 0; i < n; i++) {
    final nr = i + 1;
    final ws = DateTime(day0.year, day0.month, day0.day + i * 7);
    final week = PlanWeek(
      number: nr,
      start: ws,
      phase: i < n / 2 ? PlanPhase.start : PlanPhase.opbouw,
      focus: i == 0
          ? 'Wennen. Wandelen hoort erbij; te zwaar? Wandel langer.'
          : i == n - 1
              ? 'De laatste week: je loopt aan één stuk. Trots zijn mag.'
              : 'Elke week iets meer lopen. Niet inhalen als je een keer mist.',
      recovery: false,
    );
    for (final s in sessions.where((s) => s.week == nr)) {
      final total = s.intervals?.steps.fold<int>(0, (a, st) => a + (st.seconds ?? 0)) ?? 30 * 60;
      week.items.add(PlanItem(
        session: s,
        rpe: 4,
        key: false,
        why: w.goal == PlanGoal.terugkomen ? 'Rustig terug: je pezen en botten moeten weer wennen.' : 'Loop-wandelen: zo bouw je veilig op.',
        parts: [s.description],
        minutes: (total / 60).round(),
      ));
    }
    plan.weeks.add(week);
    final runDates = [for (final it in week.items) it.session.date];
    _extras(week, w, ws, runDates, null, week.phase, null);
  }
}

void _extras(PlanWeek week, PlanWishes w, DateTime ws, List<DateTime> runDates, DateTime? longDate, PlanPhase phase, DateTime? race, {DateTime? notBefore}) {
  final free = [
    for (var d = 0; d < 7; d++) DateTime(ws.year, ws.month, ws.day + d),
  ].where((d) => !runDates.contains(d) && (race == null || d.isBefore(race)) && (notBefore == null || !d.isBefore(notBefore))).toList();
  var strength = w.strengthPerWeek.clamp(0, 2);
  if (phase == PlanPhase.afbouw) strength = math.min(strength, 1);
  if (race != null && !race.isAfter(ws.add(const Duration(days: 6)))) strength = 0;
  final krachtDays = <DateTime>[];
  // Kracht liefst niet de dag vóór een sleuteltraining.
  final keyDates = [for (final i in week.items) if (i.key) i.session.date];
  final ordered = [...free]..sort((a, b) {
      int score(DateTime d) => keyDates.any((k) => k.difference(d).inDays == 1) ? 1 : 0;
      return score(a).compareTo(score(b));
    });
  for (final d in ordered) {
    if (krachtDays.length >= strength) break;
    if (krachtDays.any((k) => k.difference(d).inDays.abs() <= 1)) continue;
    krachtDays.add(d);
  }
  final heavy = phase == PlanPhase.opbouw || phase == PlanPhase.piek;
  for (final d in krachtDays) {
    week.extras.add(PlanExtra(
      date: d,
      kind: ExtraKind.kracht,
      title: heavy ? 'Kracht B · 30 min' : 'Kracht A · 25 min',
      description: heavy
          ? 'Bulgaarse split squat 3×8/been · step-ups 3×10/been · enkelbeens kuitheffen 3×12 · hip thrust 3×10 · zijplank 3×30 s/kant'
          : 'Squat 3×10 · lunges 3×8/been · kuitheffen 3×15 · bruggetje 3×12 · plank 3×30 s',
      minutes: heavy ? 30 : 25,
    ));
  }
  final rest = free.where((d) => !krachtDays.contains(d)).toList();
  if (w.cross && rest.isNotEmpty && phase != PlanPhase.afbouw) {
    final d = rest.removeAt(rest.length ~/ 2);
    week.extras.add(PlanExtra(date: d, kind: ExtraKind.cross, title: 'Fietsen of zwemmen · 40 min', description: 'Rustig, zwaarte 3–4. Extra conditie zonder klappen op je benen.', minutes: 40));
  }
  for (final d in rest) {
    week.extras.add(PlanExtra(date: d, kind: ExtraKind.rust, title: 'Rustdag', description: 'Herstel. Wandelen mag.'));
  }
  week.extras.sort((a, b) => a.date.compareTo(b.date));
}

String _focus(PlanPhase phase, bool recovery, bool raceWeek, PlanGoal g, PlanWishes w) {
  if (raceWeek) return 'Wedstrijdweek: weinig doen, veel slapen, koolhydraten de laatste 2 dagen. Niets nieuws proberen.';
  if (recovery) return 'Rustweek: 25% minder, zodat je lichaam de training verwerkt. Hier word je sterker van.';
  return switch (phase) {
    PlanPhase.basis => 'Basis: vooral rustig lopen. Zwaarte 3–4, je kunt praten. Slaap en eet goed.',
    PlanPhase.opbouw => g.isRace ? 'Opbouw: meer kilometers en de eerste stevige trainingen. Ga rustig de lange duurloop in.' : 'Opbouw: elke week iets meer, met één snelle training. Rustig blijft rustig.',
    PlanPhase.piek => 'Piek: de zwaarste weken. Wedstrijdtempo oefenen, ook met eten en drinken. Test je wedstrijdschoenen.',
    PlanPhase.afbouw => 'Afbouw: minder volume, korte snelle stukken houden je scherp. Onrustig gevoel is normaal.',
    PlanPhase.herstel => 'Herstel na de wedstrijd.',
    PlanPhase.start => 'Wennen aan het lopen.',
    PlanPhase.vrij => 'Vrije week.',
  };
}

List<String> _raceDayPlan(PlanWishes w, double racePace, int? predicted) {
  final m = w.goal.meters!;
  final long = m >= 21000;
  return [
    'Dag ervoor: rustig, 20 min dribbelen met 3 versnellingen, of rust. Eet vooral koolhydraten${long ? ' (pasta, rijst, brood)' : ''}, weinig vezels.',
    'Ochtend: ontbijt 2–3 uur voor de start dat je kent, bijvoorbeeld brood met jam of havermout. Koffie mag, als je dat gewend bent.',
    'Meenemen: startnummer en spelden, je bekende schoenen, iets warms voor na de finish${long ? ', gels' : ''}.',
    'Aankomst: 45–60 min voor de start. Toilet, tas, ${long ? '5 min' : '10–15 min'} inlopen.',
    'Indeling: eerste km iets rustiger dan ${fmtPace(racePace)} /km, dan gelijkmatig. Laatste kwart: versnellen als het kan.',
    if (long) 'Onderweg: vanaf 30–45 min elke 30–40 min een gel met water, en drinken bij elke post.',
    if (predicted != null) 'Verwachte tijd op basis van je training: ${fmtTime(predicted)}.',
    'Na de finish: drinken, eten, warm aankleden. De dagen erna rustig (zie herstelweek).',
  ];
}
