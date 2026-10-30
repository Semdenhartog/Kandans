import 'dart:math' as math;

import 'run_streams.dart';

/// Aerobe ontkoppeling ("hartslagdrift"): hoeveel je hartslag in de tweede helft opliep ten opzichte van je tempo.
/// Onder 5% = je duurvermogen is goed voor dit tempo; boven 10% = te snel gestart, warmte of vocht tekort.
class Decoupling {
  const Decoupling(this.percent, this.firstHr, this.secondHr);
  final double percent;
  final double firstHr;
  final double secondHr;

  String get verdict => percent < 5
      ? 'Stabiel: je duurvermogen is goed voor dit tempo.'
      : percent < 10
          ? 'Normaal. Meer rustige lange duurlopen maken dit kleiner.'
          : 'Flinke drift: te snel gestart, warmte of te weinig gedronken?';
}

/// Null als de run te kort is (< 40 min), te weinig hartslag heeft of geen gelijkmatig tempo (intervallen).
Decoupling? decouplingOf(RunStreams s) {
  final hr = s.heartRate;
  if (hr == null || s.totalTime < 40 * 60 || s.totalDistance < 5000) return null;
  final valid = hr.where((x) => x > 60 && x < 230).length;
  if (valid < s.length * 0.8) return null;

  // Alleen bij gelijkmatig tempo: variatie in km-tijden onder 10%.
  final splits = splitsOf(s).where((x) => !x.partial).toList();
  if (splits.length < 4) return null;
  final paces = [for (final x in splits) x.paceSecPerKm];
  final mean = paces.reduce((a, b) => a + b) / paces.length;
  final sd = math.sqrt(paces.map((p) => (p - mean) * (p - mean)).reduce((a, b) => a + b) / paces.length);
  if (sd / mean > 0.10) return null;

  final mid = s.time.first + s.totalTime / 2;
  ({double speed, double hr})? half(bool first) {
    var hrSum = 0.0, n = 0;
    double? d0, t0, d1, t1;
    for (var i = 0; i < s.length; i++) {
      final inHalf = first ? s.time[i] <= mid : s.time[i] >= mid;
      if (!inHalf) continue;
      d0 ??= s.distance[i];
      t0 ??= s.time[i];
      d1 = s.distance[i];
      t1 = s.time[i];
      if (hr[i] > 60 && hr[i] < 230) {
        hrSum += hr[i];
        n++;
      }
    }
    if (n == 0 || d0 == null || t0 == null || t1! - t0 <= 0) return null;
    return (speed: (d1! - d0) / (t1 - t0), hr: hrSum / n);
  }

  final a = half(true), b = half(false);
  if (a == null || b == null) return null;
  final ef1 = a.speed / a.hr, ef2 = b.speed / b.hr;
  final pct = (ef1 - ef2) / ef1 * 100;
  return Decoupling(math.max(0, pct), a.hr, b.hr);
}
