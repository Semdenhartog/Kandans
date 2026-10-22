import 'dart:math' as math;

import '../data/models/models.dart';
import 'geo.dart';
import 'run_helpers.dart' show sunTimes;

// Kleine extra's voor Vandaag en na je run: rekenwerk zonder schermen, zodat het te testen is.

/// "Nog een keer": je laatst gelopen route die nog bestaat.
({RunRoute route, Activity run, int times})? lastRouteAgain(List<Activity> runs, List<RunRoute> routes) {
  final byId = {for (final r in routes) if (r.id != null) r.id!: r};
  final sorted = [...runs]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  for (final a in sorted) {
    final r = byId[a.routeId];
    if (r == null) continue;
    final times = runs.where((x) => x.routeId == r.id).length;
    return (route: r, run: a, times: times);
  }
  return null;
}

/// Dagen tussen twee momenten, op kalenderdagen (lokale tijd).
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = from.toLocal(), b = to.toLocal();
  return DateTime(b.year, b.month, b.day).difference(DateTime(a.year, a.month, a.day)).inDays;
}

/// "Vandaag", "gisteren", "3 dagen geleden", "2 weken geleden".
String daysAgoWords(int days) {
  if (days <= 0) return 'vandaag';
  if (days == 1) return 'gisteren';
  if (days < 14) return '$days dagen geleden';
  if (days < 60) return '${(days / 7).round()} weken geleden';
  return '${(days / 30).round()} maanden geleden';
}

/// Op deze dag: per jaar je langste run op dezelfde kalenderdag. Nieuwste jaar eerst.
List<({int yearsAgo, Activity run})> onThisDay(List<Activity> runs, DateTime now) {
  final today = now.toLocal();
  final best = <int, Activity>{};
  for (final a in runs) {
    final t = a.startedAt.toLocal();
    if (t.month != today.month || t.day != today.day || t.year >= today.year) continue;
    final ago = today.year - t.year;
    final cur = best[ago];
    if (cur == null || a.distanceMeters > cur.distanceMeters) best[ago] = a;
  }
  final keys = best.keys.toList()..sort();
  return [for (final k in keys) (yearsAgo: k, run: best[k]!)];
}

/// Gouden uur: het zachte licht vlak na zonsopkomst en vlak voor zonsondergang.
class GoldenHour {
  const GoldenHour({required this.start, required this.end, required this.evening});
  final DateTime start;
  final DateTime end;
  final bool evening;

  /// Midden van het gouden uur: een mooi moment om te vertrekken.
  DateTime get middle => start.add(end.difference(start) ~/ 2);
}

/// Het eerstvolgende gouden uur vanaf [now] (vandaag of morgen).
GoldenHour? nextGoldenHour(DateTime now, double lat, double lon) {
  for (var d = 0; d < 2; d++) {
    final day = DateTime(now.year, now.month, now.day + d);
    final s = sunTimes(day, lat, lon);
    final options = <GoldenHour>[
      if (s.sunrise != null)
        GoldenHour(start: s.sunrise!, end: s.sunrise!.add(const Duration(minutes: 50)), evening: false),
      if (s.sunset != null)
        GoldenHour(start: s.sunset!.subtract(const Duration(minutes: 60)), end: s.sunset!, evening: true),
    ];
    for (final g in options) {
      if (g.end.isAfter(now)) return g;
    }
  }
  return null;
}

/// Jaardoel: hoeveel je al hebt en waar je met dit tempo op uitkomt.
class YearGoalProgress {
  const YearGoalProgress({required this.targetKm, required this.doneKm, required this.now});
  final double targetKm;
  final double doneKm;
  final DateTime now;

  int get daysInYear => DateTime(now.year, 12, 31).difference(DateTime(now.year, 1, 1)).inDays + 1;
  int get dayOfYear => DateTime(now.year, now.month, now.day).difference(DateTime(now.year, 1, 1)).inDays + 1;

  /// Verwachte stand op 31 december als je zo doorgaat.
  double get projectedKm => dayOfYear <= 0 ? doneKm : doneKm / dayOfYear * daysInYear;
  double get fraction => targetKm <= 0 ? 0 : (doneKm / targetKm).clamp(0.0, 1.0);
  bool get onTrack => projectedKm >= targetKm;

  /// Kilometers per week die je nog nodig hebt om het doel te halen.
  double get neededPerWeek {
    final daysLeft = daysInYear - dayOfYear + 1;
    final left = math.max(0, targetKm - doneKm);
    return daysLeft <= 0 ? 0 : left / daysLeft * 7;
  }
}

/// Kilometers dit kalenderjaar.
double kmInYear(List<Activity> runs, DateTime now) {
  var m = 0.0;
  for (final a in runs) {
    if (a.startedAt.toLocal().year == now.year) m += a.distanceMeters;
  }
  return m / 1000;
}

/// Hoogtemeters vergeleken met iets bekends ("2,3× de Domtoren").
String climbComparison(double meters) {
  const things = [
    (8849.0, 'de Mount Everest'),
    (322.0, 'de Vaalserberg, het hoogste punt van Nederland'),
    (185.0, 'de Euromast'),
    (112.0, 'de Domtoren'),
    (69.0, 'de Amerongse Berg'),
  ];
  if (meters <= 0) return 'Nog geen hoogtemeters.';
  for (final (h, name) in things) {
    final x = meters / h;
    if (x >= 1) {
      final n = x >= 10 ? x.round().toString() : x.toStringAsFixed(1).replaceAll('.', ',');
      return 'Dat is $n× $name.';
    }
  }
  final pct = (meters / 69 * 100).round();
  return 'Dat is $pct% van de Amerongse Berg.';
}

/// Tip voor na je run: wat eten en drinken helpt bij herstel. Hangt af van duur, intensiteit en warmte.
({String title, String text}) recoveryTip({
  required int movingSeconds,
  double? avgHeartRate,
  double? maxHeartRate,
  double? temperature,
  DateTime? when,
}) {
  final min = movingSeconds / 60;
  final hard = avgHeartRate != null && maxHeartRate != null && maxHeartRate > 0 && avgHeartRate / maxHeartRate >= 0.85;
  final hot = temperature != null && temperature >= 20;
  final pick = (when ?? DateTime.now()).day % 3;
  final drink = hot ? ' Het was warm: drink extra en neem iets zouts, zoals een kop bouillon.' : ' Drink een paar glazen water.';
  if (min < 40 && !hard) {
    return (title: 'Herstel: gewoon eten is genoeg', text: 'Na een korte, rustige run hoef je niets speciaals te eten.$drink');
  }
  const mid = [
    'Binnen een uur: kwark of Griekse yoghurt met banaan en een handje havermout.',
    'Binnen een uur: een volkoren boterham met ei of hüttenkäse en een stuk fruit.',
    'Binnen een uur: een glas chocolademelk en een banaan. Simpel en het werkt.',
  ];
  const long = [
    'Lange of zware run: eet binnen een uur iets met koolhydraten en eiwit, zoals volkoren pasta met kip of tofu en groente.',
    'Lange of zware run: rijst met zalm of bonen en veel groente vult je voorraad weer aan.',
    'Lange of zware run: begin met chocolademelk en eet daarna een warme maaltijd met aardappels of pasta en vis, vlees of peulvruchten.',
  ];
  if (min >= 75 || hard) return (title: 'Herstel na een stevige run', text: '${long[pick]}$drink');
  return (title: 'Herstel', text: '${mid[pick]}$drink');
}

/// Meters van [track] over wegen waar je nog nooit liep (verder dan ~40 m van eerdere sporen).
/// Werkt met een rooster van vakjes van ongeveer 35 bij 25 meter.
double newRoadMeters(List<LatLng> track, Iterable<List<LatLng>> previous) {
  if (track.length < 2) return 0;
  const cell = 0.0003;
  int key(double lat, double lon) => (lat / cell).floor() * 1000003 + (lon / cell).floor();
  final seen = <int>{};
  for (final t in previous) {
    for (var i = 0; i < t.length; i++) {
      final p = t[i];
      seen.add(key(p.lat, p.lon));
      // Lange stukken tussen twee punten opvullen, zodat een recht stuk weg ook telt.
      if (i > 0) {
        final q = t[i - 1];
        final d = distanceMeters(p, q);
        final steps = (d / 20).floor();
        for (var s = 1; s < steps; s++) {
          final f = s / steps;
          seen.add(key(q.lat + (p.lat - q.lat) * f, q.lon + (p.lon - q.lon) * f));
        }
      }
    }
  }
  bool known(LatLng p) {
    final la = (p.lat / cell).floor(), lo = (p.lon / cell).floor();
    for (var a = -1; a <= 1; a++) {
      for (var b = -1; b <= 1; b++) {
        if (seen.contains((la + a) * 1000003 + lo + b)) return true;
      }
    }
    return false;
  }

  var meters = 0.0;
  for (var i = 1; i < track.length; i++) {
    final a = track[i - 1], b = track[i];
    final mid = LatLng((a.lat + b.lat) / 2, (a.lon + b.lon) / 2);
    if (!known(mid)) meters += distanceMeters(a, b);
  }
  return meters;
}
