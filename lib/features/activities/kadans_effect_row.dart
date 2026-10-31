import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/kadans_effect_store.dart';

/// Het Kadans-effect dit jaar: hoe vaak je op een goed moment liep en wat je ontliep.
class KadansEffectRow extends ConsumerWidget {
  const KadansEffectRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(kadansEffectProvider).value;
    final year = DateTime.now().year;
    if (e == null || e.runs(year) == 0) return const SizedBox.shrink();
    final rain = e.rainAvoided(year);
    final line = [
      trf('{n} van {m} runs goed gekozen', {'n': e.wellChosen(year), 'm': e.runs(year)}),
      if (rain >= 1) trf('{mm} mm regen ontlopen', {'mm': rain.round()}),
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _details(context, e, year),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(Icons.verified_outlined, color: RwColors.good, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Het Kadans-effect'), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(line, style: TextStyle(color: RwColors.muted, fontSize: 13)),
            ]),
          ),
          Icon(Icons.chevron_right, color: RwColors.subtle),
        ]),
      ),
    );
  }

  void _details(BuildContext context, KadansEffect e, int year) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(trf('Het Kadans-effect in {jaar}', {'jaar': year}), style: RwText.title),
            const SizedBox(height: 12),
            for (final (icon, text) in [
              (Icons.verified_outlined, trf('{n} van je {m} runs liep je op een van de fijnste momenten van de dag.', {'n': e.wellChosen(year), 'm': e.runs(year)})),
              (Icons.umbrella_outlined, trf('{n} keer droog gebleven terwijl het die dag regende; samen {mm} mm regen ontlopen.', {'n': e.dryRuns(year), 'mm': e.rainAvoided(year).round()})),
              if (e.heatAvoided(year) >= 1)
                (Icons.wb_sunny_outlined, trf('Op warme dagen samen {g} graden hitte ontweken.', {'g': e.heatAvoided(year).round()})),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, color: RwColors.accent),
                  const SizedBox(width: 12),
                  Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
                ]),
              ),
            const SizedBox(height: 8),
            Text(tr('Telt mee vanaf 31 oktober 2026: elke run wordt vergeleken met het weer op de andere momenten van die dag.'),
                style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.35)),
          ]),
        ),
      ),
    );
  }
}
