import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../domain/clothing.dart';
import '../../domain/geo.dart';
import '../../domain/route_direction.dart';
import '../../domain/start_time_scoring.dart';
import '../../domain/run_warnings.dart';
import '../../shared/widgets.dart';
import '../profile/sources_screen.dart';

class RouteWindCard extends StatelessWidget {
  const RouteWindCard({required this.score, required this.track});
  final StartTimeScore score;
  final List<LatLng> track;

  @override
  Widget build(BuildContext context) {
    final rw = score.routeWind!;
    final diff = rw.secondHalfHead - rw.firstHalfHead;
    final String text;
    if (rw.headwindAvg < 5) {
      text = 'Weinig tegenwind op je route. Lekker lopen!';
    } else if (diff > 4) {
      text = 'Let op: tegenwind op de terugweg (gem. ${rw.secondHalfHead.round()} km/u). '
          'Loop de eerste helft rustig, zodat je energie overhoudt.';
    } else if (diff < -4) {
      text = 'Tegenwind in de eerste helft (gem. ${rw.firstHalfHead.round()} km/u), '
          'rugwind op de terugweg. Start rustig, je haalt het terug.';
    } else {
      text = 'De tegenwind is gelijk verdeeld over je route (gem. ${rw.headwindAvg.round()} km/u).';
    }
    final w = score.weather;
    final advice = adviseDirection(track, w.windSpeed, w.windDirection);
    return RwCard(
      title: tr('WIND OP JE ROUTE'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (advice != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  advice.bestLabel == 'linksom' ? Icons.rotate_left : Icons.rotate_right,
                  color: RwColors.accent,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(advice.text, style: TextStyle(height: 1.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            SizedBox(height: 10),
          ],
          Text(text, style: TextStyle(height: 1.5, color: RwColors.muted)),
        ],
      ),
    );
  }
}

/// Wat je aantrekt voor het gekozen vertrekmoment.
class ClothingCard extends StatelessWidget {
  const ClothingCard({required this.advice, required this.at});
  final ClothingAdvice advice;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    return RwCard(
      title: 'AANTREKKEN OM ${Fmt.time(at)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(advice.summary, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in advice.items)
                Container(
                  padding: EdgeInsets.fromLTRB(8, 6, 12, 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [RwColors.surface, RwColors.surfaceHigh]),
                    border: Border.all(color: RwColors.hairline),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(clothingIcon(item), size: 16, color: RwColors.accentLight),
                    SizedBox(width: 6),
                    Flexible(child: Text(item, style: TextStyle(fontSize: 13))),
                  ]),
                ),
            ],
          ),
          for (final tip in advice.extras)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: RwColors.accent),
                  SizedBox(width: 8),
                  Expanded(child: Text(tip, style: TextStyle(color: RwColors.muted, height: 1.4))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}


/// Live buien voor de komende 2 uur, per 5 minuten (Buienradar).
class RainCard extends StatelessWidget {
  const RainCard({required this.rain});
  final RainNowcast rain;

  String get _summary {
    final firstRain = rain.firstRain;
    if (rain.rainingNow) {
      final dry = rain.firstDry;
      return dry == null ? 'Het regent de komende 2 uur.' : 'Het regent nu; droog vanaf ${Fmt.time(dry)}.';
    }
    if (firstRain == null) return 'Droog de komende 2 uur.';
    return 'Droog tot ${Fmt.time(firstRain)}, daarna buien.';
  }

  @override
  Widget build(BuildContext context) {
    final maxMm = rain.points.fold<double>(1, (m, p) => p.mmPerHour > m ? p.mmPerHour : m);
    return RwCard(
      title: tr('BUIEN KOMENDE 2 UUR · LIVE'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_summary, style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final p in rain.points)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 1),
                      child: FractionallySizedBox(
                        alignment: Alignment.bottomCenter,
                        heightFactor: p.mmPerHour < 0.1 ? 0.06 : (0.2 + 0.8 * (p.mmPerHour / maxMm)).clamp(0.2, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: p.mmPerHour < 0.1 ? RwColors.bar : Color(0xFF5AA9FF),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Text(Fmt.time(rain.points.first.time), style: TextStyle(fontSize: 11, color: RwColors.subtle)),
              Spacer(),
              Text(Fmt.time(rain.points.last.time), style: TextStyle(fontSize: 11, color: RwColors.subtle)),
            ],
          ),
          SizedBox(height: 8),
          SourcesLink(prefix: 'Bijgewerkt ${Fmt.time(rain.fetchedAt)} · '),
        ],
      ),
    );
  }
}

/// Waarschuwingen voor het gekozen moment: onweer, wind, hitte, gladheid, donker, lucht en pollen.
class WarningsCard extends StatelessWidget {
  const WarningsCard({required this.warnings});
  final List<RunWarning> warnings;

  static IconData _icon(String kind) => switch (kind) {
        'thunder' => Icons.thunderstorm_outlined,
        'gusts' => Icons.air,
        'heat' => Icons.local_fire_department_outlined,
        'ice' => Icons.ac_unit,
        'dark' => Icons.dark_mode_outlined,
        'air' => Icons.masks_outlined,
        'pollen' => Icons.local_florist_outlined,
        'sun' => Icons.wb_twilight,
        'dog' => Icons.pets_outlined,
        'water' => Icons.water_drop_outlined,
        _ => Icons.info_outline,
      };

  static Color _color(WarningLevel l) => switch (l) {
        WarningLevel.danger => RwColors.danger,
        WarningLevel.caution => RwColors.warning,
        WarningLevel.info => RwColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    return RwCard(
      title: tr('LET OP'),
      child: Column(
        children: [
          for (final (i, w) in warnings.indexed) ...[
            if (i > 0) SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon(w.kind), color: _color(w.level), size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.title, style: TextStyle(fontWeight: FontWeight.w700, color: _color(w.level) == RwColors.muted ? RwColors.text : _color(w.level))),
                      SizedBox(height: 2),
                      Text(w.text, style: TextStyle(color: RwColors.muted, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


/// Passend icoontje bij een kledingstuk.
IconData clothingIcon(String item) {
  final i = item.toLowerCase();
  // Material heeft geen broek- of shirt-icoon: daarvoor een kledinghanger, die leest het rustigst.
  if (i.contains('handschoen')) return Icons.back_hand_outlined;
  if (i.contains('jack')) return Icons.dry_cleaning_outlined;
  if (i.contains('pet')) return Icons.wb_sunny_outlined;
  if (i.contains('muts')) return Icons.ac_unit;
  return Icons.checkroom;
}
