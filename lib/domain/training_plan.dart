import 'dart:math' as math;

import 'intervals.dart';

enum SessionKind {
  easy('Rustige duurloop'),
  long('Lange duurloop'),
  tempo('Tempoloop'),
  interval('Intervallen'),
  race('Wedstrijd');

  const SessionKind(this.label);
  final String label;
}

/// Eén training in het schema.
class PlanSession {
  const PlanSession({
    required this.date,
    required this.kind,
    required this.title,
    required this.description,
    this.distanceMeters,
    this.targetPace,
    this.intervals,
    this.week = 0,
  });

  final DateTime date;
  final SessionKind kind;
  final String title;
  final String description;
  final double? distanceMeters;

  /// Doeltempo (s/km) voor de coach tijdens het lopen.
  final double? targetPace;
  final IntervalPlan? intervals;

  /// Week in het schema (1 = eerste).
  final int week;

  PlanSession copyWith({DateTime? date}) => PlanSession(
        date: date ?? this.date,
        kind: kind,
        title: title,
        description: description,
        distanceMeters: distanceMeters,
        targetPace: targetPace,
        intervals: intervals,
        week: week,
      );

  /// Zware training (lang, tempo, intervallen, wedstrijd): niet twee dagen achter elkaar.
  bool get isKey => kind != SessionKind.easy;

  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId,
        'session_date': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'kind': kind.name,
        'title': title,
        'description': description,
        'distance_meters': distanceMeters?.round(),
        'target_pace': targetPace?.round(),
        'intervals': intervals?.toJson(),
        'week': week,
      };

  static PlanSession? fromRow(Map<String, dynamic> j) {
    final kind = SessionKind.values.where((k) => k.name == j['kind']).firstOrNull;
    final date = DateTime.tryParse(j['session_date'] as String? ?? '');
    if (kind == null || date == null) return null;
    return PlanSession(
      date: DateTime(date.year, date.month, date.day),
      kind: kind,
      title: j['title'] as String? ?? kind.label,
      description: j['description'] as String? ?? '',
      distanceMeters: (j['distance_meters'] as num?)?.toDouble(),
      targetPace: (j['target_pace'] as num?)?.toDouble(),
      intervals: IntervalPlan.fromJson(j['intervals']),
      week: (j['week'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Instellingen voor het schema.
class PlanSetup {
  const PlanSetup({
    required this.goalMeters,
    required this.raceDate,
    required this.runDays,
    required this.longRunDay,
    required this.currentWeeklyKm,
    required this.thresholdPace,
    this.goalTimeSeconds,
  });

  /// 5000, 10000, 21097 of 42195.
  final double goalMeters;
  final DateTime raceDate;

  /// Weekdagen (1 = maandag ... 7 = zondag) waarop je wilt lopen.
  final List<int> runDays;
  final int longRunDay;
  final double currentWeeklyKm;

  /// Drempeltempo (s/km), uit je runs geschat.
  final double thresholdPace;
  final int? goalTimeSeconds;

  PlanSetup copyWith({double? thresholdPace, double? currentWeeklyKm}) => PlanSetup(
        goalMeters: goalMeters,
        raceDate: raceDate,
        runDays: runDays,
        longRunDay: longRunDay,
        currentWeeklyKm: currentWeeklyKm ?? this.currentWeeklyKm,
        thresholdPace: thresholdPace ?? this.thresholdPace,
        goalTimeSeconds: goalTimeSeconds,
      );

  Map<String, dynamic> toJson() => {
        'g': goalMeters,
        'd': raceDate.toIso8601String(),
        'days': runDays,
        'long': longRunDay,
        'km': currentWeeklyKm,
        't': thresholdPace,
        if (goalTimeSeconds != null) 'goal': goalTimeSeconds,
      };

  static PlanSetup? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return PlanSetup(
        goalMeters: (j['g'] as num).toDouble(),
        raceDate: DateTime.parse(j['d'] as String),
        runDays: [for (final d in j['days'] as List) (d as num).toInt()],
        longRunDay: (j['long'] as num).toInt(),
        currentWeeklyKm: (j['km'] as num).toDouble(),
        thresholdPace: (j['t'] as num).toDouble(),
        goalTimeSeconds: (j['goal'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

String _pace(double s) {
  final t = s.round();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

String _km(double m) => (m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1).replaceAll('.', ',');

double _roundKm(double km) => math.max(3, (km * 2).round() / 2);

/// Maakt een schema tot en met de wedstrijddag, beginnend op [start].
List<PlanSession> buildPlan(PlanSetup s, DateTime start) {
  final day0 = DateTime(start.year, start.month, start.day);
  final race = DateTime(s.raceDate.year, s.raceDate.month, s.raceDate.day);
  final totalDays = race.difference(day0).inDays;
  if (totalDays < 7 || s.runDays.isEmpty) return const [];
  final weeks = (totalDays / 7).ceil();
  final g = s.goalMeters;
  final peakKm = g <= 5000 ? 35.0 : g <= 10000 ? 45.0 : g <= 21100 ? 55.0 : 70.0;
  final longCap = g <= 5000 ? 12.0 : g <= 10000 ? 16.0 : g <= 21100 ? 21.0 : 32.0;
  final minStart = g <= 10000 ? 12.0 : g <= 21100 ? 18.0 : 25.0;
  var volume = math.max(s.currentWeeklyKm, minStart);
  final peak = math.max(peakKm * math.min(1.0, s.runDays.length / 4), volume);

  final goalPace = s.goalTimeSeconds == null ? null : s.goalTimeSeconds! / (g / 1000);
  final t = s.thresholdPace;
  final easyPace = t * 1.25, longPace = t * 1.2, tempoPace = t;
  final intervalPace = goalPace != null && g <= 10000 ? goalPace * 0.97 : t * 0.93;

  final days = [...s.runDays]..sort();
  final out = <PlanSession>[];
  for (var w = 0; w < weeks; w++) {
    final weeksLeft = weeks - w;
    final recovery = (w + 1) % 4 == 0 && weeksLeft > 2;
    double weekKm;
    if (weeksLeft == 1) {
      weekKm = volume * 0.5;
    } else if (weeksLeft == 2) {
      weekKm = volume * 0.7;
    } else if (recovery) {
      weekKm = volume * 0.8;
    } else {
      volume = math.min(peak, w == 0 ? volume : volume * 1.08);
      weekKm = volume;
    }
    final phase = w < weeks * 0.4 ? 'basis' : (weeksLeft <= 2 ? 'taper' : 'opbouw');
    final longKm = math.min(longCap, weekKm * (days.length <= 2 ? 0.5 : 0.32));
    final qualityDays = days.where((d) => d != s.longRunDay).toList();
    final nQuality = days.length >= 5 ? 2 : (days.length >= 2 ? 1 : 0);
    // Kwaliteit niet op de dag na de lange duurloop.
    qualityDays.sort((a, b) => ((a - s.longRunDay) % 7 == 1 ? 1 : 0).compareTo((b - s.longRunDay) % 7 == 1 ? 1 : 0));
    final quality = qualityDays.take(nQuality).toSet();
    final easyCount = days.length - 1 - quality.length - (days.contains(s.longRunDay) ? 0 : -1);
    final qualityKm = quality.length * math.min(10.0, weekKm * 0.2);
    final easyKm = easyCount <= 0 ? 0.0 : math.max(3.0, (weekKm - longKm - qualityKm) / easyCount);

    for (final d in days) {
      final date = DateTime(day0.year, day0.month, day0.day + w * 7 + ((d - day0.weekday) % 7));
      if (date.isBefore(day0) || date.isAfter(race)) continue;
      if (date == race) continue;
      final isLong = d == s.longRunDay && weeksLeft > 1;
      if (isLong) {
        final km = _roundKm(longKm);
        out.add(PlanSession(
          date: date,
          kind: SessionKind.long,
          week: w + 1,
          title: 'Lange duurloop ${_km(km * 1000)} km',
          description: 'Rustig en ontspannen, rond ${_pace(longPace)} /km. Je moet kunnen praten. '
              '${phase == 'opbouw' && g > 10000 ? 'Loop de laatste 2 km iets sneller als het goed voelt.' : ''}'.trim(),
          distanceMeters: km * 1000,
          targetPace: longPace,
        ));
      } else if (quality.contains(d) && !(weeksLeft == 1 && date.difference(race).inDays.abs() <= 2)) {
        final useIntervals = (w + quality.toList().indexOf(d)) % 2 == 0 || phase == 'taper';
        if (useIntervals) {
          final plan = phase == 'basis'
              ? IntervalPlan.build(reps: 8, workSeconds: 60, restSeconds: 60, warmupMin: 10, cooldownMin: 5)
              : g <= 5000
                  ? IntervalPlan.build(reps: weeksLeft <= 2 ? 4 : 6, workMeters: 400, restSeconds: 90)
                  : g <= 10000
                      ? IntervalPlan.build(reps: weeksLeft <= 2 ? 3 : 5, workMeters: 1000, restSeconds: 120)
                      : IntervalPlan.build(reps: weeksLeft <= 2 ? 2 : 4, workSeconds: 360, restSeconds: 120);
          out.add(PlanSession(
            date: date,
            kind: SessionKind.interval,
            week: w + 1,
            title: 'Intervallen: ${plan.name}',
            description: 'Snelle stukken rond ${_pace(intervalPace)} /km, herstel rustig dribbelend. '
                'Met 10 minuten inlopen en 5 minuten uitlopen. De stem in de app begeleidt je.',
            intervals: plan,
          ));
        } else {
          final minutes = phase == 'basis' ? 15 : (weeksLeft <= 2 ? 15 : (g <= 10000 ? 20 : 30));
          out.add(PlanSession(
            date: date,
            kind: SessionKind.tempo,
            week: w + 1,
            title: 'Tempoloop $minutes min',
            description: '10 minuten inlopen, dan $minutes minuten "comfortabel zwaar" rond ${_pace(tempoPace)} /km, '
                'daarna 5 minuten uitlopen.',
            targetPace: tempoPace,
            intervals: IntervalPlan('Tempoloop $minutes min', [
              const IntervalStep(StepKind.warmup, seconds: 600),
              IntervalStep(StepKind.work, seconds: minutes * 60),
              const IntervalStep(StepKind.cooldown, seconds: 300),
            ]),
          ));
        }
      } else {
        final km = _roundKm(weeksLeft == 1 ? math.min(easyKm, 6) : easyKm);
        out.add(PlanSession(
          date: date,
          kind: SessionKind.easy,
          week: w + 1,
          title: 'Rustig ${_km(km * 1000)} km',
          description: 'Ontspannen tempo, rond ${_pace(easyPace)} /km. Dit is waar je conditie groeit.',
          distanceMeters: km * 1000,
          targetPace: easyPace,
        ));
      }
    }
  }
  out.add(PlanSession(
    date: race,
    kind: SessionKind.race,
    week: weeks,
    title: 'Wedstrijd: ${_km(g)} km',
    description: goalPace == null
        ? 'Start rustig, vind je ritme en versnel in het laatste deel als het goed voelt. Succes!'
        : 'Je doeltempo is ${_pace(goalPace)} /km. Start de eerste kilometer iets rustiger. Succes!',
    distanceMeters: g,
    targetPace: goalPace,
  ));
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// Is een training gedaan? Een run op die dag van minstens 60% van de afstand (of 20 minuten).
bool sessionDone(PlanSession s, Iterable<({DateTime start, double meters, int seconds})> runs) {
  for (final r in runs) {
    final t = r.start.toLocal();
    if (t.year != s.date.year || t.month != s.date.month || t.day != s.date.day) continue;
    final need = s.distanceMeters;
    if (need == null ? r.seconds >= 1200 : r.meters >= need * 0.6) return true;
  }
  return false;
}

/// Herstel na je laatste runs: hoeveel uur nog (0 = hersteld).
/// Grofweg 0,45 uur per belastingspunt, verminderd met de tijd die al voorbij is.
double recoveryHours(Iterable<({DateTime end, double load})> runs, DateTime now) {
  var left = 0.0;
  for (final r in runs) {
    final since = now.difference(r.end).inMinutes / 60;
    if (since < 0) continue;
    left = math.max(left, r.load * 0.45 - since);
  }
  return math.max(0, left);
}
