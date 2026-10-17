import 'dart:math' as math;

import '../data/models/models.dart';

/// Persoonlijk loopprofiel, berekend uit je eigen runs.
///
/// v1 is bewust eenvoudig en verklaarbaar: we vergelijken je tempo per
/// temperatuurgroep met je eigen gemiddelde tempo.
class PerformanceInsights {
  const PerformanceInsights({
    required this.sampleSize,
    required this.optimalMin,
    required this.optimalMax,
    this.pctFasterInOptimal,
    this.windSecPerKmPer10kmh,
    this.preferredTimeOfDay,
    this.morningPace,
    this.eveningPace,
    this.buckets = const [],
  });

  /// Aantal runs met weerdata dat is gebruikt.
  final int sampleSize;
  final double optimalMin;
  final double optimalMax;

  /// Hoeveel procent sneller je loopt in je ideale temperatuur t.o.v. je slechtste.
  final double? pctFasterInOptimal;

  /// Seconden per km trager per 10 km/u extra wind.
  final double? windSecPerKmPer10kmh;

  /// 'morning', 'evening' of 'no_preference'.
  final String? preferredTimeOfDay;
  final double? morningPace;
  final double? eveningPace;

  /// Gemiddeld relatief tempo per temperatuurgroep (1.00 = je gemiddelde).
  final List<({double from, double to, double relativePace, int count})> buckets;

  static const minRuns = 8;
  static const highConfidenceRuns = 20;

  bool get isPersonal => sampleSize >= minRuns;
  bool get isHighConfidence => sampleSize >= highConfidenceRuns;

  static const defaults = PerformanceInsights(sampleSize: 0, optimalMin: 8, optimalMax: 16);

  static PerformanceInsights compute(List<Activity> activities) {
    final runs = activities
        .where((a) =>
            a.distanceMeters >= 1000 &&
            a.paceSecondsPerKm > 150 &&
            a.paceSecondsPerKm < 1200)
        .toList();
    final withTemp = runs.where((a) => a.temperatureCelsius != null).toList();

    if (withTemp.length < minRuns) {
      return PerformanceInsights(
        sampleSize: withTemp.length,
        optimalMin: defaults.optimalMin,
        optimalMax: defaults.optimalMax,
        preferredTimeOfDay: _timeOfDay(runs).$1,
        morningPace: _timeOfDay(runs).$2,
        eveningPace: _timeOfDay(runs).$3,
      );
    }

    final median = _median(withTemp.map((a) => a.paceSecondsPerKm).toList());
    double rel(Activity a) => a.paceSecondsPerKm / median;

    // Temperatuurgroepen van 4 °C.
    const width = 4.0;
    final groups = <int, List<double>>{};
    for (final a in withTemp) {
      final t = a.feelsLikeCelsius ?? a.temperatureCelsius!;
      final key = (t / width).floor();
      groups.putIfAbsent(key, () => []).add(rel(a));
    }
    final buckets = groups.entries
        .where((e) => e.value.length >= 2)
        .map((e) => (
              from: e.key * width,
              to: e.key * width + width,
              relativePace: e.value.reduce((x, y) => x + y) / e.value.length,
              count: e.value.length,
            ))
        .toList()
      ..sort((a, b) => a.from.compareTo(b.from));

    var optMin = defaults.optimalMin;
    var optMax = defaults.optimalMax;
    double? pctFaster;
    if (buckets.length >= 2) {
      final best = buckets.reduce((a, b) => a.relativePace <= b.relativePace ? a : b);
      final worst = buckets.reduce((a, b) => a.relativePace >= b.relativePace ? a : b);
      optMin = best.from;
      optMax = best.to;
      // Breid uit met buurgroepen die bijna even snel zijn (< 1% verschil).
      for (final b in buckets) {
        if ((b.from == optMax || b.to == optMin) &&
            b.relativePace - best.relativePace < 0.01) {
          optMin = math.min(optMin, b.from);
          optMax = math.max(optMax, b.to);
        }
      }
      pctFaster = (worst.relativePace - best.relativePace) / worst.relativePace * 100;
    } else if (buckets.length == 1) {
      optMin = buckets.first.from;
      optMax = buckets.first.to;
    }

    // Windgevoeligheid: lineaire regressie relatief tempo ~ windsnelheid.
    double? windSens;
    final withWind = withTemp.where((a) => a.windSpeedKmh != null).toList();
    if (withWind.length >= minRuns) {
      final xs = withWind.map((a) => a.windSpeedKmh!).toList();
      final ys = withWind.map(rel).toList();
      final slope = _slope(xs, ys);
      if (slope != null) {
        windSens = math.max(0.0, slope * median * 10);
      }
    }

    final tod = _timeOfDay(runs);
    return PerformanceInsights(
      sampleSize: withTemp.length,
      optimalMin: optMin,
      optimalMax: optMax,
      pctFasterInOptimal: pctFaster,
      windSecPerKmPer10kmh: windSens,
      preferredTimeOfDay: tod.$1,
      morningPace: tod.$2,
      eveningPace: tod.$3,
      buckets: buckets,
    );
  }

  /// Vergelijkt ochtend (voor 12:00) met avond (vanaf 17:00).
  static (String?, double?, double?) _timeOfDay(List<Activity> runs) {
    final morning = runs.where((a) => a.startedAt.toLocal().hour < 12).toList();
    final evening = runs.where((a) => a.startedAt.toLocal().hour >= 17).toList();
    if (morning.length < 3 || evening.length < 3) return (null, null, null);
    final m = _mean(morning.map((a) => a.paceSecondsPerKm).toList());
    final e = _mean(evening.map((a) => a.paceSecondsPerKm).toList());
    final diffPct = (m - e).abs() / math.max(m, e) * 100;
    final pref = diffPct < 1.5 ? 'no_preference' : (m < e ? 'morning' : 'evening');
    return (pref, m, e);
  }

  static double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;

  static double _median(List<double> v) {
    final s = [...v]..sort();
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }

  static double? _slope(List<double> xs, List<double> ys) {
    final mx = _mean(xs);
    final my = _mean(ys);
    var cov = 0.0, den = 0.0;
    for (var i = 0; i < xs.length; i++) {
      cov += (xs[i] - mx) * (ys[i] - my);
      den += (xs[i] - mx) * (xs[i] - mx);
    }
    return den == 0 ? null : cov / den;
  }
}
