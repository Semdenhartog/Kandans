import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/hrr_store.dart';
import '../../domain/hrr.dart';
import '../../shared/widgets.dart';

/// Hartslagherstel bij deze run (als je de 1-minuut-test deed), met je trend.
class HrrCard extends StatelessWidget {
  const HrrCard({super.key, this.activity});

  /// Null = alleen het overzicht (voor het hartslagscherm).
  final Activity? activity;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<HrrResult>>(
        future: HrrStore.load(),
        builder: (context, snap) {
          final all = snap.data ?? const <HrrResult>[];
          final a = activity;
          final r = a == null ? (all.isEmpty ? null : all.last) : HrrStore.forRun(all, a.startedAt, a.movingTimeSeconds);
          if (r == null) return const SizedBox.shrink();
          final upto = [for (final x in all) if (!x.at.isAfter(r.at)) x];
          final trend = hrrTrend(upto);
          final c = r.drop >= 25 ? RwColors.good : (r.drop >= 12 ? RwColors.accent : RwColors.warning);
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: RwCard(
              title: tr('HARTSLAGHERSTEL'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('−${r.drop}',
                      style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 30, fontWeight: FontWeight.w800, color: c)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text('${tr('slagen in 1 minuut')} · ${tr(hrrLevel(r.drop))}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
                Text(trf('Van {a} naar {b} bpm.', {'a': r.startBpm, 'b': r.endBpm}), style: TextStyle(color: RwColors.muted)),
                if (trend != null) ...[
                  const SizedBox(height: 6),
                  Text(trend, style: TextStyle(color: RwColors.muted, height: 1.4)),
                ],
                if (a == null && all.length > 1) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${tr('Laatste metingen')}: ${all.reversed.take(8).map((x) => '−${x.drop}').join(' · ')}',
                    style: TextStyle(color: RwColors.subtle, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 6),
                Text(tr('Je doet de test na een run met hartslagband: Kadans vraagt dan een minuut rustig te staan.'),
                    style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.35)),
              ]),
            ),
          );
        },
      );
}
