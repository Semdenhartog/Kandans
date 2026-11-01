import '../data/models/models.dart';
import 'badges.dart' show firstPolylinePoint;
import 'geo.dart';
import 'run_helpers.dart' show sunTimes;

/// Automatische runtitel op weer, moment en afstand, bijvoorbeeld "Stormrondje", "Koude ochtendrun",
/// "Rondje bos bij zonsopkomst" of "Oudejaarsrun". [fill] vult {plekken} in (en vertaalt).
String smartTitle(Activity a, {String? routeName, String Function(String, Map<String, Object?>)? fill}) {
  String f(String t, [Map<String, Object?> v = const {}]) =>
      fill != null ? fill(t, v) : v.entries.fold(t, (s, e) => s.replaceAll('{${e.key}}', '${e.value}'));

  // Loopband (opgenomen zonder GPS-spoor en zonder weer).
  if (a.source == 'runwise' && !a.hasTrack && a.temperatureCelsius == null) return f('Loopbandrun');

  final t = a.startedAt.toLocal();
  final km = a.distanceMeters / 1000;
  final wind = a.windSpeedKmh ?? 0;
  final feels = a.feelsLikeCelsius ?? a.temperatureCelsius;
  final p = firstPolylinePoint(a.trackPolyline) ?? const LatLng(52.1, 5.6);
  final sun = sunTimes(t, p.lat, p.lon);
  bool near(DateTime? x) => x != null && t.difference(x.toLocal()).inMinutes.abs() <= 35;

  // Bijzondere dagen.
  final special = switch ((t.month, t.day)) {
    (1, 1) => 'Nieuwjaarsrun',
    (12, 31) => 'Oudejaarsrun',
    (12, 25) || (12, 26) => 'Kerstrun',
    (4, 27) => 'Koningsdagrun',
    _ => null,
  };

  // Het weer of het licht dat de run bijzonder maakte (belangrijkste eerst).
  final String? moment = wind >= 38
      ? 'storm'
      : (feels != null && feels <= -3)
          ? 'vrieskou'
          : (feels != null && feels >= 26)
              ? 'hitte'
              : near(sun.sunrise)
                  ? 'zonsopkomst'
                  : near(sun.sunset)
                      ? 'zonsondergang'
                      : wind >= 26
                          ? 'wind'
                          : (feels != null && feels <= 3)
                              ? 'kou'
                              : null;

  if (routeName != null && routeName.trim().isNotEmpty) {
    final r = routeName.trim();
    return switch (moment) {
      'storm' => f('{route} in de storm', {'route': r}),
      'vrieskou' => f('{route} in de vrieskou', {'route': r}),
      'hitte' => f('{route} in de hitte', {'route': r}),
      'zonsopkomst' => f('{route} bij zonsopkomst', {'route': r}),
      'zonsondergang' => f('{route} bij zonsondergang', {'route': r}),
      'wind' => f('{route} met wind', {'route': r}),
      _ => special != null ? f('{route} ({dag})', {'route': r, 'dag': f(special)}) : r,
    };
  }
  if (special != null) return f(special);

  if (km >= 42) return f('Marathon!');
  if (km >= 21) return f('Halve marathon');
  final part = switch (t.hour) {
    < 6 => 'nacht',
    < 12 => 'ochtend',
    < 17 => 'middag',
    < 22 => 'avond',
    _ => 'nacht',
  };
  final long = km >= 15;
  return switch (moment) {
    'storm' => f('Stormrondje'),
    'vrieskou' => f(long ? 'Lange duurloop in de vrieskou' : 'IJskoude {deel}run', {'deel': f(part)}),
    'hitte' => f(long ? 'Lange duurloop in de hitte' : 'Hete {deel}run', {'deel': f(part)}),
    'zonsopkomst' => f('Run bij zonsopkomst'),
    'zonsondergang' => f('Run bij zonsondergang'),
    'wind' => f(long ? 'Lange duurloop met wind' : 'Winderige {deel}run', {'deel': f(part)}),
    'kou' => f(long ? 'Koude lange duurloop' : 'Koude {deel}run', {'deel': f(part)}),
    _ => long
        ? f('Lange duurloop')
        : switch (part) {
            'ochtend' => f('Ochtendrun'),
            'middag' => f('Middagrun'),
            'avond' => f('Avondrun'),
            _ => f('Nachtrun'),
          },
  };
}
