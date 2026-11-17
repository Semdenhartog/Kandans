import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../domain/run_helpers.dart' show sunTimes;
import '../../data/models/models.dart';
import '../../shared/art/tilt.dart';
import '../../shared/widgets.dart';
import '../../shared/nav_buttons.dart';

/// Binnen een uur van zonsopkomst of -ondergang (gouden uur).
bool isGoldenHour(DateTime t, double lat, double lon) {
  final st = sunTimes(t, lat, lon);
  bool near(DateTime? x) => x != null && t.difference(x).inMinutes.abs() <= 60;
  return near(st.sunrise) || near(st.sunset);
}


/// Mist, buien of grijs: dan past de mistfoto beter dan de zonnige heide.
bool isFoggy(HourWeather? w) {
  if (w == null) return false;
  final c = w.weatherCode ?? 0;
  return c == 3 || c == 45 || c == 48 || (c >= 51 && c <= 67) || (c >= 80 && c <= 82) || (w.precipitationProbability ?? 0) >= 50;
}

/// Het beeld bovenaan Vandaag: een sfeerfoto met daarin je groet en het advies van vandaag.
/// De advieskaart ligt er half overheen.
class TodayScene extends StatelessWidget {
  const TodayScene({required this.greeting, required this.subLine, this.line, this.weather, this.onSpeak, this.overlap = 64, this.peek});
  final String greeting;
  final String subLine;
  final String? line;
  final HourWeather? weather;
  final VoidCallback? onSpeak;
  final double overlap;
  final Widget? peek;

  @override
  Widget build(BuildContext context) {
    final w = weather;
    final night = w != null && !w.isDay;
    final sky = night
        ? [Color(0xFF12151C), Color(0xFF2A2721), Color(0xFF3A3226)]
        : [Color(0xFF4F5A55), Color(0xFF8C8670), Color(0xFFCDB68E)];
    const white = Color(0xFFFFFBF3);
    return Semantics(
      container: true,
      label: '$greeting ${line ?? ''}',
      child: Container(
        constraints: BoxConstraints(minHeight: 250 + overlap),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RwRadius.l),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: sky),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          // Sfeerfoto (zoals op kadans.fit): heide bij droog weer, mist bij mist, buien of grijs weer.
          Positioned.fill(
            child: Image.asset(
              isFoggy(w) ? 'assets/foto/mist.jpg' : 'assets/foto/heide.jpg',
              fit: BoxFit.cover,
              alignment: Alignment(0, -0.1),
              color: night ? Colors.black.withValues(alpha: 0.45) : null,
              colorBlendMode: night ? BlendMode.darken : null,
              errorBuilder: (_, _, _) => SizedBox.shrink(),
            ),
          ),
          // Donker verloop boven- en onderin, zodat de witte tekst altijd leesbaar is (ook in de zon).
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.5), Colors.black.withValues(alpha: 0.05), Colors.transparent],
                  stops: [0, 0.6, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18, 10, 6, 18 + overlap),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(child: Text(subLine.toUpperCase(), maxLines: 2, style: SectionLabel.style(color: white.withValues(alpha: 0.8)).copyWith(fontSize: 10.5))),
                MeButton(color: white),
              ]),
              SizedBox(height: 14),
              StaggerIn(
                index: 0,
                child: Text(greeting,
                    style: TextStyle(
                        fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 34, fontWeight: FontWeight.w700, height: 1.02, letterSpacing: -0.4, color: white)),
              ),
              if (line != null) ...[
                SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(line!, style: TextStyle(fontSize: 15.5, height: 1.4, fontWeight: FontWeight.w500, color: white.withValues(alpha: 0.92))),
                  ),
                  if (onSpeak != null)
                    IconButton(
                      tooltip: tr('Voorlezen'),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.volume_up_outlined, color: white.withValues(alpha: 0.85)),
                      onPressed: onSpeak,
                    ),
                ]),
              ],
            ]),
          ),
          if (peek != null) Positioned(right: 30, bottom: overlap - 4, child: peek!),
        ]),
      ),
    );
  }
}

/// De advieskaart kantelt een fractie mee met de telefoon (3D-gevoel). Uit bij "minder beweging":
/// dan staat de bewegingssensor niet aan.
class TiltCard extends StatelessWidget {
  const TiltCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final inner = RepaintBoundary(child: child);
    return AnimatedBuilder(
      animation: Tilt.instance,
      child: inner,
      builder: (_, c) {
        final t = Tilt.instance.value;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0009)
            ..rotateX(-t.dy * 0.045)
            ..rotateY(t.dx * 0.06),
          child: c,
        );
      },
    );
  }
}

/// Grote tijd die bij verschijnen naar het beste moment toe telt (null = "Nu").
class CountClock extends StatelessWidget {
  const CountClock({required this.time, required this.style});
  final DateTime? time;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final t = time;
    if (t == null) return Text(tr('Nu'), style: style);
    final target = (t.hour * 60 + t.minute).toDouble();
    return CountUpText(
      key: ValueKey(t),
      value: target,
      from: math.max(0, target - 75),
      style: style,
      format: (v) {
        final m = v.round();
        return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
      },
    );
  }
}

/// Drie feiten op een rij tussen dunne lijntjes: label in typemachine-letters, waarde groot.
class FactRow extends StatelessWidget {
  const FactRow({required this.facts});
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.symmetric(horizontal: BorderSide(color: RwColors.hairline)),
        ),
        child: Row(children: [
          for (final (label, value) in facts)
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label.toUpperCase(), style: SectionLabel.style(color: RwColors.subtle).copyWith(fontSize: 11)),
                SizedBox(height: 3),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 19, fontWeight: FontWeight.w700, color: RwColors.text)),
              ]),
            ),
        ]),
      );
}

/// "Meer over dit moment": de zonneboog staat ingeklapt, zodat de kaart rustig blijft.
class MoreDetails extends StatefulWidget {
  const MoreDetails({required this.child});
  final Widget child;

  @override
  State<MoreDetails> createState() => MoreDetailsState();
}

class MoreDetailsState extends State<MoreDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: RwColors.muted, padding: EdgeInsets.zero),
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(_open ? Icons.expand_less : Icons.wb_twilight_outlined, size: 18),
            label: Text(_open ? 'Minder' : 'Zon en licht'),
          ),
        ),
        AnimatedSize(
          duration: Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _open ? widget.child : SizedBox(width: double.infinity),
        ),
      ]);
}

/// "§ 02 Deze week": je trainingen van de komende dagen als veegrij, met een randje van de volgende kaart.
/// Binnen de weersverwachting (36 uur) staat het beste moment erbij. Zonder schema: één knop naar Deze week.
