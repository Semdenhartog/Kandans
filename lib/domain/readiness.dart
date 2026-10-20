import 'dart:math' as math;

import '../data/models/models.dart';
import 'best_efforts.dart';
import 'intervals.dart';
import 'training_plan.dart';

/// Gegevens uit Health Connect (horloge of ring) voor je klaar-score. Alles mag ontbreken.
class BodySignals {
  const BodySignals({
    this.sleepHours,
    this.sleepAvgHours,
    this.restingHr,
    this.restingHrBaseline,
    this.hrv,
    this.hrvBaseline,
  });

  final double? sleepHours;
  final double? sleepAvgHours;
  final double? restingHr;
  final double? restingHrBaseline;
  final double? hrv;
  final double? hrvBaseline;

  bool get isEmpty => sleepHours == null && restingHr == null && hrv == null;
}

class ReadinessFactor {
  const ReadinessFactor(this.label, this.text, this.effect);
  final String label;
  final String text;

  /// Punten erbij (+) of eraf (-).
  final int effect;
}

class Readiness {
  const Readiness(this.score, this.factors);
  final int score;
  final List<ReadinessFactor> factors;

  String get title => score >= 75
      ? 'Klaar voor een stevige training'
      : score >= 50
          ? 'Prima voor een normale training'
          : score >= 30
              ? 'Houd het rustig vandaag'
              : 'Rust is vandaag beter';

  bool get suggestEasy => score < 50;
}

/// Klaar-score 1–100 (zoals Garmin Training Readiness of Polar Nightly Recharge):
/// slaap, rusthartslag en HRV ten opzichte van jouw normaal, plus herstel na je laatste runs.
Readiness readiness({BodySignals body = const BodySignals(), double recoveryHours = 0, double? form}) {
  var score = 70.0;
  final f = <ReadinessFactor>[];
  void add(String label, String text, double pts) {
    final p = pts.round();
    score += p;
    f.add(ReadinessFactor(label, text, p));
  }

  final sleep = body.sleepHours;
  if (sleep != null) {
    final ref = body.sleepAvgHours ?? 7.5;
    final d = sleep - math.max(7, ref);
    final pts = (d * 8).clamp(-20.0, 8.0);
    add('Slaap', '${sleep.toStringAsFixed(1).replaceAll('.', ',')} uur${d < -0.5 ? ', minder dan je nodig hebt' : (d > 0.5 ? ', goed uitgerust' : '')}', pts);
  }
  final rhr = body.restingHr, rhrBase = body.restingHrBaseline;
  if (rhr != null && rhrBase != null) {
    final d = rhr - rhrBase;
    final pts = (-d * 3).clamp(-15.0, 6.0);
    add('Rusthartslag', '${rhr.round()} (normaal ${rhrBase.round()})${d >= 4 ? ' – verhoogd, mogelijk vermoeid of ziek' : ''}', pts);
  }
  final hrv = body.hrv, hrvBase = body.hrvBaseline;
  if (hrv != null && hrvBase != null && hrvBase > 0) {
    final r = hrv / hrvBase - 1;
    final pts = (r * 60).clamp(-15.0, 8.0);
    add('HRV', '${hrv.round()} ms (normaal ${hrvBase.round()})${r < -0.15 ? ' – lager dan normaal' : ''}', pts);
  }
  if (recoveryHours >= 1) {
    add('Herstel', 'nog ${recoveryHours.round()} uur herstel na je laatste runs', -math.min(25.0, recoveryHours * 0.6));
  } else {
    add('Herstel', 'hersteld van je laatste runs', 5);
  }
  if (form != null) {
    if (form < -25) add('Belasting', 'je hebt de laatste week veel gelopen', -10);
    if (form > 10) add('Belasting', 'je bent fris', 4);
  }
  return Readiness(score.round().clamp(1, 100), f);
}

/// Lichtere versie van een training ("ik voel me niet 100%").
PlanSession easierSession(PlanSession s, {double factor = 0.7}) {
  final ip = s.intervals;
  if (ip != null && ip.walkRun) {
    // Lopen/wandelen: kortere loopstukken, zelfde opbouw.
    final steps = [
      for (final st in ip.steps)
        st.kind == StepKind.work && st.seconds != null
            ? IntervalStep(StepKind.work, seconds: math.max(60, (st.seconds! * factor / 30).round() * 30))
            : st,
    ];
    return PlanSession(
      date: s.date,
      kind: s.kind,
      week: s.week,
      title: '${s.title} (aangepast)',
      description: 'Lichtere versie: kortere stukken hardlopen, verder hetzelfde. Wandelen mag altijd. Voel je je ziek: sla hem over.',
      intervals: IntervalPlan('${ip.name} (lichter)', steps, walkRun: true),
    );
  }
  final km = math.max(3.0, ((s.distanceMeters ?? 5000) / 1000 * factor * 2).round() / 2);
  return PlanSession(
    date: s.date,
    kind: SessionKind.easy,
    week: s.week,
    title: 'Rustig ${km.toStringAsFixed(km % 1 == 0 ? 0 : 1).replaceAll('.', ',')} km (aangepast)',
    description: 'Lichtere versie van "${s.title}". Rustig tempo, alleen als het goed voelt. Voel je je ziek: sla hem over.',
    distanceMeters: km * 1000,
    targetPace: s.targetPace == null ? null : s.targetPace! * (s.kind == SessionKind.easy || s.kind == SessionKind.long ? 1.03 : 1.25),
  );
}

/// Tempo aanpassen voor warmte (zoals Runna's "Adapt for Heat"): ongeveer 0,35% trager per graad boven 15 °C
/// gevoelstemperatuur, en 0,15% per procent luchtvochtigheid boven 70% bij warmte.
double heatAdjustedPace(double pace, {required double feelsLike, double? humidity}) {
  if (feelsLike <= 15) return pace;
  var f = 1 + (feelsLike - 15) * 0.0035;
  if (humidity != null && humidity > 70 && feelsLike > 20) f += (humidity - 70) * 0.0015;
  return pace * f;
}

/// Nieuw drempeltempo uit je recente prestaties (pace-recalibratie zoals Runna).
/// Gebruikt je snelste 5 km / 10 km van de laatste 6 weken als die er zijn, anders je runs.
double recalibratedThreshold(List<Activity> runs, DateTime now, {required double fallback}) {
  final recent = runs.where((a) => now.difference(a.startedAt).inDays <= 42).toList();
  final efforts = bestOverall([
    for (final a in recent)
      if (a.id != null && a.bestEfforts != null) (id: a.id!, efforts: a.bestEfforts!),
  ]);
  final cands = <double>[
    if (efforts[5000] != null) efforts[5000]!.seconds / 5 * 1.04,
    if (efforts[10000] != null) efforts[10000]!.seconds / 10 * 1.01,
  ];
  if (cands.isEmpty) return fallback;
  return cands.reduce(math.min);
}

/// Schema vanaf vandaag opnieuw opbouwen met nieuwe tempo's; gedane trainingen blijven staan.
List<PlanSession> recalibratePlan(List<PlanSession> current, PlanSetup setup, DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  final past = current.where((s) => s.date.isBefore(day)).toList();
  final future = buildPlan(setup, day);
  // Weeknummers laten doorlopen.
  final base = past.isEmpty ? 0 : past.last.week;
  return [
    ...past,
    for (final s in future)
      PlanSession(
        date: s.date,
        kind: s.kind,
        title: s.title,
        description: s.description,
        distanceMeters: s.distanceMeters,
        targetPace: s.targetPace,
        intervals: s.intervals,
        week: base + s.week,
      ),
  ];
}
