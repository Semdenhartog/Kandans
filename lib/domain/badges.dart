import '../data/models/models.dart';
import 'weekly_load.dart';

/// Een badge (mijlpaal). [progress] 0..1 voor badges die je nog niet hebt.
class Badge {
  const Badge({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.earnedAt,
    this.progress = 0,
    this.weather = false,
  });

  final String id;
  final String title;
  final String description;

  /// Naam van een Material-icoon (de app kiest het plaatje).
  final String icon;
  final DateTime? earnedAt;
  final double progress;

  /// RunWise-badges voor lopen in bijzonder weer.
  final bool weather;

  bool get earned => earnedAt != null;
}

Badge _single(String id, String title, String desc, String icon, List<Activity> runs, bool Function(Activity) test,
    {bool weather = false}) {
  final hits = runs.where(test).toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  return Badge(id: id, title: title, description: desc, icon: icon, earnedAt: hits.isEmpty ? null : hits.first.startedAt, weather: weather);
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
  return Badge(id: id, title: title, description: desc, icon: 'local_fire_department', earnedAt: earned, progress: (best / weeks).clamp(0, 1).toDouble());
}

/// Alle badges met je voortgang.
List<Badge> computeBadges(List<Activity> runs) {
  final sorted = [...runs]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final routes = <String>{};
  DateTime? explorer;
  for (final a in sorted) {
    if (a.routeId != null && routes.add(a.routeId!) && routes.length == 5) explorer = a.startedAt;
  }
  return [
    _single('first', 'Eerste stap', 'Je eerste run in RunWise.', 'flag', sorted, (_) => true),
    _single('5k', '5 kilometer', 'Een run van 5 km of meer.', 'looks_5', sorted, (a) => a.distanceMeters >= 4950),
    _single('10k', '10 kilometer', 'Een run van 10 km of meer.', 'filter_9_plus', sorted, (a) => a.distanceMeters >= 9900),
    _single('half', 'Halve marathon', 'Een run van 21,1 km of meer.', 'military_tech', sorted, (a) => a.distanceMeters >= 21000),
    _single('full', 'Marathon', 'Een run van 42,2 km of meer.', 'emoji_events', sorted, (a) => a.distanceMeters >= 42000),
    _total('runs10', '10 runs', 'Tien keer gelopen.', 'directions_run', sorted, 10, (_) => 1),
    _total('runs50', '50 runs', 'Vijftig keer gelopen.', 'directions_run', sorted, 50, (_) => 1),
    _total('runs100', '100 runs', 'Honderd keer gelopen!', 'directions_run', sorted, 100, (_) => 1),
    _total('km100', '100 km', 'In totaal 100 kilometer.', 'route', sorted, 100, (a) => a.distanceMeters / 1000),
    _total('km500', '500 km', 'In totaal 500 kilometer.', 'route', sorted, 500, (a) => a.distanceMeters / 1000),
    _total('km1000', '1000 km', 'In totaal 1000 kilometer. Wauw.', 'public', sorted, 1000, (a) => a.distanceMeters / 1000),
    _streak('streak4', '4 weken op rij', 'Vier weken achter elkaar minstens één run.', sorted, 4),
    _streak('streak12', '12 weken op rij', 'Drie maanden lang elke week gelopen.', sorted, 12),
    _single('early', 'Vroege vogel', 'Een run gestart voor 7:00.', 'wb_twilight', sorted, (a) => a.startedAt.toLocal().hour < 7),
    _single('night', 'Nachtloper', 'Een run gestart na 21:00.', 'nightlight', sorted, (a) => a.startedAt.toLocal().hour >= 21),
    _single('climb', 'Klimmer', 'Minstens 150 hoogtemeters in één run.', 'terrain', sorted, (a) => (a.elevationGainMeters ?? 0) >= 150),
    Badge(
      id: 'explorer',
      title: 'Ontdekker',
      description: 'Op 5 verschillende routes gelopen.',
      icon: 'explore',
      earnedAt: explorer,
      progress: (routes.length / 5).clamp(0, 1).toDouble(),
    ),
    // RunWise-weerbadges.
    _single('wind', 'Windtrotser', 'Gelopen met 30 km/u wind of meer.', 'air', sorted, (a) => (a.windSpeedKmh ?? 0) >= 30, weather: true),
    _single('storm', 'Stormloper', 'Gelopen met 45 km/u wind of meer.', 'storm', sorted, (a) => (a.windSpeedKmh ?? 0) >= 45, weather: true),
    _single('heat', 'Hittebestendig', 'Gelopen bij 25 °C of warmer.', 'local_fire_department', sorted,
        (a) => (a.feelsLikeCelsius ?? a.temperatureCelsius ?? 0) >= 25, weather: true),
    _single('frost', 'IJsloper', 'Gelopen bij een gevoelstemperatuur onder 0 °C.', 'ac_unit', sorted,
        (a) => (a.feelsLikeCelsius ?? a.temperatureCelsius ?? 99) < 0, weather: true),
    _single('humid', 'Klamme kilometers', 'Gelopen bij 90% luchtvochtigheid of meer.', 'water_drop', sorted,
        (a) => (a.humidityPct ?? 0) >= 90, weather: true),
  ];
}

/// Badges die met deze run nieuw verdiend zijn.
List<Badge> newBadges(List<Activity> before, List<Activity> after) {
  final had = {for (final b in computeBadges(before)) if (b.earned) b.id};
  return [for (final b in computeBadges(after)) if (b.earned && !had.contains(b.id)) b];
}
