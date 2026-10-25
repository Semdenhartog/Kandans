import 'dart:math' as math;

import '../data/models/models.dart';
import 'geo.dart';
import 'run_helpers.dart' show sunTimes;
import 'weekly_load.dart';

/// Groep op het badgescherm.
enum BadgeCategory {
  milestone('MIJLPALEN', null),
  speed('SNELHEID EN RECORDS', 'Snelle tijden, gemeten op het snelste stuk binnen een run.'),
  weather('WEER EN SEIZOEN', 'Alleen in RunWise: voor lopen in bijzonder weer en op bijzondere dagen.'),
  streak('VOLHOUDEN', 'Voor wie blijft lopen, week in week uit.'),
  explore('ONTDEKKEN', 'Nieuwe routes en nieuwe plekken.');

  const BadgeCategory(this.title, this.subtitle);
  final String title;
  final String? subtitle;
}

/// Een badge (mijlpaal). [progress] 0..1 voor badges die je nog niet hebt.
class Badge {
  const Badge({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.earnedAt,
    this.progress = 0,
    this.category = BadgeCategory.milestone,
  });

  final String id;
  final String title;
  final String description;

  /// Naam van een Material-icoon (de app kiest het plaatje).
  final String icon;
  final DateTime? earnedAt;
  final double progress;
  final BadgeCategory category;

  /// RunWise-badges voor lopen in bijzonder weer (blauw op het scherm).
  bool get weather => category == BadgeCategory.weather;

  bool get earned => earnedAt != null;
}

Badge _single(String id, String title, String desc, String icon, List<Activity> sorted, bool Function(Activity) test,
    {BadgeCategory category = BadgeCategory.milestone}) {
  for (final a in sorted) {
    if (test(a)) return Badge(id: id, title: title, description: desc, icon: icon, earnedAt: a.startedAt, category: category);
  }
  return Badge(id: id, title: title, description: desc, icon: icon, category: category);
}

/// Badge als een totaal een grens haalt (bijv. 100 km); verdiend op de run waarmee je erover ging.
Badge _total(String id, String title, String desc, String icon, List<Activity> sorted, double goal, double Function(Activity) value) {
  var sum = 0.0;
  for (final a in sorted) {
    sum += value(a);
    if (sum >= goal) return Badge(id: id, title: title, description: desc, icon: icon, earnedAt: a.startedAt, progress: 1);
  }
  return Badge(id: id, title: title, description: desc, icon: icon, progress: goal <= 0 ? 0 : (sum / goal).clamp(0, 1).toDouble());
}

Badge _streak(String id, String title, String desc, List<Activity> sorted, int weeks) {
  final ws = sorted.map((a) => weekStart(a.startedAt)).toSet().toList()..sort();
  var run = 0, best = 0;
  DateTime? prev, earned;
  for (final w in ws) {
    run = prev != null && (w.difference(prev).inHours / 24).round() == 7 ? run + 1 : 1;
    if (run > best) best = run;
    if (run >= weeks && earned == null) earned = w.add(const Duration(days: 6));
    prev = w;
  }
  return Badge(
    id: id,
    title: title,
    description: desc,
    icon: 'local_fire_department',
    earnedAt: earned,
    progress: (best / weeks).clamp(0, 1).toDouble(),
    category: BadgeCategory.streak,
  );
}

/// Badge voor een aantal opeenvolgende eenheden (dagen of maanden) met minstens één run.
Badge _consecutive(String id, String title, String desc, String icon, List<Activity> sorted, int need, int Function(DateTime) unit) {
  final units = sorted.map((a) => unit(a.startedAt.toLocal())).toSet().toList()..sort();
  var run = 0, best = 0;
  int? prev;
  int? earnedUnit;
  for (final u in units) {
    run = prev != null && u == prev + 1 ? run + 1 : 1;
    best = math.max(best, run);
    if (run >= need && earnedUnit == null) earnedUnit = u;
    prev = u;
  }
  final earned = earnedUnit == null ? null : sorted.firstWhere((a) => unit(a.startedAt.toLocal()) == earnedUnit).startedAt;
  return Badge(
    id: id,
    title: title,
    description: desc,
    icon: icon,
    earnedAt: earned,
    progress: (best / need).clamp(0, 1).toDouble(),
    category: BadgeCategory.streak,
  );
}

int _dayNumber(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;
int _monthNumber(DateTime d) => d.year * 12 + d.month - 1;

/// Tijd (s) over [meters] in deze run: het snelste stuk als dat bekend is, anders de hele run
/// omgerekend (alleen als de run er dichtbij zit, zodat een lange run geen te snelle tijd geeft).
double? effortSeconds(Activity a, int meters) {
  final e = a.bestEfforts?['$meters'];
  if (e != null && e > 0) return e;
  final d = a.distanceMeters;
  if (d < meters * 0.99 || d > meters * 1.15 || a.movingTimeSeconds <= 0) return null;
  return a.movingTimeSeconds * meters / d;
}

Badge _faster(String id, String title, String desc, List<Activity> sorted, int meters, int seconds) => _single(
      id,
      title,
      desc,
      'bolt',
      sorted,
      (a) {
        final t = effortSeconds(a, meters);
        return t != null && t <= seconds;
      },
      category: BadgeCategory.speed,
    );

/// Eerste punt van een (Google-)polyline, zonder de hele lijn te ontcijferen.
LatLng? firstPolylinePoint(String? encoded) {
  if (encoded == null || encoded.isEmpty) return null;
  var index = 0;
  int next() {
    var result = 0, shift = 0, b = 0;
    do {
      if (index >= encoded.length) throw const FormatException('kapotte polyline');
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  try {
    final lat = next() / 1e5;
    final lon = next() / 1e5;
    return LatLng(lat, lon);
  } catch (_) {
    return null;
  }
}

/// Startpunten van runs met GPS, in volgorde.
List<({Activity run, LatLng start})> _starts(List<Activity> sorted) => [
      for (final a in sorted)
        if (firstPolylinePoint(a.trackPolyline) case final p?) (run: a, start: p),
    ];

/// Aantal verschillende plekken (minstens [radiusKm] uit elkaar) waar je een run begon, en wanneer de [need]e erbij kwam.
({int count, DateTime? reached}) _places(List<({Activity run, LatLng start})> starts, double radiusKm, int need) {
  final centers = <LatLng>[];
  DateTime? reached;
  for (final s in starts) {
    if (centers.every((c) => distanceMeters(c, s.start) > radiusKm * 1000)) {
      centers.add(s.start);
      if (centers.length == need) reached = s.run.startedAt;
    }
  }
  return (count: centers.length, reached: reached);
}

/// Seizoen: 0 winter (dec–feb), 1 lente, 2 zomer, 3 herfst.
int _season(DateTime d) => switch (d.month) { 12 || 1 || 2 => 0, 3 || 4 || 5 => 1, 6 || 7 || 8 => 2, _ => 3 };

/// Alle badges met je voortgang.
List<Badge> computeBadges(List<Activity> runs, {DateTime? now}) {
  final sorted = [...runs]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final today = now ?? DateTime.now();

  // Verschillende routes.
  final routes = <String>{};
  DateTime? explorer, routes10, routes25;
  for (final a in sorted) {
    if (a.routeId != null && routes.add(a.routeId!)) {
      if (routes.length == 5) explorer = a.startedAt;
      if (routes.length == 10) routes10 = a.startedAt;
      if (routes.length == 25) routes25 = a.startedAt;
    }
  }

  // Plekken. "Thuis" = de plek waar je het vaakst begint; op reis = meer dan 50 km daarvandaan.
  final starts = _starts(sorted);
  DateTime? farAway;
  if (starts.length >= 3) {
    var home = starts.first.start;
    var bestCount = -1;
    for (final s in starts.take(200)) {
      final n = starts.where((o) => distanceMeters(o.start, s.start) < 5000).length;
      if (n > bestCount) {
        bestCount = n;
        home = s.start;
      }
    }
    for (final s in starts) {
      if (distanceMeters(home, s.start) > 50000) {
        farAway = s.run.startedAt;
        break;
      }
    }
  }
  final places = _places(starts, 10, 5);

  // Vier seizoenen in één kalenderjaar.
  DateTime? allSeasons;
  final seasonsPerYear = <int, Set<int>>{};
  for (final a in sorted) {
    final d = a.startedAt.toLocal();
    final set = seasonsPerYear.putIfAbsent(d.year, () => <int>{})..add(_season(d));
    if (set.length == 4 && allSeasons == null) allSeasons = a.startedAt;
  }
  final bestSeasons = seasonsPerYear.values.fold<int>(0, (m, s) => math.max(m, s.length));

  // Een jaar loper: een run minstens 365 dagen na je eerste.
  final first = sorted.isEmpty ? null : sorted.first.startedAt;
  DateTime? oneYear;
  if (first != null) {
    for (final a in sorted) {
      if (a.startedAt.difference(first).inDays >= 365) {
        oneYear = a.startedAt;
        break;
      }
    }
  }
  final daysSinceFirst = first == null ? 0 : today.difference(first).inDays;

  bool atSunrise(Activity a) {
    final p = firstPolylinePoint(a.trackPolyline) ?? const LatLng(52.1, 5.3);
    final rise = sunTimes(a.startedAt.toLocal(), p.lat, p.lon).sunrise;
    return rise != null && a.startedAt.difference(rise).inMinutes.abs() <= 30;
  }

  bool onDay(Activity a, int month, List<int> days) {
    final d = a.startedAt.toLocal();
    return d.month == month && days.contains(d.day);
  }

  double feels(Activity a, double missing) => a.feelsLikeCelsius ?? a.temperatureCelsius ?? missing;

  const w = BadgeCategory.weather, e = BadgeCategory.explore, k = BadgeCategory.streak;
  return [
    // Mijlpalen.
    _single('first', 'Eerste stap', 'Je eerste run in RunWise.', 'flag', sorted, (_) => true),
    _single('5k', '5 kilometer', 'Een run van 5 km of meer.', 'looks_5', sorted, (a) => a.distanceMeters >= 4950),
    _single('10k', '10 kilometer', 'Een run van 10 km of meer.', 'filter_9_plus', sorted, (a) => a.distanceMeters >= 9900),
    _single('15k', '15 kilometer', 'Een run van 15 km of meer.', 'route', sorted, (a) => a.distanceMeters >= 14900),
    _single('half', 'Halve marathon', 'Een run van 21,1 km of meer.', 'military_tech', sorted, (a) => a.distanceMeters >= 21000),
    _single('30k', '30 kilometer', 'Een run van 30 km of meer.', 'military_tech', sorted, (a) => a.distanceMeters >= 29900),
    _single('full', 'Marathon', 'Een run van 42,2 km of meer.', 'emoji_events', sorted, (a) => a.distanceMeters >= 42000),
    _total('runs10', '10 runs', 'Tien keer gelopen.', 'directions_run', sorted, 10, (_) => 1),
    _total('runs50', '50 runs', 'Vijftig keer gelopen.', 'directions_run', sorted, 50, (_) => 1),
    _total('runs100', '100 runs', 'Honderd keer gelopen!', 'directions_run', sorted, 100, (_) => 1),
    _total('runs250', '250 runs', 'Tweehonderdvijftig keer gelopen.', 'directions_run', sorted, 250, (_) => 1),
    _total('km100', '100 km', 'In totaal 100 kilometer.', 'route', sorted, 100, (a) => a.distanceMeters / 1000),
    _total('km500', '500 km', 'In totaal 500 kilometer.', 'route', sorted, 500, (a) => a.distanceMeters / 1000),
    _total('km1000', '1000 km', 'In totaal 1000 kilometer. Wauw.', 'public', sorted, 1000, (a) => a.distanceMeters / 1000),
    _total('km2500', '2500 km', 'In totaal 2500 kilometer.', 'public', sorted, 2500, (a) => a.distanceMeters / 1000),
    _single('early', 'Vroege vogel', 'Een run gestart voor 7:00.', 'wb_twilight', sorted, (a) => a.startedAt.toLocal().hour < 7),
    _single('night', 'Nachtloper', 'Een run gestart na 21:00.', 'nightlight', sorted, (a) => a.startedAt.toLocal().hour >= 21),
    _single('climb', 'Klimmer', 'Minstens 150 hoogtemeters in één run.', 'terrain', sorted, (a) => (a.elevationGainMeters ?? 0) >= 150),

    // Snelheid en records.
    _faster('5k_30', '5 km onder 30 min', 'Je snelste 5 km onder de 30 minuten.', sorted, 5000, 30 * 60),
    _faster('5k_25', '5 km onder 25 min', 'Je snelste 5 km onder de 25 minuten.', sorted, 5000, 25 * 60),
    _faster('5k_20', '5 km onder 20 min', 'Je snelste 5 km onder de 20 minuten. Snel!', sorted, 5000, 20 * 60),
    _faster('10k_60', '10 km onder het uur', 'Je snelste 10 km onder de 60 minuten.', sorted, 10000, 60 * 60),
    _faster('10k_50', '10 km onder 50 min', 'Je snelste 10 km onder de 50 minuten.', sorted, 10000, 50 * 60),
    _faster('1k_4', 'Snelle kilometer', 'Een kilometer onder de 4 minuten.', sorted, 1000, 4 * 60),
    _faster('half_2h', 'Halve onder 2 uur', 'Een halve marathon onder de 2 uur.', sorted, 21098, 2 * 3600),

    // Weer en seizoen.
    _single('wind', 'Windtrotser', 'Gelopen met 30 km/u wind of meer.', 'air', sorted, (a) => (a.windSpeedKmh ?? 0) >= 30, category: w),
    _single('storm', 'Stormloper', 'Gelopen met 45 km/u wind of meer.', 'storm', sorted, (a) => (a.windSpeedKmh ?? 0) >= 45, category: w),
    _single('heat', 'Hittebestendig', 'Gelopen bij 25 °C of warmer.', 'local_fire_department', sorted, (a) => feels(a, 0) >= 25, category: w),
    _single('tropical', 'Tropenloper', 'Gelopen bij een gevoelstemperatuur van 30 °C of meer.', 'wb_sunny', sorted, (a) => feels(a, 0) >= 30,
        category: w),
    _single('frost', 'IJsloper', 'Gelopen bij een gevoelstemperatuur onder 0 °C.', 'ac_unit', sorted, (a) => feels(a, 99) < 0, category: w),
    _single('arctic', 'Poolloper', 'Gelopen bij een gevoelstemperatuur van -10 °C of kouder.', 'ac_unit', sorted, (a) => feels(a, 99) <= -10,
        category: w),
    _single('humid', 'Klamme kilometers', 'Gelopen bij 90% luchtvochtigheid of meer.', 'water_drop', sorted, (a) => (a.humidityPct ?? 0) >= 90,
        category: w),
    _single('sunrise', 'Zonsopkomst', 'Gestart binnen een halfuur van zonsopkomst.', 'wb_twilight', sorted, atSunrise, category: w),
    _single('midsummer', 'Langste dag', 'Gelopen op 20, 21 of 22 juni.', 'light_mode', sorted, (a) => onDay(a, 6, [20, 21, 22]), category: w),
    _single('xmas', 'Kerstloop', 'Gelopen op 24, 25 of 26 december.', 'park', sorted, (a) => onDay(a, 12, [24, 25, 26]), category: w),
    _single('nye', 'Oud en nieuw', 'Gelopen op oudejaarsdag of nieuwjaarsdag.', 'celebration', sorted,
        (a) => onDay(a, 12, [31]) || onDay(a, 1, [1]), category: w),
    Badge(
      id: 'seasons',
      title: 'Vier seizoenen',
      description: 'In één kalenderjaar gelopen in winter, lente, zomer en herfst.',
      icon: 'eco',
      earnedAt: allSeasons,
      progress: bestSeasons / 4,
      category: w,
    ),

    // Volhouden.
    _streak('streak4', '4 weken op rij', 'Vier weken achter elkaar minstens één run.', sorted, 4),
    _streak('streak12', '12 weken op rij', 'Drie maanden lang elke week gelopen.', sorted, 12),
    _streak('streak26', '26 weken op rij', 'Een half jaar lang elke week gelopen.', sorted, 26),
    _consecutive('days7', '7 dagen op rij', 'Een week lang elke dag gelopen.', 'event_repeat', sorted, 7, _dayNumber),
    _consecutive('months12', '12 maanden op rij', 'Een jaar lang elke maand minstens één run.', 'calendar_month', sorted, 12, _monthNumber),
    Badge(
      id: 'year1',
      title: 'Een jaar loper',
      description: 'Nog steeds aan het lopen, een jaar na je eerste run.',
      icon: 'cake',
      earnedAt: oneYear,
      progress: (daysSinceFirst / 365).clamp(0, 1).toDouble(),
      category: k,
    ),

    // Ontdekken.
    Badge(
      id: 'explorer',
      title: 'Ontdekker',
      description: 'Op 5 verschillende routes gelopen.',
      icon: 'explore',
      earnedAt: explorer,
      progress: (routes.length / 5).clamp(0, 1).toDouble(),
      category: e,
    ),
    Badge(
      id: 'routes10',
      title: 'Routekenner',
      description: 'Op 10 verschillende routes gelopen.',
      icon: 'explore',
      earnedAt: routes10,
      progress: (routes.length / 10).clamp(0, 1).toDouble(),
      category: e,
    ),
    Badge(
      id: 'routes25',
      title: 'Padvinder',
      description: 'Op 25 verschillende routes gelopen.',
      icon: 'map',
      earnedAt: routes25,
      progress: (routes.length / 25).clamp(0, 1).toDouble(),
      category: e,
    ),
    Badge(
      id: 'places5',
      title: 'Wereldloper',
      description: 'Op 5 plekken gelopen die minstens 10 km uit elkaar liggen.',
      icon: 'travel_explore',
      earnedAt: places.reached,
      progress: (places.count / 5).clamp(0, 1).toDouble(),
      category: e,
    ),
    Badge(
      id: 'far',
      title: 'Op reis',
      description: 'Gelopen op meer dan 50 km van de plek waar je meestal start.',
      icon: 'luggage',
      earnedAt: farAway,
      category: e,
    ),
    _single('mountain', 'Bergloper', 'Minstens 400 hoogtemeters in één run.', 'landscape', sorted, (a) => (a.elevationGainMeters ?? 0) >= 400,
        category: e),
  ];
}

/// Badges die met deze run nieuw verdiend zijn.
List<Badge> newBadges(List<Activity> before, List<Activity> after) {
  final had = {for (final b in computeBadges(before)) if (b.earned) b.id};
  return [for (final b in computeBadges(after)) if (b.earned && !had.contains(b.id)) b];
}
