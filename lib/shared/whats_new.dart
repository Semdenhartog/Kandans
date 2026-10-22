import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

/// Versie van het "Nieuw in RunWise"-overzicht. Ophogen als er iets nieuws te vertellen is.
const whatsNewVersion = 'luxe-2026-10';

const _items = <(IconData, String, String)>[
  (Icons.u_turn_right, 'Overal instappen op je route',
      'Begin waar je wilt. RunWise zegt hoe ver en welke kant op de route ligt, en wijst je terug als je ervan af raakt.'),
  (Icons.watch_outlined, 'Afslagen op je Galaxy of Pixel Watch',
      'De volgende afslag staat nu altijd in de melding, dus ook op je Wear OS-horloge en je vergrendelscherm.'),
  (Icons.emoji_events_outlined, 'Recordjacht onderweg',
      '"Houd dit tempo vast en je loopt een nieuw 5 km-record." Plus je verwachte eindtijd en elke km een vergelijking met de vorige.'),
  (Icons.record_voice_over_outlined, 'Kies je coachstem',
      'Rustig, motiverend of kort. En bij de start een korte briefing: temperatuur en waar je tegenwind hebt.'),
  (Icons.u_turn_left, 'Heen en terug op tijd',
      'Kies 40 minuten, dan zegt RunWise halverwege dat je moet omdraaien.'),
  (Icons.lightbulb_outline, 'Verlichting en bezienswaardigheden',
      'Zie hoeveel van je route verlicht is, en hoor onderweg langs welke bezienswaardigheden je komt.'),
  (Icons.wb_twilight, 'Gouden uur, weekend en jaardoel',
      'Nieuwe kaarten op Vandaag. Verplaats of verberg ze met het schuifje rechtsboven.'),
  (Icons.play_circle_outline, 'Je run nog eens zien',
      'Bij elke run met GPS: tik op de afspeelknop en zie je run zich intekenen op de kaart.'),
  (Icons.image_outlined, 'Route als poster en samen lopen',
      'Deel een route als mooie poster, of nodig een loopmaatje uit met het beste moment en het routebestand.'),
];

/// Toont één keer per versie wat er nieuw is. [skip] = alleen als gezien markeren (bijv. na de rondleiding).
Future<void> showWhatsNewIfNeeded(BuildContext context, {bool skip = false}) async {
  SharedPreferences p;
  try {
    p = await SharedPreferences.getInstance();
  } catch (_) {
    return;
  }
  if (p.getString('whats_new_seen') == whatsNewVersion) return;
  await p.setString('whats_new_seen', whatsNewVersion);
  if (skip || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: RwColors.surface,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nieuw in RunWise', style: RwText.title),
            const SizedBox(height: 16),
            for (final (icon, title, text) in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: RwColors.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(text, style: const TextStyle(color: RwColors.muted, height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Top, laten we lopen')),
          ],
        ),
      ),
    ),
  );
}
