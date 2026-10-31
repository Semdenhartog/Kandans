import 'dart:math' as math;

import '../data/models/models.dart';
import 'badges.dart' show firstPolylinePoint;
import 'geo.dart';
import 'run_helpers.dart' show sunTimes;

/// Loop-bingo: elke maand negen vakjes met kleine opdrachten (het midden is gratis).
/// Iedereen krijgt in dezelfde maand dezelfde kaart, zodat je hem kunt vergelijken.

class BingoTask {
  const BingoTask(this.id, this.label, this.hint, {this.months});
  final String id;

  /// Kort, past in een vakje.
  final String label;

  /// Uitleg als je op het vakje tikt.
  final String hint;

  /// Alleen in deze maanden (null = altijd).
  final Set<int>? months;
}

const bingoTasks = <BingoTask>[
  BingoTask('dark', 'In het donker', 'Loop vóór zonsopkomst of na zonsondergang.'),
  BingoTask('wind', 'Wind 25+', 'Loop met wind van 25 km/u of meer.'),
  BingoTask('cold', 'Gevoel 3° of kouder', 'Loop als het 3 graden of kouder aanvoelt.', months: {11, 12, 1, 2, 3}),
  BingoTask('warm', 'Gevoel 20°+', 'Loop als het 20 graden of warmer aanvoelt.', months: {5, 6, 7, 8, 9}),
  BingoTask('ten', '10 km', 'Loop 10 kilometer of meer in één keer.'),
  BingoTask('long', '45 minuten', 'Loop 45 minuten of langer.'),
  BingoTask('short', 'Rondje ≤ 4 km', 'Een kort rondje van hooguit 4 kilometer telt ook.'),
  BingoTask('week3', '3× in een week', 'Loop 3 keer in dezelfde week (maandag t/m zondag).'),
  BingoTask('weekend', 'Weekend vóór 9:00', 'Loop op zaterdag of zondag en start vóór 9 uur.'),
  BingoTask('early', 'Vóór 7:00', 'Start een run vóór 7 uur \'s ochtends.'),
  BingoTask('evening', 'Na 20:00', 'Start een run na 8 uur \'s avonds.'),
  BingoTask('twoDays', '2 dagen op rij', 'Loop twee dagen achter elkaar.'),
  BingoTask('newRoute', 'Nieuwe route', 'Loop een route die je nog nooit hebt gelopen.'),
  BingoTask('climb', '40 hoogtemeters', 'Loop een run met 40 hoogtemeters of meer.'),
  BingoTask('photo', 'Foto onderweg', 'Bewaar een foto bij een run.'),
  BingoTask('top', 'Voelde top', 'Geef een run de beoordeling "top".'),
  BingoTask('wise', 'Goed gekozen', 'Loop op een moment dat Kadans achteraf goed gekozen noemt.'),
  BingoTask('hr', 'Met hartslag', 'Loop met een hartslagmeter of horloge.'),
];

class BingoCell {
  const BingoCell(this.task, {this.doneAt});

  /// null = het gratis vakje in het midden.
  final BingoTask? task;
  final DateTime? doneAt;

  bool get free => task == null;
  bool get done => free || doneAt != null;
}

class BingoCard {
  const BingoCard(this.month, this.cells);
  final DateTime month;
  final List<BingoCell> cells;

  static const _lines = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8], // rijen
    [0, 3, 6], [1, 4, 7], [2, 5, 8], // kolommen
    [0, 4, 8], [2, 4, 6], // diagonalen
  ];

  /// Aantal volle rijen, kolommen en diagonalen.
  int get lines => _lines.where((l) => l.every((i) => cells[i].done)).length;
  int get doneCount => cells.where((c) => c.done && !c.free).length;
  bool get full => cells.every((c) => c.done);

  /// Indexen van de vakjes die in een volle lijn liggen.
  Set<int> get winning => {
        for (final l in _lines)
          if (l.every((i) => cells[i].done)) ...l,
      };
}

/// De acht opdrachten van deze maand (vast per maand, zelfde voor iedereen).
List<BingoTask> bingoTasksFor(DateTime month) {
  final pool = [for (final t in bingoTasks) if (t.months == null || t.months!.contains(month.month)) t];
  pool.shuffle(math.Random(month.year * 100 + month.month));
  return pool.take(8).toList();
}

BingoCard bingoFor(DateTime month, List<Activity> all, {Set<String> wellChosen = const {}}) {
  final m = DateTime(month.year, month.month);
  final next = DateTime(m.year, m.month + 1);
  final local = [for (final a in all) (a, a.startedAt.toLocal())]..sort((x, y) => x.$2.compareTo(y.$2));
  final inMonth = [for (final e in local) if (!e.$2.isBefore(m) && e.$2.isBefore(next)) e];

  // Routes die vóór deze maand al gelopen waren.
  final oldRoutes = {for (final e in local) if (e.$2.isBefore(m) && e.$1.routeId != null) e.$1.routeId!};

  DateTime? first(bool Function(Activity a, DateTime t) test) {
    for (final (a, t) in inMonth) {
      if (test(a, t)) return t;
    }
    return null;
  }

  double? feels(Activity a) => a.feelsLikeCelsius ?? a.temperatureCelsius;

  bool dark(Activity a, DateTime t) {
    final p = firstPolylinePoint(a.trackPolyline) ?? const LatLng(52.1, 5.3);
    final s = sunTimes(t, p.lat, p.lon);
    final end = t.add(Duration(seconds: a.movingTimeSeconds));
    return (s.sunrise != null && t.isBefore(s.sunrise!)) || (s.sunset != null && end.isAfter(s.sunset!.add(const Duration(minutes: 10))));
  }

  DateTime? week3() {
    final perWeek = <DateTime, List<DateTime>>{};
    for (final (_, t) in inMonth) {
      final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
      (perWeek[monday] ??= []).add(t);
    }
    DateTime? best;
    for (final ts in perWeek.values) {
      if (ts.length >= 3 && (best == null || ts[2].isBefore(best))) best = ts[2];
    }
    return best;
  }

  DateTime? twoDays() {
    for (var i = 1; i < inMonth.length; i++) {
      final a = inMonth[i - 1].$2, b = inMonth[i].$2;
      final da = DateTime(a.year, a.month, a.day), db = DateTime(b.year, b.month, b.day);
      final h = db.difference(da).inHours;
      if (h >= 23 && h <= 25) return b;
    }
    return null;
  }

  DateTime? check(BingoTask task) => switch (task.id) {
        'dark' => first(dark),
        'wind' => first((a, _) => (a.windSpeedKmh ?? 0) >= 25),
        'cold' => first((a, _) => (feels(a) ?? 99) <= 3),
        'warm' => first((a, _) => (feels(a) ?? -99) >= 20),
        'ten' => first((a, _) => a.distanceMeters >= 10000),
        'long' => first((a, _) => a.movingTimeSeconds >= 45 * 60),
        'short' => first((a, _) => a.distanceMeters > 500 && a.distanceMeters <= 4000),
        'week3' => week3(),
        'weekend' => first((_, t) => t.weekday >= DateTime.saturday && t.hour < 9),
        'early' => first((_, t) => t.hour < 7),
        'evening' => first((_, t) => t.hour >= 20),
        'twoDays' => twoDays(),
        'newRoute' => first((a, _) => a.routeId != null && !oldRoutes.contains(a.routeId)),
        'climb' => first((a, _) => (a.elevationGainMeters ?? 0) >= 40),
        'photo' => first((a, _) => a.photos.isNotEmpty),
        'top' => first((a, _) => a.feel == 3),
        'wise' => first((a, _) => a.id != null && wellChosen.contains(a.id)),
        'hr' => first((a, _) => a.averageHeartRate != null),
        _ => null,
      };

  final tasks = bingoTasksFor(m);
  final cells = <BingoCell>[
    for (final t in tasks.take(4)) BingoCell(t, doneAt: check(t)),
    const BingoCell(null),
    for (final t in tasks.skip(4)) BingoCell(t, doneAt: check(t)),
  ];
  return BingoCard(m, cells);
}
