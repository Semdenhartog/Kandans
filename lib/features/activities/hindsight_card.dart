import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/kadans_effect_store.dart';
import '../../data/services/weather_service.dart';
import '../../domain/geo.dart';
import '../../domain/hindsight.dart';

/// Terugblik voor een run (weer van die dag ophalen en vergelijken). Null als het niet kan.
Future<Hindsight?> evaluateHindsight(WeatherService weather, Activity a) async {
  if (!HindsightCard.applies(a)) return null;
  final pts = decodePolyline(a.trackPolyline!);
  if (pts.isEmpty) return null;
  final start = a.startedAt.toLocal();
  try {
    final day = await weather.dayHours(pts.first.lat, pts.first.lon, start);
    return hindsight(day, start, (a.movingTimeSeconds / 60).round());
  } catch (_) {
    return null;
  }
}

/// Na het opslaan van een run: terugblik op de achtergrond berekenen en bewaren voor het Kadans-effect.
Future<void> recordKadansEffect(WeatherService weather, Activity a) async {
  if (a.id == null) return;
  final h = await evaluateHindsight(weather, a);
  if (h != null) await KadansEffectStore.save(a.id!, h, a.startedAt);
}

/// "Goed gekozen?": je run vergeleken met het weer op de andere momenten van die dag.
class HindsightCard extends ConsumerStatefulWidget {
  const HindsightCard({super.key, required this.activity});
  final Activity activity;

  /// Alleen bij runs buiten met een spoor, van de afgelopen 2 jaar.
  static bool applies(Activity a) =>
      a.hasTrack && a.movingTimeSeconds >= 600 && DateTime.now().difference(a.startedAt).inDays <= 730 && a.startedAt.isBefore(DateTime.now());

  @override
  ConsumerState<HindsightCard> createState() => _HindsightCardState();
}

class _HindsightCardState extends ConsumerState<HindsightCard> {
  late final Future<Hindsight?> _future = _load();

  Future<Hindsight?> _load() async {
    final h = await evaluateHindsight(ref.read(weatherServiceProvider), widget.activity);
    if (h != null && widget.activity.id != null) {
      final isNew = await KadansEffectStore.save(widget.activity.id!, h, widget.activity.startedAt);
      if (isNew) ref.invalidate(kadansEffectProvider);
    }
    return h;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Hindsight?>(
        future: _future,
        builder: (context, snap) {
          final h = snap.data;
          if (h == null) return const SizedBox.shrink();
          final color = h.good ? RwColors.good : RwColors.accentLight;
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(h.good ? Icons.verified_outlined : Icons.lightbulb_outline, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('GOED GEKOZEN?'), style: TextStyle(color: RwColors.subtle, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                    const SizedBox(height: 2),
                    Text(h.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(h.text, style: TextStyle(color: RwColors.muted, height: 1.4)),
                  ]),
                ),
              ]),
            ),
          );
        },
      );
}
