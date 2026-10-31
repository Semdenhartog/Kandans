import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/pain_log.dart';
import '../../shared/widgets.dart';

void openPainScreen(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PainScreen()));

/// Waar en hoe erg? Geeft null als je annuleert.
Future<(PainSpot, int)?> askPain(BuildContext context) {
  var spot = PainSpot.shin;
  var sev = 3.0;
  return showModalBottomSheet<(PainSpot, int)>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Waar heb je last van?'), style: RwText.title),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in PainSpot.values)
                ChoiceChip(label: Text(tr(s.label)), selected: spot == s, onSelected: (_) => set(() => spot = s)),
            ]),
            const SizedBox(height: 14),
            Text(trf('Hoe erg: {n} van 10', {'n': sev.round()}), style: const TextStyle(fontWeight: FontWeight.w700)),
            Slider(value: sev, min: 1, max: 10, divisions: 9, onChanged: (v) => set(() => sev = v)),
            Text(tr('1 = merk je net, 5 = hinderlijk, 8 = je loopt er anders door.'), style: TextStyle(color: RwColors.subtle, fontSize: 12)),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(ctx, (spot, sev.round())), child: Text(tr('Bewaren'))),
          ]),
        ),
      ),
    ),
  );
}

/// Kort bericht als een pijntje terugkomt (na het invullen).
String? painPatternMessage(List<Activity> runs, PainSpot spot) {
  final p = painPatterns(runs).where((x) => x.spot == spot).firstOrNull;
  if (p == null) return null;
  return p.seeProfessional
      ? trf('Al {n}× {plek} in 2 weken. Laat er een fysiotherapeut naar kijken. Meer in Ik → Pijntjes.', {'n': p.count, 'plek': tr(spot.label)})
      : trf('{plek} komt terug ({n}× in 2 weken). Kijk in Ik → Pijntjes wat het kan zijn.', {'plek': tr(spot.label), 'n': p.count});
}

class PainScreen extends ConsumerWidget {
  const PainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final patterns = painPatterns(runs);
    final history = painEntries(runs.where((a) => DateTime.now().difference(a.startedAt).inDays <= 90).toList());
    return Scaffold(
      appBar: AppBar(title: Text(tr('Pijntjes'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr('Tik na een run op "Pijntje" en kies waar en hoe erg. Kadans let op patronen: komt het terug, en bij wat voor runs?'),
            style: TextStyle(color: RwColors.muted, height: 1.45),
          ),
          const SizedBox(height: 12),
          if (patterns.isEmpty)
            RwCard(child: Text(tr('Geen terugkerende pijntjes in de laatste 2 weken. Mooi zo.')))
          else
            for (final p in patterns) ...[
              RwCard(
                title: '${tr(p.spot.label).toUpperCase()} · ${p.count}× ${tr('IN 2 WEKEN')}',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (p.reasons.isNotEmpty)
                    Text(trf('Vooral {wanneer}.', {'wanneer': p.reasons.map(tr).join(', ')}), style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(tr(p.spot.advice), style: TextStyle(color: RwColors.muted, height: 1.4)),
                  if (p.seeProfessional) ...[
                    const SizedBox(height: 8),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.medical_services_outlined, color: RwColors.warning, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tr('Het komt vaker terug of is flink: laat een fysiotherapeut of huisarts ernaar kijken. Een paar dagen rust is geen verloren tijd.'),
                            style: TextStyle(color: RwColors.warning, height: 1.4)),
                      ),
                    ]),
                  ],
                ]),
              ),
              const SizedBox(height: 10),
            ],
          if (history.isNotEmpty) ...[
            const SizedBox(height: 6),
            RwCard(
              title: tr('LAATSTE 3 MAANDEN'),
              child: Column(children: [
                for (final e in history.take(20))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: (e.severity >= 6 ? RwColors.warning : RwColors.accent).withValues(alpha: 0.2),
                      child: Text('${e.severity}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    title: Text(tr(e.spot.label)),
                    subtitle: Text('${Fmt.date(e.run.startedAt)} · ${Fmt.km(e.run.distanceMeters, decimals: 1)}'),
                    onTap: e.run.id == null ? null : () => context.go('/runs/${e.run.id}'),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          Text(tr('Dit is geen medisch advies. Bij twijfel of pijn die niet weggaat: naar de huisarts of fysio.'),
              style: TextStyle(color: RwColors.subtle, fontSize: 12)),
        ],
      ),
    );
  }
}
