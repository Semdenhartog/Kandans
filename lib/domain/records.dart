import '../data/models/models.dart';
import 'weather_correction.dart';

/// Zelfde run? Op id als die er is, anders hetzelfde object.
bool sameRun(Activity a, Activity b) => a.id != null && b.id != null ? a.id == b.id : identical(a, b);

/// Een afstand waarop we records bijhouden.
class RecordDistance {
  const RecordDistance(this.label, this.meters);
  final String label;
  final double meters;

  /// Runs tussen 98% en 108% van de afstand tellen mee; de tijd wordt
  /// omgerekend naar de precieze afstand.
  bool fits(double distance) => distance >= meters * 0.98 && distance <= meters * 1.08;
}

const recordDistances = [
  RecordDistance('5 km', 5000),
  RecordDistance('10 km', 10000),
  RecordDistance('15 km', 15000),
  RecordDistance('Halve marathon', 21097.5),
  RecordDistance('Marathon', 42195),
];

/// Beste tijd op één afstand: echt gelopen en gecorrigeerd voor het weer.
class DistanceRecord {
  const DistanceRecord({
    required this.distance,
    required this.best,
    required this.bestSeconds,
    required this.bestWeather,
    required this.bestWeatherSeconds,
    required this.count,
  });

  final RecordDistance distance;

  /// Snelste echte tijd.
  final Activity best;
  final int bestSeconds;

  /// Snelste tijd als het weer ideaal was geweest.
  final Activity bestWeather;
  final int bestWeatherSeconds;

  /// Aantal runs op deze afstand.
  final int count;

  /// Was je weer-record een andere run dan je echte record?
  bool get weatherRecordDiffers => !sameRun(best, bestWeather);
}

/// Alle records, plus je langste run.
class Records {
  const Records({required this.distances, this.longest});
  final List<DistanceRecord> distances;
  final Activity? longest;

  bool get isEmpty => distances.isEmpty && longest == null;

  /// Welke records deze run heeft (bijv. "PR 10 km", "Weer-PR 5 km").
  List<String> badgesFor(Activity a) => [
        for (final r in distances) ...[
          if (sameRun(r.best, a)) 'PR ${r.distance.label}',
          if (sameRun(r.bestWeather, a) && !sameRun(r.best, a)) 'Weer-PR ${r.distance.label}',
        ],
        if (longest != null && sameRun(longest!, a) && a.distanceMeters >= 5000) 'Langste run',
      ];
}

/// Tijd omgerekend naar precies [meters] (zelfde tempo).
int scaledSeconds(int seconds, double distance, double meters) => (seconds * meters / distance).round();

bool _plausible(Activity a) =>
    a.distanceMeters >= 1000 && a.paceSecondsPerKm >= 150 && a.paceSecondsPerKm <= 1200;

Records computeRecords(List<Activity> activities) {
  final runs = activities.where(_plausible).toList();
  final out = <DistanceRecord>[];
  for (final d in recordDistances) {
    final fit = runs.where((a) => d.fits(a.distanceMeters)).toList();
    if (fit.isEmpty) continue;
    Activity? best, bestW;
    var bestS = 0, bestWS = 0;
    for (final a in fit) {
      final s = scaledSeconds(a.movingTimeSeconds, a.distanceMeters, d.meters);
      final ws = scaledSeconds(correctedSeconds(a), a.distanceMeters, d.meters);
      if (best == null || s < bestS) {
        best = a;
        bestS = s;
      }
      if (bestW == null || ws < bestWS) {
        bestW = a;
        bestWS = ws;
      }
    }
    out.add(DistanceRecord(
      distance: d,
      best: best!,
      bestSeconds: bestS,
      bestWeather: bestW!,
      bestWeatherSeconds: bestWS,
      count: fit.length,
    ));
  }
  Activity? longest;
  for (final a in runs) {
    if (longest == null || a.distanceMeters > longest.distanceMeters) longest = a;
  }
  return Records(distances: out, longest: longest);
}

/// Een run op een vaste route, met de weergecorrigeerde tijd.
class RouteRun {
  const RouteRun(this.activity, this.correctedSeconds);
  final Activity activity;
  final int correctedSeconds;
  double get correctedPace => correctedSeconds / (activity.distanceMeters / 1000);
}

/// Je runs op één route, nieuwste eerst, met trend.
class RouteHistory {
  const RouteHistory(this.runs);
  final List<RouteRun> runs;

  bool get isEmpty => runs.isEmpty;

  RouteRun? get fastest => runs.isEmpty
      ? null
      : runs.reduce((a, b) => a.activity.movingTimeSeconds <= b.activity.movingTimeSeconds ? a : b);

  RouteRun? get fastestCorrected =>
      runs.isEmpty ? null : runs.reduce((a, b) => a.correctedSeconds <= b.correctedSeconds ? a : b);

  /// Verschil in weergecorrigeerd tempo (s/km) tussen je laatste 3 en je eerste 3 runs.
  /// Negatief = je bent sneller geworden. Null bij minder dan 4 runs.
  double? get trendSecPerKm {
    if (runs.length < 4) return null;
    final n = runs.length >= 6 ? 3 : 2;
    double avg(Iterable<RouteRun> r) => r.fold<double>(0, (s, x) => s + x.correctedPace) / r.length;
    final recent = runs.take(n);
    final first = runs.skip(runs.length - n);
    return avg(recent) - avg(first);
  }
}

RouteHistory routeHistory(List<Activity> activities, String routeId) {
  final list = activities.where((a) => a.routeId == routeId && _plausible(a)).toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return RouteHistory([for (final a in list) RouteRun(a, correctedSeconds(a))]);
}
