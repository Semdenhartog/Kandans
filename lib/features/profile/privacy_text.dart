// GEMAAKT DOOR tools/privacy_naar_dart.py uit site/privacy.html — niet met de hand aanpassen.
// ignore_for_file: lines_longer_than_80_chars

/// Eén stukje van de privacyverklaring.
class PrivacyBlock {
  const PrivacyBlock.heading(this.text) : kind = 'h', detail = null;
  const PrivacyBlock.paragraph(this.text) : kind = 'p', detail = null;
  const PrivacyBlock.meta(this.text) : kind = 'meta', detail = null;
  const PrivacyBlock.bullet(this.text) : kind = 'li', detail = null;
  const PrivacyBlock.row(this.text, String this.detail) : kind = 'row';
  final String kind;
  final String text;
  final String? detail;
}

const privacyBlocks = <PrivacyBlock>[
  PrivacyBlock.meta('Versie 1.3 · laatst bijgewerkt: 27 oktober 2026'),
  PrivacyBlock.paragraph('Kadans is een app die berekent wanneer je het beste kunt gaan hardlopen, op basis van het weer, je route en je eigen prestaties. In deze verklaring lees je welke gegevens we verzamelen, waarom we dat doen en hoe je je rechten kunt uitoefenen.'),
  PrivacyBlock.heading('Wie zijn wij?'),
  PrivacyBlock.paragraph('Kadans is een app van Sem den Hartog, gevestigd in Barneveld. De verantwoordelijke voor de verwerking van je persoonsgegevens is Sem den Hartog.'),
  PrivacyBlock.paragraph('Vragen over privacy? Mail naar sb.denhartog@hotmail.com.'),
  PrivacyBlock.heading('Welke gegevens gebruiken we?'),
  PrivacyBlock.row('E-mailadres en wachtwoord', 'Je account. Je wachtwoord wordt versleuteld opgeslagen door onze databasedienst; wij kunnen het niet zien.'),
  PrivacyBlock.row('Voornaam', 'Om je aan te spreken in de app.'),
  PrivacyBlock.row('Runs die je invoert of uit een GPX/TCX-bestand importeert (datum, afstand, tijd, en uit een bestand ook het spoor, hoogte en hartslag)', 'Om je persoonlijke loopprofiel te berekenen.'),
  PrivacyBlock.row('Weer tijdens je runs', 'Wordt automatisch opgehaald, om te leren bij welk weer jij het snelst loopt.'),
  PrivacyBlock.row('Routes die je importeert (GPS-punten)', 'Om de wind op je looprichting te berekenen.'),
  PrivacyBlock.row('Wedstrijddoelen', 'Voor je wedstrijdvoorspelling en advies.'),
  PrivacyBlock.row('Trainingen, afstand en hartslag uit Health Connect (alleen als je je horloge koppelt)', 'Om je runs automatisch toe te voegen. Kadans leest alleen hardlooptrainingen.'),
  PrivacyBlock.row('Runs uit Strava (alleen als je Strava koppelt)', 'Om je runs automatisch toe te voegen. Ontkoppel je Strava, dan verwijderen we deze runs.'),
  PrivacyBlock.row('Vragen aan de coach en de antwoorden', 'Om je persoonlijk trainingsadvies te geven en het gesprek te onthouden. Je kunt het gesprek altijd wissen.'),
  PrivacyBlock.row('Abonnementsstatus', 'Om te weten of je Premium hebt. Betalingen lopen via Google Play; wij zien geen betaalgegevens.'),
  PrivacyBlock.row('Foutmeldingen (technische gegevens: wat er misging, appversie, Android of iOS)', 'Om fouten in de app op te sporen en op te lossen. We bewaren ze maximaal 60 dagen.'),
  PrivacyBlock.row('Runs die je in Kadans opneemt (GPS-spoor, afstand, tijd, hoogte en eventueel hartslag per meetpunt)', 'Om je run op te slaan, aan je routes te koppelen en je tijden per kilometer, grafieken en trainingen te berekenen.'),
  PrivacyBlock.row('Hartslag van je hartslagband (alleen als je zelf een band koppelt)', 'Om tijdens je run je hartslag en zone te tonen, en je gemiddelde hartslag bij de run te bewaren. De verbinding loopt rechtstreeks via je telefoon.'),
  PrivacyBlock.row('Foto\'s die je bij een run zet', 'Om ze bij je run en op je deelkaart te tonen. Ze staan in een afgeschermde opslag die alleen jij kunt openen, en worden gewist als je de run of je account verwijdert.'),
  PrivacyBlock.row('Runs naar Health Connect (alleen als je dit aanzet)', 'Opgenomen runs (tijd en afstand) worden in Health Connect op je telefoon gezet, zodat ze ook in bijvoorbeeld Samsung Health staan.'),
  PrivacyBlock.row('Verloop van je Strava-runs (tijd, afstand, hoogte, hartslag, positie per meetpunt)', 'Alleen als je een Strava-run opent, om tijden per kilometer en een grafiek te tonen. Ontkoppel je Strava, dan stoppen we met het ophalen.'),
  PrivacyBlock.row('Schoenen, hoe een run voelde en notities', 'Om de kilometers op je schoenen bij te houden en de coach beter advies te laten geven.'),
  PrivacyBlock.row('Slaap, rusthartslag en HRV uit Health Connect (alleen als je dit koppelt)', 'Om je klaar-score te berekenen. Dit gebeurt alleen op je telefoon; deze gegevens gaan niet naar onze server.'),
  PrivacyBlock.row('Noodcontact (naam en telefoonnummer, alleen als je dit instelt)', 'Om tijdens een run met de SOS-knop je locatie per sms te sturen. Het blijft alleen op je telefoon; de sms verstuur je zelf vanuit de app.'),
  PrivacyBlock.row('Startscherm-widget (alleen als je hem plaatst)', 'Toont je beste vertrekmoment van vandaag op je startscherm. De gegevens staan alleen op je telefoon.'),
  PrivacyBlock.row('Coach-analyse van een run', 'Als je erom vraagt, maakt de coach een korte analyse van die run. De tekst bewaren we bij de run, zodat je hem later terugziet.'),
  PrivacyBlock.row('Trainingsschema (je doel, datum en trainingen)', 'Om je schema te tonen, de training van vandaag klaar te zetten en de coach je schema te laten kennen.'),
  PrivacyBlock.row('Maanddoel', 'Om je voortgang in de maanduitdaging te tonen.'),
  PrivacyBlock.row('Live locatie (alleen als je zelf live delen start)', 'Zodat iemand met jouw geheime link kan zien waar je loopt. Het delen stopt vanzelf na de tijd die je kiest (maximaal 5 uur). Bij live delen worden je locatiegegevens alleen tijdelijk gedeeld.'),
  PrivacyBlock.row('Posterbestelling (alleen als je een poster laat drukken): naam, bezorgadres, e-mailadres, het gekozen formaat en het drukbestand', 'Om je poster te laten drukken, te bezorgen en de bestelling te verwerken.'),
  PrivacyBlock.row('Wachtlijst of toezegging via de website: e-mailadres en (bij een toezegging) het gekozen pakket', 'Om je te laten weten wanneer je kunt meedoen, je een betaallink te sturen en na de lancering je code te mailen.'),
  PrivacyBlock.row('Samen en community (alleen als je meedoet): bijnaam, vriendcode, wie je volgt en wie jou volgt, berichten en reacties, applaus, meldingen en blokkades', 'Voor ranglijsten, volgen, gesprekken en reacties met andere lopers. Anderen zien alleen je bijnaam, nooit je naam of e-mailadres. Stop je met Samen, dan verwijderen we dit.'),
  PrivacyBlock.row('Runs die je zelf deelt met volgers of iedereen: titel, datum (zonder tijdstip), afstand, tijd, tempo, hoogtemeters en de route zonder begin en eind (privacyzone)', 'Zodat je volgers (of alle leden, als je dat kiest) je run kunnen zien en er applaus en reacties op kunnen geven. Alleen als je per run kiest om te delen; hartslag en andere gezondheidsgegevens delen we nooit, runs uit Strava kunnen niet gedeeld worden. Je kunt het delen altijd stoppen.'),
  PrivacyBlock.row('Locatie (alleen als je toestemming geeft)', 'Om het weer op jouw plek op te halen. We bewaren alleen een grove thuislocatie (afgerond op ongeveer 1 km).'),
  PrivacyBlock.paragraph('We gebruiken geen advertenties, verkopen geen gegevens en volgen je niet buiten de app.'),
  PrivacyBlock.heading('Grondslag'),
  PrivacyBlock.paragraph('We verwerken deze gegevens omdat ze nodig zijn om de app te laten werken (uitvoering van de overeenkomst). Voor je locatie vragen we eerst toestemming in je telefoon; die kun je altijd intrekken in je telefooninstellingen.'),
  PrivacyBlock.heading('Met wie delen we gegevens?'),
  PrivacyBlock.bullet('**Supabase** – slaat je account en gegevens op, op servers in de EU.'),
  PrivacyBlock.bullet('**Open-Meteo** en **Buienradar** – leveren het weer en de buien. Daarvoor sturen we alleen afgeronde coördinaten (zonder naam of e-mailadres).'),
  PrivacyBlock.bullet('**Anthropic** – levert de AI achter de coach. Als je een vraag stelt of om een analyse van een run vraagt, sturen we je vraag, je voornaam en een samenvatting van je runs (inclusief relevante data) om een persoonlijk antwoord te geven.'),
  PrivacyBlock.bullet('**Strava** – alleen als je Strava koppelt, om je runs op te halen.'),
  PrivacyBlock.bullet('**Mapillary** (Meta) – straatfoto\'s langs je route. Onze server stuurt een paar punten van de route (zonder je naam of account) om foto\'s in de buurt te zoeken.'),
  PrivacyBlock.bullet('**Open-Meteo** – hoogtekaart: om de hoogtemeters van je opgenomen runs te verbeteren sturen we punten van je spoor (zonder naam of account).'),
  PrivacyBlock.bullet('**Wikipedia** (Wikimedia Foundation) – foto\'s van bezienswaardigheden langs je route. De app vraagt daarvoor het gebied rond de route op.'),
  PrivacyBlock.bullet('**openrouteservice** (HeiGIT) – maakt rondjes als je Route maken gebruikt. Daarvoor sturen we alleen het startpunt en de gewenste afstand. Teken je zelf een route, dan sturen we alleen de routepunten om de route te maken.'),
  PrivacyBlock.bullet('**PDOK** (Kadaster) – zoekt adressen en levert de kaarten en luchtfoto\'s. Daarvoor sturen we je zoekopdracht en het kaartgebied dat je bekijkt.'),
  PrivacyBlock.bullet('**OpenStreetMap / Overpass** – zoekt watertappunten en toiletten langs je route. Daarvoor sturen we alleen het gebied rond de route.'),
  PrivacyBlock.bullet('**Google Play** en **RevenueCat** – voor het afhandelen en bijhouden van je Premium-abonnement en losse aankopen (zoals de Luxe-ontwerpen).'),
  PrivacyBlock.bullet('**Stripe** – handelt de betaling van een posterbestelling af (iDEAL, bankpas of creditcard). Stripe krijgt je e-mailadres en het bedrag; je betaalgegevens zien wij niet.'),
  PrivacyBlock.bullet('**Gelato** – drukt en bezorgt je poster. Gelato krijgt het drukbestand, je naam, bezorgadres en e-mailadres.'),
  PrivacyBlock.bullet('**Hardloopwinkel** – tik je bij "Tijd voor nieuwe schoenen" op de knop naar een winkel, dan open je hun website. Wij sturen daarbij alleen het schoenmodel mee, geen persoonlijke gegevens.'),
  PrivacyBlock.heading('Hoe lang bewaren we gegevens?'),
  PrivacyBlock.paragraph('Zolang je account bestaat. Verwijder je je account, dan worden al je gegevens direct en definitief verwijderd. Eén uitzondering: heb je een poster besteld, dan bewaren we die bestelling (naam, bezorgadres, e-mailadres en aantal) zolang dat nodig is om de bestelling te kunnen uitvoeren en eventueel te kunnen oplossen. Een e-mailadres op de wachtlijst of bij een toezegging bewaren we tot de lancering en het versturen van je code; daarna verwijderen we het, of eerder als je dat vraagt.'),
  PrivacyBlock.heading('Jouw rechten'),
  PrivacyBlock.bullet('**Inzien:** in de app via Ik → Mijn gegevens kopiëren.'),
  PrivacyBlock.bullet('**Verwijderen:** in de app via Ik → Account verwijderen. Je Strava-koppeling wordt dan ook ingetrokken. Een Premium-abonnement zeg je apart op in Google Play. Kun je de app niet meer openen, mail ons dan.'),
  PrivacyBlock.bullet('**Corrigeren, bezwaar maken of overdragen:** mail ons.'),
  PrivacyBlock.bullet('Ben je het niet eens met hoe we met je gegevens omgaan? Dan kun je een klacht indienen bij de Autoriteit Persoonsgegevens.'),
  PrivacyBlock.heading('Beveiliging'),
  PrivacyBlock.paragraph('Alle verbindingen zijn versleuteld (HTTPS). In de database kan elke gebruiker alleen zijn eigen gegevens zien.'),
  PrivacyBlock.heading('Wijzigingen'),
  PrivacyBlock.paragraph('Als deze verklaring verandert, passen we de datum bovenaan aan. Bij grote wijzigingen laten we het je in de app weten.'),
];
