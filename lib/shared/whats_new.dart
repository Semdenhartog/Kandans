import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

/// Versie van het "Nieuw in RunWise"-overzicht. Ophogen als er iets nieuws te vertellen is.
const whatsNewVersion = 'nav-2026-10';

const _items = <(IconData, String, String)>[
  (Icons.watch_outlined, 'Route op je horloge',
      'Kies één keer je horloge. Daarna zet één knop de route erop, met uitleg voor jouw merk. Garmin trilt bij elke afslag.'),
  (Icons.turn_right, 'Afslag voor afslag',
      'Volg je een route, dan hoor je "over 100 meter rechtsaf", zie je een grote pijl en krijg je een melding op je horloge.'),
  (Icons.terrain_outlined, 'Klim en drinkwater vooraf',
      'RunWise zegt het als er een klim aankomt of een watertappunt vlak bij de route ligt.'),
  (Icons.graphic_eq, 'Cadans-tik',
      'Een zachte tik op je stappen per minuut, voor lichtere passen. Aan te zetten bij het starten van een run.'),
  (Icons.wb_twilight, 'Daglicht-seintje',
      'Loop je rond zonsondergang, dan hoor je hoeveel minuten daglicht je nog hebt.'),
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
