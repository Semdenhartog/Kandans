import 'dart:math' as math;

import '../data/models/models.dart';
import 'geo.dart';
import 'roster.dart';
import 'sun_position.dart' show angleBetween;

/// Rennend naar (of van) je werk: met je rooster en de verwachting de beste ritten van de week.
class CommuteSettings {
  const CommuteSettings({this.home, this.work, this.maxKm = 12, this.toWork = true, this.fromWork = true, this.showerMinutes = 15});

  final LatLng? home;
  final LatLng? work;
  final double maxKm;
  final bool toWork;
  final bool fromWork;

  /// Tijd om je om te kleden of te douchen op je werk.
  final int showerMinutes;

  bool get ready => home != null && work != null;

  /// Geschatte looproute: hemelsbreed × 1,3 (wegen en paden lopen niet recht).
  double get km => !ready ? 0 : distanceMeters(home!, work!) / 1000 * 1.3;

  Map<String, dynamic> toJson() => {
        if (home != null) 'home': [home!.lat, home!.lon],
        if (work != null) 'work': [work!.lat, work!.lon],
        'max': maxKm,
        'to': toWork,
        'from': fromWork,
        'shower': showerMinutes,
      };

  static CommuteSettings fromJson(Object? j) {
    if (j is! Map) return const CommuteSettings();
    LatLng? ll(Object? v) => v is List && v.length == 2 ? LatLng((v[0] as num).toDouble(), (v[1] as num).toDouble()) : null;
    return CommuteSettings(
      home: ll(j['home']),
      work: ll(j['work']),
      maxKm: (j['max'] as num?)?.toDouble() ?? 12,
      toWork: j['to'] as bool? ?? true,
      fromWork: j['from'] as bool? ?? true,
      showerMinutes: (j['shower'] as num?)?.toInt() ?? 15,
    );
  }

  CommuteSettings copyWith({LatLng? home, LatLng? work, double? maxKm, bool? toWork, bool? fromWork}) => CommuteSettings(
        home: home ?? this.home,
        work: work ?? this.work,
        maxKm: maxKm ?? this.maxKm,
        toWork: toWork ?? this.toWork,
        fromWork: fromWork ?? this.fromWork,
        showerMinutes: showerMinutes,
      );
}

class CommuteRun {
  const CommuteRun({required this.start, required this.toWork, required this.km, required this.minutes, required this.shift, required this.good, required this.text});
  final DateTime start;
  final bool toWork;
  final double km;
  final int minutes;
  final BusyBlock shift;

  /// Fijn loopweer (droog, niet te warm/koud, niet te hard).
  final bool good;
  final String text;
}

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Woon-werk-runs voor de diensten in de verwachting. [paceSecPerKm] = je rustige tempo.
List<CommuteRun> commuteRuns(CommuteSettings c, List<BusyBlock> shifts, Forecast f, {double paceSecPerKm = 360, DateTime? now}) {
  if (!c.ready) return const [];
  final km = c.km;
  if (km < 2 || km > c.maxKm) return const [];
  final minutes = (km * paceSecPerKm / 60).round();
  final n = now ?? DateTime.now();
  final bearingToWork = bearingDegrees(c.home!, c.work!);
  final out = <CommuteRun>[];
  for (final s in shifts) {
    final night = isNightShift(s);
    final options = <(DateTime, bool)>[
      if (c.toWork) (s.start.subtract(Duration(minutes: minutes + c.showerMinutes)), true),
      // Na een nachtdienst niet nog naar huis rennen.
      if (c.fromWork && !night) (s.end.add(const Duration(minutes: 5)), false),
    ];
    for (final (start, toWork) in options) {
      if (start.isBefore(n)) continue;
      final during = [
        for (var m = 0; m <= minutes; m += 15)
          if (f.precise(start.add(Duration(minutes: m))) case final w?) w,
      ];
      if (during.isEmpty) continue;
      final rain = during.fold<double>(0, (a, w) => a + (w.precipitation ?? 0) * 0.25);
      final prob = during.map((w) => w.precipitationProbability ?? 0).reduce(math.max);
      final feelsMax = during.map((w) => w.feelsLike ?? w.temperature).reduce(math.max);
      final feelsMin = during.map((w) => w.feelsLike ?? w.temperature).reduce(math.min);
      final wind = during.map((w) => w.windSpeed).reduce(math.max);
      final dark = during.any((w) => !w.isDay);
      final good = rain < 0.3 && prob < 40 && feelsMax <= 22 && feelsMin >= -3 && wind < 32;
      final dir = toWork ? bearingToWork : (bearingToWork + 180) % 360;
      final w0 = during.first;
      String windNote = '';
      if (w0.windDirection != null && w0.windSpeed >= 12) {
        // Wind "uit" een richting: meewind als je die kant op loopt waar de wind heen waait.
        final towards = (w0.windDirection! + 180) % 360;
        final a = angleBetween(dir, towards);
        windNote = a <= 50 ? ', wind mee' : (a >= 130 ? ', tegenwind' : '');
      }
      final what = toWork ? 'naar je werk' : 'naar huis';
      final weather = rain >= 0.3 || prob >= 40 ? 'kans op regen' : (good ? 'droog' : 'matig weer');
      out.add(CommuteRun(
        start: start,
        toWork: toWork,
        km: km,
        minutes: minutes,
        shift: s,
        good: good,
        text: 'Om ${_hm(start)} $what: ${km.toStringAsFixed(1).replaceAll('.', ',')} km, ±$minutes min, $weather, '
            '${feelsMax.round()} °C$windNote${dark ? ', in het donker (lampje mee)' : ''}.',
      ));
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}
