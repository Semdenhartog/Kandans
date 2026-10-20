import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/best_efforts.dart';
import '../../domain/year_recap.dart';
import 'run_insights_screens.dart' show openYearRecap;

void openYearStory(BuildContext context, {int? year}) {
  Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (_, _, _) => YearStoryScreen(year: year ?? DateTime.now().year),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ));
}

const _months = ['januari', 'februari', 'maart', 'april', 'mei', 'juni', 'juli', 'augustus', 'september', 'oktober', 'november', 'december'];
const _days = ['maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'];

/// Leuke vergelijking voor je kilometers.
String kmComparison(double km) {
  if (km >= 1200) return 'Dat is verder dan van Den Helder naar Rome, ongeveer ${(km / 1300).toStringAsFixed(1).replaceAll('.', ',')} keer.';
  if (km >= 500) return 'Dat is meer dan van Amsterdam naar Parijs: ${(km / 500).toStringAsFixed(1).replaceAll('.', ',')} keer.';
  if (km >= 200) return 'Dat is de hele kust van Nederland af, van Cadzand tot Den Helder (${(km / 250 * 100).round()}%).';
  if (km >= 32) return 'Dat is ${(km / 32).floor()} keer de Afsluitdijk over.';
  return 'Elke kilometer telt. Volgend jaar nog meer!';
}

/// Het jaaroverzicht als verhaal (zoals Spotify Wrapped): kaarten die vanzelf doorgaan.
class YearStoryScreen extends ConsumerStatefulWidget {
  const YearStoryScreen({super.key, required this.year});
  final int year;

  @override
  ConsumerState<YearStoryScreen> createState() => _YearStoryScreenState();
}

class _YearStoryScreenState extends ConsumerState<YearStoryScreen> with SingleTickerProviderStateMixin {
  late final _progress = AnimationController(vsync: this, duration: const Duration(seconds: 6))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
  int _page = 0;
  int _count = 1;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _progress.forward();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _progress.dispose();
    super.dispose();
  }

  void _go(int p) {
    if (p < 0) p = 0;
    if (p >= _count) {
      _progress.stop();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _page = p);
    _progress
      ..reset()
      ..forward();
  }

  void _next() => _go(_page + 1);

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final r = yearRecap(all, widget.year);
    final yearRuns = all.where((a) => a.startedAt.toLocal().year == widget.year).toList();
    final slides = r == null ? [_Slide.empty(widget.year)] : _slides(r, yearRuns);
    _count = slides.length;
    final s = slides[_page.clamp(0, slides.length - 1)];
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => d.globalPosition.dx < MediaQuery.sizeOf(context).width / 3 ? _go(_page - 1) : _next(),
        onLongPressStart: (_) => _progress.stop(),
        onLongPressEnd: (_) => _progress.forward(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: s.colors),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Row(children: [
                    for (var i = 0; i < slides.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: AnimatedBuilder(
                              animation: _progress,
                              builder: (_, _) => LinearProgressIndicator(
                                value: i < _page ? 1 : (i == _page ? _progress.value : 0),
                                minHeight: 3,
                                color: Colors.white,
                                backgroundColor: Colors.white24,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
                Row(children: [
                  const SizedBox(width: 16),
                  Text('RunWise · ${widget.year}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Sluiten',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ]),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(key: ValueKey(_page), child: Padding(padding: const EdgeInsets.all(28), child: s.body)),
                  ),
                ),
                if (_page == slides.length - 1 && r != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                      onPressed: () {
                        Navigator.pop(context);
                        openYearRecap(context);
                      },
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Deel je jaar'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_Slide> _slides(YearRecap r, List<Activity> runs) {
    final coldest = runs.where((a) => (a.feelsLikeCelsius ?? a.temperatureCelsius) != null).fold<Activity?>(
        null, (m, a) => m == null || (a.feelsLikeCelsius ?? a.temperatureCelsius)! < (m.feelsLikeCelsius ?? m.temperatureCelsius)! ? a : m);
    final windiest = runs.where((a) => a.windSpeedKmh != null).fold<Activity?>(null, (m, a) => m == null || a.windSpeedKmh! > m.windSpeedKmh! ? a : m);
    final hottest = runs.where((a) => (a.feelsLikeCelsius ?? a.temperatureCelsius) != null).fold<Activity?>(
        null, (m, a) => m == null || (a.feelsLikeCelsius ?? a.temperatureCelsius)! > (m.feelsLikeCelsius ?? m.temperatureCelsius)! ? a : m);
    final fast = r.fastest.entries.where((e) => const [1000, 5000, 10000, 21098].contains(e.key)).toList();
    final maxM = r.perMonthKm.fold<double>(1, (a, b) => a > b ? a : b);
    return [
      _Slide(
        colors: const [Color(0xFF2A0E05), Colors.black],
        body: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Small('Klaar voor je jaar?'),
          _Big('${r.year}', size: 120, color: RwColors.accent),
          const _Text('Een jaar vol kilometers, weer en wind. Tik om verder te gaan.'),
        ]),
      ),
      _Slide(
        colors: const [RwColors.accentDeep, Color(0xFF6B1A0B)],
        body: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Small('Je liep dit jaar'),
          _Count(r.km, decimals: 0, suffix: ' km', size: 96),
          const SizedBox(height: 12),
          _Text(kmComparison(r.km)),
        ]),
      ),
      _Slide(
        colors: const [Color(0xFF141417), Color(0xFF2B1A10)],
        body: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Small('Je ging'),
          _Count(r.runs.toDouble(), suffix: ' keer', size: 80),
          const _Small('de deur uit, samen'),
          _Count(r.seconds / 3600, suffix: ' uur', size: 80, color: RwColors.accent),
          const SizedBox(height: 12),
          _Text('Op ${r.daysRun} verschillende dagen. ${r.elevation >= 100 ? 'En ${r.elevation.round()} meter omhoog.' : ''}'),
        ]),
      ),
      _Slide(
        colors: const [Color(0xFF0E1A2B), Colors.black],
        body: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Small('Je drukste maand'),
          _Big(_months[r.bestMonth - 1], size: 56),
          _Text('${r.bestMonthKm.round()} km in één maand.'),
          const SizedBox(height: 24),
          SizedBox(
            height: 140,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (_, t, _) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var m = 0; m < 12; m++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Container(
                        height: 6 + 120 * (r.perMonthKm[m] / maxM) * t,
                        decoration: BoxDecoration(
                          color: m == r.bestMonth - 1 ? RwColors.accent : Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ]),
      ),
      _Slide(
        colors: const [Color(0xFF1A1A1F), Color(0xFF3A2A12)],
        body: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Small('Jouw ritme'),
          _Big('Op ${_days[r.favouriteWeekday - 1]}', size: 48),
          _Big('in de ${r.favouritePartOfDay}', size: 40, color: RwColors.accent),
          const SizedBox(height: 12),
          _Text(r.longestStreakWeeks >= 2 ? 'Je langste reeks: ${r.longestStreakWeeks} weken op rij gelopen.' : 'Volgend jaar: kun jij een paar weken op rij?'),
        ]),
      ),
      if (coldest != null || windiest != null)
        _Slide(
          colors: const [Color(0xFF0C2233), Color(0xFF091017)],
          body: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _Small('Weer of geen weer'),
            if (coldest != null)
              _WeatherLine(Icons.ac_unit, 'Koudste run', '${Fmt.temp(coldest.feelsLikeCelsius ?? coldest.temperatureCelsius)} gevoel', Fmt.date(coldest.startedAt)),
            if (hottest != null && hottest != coldest)
              _WeatherLine(Icons.wb_sunny_outlined, 'Warmste run', '${Fmt.temp(hottest.feelsLikeCelsius ?? hottest.temperatureCelsius)} gevoel', Fmt.date(hottest.startedAt)),
            if (windiest != null)
              _WeatherLine(Icons.air, 'Hardste wind', Fmt.wind(windiest.windSpeedKmh), Fmt.date(windiest.startedAt)),
            const SizedBox(height: 12),
            const _Text('Alleen RunWise houdt bij in wat voor weer jij liep.'),
          ]),
        ),
      if (r.longest != null || fast.isNotEmpty)
        _Slide(
          colors: const [Color(0xFF2B1206), Colors.black],
          body: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _Small('Je hoogtepunten'),
            if (r.longest != null) ...[
              _Count(r.longest!.distanceMeters / 1000, decimals: 1, suffix: ' km', size: 72, color: RwColors.accent),
              _Text('Je langste run, op ${Fmt.dateLong(r.longest!.startedAt)}.'),
              const SizedBox(height: 20),
            ],
            for (final e in fast)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const Icon(Icons.emoji_events, color: RwColors.accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Snelste ${bestEffortLabel(e.key)}', style: const TextStyle(color: Colors.white70, fontSize: 16))),
                  Text(Fmt.duration(e.value),
                      style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800, fontSize: 22, color: Colors.white)),
                ]),
              ),
          ]),
        ),
      _Slide(
        colors: const [RwColors.accent, RwColors.accentDeep],
        body: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Small('Dat was je', dark: true),
          _Big('${r.year}', size: 110, color: Colors.black),
          _Text('${r.km.round()} km · ${r.runs} runs · ${(r.seconds / 3600).round()} uur', dark: true),
          const SizedBox(height: 12),
          const _Text('Op naar het volgende jaar. Loop op het beste moment!', dark: true),
        ]),
      ),
    ];
  }
}

class _Slide {
  const _Slide({required this.colors, required this.body});
  final List<Color> colors;
  final Widget body;

  factory _Slide.empty(int year) => _Slide(
        colors: const [Color(0xFF141417), Colors.black],
        body: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Big('$year', size: 96, color: RwColors.accent),
          const _Text('Nog geen runs dit jaar. Zodra je loopt, maken we hier je verhaal.'),
        ]),
      );
}

class _Small extends StatelessWidget {
  const _Small(this.text, {this.dark = false});
  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: dark ? Colors.black87 : Colors.white70, fontSize: 20, fontWeight: FontWeight.w600));
}

class _Big extends StatelessWidget {
  const _Big(this.text, {this.size = 64, this.color = Colors.white});
  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text,
            maxLines: 1,
            style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: size, fontWeight: FontWeight.w800, color: color, height: 1.05)),
      );
}

class _Text extends StatelessWidget {
  const _Text(this.text, {this.dark = false});
  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: dark ? Colors.black : Colors.white, fontSize: 18, height: 1.4, fontWeight: FontWeight.w500));
}

/// Getal dat optelt bij het verschijnen van de kaart.
class _Count extends StatelessWidget {
  const _Count(this.value, {this.decimals = 0, this.suffix = '', this.size = 80, this.color = Colors.white});
  final double value;
  final int decimals;
  final String suffix;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 1500),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => _Big('${v.toStringAsFixed(decimals).replaceAll('.', ',')}$suffix', size: size, color: color),
      );
}

class _WeatherLine extends StatelessWidget {
  const _WeatherLine(this.icon, this.label, this.value, this.date);
  final IconData icon;
  final String label;
  final String value;
  final String date;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(icon, color: const Color(0xFF7CC4FF), size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 15)),
              Text(value, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800, fontSize: 32, color: Colors.white)),
            ]),
          ),
          Text(date, style: const TextStyle(color: Colors.white54)),
        ]),
      );
}
