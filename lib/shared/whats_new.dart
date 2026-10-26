import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

/// Versie van het "Nieuw in Kadans"-overzicht. Ophogen als er iets nieuws te vertellen is.
const whatsNewVersion = 'kadans-2026-10b';

const _items = <(IconData, String, String)>[
  (Icons.shopping_bag_outlined, 'De Kadans-shop',
      'Routeposters, Luxe-ontwerpen, Premium en schoenen op één plek: tik op het tasje op Vandaag of Routes, of op Shop in Ik.'),
  (Icons.bolt_outlined, 'Live opdrachten en rondes',
      'Zet bij de start "Live opdrachten" aan voor sprintjes onderweg, en tik tijdens het lopen op Ronde voor je eigen rondetijden.'),
  (Icons.card_giftcard, 'Vrienden uitnodigen',
      'In Samen deel je een gouden uitnodiging met een link die je vriend meteen toevoegt.'),
  (Icons.auto_awesome_outlined, 'RunWise heet nu Kadans',
      'Nieuwe naam, nieuw icoon en nieuwe kleuren: Zand overdag en Zand avond in het donker (kies in Ik → Weergave). Je runs, routes en instellingen blijven zoals ze waren.'),
  (Icons.groups_outlined, 'Samen lopen',
      'Uitdagingen → Samen: ranglijsten met andere lopers en vrienden. Alleen je bijnaam en totaal zijn zichtbaar.'),
  (Icons.cloud_off_outlined, 'Je run is altijd veilig',
      'Geen bereik na je run? Je run blijft op je telefoon staan en wordt vanzelf opgeslagen zodra je weer internet hebt.'),
  (Icons.content_cut, 'Run bijsnijden',
      'Vergeten te stoppen? Schuif in het rundetail het begin en eind naar waar je echt liep. Tijd, tempo en kaart rekenen mee.'),
  (Icons.lightbulb_outline, 'Waarom later beter is',
      'Vandaag zegt nu ook waarom wachten loont, bijvoorbeeld "12 punten beter dan nu: minder warm en droger".'),
  (Icons.umbrella_outlined, 'Lopen in de regen',
      'Vind je regen niet erg? Zeg het in Ik, dan telt regen minder mee. Onweer telt nu altijd zwaar mee.'),
  (Icons.notifications_none, 'Slimmere ochtendmelding',
      'Loop je meestal rond hetzelfde tijdstip, dan krijg je alleen een melding als een ander moment echt beter is.'),
  (Icons.battery_std, 'GPS en accu per run',
      'Na je run zie je hoeveel accu het kostte, en bij je tijden per km hoe goed de GPS was.'),
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
  await showWhatsNew(context);
}

/// Het overzicht van wat er nieuw is (ook later terug te zien via Ik → Hulp).
Future<void> showWhatsNew(BuildContext context) async {
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
            Text('Nieuw in Kadans', style: RwText.title),
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
                          Text(text, style: TextStyle(color: RwColors.muted, height: 1.4)),
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
