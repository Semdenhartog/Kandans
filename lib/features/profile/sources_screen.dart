import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Opent "Bronnen en licenties": alle diensten en gegevens waar Kadans op leunt, op één plek.
void openSources(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SourcesScreen()));
}

/// Klein, rustig linkje "bronnen" onder een kaart of lijst (in plaats van overal namen te noemen).
class SourcesLink extends StatelessWidget {
  const SourcesLink({super.key, this.prefix});

  /// Tekst ervoor, bijv. "Bijgewerkt 07:30 · ".
  final String? prefix;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => openSources(context),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (prefix != null) Text(prefix!, style: TextStyle(fontSize: 11, color: RwColors.subtle)),
            Icon(Icons.info_outline, size: 12, color: RwColors.subtle),
            const SizedBox(width: 3),
            Text('bronnen', style: TextStyle(fontSize: 11, color: RwColors.subtle)),
          ]),
        ),
      );
}

const _sources = <(String, String, String, String)>[
  ('Weer en hoogtes', 'Open-Meteo', 'Weersverwachting per uur en kwartier (o.a. KNMI- en DWD-modellen), luchtkwaliteit en pollen (CAMS), hoogtekaart.', 'https://open-meteo.com'),
  ('Buien komende 2 uur', 'Buienradar', 'Neerslagverwachting voor de komende twee uur.', 'https://www.buienradar.nl'),
  ('Kaarten en adressen', 'PDOK / Kadaster', 'Achtergrondkaart, luchtfoto (Beeldmateriaal.nl) en adressen zoeken. CC BY 4.0.', 'https://www.pdok.nl'),
  ('Wegen, paden en voorzieningen', 'OpenStreetMap-bijdragers', 'Paden, ondergrond, verlichting, water en toiletten. © OpenStreetMap-bijdragers, ODbL.', 'https://www.openstreetmap.org/copyright'),
  ('Rondjes maken', 'openrouteservice (HeiGIT)', 'Berekent routes over echte paden.', 'https://openrouteservice.org'),
  ('Straatfoto\'s', 'Mapillary', 'Foto\'s langs je route. CC BY-SA 4.0, met de naam van de maker bij elke foto.', 'https://www.mapillary.com'),
  ('Bezienswaardigheden', 'Wikipedia / Wikimedia Commons', 'Foto\'s en uitleg van plekken langs je route; licentie per foto.', 'https://commons.wikimedia.org'),
  ('Coach', 'Anthropic (Claude)', 'De AI achter de coach.', 'https://www.anthropic.com'),
];

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Bronnen en licenties')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text('Kadans combineert open gegevens en diensten. Dank aan iedereen die ze mogelijk maakt.',
                style: TextStyle(color: RwColors.muted, height: 1.45)),
            const SizedBox(height: 14),
            for (final (what, who, text, url) in _sources) ...[
              RwCard(
                onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((Object _) => false),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(what.toUpperCase(), style: RwText.overline),
                      const SizedBox(height: 4),
                      Text(who, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(text, style: TextStyle(color: RwColors.muted, fontSize: 13, height: 1.4)),
                    ]),
                  ),
                  Icon(Icons.open_in_new, size: 18, color: RwColors.subtle),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => showLicensePage(context: context, applicationName: 'Kadans'),
              child: const Text('Licenties van gebruikte software'),
            ),
          ],
        ),
      );
}
