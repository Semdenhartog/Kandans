import 'dart:math' as math;

import '../data/models/models.dart';

/// Belasting van één run (vergelijkbaar met "TSS": 100 = een uur op je drempeltempo).
/// Met hartslag (als je maximale hartslag bekend is) op basis van TRIMP, anders op tempo.
double runLoad(Activity a, {required double thresholdPace, int? maxHr, int restHr = 60}) {
  final hours = a.movingTimeSeconds / 3600;
  if (hours <= 0) return 0;
  final hr = a.averageHeartRate;
  if (hr != null && maxHr != null && maxHr > restHr + 20 && hr > restHr) {
    final hrr = ((hr - restHr) / (maxHr - restHr)).clamp(0.0, 1.0);
    // TRIMP (Banister), geschaald zodat een uur op ~88% hartslagreserve rond de 100 uitkomt.
    final trimp = a.movingTimeSeconds / 60 * hrr * 0.64 * math.exp(1.92 * hrr);
    return trimp / 1.6;
  }
  final pace = a.paceSecondsPerKm;
  if (pace <= 0 || thresholdPace <= 0) return hours * 50;
  final intensity = (thresholdPace / pace).clamp(0.5, 1.2);
  return hours * intensity * intensity * 100;
}

/// Drempeltempo schatten: iets langzamer dan het tempo van je snelste runs van 20–60 minuten.
double estimateThresholdPace(List<Activity> runs) {
  final cands = [
    for (final a in runs)
      if (a.movingTimeSeconds >= 1200 && a.movingTimeSeconds <= 3600 && a.paceSecondsPerKm > 150) a.paceSecondsPerKm,
  ]..sort();
  if (cands.isEmpty) return 330;
  final top = cands.take(math.max(1, (cands.length * 0.2).ceil())).toList();
  final avg = top.reduce((x, y) => x + y) / top.length;
  return avg * 1.03;
}

class FitnessDay {
  const FitnessDay(this.day, this.load, this.fitness, this.fatigue);
  final DateTime day;
  final double load;

  /// Fitheid: gemiddelde belasting van de laatste ~6 weken.
  final double fitness;

  /// Vermoeidheid: gemiddelde belasting van de laatste week.
  final double fatigue;

  /// Vorm: fitheid min vermoeidheid. Positief = fris, negatief = moe.
  double get form => fitness - fatigue;
}

/// Fitheid, vermoeidheid en vorm per dag (zoals Strava's Fitness & Freshness).
List<FitnessDay> fitnessSeries(List<Activity> runs, DateTime today, {int days = 90, int? maxHr}) {
  final threshold = estimateThresholdPace(runs);
  final end = DateTime(today.year, today.month, today.day);
  // Opwarmen: 120 dagen ervoor meenemen zodat de lijnen kloppen.
  final start = end.subtract(Duration(days: days + 120));
  final perDay = <DateTime, double>{};
  for (final a in runs) {
    final t = a.startedAt.toLocal();
    final d = DateTime(t.year, t.month, t.day);
    if (d.isBefore(start) || d.isAfter(end)) continue;
    perDay[d] = (perDay[d] ?? 0) + runLoad(a, thresholdPace: threshold, maxHr: maxHr);
  }
  const kFit = 42.0, kFat = 7.0;
  var fit = 0.0, fat = 0.0;
  final out = <FitnessDay>[];
  for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    final load = perDay[d] ?? 0;
    fit += (load - fit) / kFit;
    fat += (load - fat) / kFat;
    if (!d.isBefore(end.subtract(Duration(days: days - 1)))) out.add(FitnessDay(d, load, fit, fat));
  }
  return out;
}

/// Korte uitleg bij je vorm.
({String title, String text}) formAdvice(FitnessDay d) {
  final f = d.form;
  if (d.fitness < 5) {
    return (title: 'Opbouwen', text: 'Er zijn nog weinig runs. Loop een paar weken regelmatig, dan krijg je hier een goed beeld.');
  }
  if (f > 15) return (title: 'Uitgerust', text: 'Je bent fris. Goed moment voor een wedstrijd of een stevige training.');
  if (f > 0) return (title: 'Fris', text: 'Je belasting en herstel zijn in balans. Je kunt rustig opbouwen.');
  if (f > -15) return (title: 'Productief', text: 'Je traint goed door; een beetje moe is normaal. Plan genoeg rustige runs.');
  if (f > -30) {
    return (title: 'Vermoeid', text: 'Je hebt de laatste week veel gedaan. Neem een rustdag of een paar rustige runs.');
  }
  return (title: 'Overbelast', text: 'Veel meer gelopen dan je gewend bent. Pas op voor blessures en neem echt rust.');
}

/// Verdeling rustig/stevig (de 80/20-regel: zo'n 80% van je tijd rustig, 20% stevig).
class IntensityBalance {
  const IntensityBalance(this.easySeconds, this.hardSeconds);
  final double easySeconds;
  final double hardSeconds;
  double get easyShare => easySeconds + hardSeconds <= 0 ? 0 : easySeconds / (easySeconds + hardSeconds);

  String get advice {
    final p = (easyShare * 100).round();
    if (easyShare >= 0.75) return '$p% rustig: precies goed. Rustige kilometers bouwen je conditie, de stevige maken je snel.';
    if (easyShare >= 0.6) return '$p% rustig: net iets te veel stevig. Loop je rustige runs echt rustig (je moet kunnen praten).';
    return 'Maar $p% rustig: je loopt bijna alles stevig. Dat geeft meer kans op blessures en minder vooruitgang. Maak de meeste runs rustiger.';
  }
}

/// Over de laatste [days] dagen; null als er te weinig is gelopen (minder dan een half uur).
IntensityBalance? intensityBalance(List<Activity> runs, {required DateTime now, int days = 28, int? maxHr}) {
  final threshold = estimateThresholdPace(runs);
  var easy = 0.0, hard = 0.0;
  for (final a in runs) {
    final age = now.difference(a.startedAt);
    if (age.isNegative || age.inDays >= days) continue;
    final hr = a.averageHeartRate;
    final isEasy = hr != null && maxHr != null ? hr < maxHr * 0.8 : a.paceSecondsPerKm >= threshold * 1.12;
    if (isEasy) {
      easy += a.movingTimeSeconds;
    } else {
      hard += a.movingTimeSeconds;
    }
  }
  if (easy + hard < 1800) return null;
  return IntensityBalance(easy, hard);
}
