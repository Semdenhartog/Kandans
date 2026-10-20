import 'dart:math' as math;

import 'geo.dart';
import 'run_streams.dart';

/// Tijd (seconden) in elke zone 1..5. Index 0 = zone 1.
class ZoneTimes {
  const ZoneTimes(this.seconds, {required this.byHeartRate});
  final List<double> seconds;
  final bool byHeartRate;

  double get total => seconds.fold(0, (a, b) => a + b);

  static const hrNames = ['Herstel', 'Rustig', 'Tempo', 'Drempel', 'Maximaal'];
  static const paceNames = ['Herstel', 'Rustig', 'Duurtempo', 'Drempel', 'Snel'];
  List<String> get names => byHeartRate ? hrNames : paceNames;
}

/// Op hartslag (50-60-70-80-90% van je maximale hartslag).
ZoneTimes? heartRateZoneTimes(RunStreams s, int maxHr) {
  final hr = s.heartRate;
  if (hr == null || maxHr <= 0) return null;
  final out = List<double>.filled(5, 0);
  for (var i = 1; i < s.length; i++) {
    final dt = s.time[i] - s.time[i - 1];
    if (dt <= 0 || dt > 30 || hr[i] < 40) continue;
    final f = hr[i] / maxHr;
    final z = f < 0.6 ? 0 : f < 0.7 ? 1 : f < 0.8 ? 2 : f < 0.9 ? 3 : 4;
    out[z] += dt;
  }
  final zt = ZoneTimes(out, byHeartRate: true);
  return zt.total < 60 ? null : zt;
}

/// Op tempo, ten opzichte van je drempeltempo.
ZoneTimes? paceZoneTimes(RunStreams s, double thresholdPace) {
  if (thresholdPace <= 0) return null;
  final out = List<double>.filled(5, 0);
  // Over stukjes van ~100 m, anders springt het tempo te veel.
  var j = 0;
  for (var i = 1; i < s.length; i++) {
    final dd = s.distance[i] - s.distance[j];
    if (dd < 100) continue;
    final dt = s.time[i] - s.time[j];
    j = i;
    if (dt <= 0) continue;
    final pace = dt / (dd / 1000);
    if (pace > 1200) continue;
    final r = pace / thresholdPace;
    final z = r > 1.29 ? 0 : r > 1.14 ? 1 : r > 1.06 ? 2 : r > 0.97 ? 3 : 4;
    out[z] += dt;
  }
  final zt = ZoneTimes(out, byHeartRate: false);
  return zt.total < 60 ? null : zt;
}

// ---------------------------------------------------------------------------
// Hoogte corrigeren met een hoogtekaart (GPS-hoogte is onnauwkeurig)
// ---------------------------------------------------------------------------

/// Welke meetpunten we opvragen: ongeveer elke [every] meter, hooguit [max].
List<int> elevationSampleIndices(List<double> distance, {double every = 50, int max = 300}) {
  if (distance.isEmpty) return const [];
  final total = distance.last;
  final step = math.max(every, total / max);
  final out = <int>[0];
  var next = step;
  for (var i = 1; i < distance.length; i++) {
    if (distance[i] >= next) {
      out.add(i);
      next = distance[i] + step;
    }
  }
  if (out.last != distance.length - 1) out.add(distance.length - 1);
  return out;
}

/// Hoogtes van de opgevraagde punten verdelen over alle meetpunten (lineair op afstand).
List<double> interpolateElevation(List<double> distance, List<int> idx, List<double> ele) {
  final out = List<double>.filled(distance.length, ele.isEmpty ? 0 : ele.first);
  for (var k = 0; k + 1 < idx.length; k++) {
    final a = idx[k], b = idx[k + 1];
    final da = distance[a], db = distance[b];
    for (var i = a; i <= b; i++) {
      final f = db - da <= 0 ? 0.0 : (distance[i] - da) / (db - da);
      out[i] = double.parse((ele[k] + (ele[k + 1] - ele[k]) * f).toStringAsFixed(1));
    }
  }
  return out;
}

/// Hoogtemeters omhoog, kleine schommelingen (< 2 m) genegeerd.
double elevationGain(List<double> ele) {
  if (ele.isEmpty) return 0;
  // Van dal naar top tellen; pas een klim als die minstens 2 m is (tegen ruis).
  var gain = 0.0;
  var low = ele.first, high = ele.first;
  var up = false;
  for (final e in ele.skip(1)) {
    if (!up) {
      if (e < low) {
        low = e;
      } else if (e - low >= 2) {
        up = true;
        high = e;
      }
    } else {
      if (e > high) {
        high = e;
      } else if (high - e >= 2) {
        gain += high - low;
        up = false;
        low = e;
      }
    }
  }
  if (up) gain += high - low;
  return gain;
}

/// Punten voor de hoogte-aanvraag.
List<LatLng> pointsAt(List<LatLng> positions, List<int> idx) => [for (final i in idx) positions[i]];

// ---------------------------------------------------------------------------
// Tempoplan voor een wedstrijd
// ---------------------------------------------------------------------------

enum PacingStrategy {
  even('Gelijkmatig'),
  negative('Negatieve split'),
  easyStart('Rustige start');

  const PacingStrategy(this.label);
  final String label;
}

class PlannedSplit {
  const PlannedSplit(this.km, this.meters, this.seconds, this.cumulative);
  final int km;
  final double meters;
  final double seconds;
  final double cumulative;

  double get pace => seconds / (meters / 1000);
}

/// Tijd per km zodat je precies op je doeltijd uitkomt.
List<PlannedSplit> pacingPlan(double distanceMeters, int goalSeconds, PacingStrategy strategy) {
  final n = (distanceMeters / 1000).ceil();
  if (n == 0 || goalSeconds <= 0) return const [];
  final meters = [for (var k = 0; k < n; k++) math.min(1000.0, distanceMeters - k * 1000)];
  // Gewicht per km (1 = gemiddeld); daarna zo schalen dat het precies klopt.
  final weights = <double>[
    for (var k = 0; k < n; k++)
      switch (strategy) {
        PacingStrategy.even => 1.0,
        PacingStrategy.negative => k < n / 2 ? 1.02 : 0.98,
        PacingStrategy.easyStart => k == 0 ? 1.04 : (k == 1 ? 1.02 : 1.0),
      },
  ];
  final raw = [for (var k = 0; k < n; k++) weights[k] * meters[k]];
  final sum = raw.fold(0.0, (a, b) => a + b);
  var cum = 0.0;
  return [
    for (var k = 0; k < n; k++)
      () {
        final sec = goalSeconds * raw[k] / sum;
        cum += sec;
        return PlannedSplit(k + 1, meters[k], sec, cum);
      }(),
  ];
}
