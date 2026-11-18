import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/weather_service.dart';
import '../../domain/start_time_scoring.dart';
import '../../shared/alarm.dart';
import '../../domain/run_helpers.dart';
import '../../shared/calendar.dart';
import '../../shared/glass.dart';
import '../../shared/art/sun_arc.dart';
import '../../shared/art/weather_icon.dart';
import '../../shared/widgets.dart';
import '../planner/week_planner_screen.dart';
import '../record/record_run_screen.dart';
import '../../domain/verdict.dart';
import 'confidence_chip.dart';
import 'weather_ambience.dart';
import 'hour_bars.dart';
import 'why_sheet.dart';
import 'today_scene.dart';

Color scoreColor(int score) {
  if (score >= 70) return RwColors.good;
  if (score >= 45) return RwColors.warning;
  return RwColors.danger;
}

/// Hoofdkaart: één oordeel, het beste moment en het weer dan (vervangt de losse oordeel-, beste- en nu-kaarten).
class HeroCard extends StatelessWidget {
  const HeroCard({
    required this.verdict,
    required this.shown,
    required this.isBest,
    required this.onShowBest,
    required this.durationMinutes,
    required this.lat,
    required this.lon,
  });
  final int durationMinutes;
  final double lat, lon;
  final RunVerdict verdict;
  final StartTimeScore shown;
  final bool isBest;
  final VoidCallback onShowBest;

  @override
  Widget build(BuildContext context) {
    final v = verdict;
    final (color, label) = switch (v.kind) {
      VerdictKind.goNow => (RwColors.good, 'NU LOPEN'),
      VerdictKind.later => (RwColors.accent, 'LATER LOPEN'),
      VerdictKind.tough => (RwColors.warning, 'LASTIGE DAG'),
    };
    final goNowShown = isBest && v.kind == VerdictKind.goNow;
    // Bij "Nu lopen" gaan dag, weer en cijfers over nú, niet over het (latere) beste moment.
    final s = goNowShown ? v.now : shown;
    final w = s.weather;
    final remindAt = s.start.subtract(Duration(minutes: 15));
    final gain = v.best.score - v.now.score;
    // Redenen die nog niet in de tekst hierboven staan.
    final shownText = isBest ? v.detail.toLowerCase() : '';
    final extraReasons = [
      for (final r in s.reasons)
        if (!r.startsWith('Prima') && !shownText.contains(r.toLowerCase())) r,
    ];
    return Semantics(
      container: true,
      label: '${v.title}. ${v.detail}',
      child: GlassFrame(
        radius: RwRadius.l,
        child: Stack(children: [
          Positioned.fill(child: WeatherAmbience(weather: w, golden: isGoldenHour(s.start, lat, lon))),
          Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  Expanded(child: SectionLabel(isBest ? label : tr('Gekozen moment'), number: 1, color: color)),
                  IconButton(
                    tooltip: tr('Nodig iemand uit om mee te lopen'),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.group_add_outlined, size: 20, color: RwColors.muted),
                    onPressed: () {
                      final when = goNowShown ? 'nu meteen' : '${dayLabel(s.start).toLowerCase()} om ${Fmt.time(s.start)}';
                      SharePlus.instance.share(ShareParams(
                        text: 'Zin om mee te lopen? Volgens Kadans is $when het beste moment: '
                            '${Fmt.temp(w.feelsLike ?? w.temperature)} gevoel, wind ${Fmt.wind(w.windSpeed)}'
                            '${(w.precipitationProbability ?? 0) < 20 ? ', droog' : ', regenkans ${Fmt.pct(w.precipitationProbability)}'}. Doe je mee?',
                      )).ignore();
                    },
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: s.score.toDouble()),
                    duration: Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => Text('${v.round()}',
                        style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800, fontSize: 22, color: scoreColor(s.score))),
                  ),
                  SizedBox(width: 4),
                  Text(s.verdict, style: TextStyle(color: scoreColor(s.score), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            SizedBox(height: 10),
            ExcludeSemantics(
              // Wrap: met grote letters gaat "Morgen / bewolkt" netjes onder de tijd in plaats van letter voor letter.
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 12,
                runSpacing: 4,
                children: [
                  CountClock(
                    time: goNowShown ? null : s.start,
                    style: TextStyle(
                      fontFamily: RwFonts.display, fontFeatures: rwTnum,
                      fontSize: 68,
                      fontWeight: FontWeight.w800,
                      color: RwColors.text,
                      height: 1,
                      letterSpacing: -1.5,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: AnimatedWeatherIcon(code: w.weatherCode, day: w.isDay, size: 40),
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${dayLabel(s.start)}\n${weatherLabel(w.weatherCode)}',
                      style: TextStyle(color: RwColors.muted, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            ConfidenceChip(lat: lat, lon: lon, start: s.start, minutes: durationMinutes, weather: w, isBest: isBest),
            SizedBox(height: 8),
            Text(isBest ? v.detail : 'Je bekijkt ${Fmt.time(s.start)}. Het beste moment is ${Fmt.time(v.best.start)} (score ${v.best.score}).',
                style: TextStyle(color: RwColors.muted, height: 1.4)),
            SizedBox(height: 14),
            FactRow(facts: [
              ('Gevoel', Fmt.temp(w.feelsLike ?? w.temperature)),
              ('Wind', w.windDirection == null ? Fmt.wind(w.windSpeed) : '${w.windSpeed.round()} ${Fmt.compass(w.windDirection!)}'),
              ('Regen', Fmt.pct(w.precipitationProbability)),
            ]),
            if (extraReasons.isNotEmpty) ...[
              SizedBox(height: 4),
              for (final r in extraReasons.take(2))
                Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.info_outline, size: 15, color: RwColors.subtle)),
                      SizedBox(width: 8),
                      Expanded(child: Text(r, style: TextStyle(color: RwColors.muted, fontSize: 13))),
                    ],
                  ),
                ),
            ],
            SizedBox(height: 10),
            // Wanneer ben je terug, en is het dan nog licht?
            Builder(builder: (context) {
              final start = goNowShown ? DateTime.now() : s.start;
              final back = start.add(Duration(minutes: durationMinutes));
              final dark = darkWarning(start, Duration(minutes: durationMinutes), lat, lon);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.home_outlined, size: 16, color: RwColors.subtle),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${goNowShown ? 'Ga je nu' : 'Ga je om ${Fmt.time(start)}'}, dan ben je rond ${Fmt.time(back)} terug ($durationMinutes min).',
                      style: TextStyle(color: RwColors.muted, fontSize: 13),
                    ),
                  ),
                ]),
                if (dark != null)
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.nights_stay_outlined, size: 16, color: RwColors.warning)),
                      SizedBox(width: 6),
                      Expanded(child: Text(dark, style: TextStyle(color: RwColors.warning, fontSize: 13, height: 1.35))),
                    ]),
                  ),
              ]);
            }),
            MoreDetails(child: SunArc(start: s.start, minutes: durationMinutes, lat: lat, lon: lon)),
            SizedBox(height: 12),
            Row(
              children: [
                if (goNowShown)
                  Expanded(
                    // Glas-stijl: de oranje hoofdknop "Start run" zweeft al onderin.
                    child: KadansButton(label: tr('Start run'), icon: Icons.play_arrow, onPressed: () => openRecorder(context)),
                  )
                else if (remindAt.isAfter(DateTime.now()))
                  Expanded(
                    // Secundair (glas met oranje rand): de oranje hoofdknop is "Start run".
                    child: KadansButton(
                      label: 'Wekker ${Fmt.time(remindAt)}',
                      icon: Icons.alarm_add_outlined,
                      onPressed: () async {
                        final ok = await setAlarm(remindAt, 'Kadans: om ${Fmt.time(s.start)} lopen');
                        if (!ok && context.mounted) {
                          showMessage(context, 'Kon geen wekker zetten. Zet hem zelf op ${Fmt.time(remindAt)}.', error: true);
                        }
                      },
                    ),
                  )
                else
                  Expanded(
                    child: KadansButton(label: tr('Start run'), icon: Icons.play_arrow, onPressed: () => openRecorder(context)),
                  ),
                if (!goNowShown) ...[
                  SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: tr('In je agenda zetten'),
                    style: IconButton.styleFrom(
                      minimumSize: Size(52, 52),
                      side: BorderSide(color: RwColors.hairline),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RwRadius.s)),
                    ),
                    onPressed: () => addToCalendar(
                      context,
                      title: tr('Hardlopen (Kadans)'),
                      start: s.start,
                      minutes: durationMinutes,
                      details: 'Beste moment volgens Kadans: score ${s.score}. ${Fmt.temp(w.feelsLike ?? w.temperature)} gevoel, wind ${Fmt.wind(w.windSpeed)}.',
                    ),
                    icon: Icon(Icons.event_available_outlined, color: RwColors.accentLight),
                  ),
                ],
                if (v.kind == VerdictKind.tough) ...[
                  SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => openWeekPlanner(context),
                      child: Text(tr('Betere dag')),
                    ),
                  ),
                ],
              ],
            ),
            if (isBest && v.best.reasons.isNotEmpty)
              Center(
                child: TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: RwColors.subtle),
                  onPressed: () => showWhySheet(context, v),
                  child: Text(tr('Waarom dit moment?')),
                ),
              ),
            if (!isBest)
              Center(child: TextButton(onPressed: onShowBest, child: Text(tr('Terug naar het beste moment'))))
            else if (v.kind != VerdictKind.goNow && gain > 0)
              Padding(
                padding: EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Icon(Icons.directions_run, size: 16, color: RwColors.subtle),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          'Nu vertrekken kan ook: ${gain <= 3 ? 'bijna even goed' : (gain >= 25 ? 'een stuk minder' : 'iets minder')}.'
                          '${whyNotNow(v) == null ? '' : '\n${whyNotNow(v)}.'}',
                          style: TextStyle(color: RwColors.subtle, fontSize: 13)),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: RwColors.accent),
                      onPressed: () => openRecorder(context),
                      child: Text(tr('Toch nu')),
                    ),
                  ],
                ),
              ),
          ],
        ),
          ),
        ]),
      ),
    );
  }
}
