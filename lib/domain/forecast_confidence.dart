/// "Hoe zeker is dit moment?" – vergelijkt de tientallen varianten van een weermodel (ensemble).
///
/// Zijn bijna alle varianten het eens (droog, of juist nat), dan is het moment zeker.
/// Lopen ze uiteen, dan kan het nog omslaan en is het slim om later nog even te kijken.
library;

/// Eén uur uit het ensemble: per variant de neerslag (mm) en temperatuur (°C).
class EnsembleHour {
  const EnsembleHour(this.time, this.precip, this.temp);
  final DateTime time;
  final List<double> precip;
  final List<double> temp;
}

enum ConfidenceLevel { sure, likely, shaky }

class ForecastConfidence {
  const ForecastConfidence({
    required this.level,
    required this.wetShare,
    required this.tempSpread,
    required this.members,
    this.recheckAt,
  });

  final ConfidenceLevel level;

  /// Aandeel varianten met regen tijdens de run (0–1).
  final double wetShare;

  /// Verschil tussen de warmste en koudste varianten (10e–90e percentiel), °C.
  final double tempSpread;
  final int members;

  /// Wanneer het slim is om nog even te kijken (alleen bij twijfel).
  final DateTime? recheckAt;

  bool get mostlyDry => wetShare < 0.5;
}

/// Vanaf deze hoeveelheid (mm per uur) telt een variant als "nat".
const double wetMm = 0.2;

ForecastConfidence? confidenceFor(List<EnsembleHour> hours, DateTime start, int minutes, {DateTime? now}) {
  final end = start.add(Duration(minutes: minutes));
  final hourStart = DateTime(start.year, start.month, start.day, start.hour);
  final inRun = [
    for (final h in hours)
      if (!h.time.isBefore(hourStart) && h.time.isBefore(end)) h,
  ];
  if (inRun.isEmpty) return null;
  final n = inRun.map((h) => h.precip.length).reduce((a, b) => a < b ? a : b);
  if (n < 3) return null;

  var wet = 0;
  for (var m = 0; m < n; m++) {
    if (inRun.any((h) => h.precip[m] >= wetMm)) wet++;
  }
  final wetShare = wet / n;

  final temps = [...inRun.first.temp]..sort();
  final spread = temps.isEmpty ? 0.0 : _pct(temps, 0.9) - _pct(temps, 0.1);

  final agree = wetShare > 0.5 ? wetShare : 1 - wetShare;
  ConfidenceLevel level;
  if (agree >= 0.85 && spread <= 4) {
    level = ConfidenceLevel.sure;
  } else if (agree >= 0.65) {
    level = ConfidenceLevel.likely;
  } else {
    level = ConfidenceLevel.shaky;
  }

  DateTime? recheck;
  if (level != ConfidenceLevel.sure) {
    final t = start.subtract(const Duration(minutes: 90));
    final cur = now ?? DateTime.now();
    if (t.isAfter(cur.add(const Duration(minutes: 20)))) {
      // Afronden op een heel of half uur, dat leest prettiger.
      recheck = DateTime(t.year, t.month, t.day, t.hour, t.minute < 30 ? 0 : 30);
    }
  }
  return ForecastConfidence(level: level, wetShare: wetShare, tempSpread: spread, members: n, recheckAt: recheck);
}

double _pct(List<double> sorted, double p) {
  final i = ((sorted.length - 1) * p).round();
  return sorted[i];
}

/// Leest het antwoord van ensemble-api.open-meteo.com (hourly met *_memberNN-sleutels).
List<EnsembleHour> parseEnsemble(Map<String, dynamic> json) {
  final hourly = json['hourly'] as Map<String, dynamic>?;
  if (hourly == null) return const [];
  final times = (hourly['time'] as List).cast<String>();
  List<List<double?>> series(String name) => [
        for (final e in hourly.entries)
          if (e.key == name || e.key.startsWith('${name}_member'))
            [for (final v in e.value as List) (v as num?)?.toDouble()],
      ];
  final p = series('precipitation');
  final t = series('temperature_2m');
  return [
    for (var i = 0; i < times.length; i++)
      EnsembleHour(
        DateTime.parse(times[i]),
        [for (final s in p) if (s[i] != null) s[i]!],
        [for (final s in t) if (s[i] != null) s[i]!],
      ),
  ];
}

// ---------------------------------------------------------------------------
// Klopte de voorspelling?
// ---------------------------------------------------------------------------

/// Wat Kadans voorspelde voor het beste moment van een dag.
class ForecastSnapshot {
  const ForecastSnapshot({
    required this.time,
    required this.lat,
    required this.lon,
    required this.temp,
    required this.rainChance,
    required this.rainMm,
    required this.wind,
    this.ok,
  });

  final DateTime time;
  final double lat, lon, temp, rainChance, rainMm, wind;

  /// null = nog niet gecontroleerd.
  final bool? ok;

  bool get predictedDry => rainChance < 40 && rainMm < 0.3;

  ForecastSnapshot withResult(bool v) => ForecastSnapshot(
      time: time, lat: lat, lon: lon, temp: temp, rainChance: rainChance, rainMm: rainMm, wind: wind, ok: v);

  Map<String, dynamic> toJson() => {
        't': time.toIso8601String(),
        'la': lat,
        'lo': lon,
        'T': temp,
        'p': rainChance,
        'mm': rainMm,
        'w': wind,
        if (ok != null) 'ok': ok,
      };

  static ForecastSnapshot? fromJson(Map<String, dynamic> j) {
    final t = DateTime.tryParse(j['t'] as String? ?? '');
    if (t == null) return null;
    double d(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return ForecastSnapshot(
        time: t, lat: d('la'), lon: d('lo'), temp: d('T'), rainChance: d('p'), rainMm: d('mm'), wind: d('w'), ok: j['ok'] as bool?);
  }
}

/// Klopte het? Droog/nat goed voorspeld én temperatuur binnen 2,5 graad.
/// Bij een uur met regen telt elke druppel (≥ 0,3 mm) als nat.
bool forecastWasRight(ForecastSnapshot s, {required double actualTemp, required double actualMm}) {
  final actualDry = actualMm < 0.3;
  return s.predictedDry == actualDry && (actualTemp - s.temp).abs() <= 2.5;
}

/// (goed, totaal) over de gecontroleerde momenten in de afgelopen [days] dagen.
(int, int) forecastScore(Iterable<ForecastSnapshot> all, {int days = 30, DateTime? now}) {
  final from = (now ?? DateTime.now()).subtract(Duration(days: days));
  var hit = 0, total = 0;
  for (final s in all) {
    if (s.ok == null || s.time.isBefore(from)) continue;
    total++;
    if (s.ok!) hit++;
  }
  return (hit, total);
}
