import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../shared/first_tips.dart';
import '../../shared/widgets.dart';
import '../activities/badges_screen.dart';
import '../activities/fitness_screen.dart';
import '../activities/run_insights_screens.dart';
import '../activities/strength_screen.dart';
import '../activities/year_story_screen.dart';
import '../planner/training_plan_screen.dart';
import '../routes/watch_export.dart';
import 'heart_rate_screen.dart';

void openHelp(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen()));

/// Veelgestelde vragen, in gewone taal.
const helpFaq = <(String, String)>[
  (
    'Hoe zet ik een route op mijn horloge?',
    'Open een route en tik op "Zet op je horloge". De eerste keer kies je je merk. Garmin krijgt een koers die trilt bij '
        'elke afslag; Coros, Suunto, Polar en Amazfit krijgen een GPX-bestand. Volg daarna de stappen op het scherm. '
        'Een Galaxy Watch of Pixel Watch laat de afslagen zien als melding terwijl je met Kadans loopt.'
  ),
  (
    'Moet ik bij het begin van een route starten?',
    'Nee. Start je run en loop naar de route: Kadans zegt hoe ver en welke kant op. Kom je halverwege op de route, '
        'dan gaat de begeleiding daar verder. Bij een rondje loop je het hele rondje vanaf dat punt.'
  ),
  (
    'Ik ben van mijn route af. Wat nu?',
    'Kadans trilt twee keer lang en zegt waar de route ligt, bijvoorbeeld "60 meter links van je". Dat herhaalt '
        'zich elke 30 seconden tot je er weer op bent. Je ziet ook een pijl op het scherm.'
  ),
  (
    'Waarom stopt mijn run soms met meten?',
    'Sommige telefoons zetten apps in de slaapstand. Kies bij het starten van een run "Zorg dat je telefoon je run '
        'niet stopt" en volg de stappen. Dan blijft Kadans meten met het scherm uit.'
  ),
  (
    'Hoe komt de beste vertrektijd tot stand?',
    'Kadans kijkt per kwartier naar temperatuur, regen, wind op je route, donker, UV en benauwdheid, en naar wat jij '
        'fijn vindt (dat leert de app van je eerdere runs). Tik op een uur in de grafiek op Vandaag voor de uitleg.'
  ),
  (
    'Hoe krijg ik mijn runs van mijn horloge in Kadans?',
    'Koppel Strava of Health Connect in Ik → Apparaten en koppelingen. Nieuwe runs komen dan vanzelf binnen als je de '
        'app opent.'
  ),
  (
    'Wat kost Premium?',
    'De AI-coach zit in Premium: de eerste maand is gratis, daarna €5 per maand of €40 per jaar. Opzeggen kan altijd '
        'in Google Play.'
  ),
];

/// Moeilijke woorden uitgelegd.
const helpGlossary = <(String, String)>[
  ('Cadans', 'Het aantal stappen per minuut. Rond de 170–180 voelt voor veel lopers licht en soepel.'),
  ('Tempo', 'Hoeveel minuten je over een kilometer doet, bijvoorbeeld 5:30 /km.'),
  ('Hartslagzones', 'Vijf vakken van rustig (zone 1) tot heel zwaar (zone 5). De meeste kilometers loop je het best in zone 2.'),
  ('Trainingsbelasting', 'Hoe zwaar je de laatste weken trainde, vergeleken met wat je gewend bent. Te snel omhoog vergroot de kans op blessures.'),
  ('Vorm en fitheid', 'Fitheid bouw je op over weken; vorm is hoe fris je nu bent. Voor een wedstrijd laat je je vorm bewust stijgen.'),
  ('Negatieve split', 'De tweede helft sneller lopen dan de eerste. Vaak de snelste manier om een wedstrijd te lopen.'),
  ('Gevoelstemperatuur', 'Hoe warm of koud het aanvoelt door wind en vocht. Kadans gebruikt die voor kledingadvies.'),
];

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hulp')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text('VEELGESTELDE VRAGEN', style: RwText.overline),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              for (final (q, a) in helpFaq)
                ExpansionTile(
                  title: Text(q, style: const TextStyle(fontWeight: FontWeight.w600)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  expandedAlignment: Alignment.centerLeft,
                  children: [Text(a, style: const TextStyle(color: RwColors.muted, height: 1.5))],
                ),
            ]),
          ),
          const SizedBox(height: 20),
          const Text('WOORDENLIJST', style: RwText.overline),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              for (final (w, a) in helpGlossary)
                ListTile(
                  title: Text(w, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(a, style: const TextStyle(height: 1.4)),
                ),
            ]),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () async {
              await resetFirstTips();
              if (context.mounted) showMessage(context, 'De tips staan weer bovenaan de tabbladen.');
            },
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('Tips opnieuw tonen'),
          ),
        ],
      ),
    );
  }
}

/// Eén plek in de app die je via zoeken in Ik kunt vinden.
class SettingsDestination {
  const SettingsDestination(this.title, this.icon, this.keywords, this.open);
  final String title;
  final IconData icon;
  final String keywords;
  final void Function(BuildContext context) open;

  bool matches(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return true;
    return title.toLowerCase().contains(s) || keywords.contains(s);
  }
}

final settingsDestinations = <SettingsDestination>[
  SettingsDestination('Mijn schoenen', Icons.directions_run, 'schoen schoenen kilometers vervangen', (c) => c.go('/me/shoes')),
  SettingsDestination('Wedstrijden', Icons.flag_outlined, 'race wedstrijd doel eindtijd marathon', (c) => c.go('/me/races')),
  SettingsDestination('Trainingsschema', Icons.calendar_month_outlined, 'schema plan training', openTrainingPlan),
  SettingsDestination('Badges', Icons.military_tech_outlined, 'badge medaille mijlpaal', openBadges),
  SettingsDestination('Kracht en mobiliteit', Icons.fitness_center, 'kracht rekken warming-up stretch', openStrength),
  SettingsDestination('Hartslagband', Icons.monitor_heart_outlined, 'hartslag band bluetooth zones', openHeartRateScreen),
  SettingsDestination('Fitheid en vorm', Icons.trending_up, 'fitheid vorm belasting', openFitness),
  SettingsDestination('Mijn heatmap', Icons.map_outlined, 'heatmap kaart waar gelopen', openHeatmap),
  SettingsDestination('Kalender', Icons.event_outlined, 'kalender maand overzicht', openCalendar),
  SettingsDestination('Jaaroverzicht', Icons.auto_stories_outlined, 'jaar overzicht wrapped terugblik', (c) => openYearStory(c)),
  SettingsDestination('Mijn records', Icons.emoji_events_outlined, 'record pr snelste tijden', (c) => c.go('/runs/records')),
  SettingsDestination('Run toevoegen of importeren', Icons.add, 'toevoegen importeren gpx tcx handmatig', (c) => c.go('/runs/new')),
  SettingsDestination('Exporteren', Icons.download_outlined, 'export csv gpx gegevens downloaden', (c) => c.go('/runs')),
  SettingsDestination('Mijn horloge', Icons.watch_outlined, 'horloge garmin coros suunto polar amazfit wear', (c) async {
    final b = await pickWatchBrand(c, current: await loadWatchBrand());
    if (b != null) await saveWatchBrand(b);
  }),
  SettingsDestination('Premium', Icons.workspace_premium_outlined, 'premium abonnement coach betalen', (c) => c.push('/premium')),
  SettingsDestination('Hulp en woordenlijst', Icons.help_outline, 'hulp vraag uitleg faq woord', openHelp),
];

/// Zoeken in Ik: typ een woord en ga naar het goede scherm.
Future<void> showSettingsSearch(BuildContext context) async {
  final picked = await showModalBottomSheet<SettingsDestination>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: RwColors.surface,
    builder: (ctx) => const _SearchSheet(),
  );
  if (picked != null && context.mounted) picked.open(context);
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet();

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = settingsDestinations.where((d) => d.matches(_q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Zoek, bijvoorbeeld "schoen" of "export"',
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('Niets gevonden.', style: TextStyle(color: RwColors.muted)))
                : ListView(children: [
                    for (final d in list)
                      ListTile(
                        leading: Icon(d.icon, color: RwColors.accent),
                        title: Text(d.title),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, d),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}
