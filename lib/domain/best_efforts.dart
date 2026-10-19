import 'run_streams.dart';

/// Afstanden waarop we je snelste stuk binnen een run zoeken.
const bestEffortDistances = <({String label, double meters})>[
  (label: '400 m', meters: 400),
  (label: '1 km', meters: 1000),
  (label: '1 mijl', meters: 1609.34),
  (label: '5 km', meters: 5000),
  (label: '10 km', meters: 10000),
  (label: 'Halve marathon', meters: 21097.5),
  (label: 'Marathon', meters: 42195),
];

/// Je snelste stuk van een bepaalde afstand binnen één run (ook midden in een langere run).
class BestEffort {
  const BestEffort({required this.label, required this.meters, required this.seconds, required this.startMeters});
  final String label;
  final double meters;
  final double seconds;

  /// Waar in de run het snelste stuk begon.
  final double startMeters;

  double get paceSecPerKm => seconds / (meters / 1000);
}

/// Tijd op afstand [m] (lineair tussen de meetpunten), vanaf index [from] zoekend.
double _timeAt(RunStreams s, double m, int from) {
  var i = from;
  while (i < s.length - 1 && s.distance[i + 1] < m) {
    i++;
  }
  if (i >= s.length - 1) return s.time.last;
  final d0 = s.distance[i], d1 = s.distance[i + 1];
  final f = d1 - d0 <= 0 ? 0.0 : ((m - d0) / (d1 - d0)).clamp(0.0, 1.0);
  return s.time[i] + (s.time[i + 1] - s.time[i]) * f;
}

/// Snelste stukken voor alle afstanden die in de run passen.
List<BestEffort> bestEfforts(RunStreams s) {
  final total = s.totalDistance;
  final out = <BestEffort>[];
  for (final e in bestEffortDistances) {
    if (total < e.meters) continue;
    var best = double.infinity, bestStart = 0.0;
    var j = 0;
    for (var i = 0; i < s.length; i++) {
      final start = s.distance[i];
      final end = start + e.meters;
      if (end > total) break;
      while (j < s.length - 1 && s.distance[j + 1] < end) {
        j++;
      }
      final t = _timeAt(s, end, j) - s.time[i];
      if (t > 0 && t < best) {
        best = t;
        bestStart = start;
      }
    }
    // Onrealistisch snel (GPS-sprong): overslaan. Sneller dan 2:30/km houden we niet voor waar.
    if (best.isFinite && best / (e.meters / 1000) >= 150) {
      out.add(BestEffort(label: e.label, meters: e.meters, seconds: best, startMeters: bestStart));
    }
  }
  return out;
}

/// Opslaan als {"1000": 245.3, ...}.
Map<String, double> bestEffortsToJson(List<BestEffort> list) => {
      for (final b in list) b.meters.round().toString(): double.parse(b.seconds.toStringAsFixed(1)),
    };

/// Snelste tijden over al je runs heen, per afstand: (seconden, activity-id).
Map<int, ({double seconds, String activityId})> bestOverall(Iterable<({String id, Map<String, double> efforts})> runs) {
  final out = <int, ({double seconds, String activityId})>{};
  for (final r in runs) {
    r.efforts.forEach((k, v) {
      final m = int.tryParse(k);
      if (m == null || v <= 0) return;
      final cur = out[m];
      if (cur == null || v < cur.seconds) out[m] = (seconds: v, activityId: r.id);
    });
  }
  return out;
}

String bestEffortLabel(int meters) =>
    bestEffortDistances.where((e) => e.meters.round() == meters).map((e) => e.label).firstOrNull ?? '$meters m';
