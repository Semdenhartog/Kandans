import 'dart:math' as math;

import '../data/models/models.dart';

/// Terugblik na je run: was dit een goed moment, vergeleken met de rest van die dag?
/// Maakt de belofte van Kadans ("loop op het beste moment") zichtbaar na afloop.
class Hindsight {
  const Hindsight({required this.title, required this.text, required this.good, this.rainAvoided = 0, this.heatAvoided = 0});
  final String title;
  final String text;

  /// true = goed gekozen (groen), false = een ander moment was beter (tip).
  final bool good;

  /// Regen (mm) die je ontliep vergeleken met het natste andere moment van die dag.
  final double rainAvoided;

  /// Graden (gevoel) die je ontliep vergeleken met het warmste andere moment, alleen op warme dagen.
  final double heatAvoided;

  Hindsight _with(double rain, double heat) =>
      Hindsight(title: title, text: text, good: good, rainAvoided: rain, heatAvoided: heat);
}

class _Window {
  _Window(this.start, this.rain, this.feels, this.wind);
  final DateTime start;
  final double rain;
  final double feels;
  final double wind;

  /// Hoe ongunstig (0 = ideaal). Regen weegt het zwaarst, dan hitte, kou en wind.
  double get penalty =>
      rain * 12 + math.max(0, feels - 16) * 1.6 + math.max(0, 2 - feels) * 1.0 + math.max(0, wind - 18) * 0.5;
}

/// Weer over een run van [minutes] minuten die om [start] begint (uurwaarden, gewogen naar overlap).
_Window? _window(List<HourWeather> day, DateTime start, int minutes) {
  final end = start.add(Duration(minutes: minutes));
  var rain = 0.0, feels = -100.0, wind = 0.0, covered = 0.0;
  for (final h in day) {
    final hs = h.time, he = h.time.add(const Duration(hours: 1));
    final s = start.isAfter(hs) ? start : hs, e = end.isBefore(he) ? end : he;
    final overlap = e.difference(s).inMinutes / 60;
    if (overlap <= 0) continue;
    covered += overlap;
    rain += (h.precipitation ?? 0) * overlap;
    feels = math.max(feels, h.feelsLike ?? h.temperature);
    wind = math.max(wind, h.windSpeed);
  }
  if (covered < minutes / 60 * 0.8) return null;
  return _Window(start, rain, feels, wind);
}

String _hh(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
String _mm(double v) => v < 1 ? v.toStringAsFixed(1).replaceAll('.', ',') : v.round().toString();

/// Vergelijkt jouw run met elk ander heel uur die dag (tussen [earliest] en [latest] uur).
/// Null als er te weinig weerdata is.
Hindsight? hindsight(List<HourWeather> day, DateTime start, int minutes, {int earliest = 6, int latest = 22}) {
  final r = _hindsight(day, start, minutes, earliest, latest);
  if (r == null) return null;
  final mine = _window(day, start, minutes)!;
  final d0 = DateTime(start.year, start.month, start.day);
  final others = [
    for (var h = earliest; h * 60 + minutes <= latest * 60; h++)
      if (_window(day, d0.add(Duration(hours: h)), minutes) case final w?) w,
  ];
  final wettest = others.fold<double>(0, (m, w) => math.max(m, w.rain));
  final hottest = others.fold<double>(-100, (m, w) => math.max(m, w.feels));
  return r._with(
    math.max(0, wettest - mine.rain),
    hottest >= 20 ? math.max(0, hottest - mine.feels) : 0,
  );
}

Hindsight? _hindsight(List<HourWeather> day, DateTime start, int minutes, int earliest, int latest) {
  if (minutes < 10) return null;
  final mine = _window(day, start, minutes);
  if (mine == null) return null;
  final d0 = DateTime(start.year, start.month, start.day);
  final others = <_Window>[
    for (var h = earliest; h * 60 + minutes <= latest * 60; h++)
      if (_window(day, d0.add(Duration(hours: h)), minutes) case final w?)
        if (w.start.difference(start).inMinutes.abs() >= minutes) w,
  ];
  if (others.length < 3) return null;

  // 1. Droog gebleven terwijl het op een ander moment flink regende.
  final wettest = others.reduce((a, b) => b.rain > a.rain ? b : a);
  if (mine.rain < 0.2 && wettest.rain >= 1.0) {
    return Hindsight(
      title: 'Droog gebleven',
      text: 'Om ${_hh(wettest.start)} viel er ${_mm(wettest.rain)} mm regen. Jij liep droog.',
      good: true,
      rainAvoided: wettest.rain - mine.rain,
    );
  }

  // Het beste andere moment, liefst niet al te ver van jouw tijd (±4 uur).
  final near = others.where((w) => w.start.difference(start).inHours.abs() <= 4).toList();
  final pool = near.length >= 2 ? near : others;
  final best = pool.reduce((a, b) => b.penalty < a.penalty ? b : a);

  // 2. Nat geworden terwijl het kort ervoor of erna droog was.
  if (mine.rain >= 0.5 && best.rain < 0.1) {
    return Hindsight(
      title: 'Om ${_hh(best.start)} was het droog',
      text: 'Jij kreeg ${_mm(mine.rain)} mm regen op je hoofd. Kijk voor je volgende run even op Vandaag: '
          'Kadans rekent de buien mee.',
      good: false,
    );
  }

  // 3. Warm gelopen terwijl het koeler kon.
  if (mine.feels >= 22 && best.feels <= mine.feels - 4) {
    return Hindsight(
      title: 'Om ${_hh(best.start)} was het ${(mine.feels - best.feels).round()} °C koeler',
      text: 'Jij liep bij ${mine.feels.round()} °C gevoel. Bij warmte zijn de vroege ochtend en de avond meestal het fijnst.',
      good: false,
    );
  }

  // 4. Harde wind terwijl het rustiger kon.
  if (mine.wind >= 28 && best.wind <= mine.wind - 12) {
    return Hindsight(
      title: 'Om ${_hh(best.start)} waaide het veel minder',
      text: 'Jij had wind tot ${mine.wind.round()} km/u, om ${_hh(best.start)} ${best.wind.round()} km/u.',
      good: false,
    );
  }

  // 5. Zat je bij de beste momenten van de dag?
  final better = others.where((w) => w.penalty < mine.penalty - 1).length;
  if (better <= others.length / 4) {
    return Hindsight(
      title: 'Goed gekozen',
      text: better == 0
          ? 'Dit was het fijnste loopweer van de hele dag.'
          : 'Je liep op een van de fijnste momenten van de dag.',
      good: true,
    );
  }
  return null;
}
