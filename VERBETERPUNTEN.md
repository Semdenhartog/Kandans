# RunWise – 100 verbeterpunten

Gemaakt op 22-10-2026 na het doorlezen van de code (±38.000 regels Dart, 7 edge functions).

**Let op:** bij het nalopen bleken 18 punten al (grotendeels) in de app te zitten; die staan op ✅ met "Bestond al".

**Eerlijke conclusie vooraf:** RunWise heeft al meer functies dan de meeste betaalde hardloop-apps.
De grootste winst zit niet in nóg meer functies, maar in **betrouwbaarheid, testen, eenvoud en de lancering**.
Daarom staan die bovenaan. Nieuwe functies staan verderop en zijn bewust minder.

Legenda: **P1** = eerst doen (risico of grote winst) · **P2** = daarna · **P3** = leuk, niet nodig.
Status: ✅ gedaan · 📄 voorbereid, Sem moet het zelf indienen · ⬜ open.

---

## A. Je run gaat nooit verloren (opnemen)

1. ✅ **P1 Opslaan zonder internet.** *Waarom:* het herstelbestand werd gewist vóór de run in de database stond. Geen bereik na je run = run weg zodra je de app sluit. *Wat:* lukt opslaan niet, dan gaat de run in een wachtrij op de telefoon en wordt later vanzelf geüpload.
2. ✅ **P1 Opslaan mag niet hangen.** *Waarom:* het weer ophalen wachtte tot 15 s, de database had geen tijdslimiet. *Wat:* weer max 6 s (mag ontbreken), database max 20 s, daarna de wachtrij.
3. ✅ **P1 Geen dubbele runs bij opnieuw proberen.** *Waarom:* als de upload lukt maar het antwoord verloren gaat, zou opnieuw proberen een tweede run maken. *Wat:* elke opgenomen run krijgt een vaste sleutel; opnieuw versturen overschrijft in plaats van verdubbelt.
4. ✅ **P1 Laat zien dat er iets wacht.** *Wat:* smalle balk "1 run wacht op internet" boven de navigatie, tot hij geüpload is.
5. ✅ **P1 GPS vast op een verkeerd eerste punt.** *Waarom:* begint de opname met een uitschieter, dan werd elk goed punt daarna als "sprong" weggegooid. *Wat:* na 3 sprongen achter elkaar opnieuw beginnen vanaf het nieuwe punt, zonder afstand mee te tellen.
6. ✅ **P1 Accubesparing van Android.** *Bleek er al in te zitten (uitleg + knop op het opnamescherm).* *Waarom:* Samsung, Xiaomi en OnePlus sluiten apps op de achtergrond, ook met een voorgrondmelding. *Wat:* vóór de eerste run vragen om RunWise uit te zonderen, met uitleg per merk.
7. ✅ **P2 GPS-gat overbruggen.** *Waarom:* onder een viaduct of in een tunnel valt GPS weg. *Wat:* bij een gat < 2 min de rechte lijn meetellen en in het rundetail markeren. *Bestond al grotendeels: valt GPS even weg, dan telt de rechte lijn naar het volgende goede punt mee (zolang dat niet als sprong telt).*
8. ✅ **P2 GPS-kwaliteit per run.** Onder de tijden per km: "GPS: goed. 1× even geen GPS (samen 40 s, rechte lijn geteld), 2 sprongen weggefilterd". Alleen bij nieuwe opnames.
9. ⬜ **P2 Nep-GPS-modus voor testen.** *Waarom:* opnemen is nu alleen te testen door echt te lopen. *Wat:* een verborgen testmodus die een route afspeelt. Ook bruikbaar in de schermafbeeldingen-workflow.
10. ✅ **P3 Weggooien ongedaan maken.** Na "Weggooien" bij een onderbroken run 8 s een knop "Toch bewaren"; pas daarna wordt het herstelbestand gewist.

## B. De kern: beste vertrektijd

11. ✅ **P1 Uitleg in één zin:** "11 punten beter dan nu: minder warm en droger." Vergelijkt het beste moment met nu, per soort weer. *Waarom:* een score zonder reden voelt willekeurig. *Wat:* "18:00 wint van 17:00: minder tegenwind op de terugweg".
12. ⬜ **P1 Voorspelling achteraf controleren.** *Wat:* na de run vergelijken wat voorspeld was met het echte weer; zo zie je of het model klopt ("8 van de 10 keer goed").
13. ✅ **P2 Leren van wanneer je echt loopt (deels).** RunWise herkent je gewone looptijd uit je runs van de laatste 60 dagen (alleen als je echt meestal rond hetzelfde tijdstip loopt; bij wisseldiensten niet). Wordt nu gebruikt voor de ochtendmelding; de score zelf is bewust niet aangepast.
14. ⬜ **P2 KNMI-weeralarm meenemen.** *Wat:* bij code oranje/rood een duidelijke waarschuwing bovenaan Vandaag.
15. ⬜ **P2 Onzekerheid tonen.** *Wat:* "regen om 18:00 – onzeker" als de weermodellen het oneens zijn.
16. ⬜ **P2 Hitte-gewenning.** *Wat:* de eerste warme dagen van het jaar zwaarder wegen dan dezelfde temperatuur in juli.
17. ✅ **P2 Regen-voorkeur.** Ik → Lopen in de regen: Liever droog / Normaal / Regen vind ik niet erg. Telt mee in Vandaag, weekplanner en meldingen. Extra: **onweer** telde nog helemaal niet mee en geeft nu altijd 40 strafpunten.
18. ✅ **P2 Ochtendmelding alleen als het uitmaakt.** Stil als je gewone looptijd prima is; wel een melding als een ander moment ≥8 punten beter is ("12 punten beter dan je gewone tijd (18:30)") of je gewone tijd slecht uitkomt. Schakelaar in Ik → Dagelijkse melding; staat standaard aan.
19. ⬜ **P3 Ideale temperatuur per seizoen.** *Wat:* het loopprofiel apart voor zomer en winter.
20. ⬜ **P3 Diensten uit je agenda lezen.** *Waarom:* met wisseldiensten verschuift je vrije tijd elke week. *Wat:* bezette blokken uit de agenda automatisch overslaan in het advies.

## C. Tijdens de run

21. ⬜ **P1 Pauzeren met de knop van je oortjes.** *Wat:* play/pauze op de koptelefoon pauzeert de run.
22. ✅ **P2 Alleen trillen, geen stem.** *Wat:* stille modus met trilpatronen per km en bij zones. *Bestond al: knop Trillen op het opnamescherm.*
23. ⬜ **P2 Minimaal scherm.** *Wat:* twee enorme cijfers (tijd en afstand), verder niets.
24. ⬜ **P2 Handmatige ronde.** *Wat:* een "ronde"-knop voor baantraining of eigen intervallen.
25. ✅ **P2 Drinkherinnering bij warm weer.** *Wat:* boven 22 °C elke 20 min een seintje. *Bestond al als drink- en gelherinnering voor lange runs (nog niet weerafhankelijk).*
26. ⬜ **P2 Stilstand-alarm voor je noodcontact.** *Wat:* sta je 5 min stil zonder pauze, dan vraagt de app "Alles goed?"; geen antwoord = sms met locatie. *Let op:* goed testen, vals alarm is erger dan geen alarm.
27. ✅ **P3 Tempo-doel per km.** *Wat:* "houd 5:30 aan" met seintjes bij te snel/te langzaam (los van intervallen). *Bestond al: tempodoel instellen bij de start (ook vanuit het schema).*
28. ✅ **P3 Zelfde route, vorige keer.** *Wat:* tijdens het lopen "12 s sneller dan vorige keer op dit punt". *Bestond al: tegen je vorige keer lopen (ghost).*

## D. Na de run

29. ✅ **P1 Run bijsnijden.** Knop in het rundetail van eigen opnames; schuif begin en eind, zie de nieuwe afstand/tijd/tempo en kaart. *Waarom:* vergeten te stoppen is de meest voorkomende ergernis. *Wat:* begin en eind wegknippen, afstand en tijd rekenen opnieuw.
30. ⬜ **P2 Runs splitsen en samenvoegen.**
31. ⬜ **P2 Gevoel op schaal 1–10.** *Waarom:* zwaar/oké/top is te grof voor trainingsbelasting. *Wat:* optionele schuif, de drie knoppen blijven.
32. ⬜ **P2 Eigen runs naar Strava sturen.** *Wat:* opgenomen RunWise-runs uploaden naar Strava (mag volgens de voorwaarden, wij zijn dan de bron).
33. ⬜ **P2 Notitie inspreken.** *Wat:* microfoonknop bij "hoe voelde het".
34. ✅ **P2 Weer-gecorrigeerd tempo in de runlijst:** "≈ 5:12 /km bij ideaal weer" onder elke run waar het weer meer dan 5 s kostte.
35. ✅ **P3 Vergelijken met dezelfde route.** *Wat:* grafiek van al je tijden op een route. *Bestond al: tijden per route en "je 19e keer op deze route".*
36. ⬜ **P3 Foto bij de deelkaart als achtergrond.**

## E. Coach en training

37. ✅ **P1 AI-kosten per gebruiker bewaken (stap 1).** De coach logt per vraag het aantal tokens (zonder inhoud) als `coach_usage` in de Supabase-logboeken. Sem: coach-functie opnieuw live zetten. Stap 2 (context inkorten, hergebruik) pas als de cijfers er zijn. Oorspronkelijk: *Waarom:* bij €5/maand moet de coach goedkoper blijven dan wat hij oplevert. *Wat:* kosten per gebruiker loggen, context inkorten, veelgestelde vragen hergebruiken.
38. ✅ **P1 Schema past zich aan na gemiste training.** *Wat:* een training overgeslagen? De week schuift slim, zonder twee zware dagen achter elkaar. *Bestond al: bij 2 gemiste trainingen biedt de app aan de week te herhalen of lichter te maken.*
39. ⬜ **P2 Coach onthoudt doelen en klachten.** *Wat:* met toestemming, en altijd te wissen.
40. ⬜ **P2 Bronnen in het coach-antwoord.** *Wat:* "op basis van je laatste 3 lange runs" met links naar die runs.
41. ✅ **P2 Te snel opbouwen.** *Wat:* waarschuwing als je weekkilometers > 30% stijgen. *Bestond al: "Je loopt meer dan gepland" met knop om de week lichter te maken.*
42. ⬜ **P2 Zondagavond-terugblik als melding.**
43. ⬜ **P3 Coach in gesproken vorm tijdens de warming-up.**
44. ⬜ **P3 Kracht-oefeningen met korte filmpjes of animaties.**

## F. Routes

45. ✅ **P2 Route omdraaien met één knop** (andere kant op, andere wind). *Bestond al: routeadvies kan de route omdraaien voor de wind.*
46. ⬜ **P2 Verlichte route 's avonds voorrang geven** bij het genereren.
47. ⬜ **P2 Onverhard of verhard kiezen** bij het genereren.
48. ⬜ **P2 Routes delen als link** (zonder account te bekijken).
49. ✅ **P3 Favoriete routes bovenaan.** *Bestond al: favoriete routes.*
50. ⬜ **P3 Afstand van een getekende route live tijdens het tekenen.**
51. ✅ **P3 Toiletten en kraantjes onderweg** uit OpenStreetMap. *Bleek er al in te zitten (Overpass).*

## G. Gebruiksgemak en toegankelijkheid

52. ✅ **P1 Grotere tekst:** limiet van 135% naar 160%. Schermtests op 160%; de workflow Schermen wordt nu rood als er iets uit beeld valt (drie plekken gevonden en opgelost: hartslagregel, km-ring met afslag, "bij ideaal weer"). 200% vraagt een herontwerp van de grote cijfers; nog open. Bekend: op het startscherm bij 160% schuift "Geen signaal" half achter de keuzeknop Buiten/Loopband (scrollbaar, maar niet mooi).
53. ✅ **P1 Schermlezer (TalkBack).** Nagelopen: bijna alle icoonknoppen hadden al een naam; de laatste 4 en de uur-staafjes op Vandaag ("18:00, score 86, top, beste moment") toegevoegd. *Echt testen met TalkBack aan op de telefoon blijft nodig.* *Waarom:* maar ±40 Semantics-labels op ±100 schermen. *Wat:* labels voor grafieken, kaarten en icoonknoppen.
54. ⬜ **P2 Licht thema.** *Wat:* nu alleen donker (zonmodus is alleen voor opnemen).
55. ⬜ **P2 Kleurenblind-veilig.** *Wat:* scores niet alleen met rood/groen, ook met vorm of tekst.
56. ⬜ **P2 Instellingen doorzoekbaar.** *Waarom:* er zijn er inmiddels erg veel.
57. ⬜ **P2 Engelse taal.** *Wat:* teksten naar een vertaalbestand. Groot werk, pas zinvol voor buitenlandse lancering.
58. ✅ **P2 Lege schermen met één duidelijke actie** (geen runs, geen routes). *Bestond al: nagekeken met nieuwe schermtests 40–43 (Vandaag, Runs, Routes, Coach zonder gegevens); elk scherm heeft uitleg en één duidelijke knop.*
59. ✅ **P2 Onboarding inkorten** tot max. 3 schermen; de rest uitleggen op het moment dat je het nodig hebt. *Bestond al: de rondleiding heeft 3 schermen.*
60. ⬜ **P3 Trillen consequent** (alleen bij echte acties, niet overal).

## H. Snelheid en accu

61. ✅ **P1 Accuverbruik per run** na afloop: "Deze run kostte 9% accu" (niet als de telefoon aan de lader hing). Wordt niet bewaard, alleen getoond.
62. ⬜ **P1 R8/verkleinen aanzetten.** *Waarom:* `minifyEnabled false` in de release. *Wat:* aanzetten met regels voor Health, RevenueCat en BLE. Kleinere app, sneller. Risico: crashes bij ontbrekende regels, dus eerst op een telefoon testen.
63. ⬜ **P2 Opstarttijd meten** en Vandaag eerst tonen, de rest later laden.
64. ⬜ **P2 Kaarttegels bewaren** voor routes die je vaak loopt (minder data, werkt zonder bereik).
65. ⬜ **P2 Opnamescherm minder vaak opnieuw tekenen.** *Waarom:* één bestand van 2.800 regels; elke seconde wordt veel ververst.
66. ⬜ **P2 Weer niet dubbel ophalen** tussen Vandaag, widget en melding.
67. ⬜ **P3 Foto's kleiner opslaan** vóór upload.
68. ⬜ **P3 Animaties uit bij "minder beweging"** in de Android-instellingen.

## I. Code en tests

69. ⬜ **P1 Opnamescherm opsplitsen.** *Waarom:* `record_run_screen.dart` is 2.794 regels; elke wijziging is risicovol. *Wat:* losse onderdelen per blok.
70. ⬜ **P1 Dashboard opsplitsen** (1.362 regels).
71. ✅ **P1 Stille fouten loggen** op de plekken waar je data kwijt kan raken (herstelbestand, wachtrij, km-tijden). *Waarom:* 59 keer `catch (_) {}`; fouten verdwijnen zonder spoor. *Wat:* op de belangrijke plekken naar de foutmelder.
72. ✅ **P1 Widgettests (deels).** Correctie: er waren al 2 widgettests (mijn eerste telling miste ze). Toegevoegd: balk "runs wachten op internet" en het bijsnijdscherm. Een test van starten → opnemen → opslaan kan pas met nep-GPS (punt 9).
73. ⬜ **P2 Schermafbeeldingen vergelijken.** *Wat:* screens.yml laat een verschil zien t.o.v. de vorige ronde, zodat onbedoelde wijzigingen opvallen.
74. ⬜ **P2 Integratietest op een emulator in GitHub Actions** met nep-GPS (koppelt aan punt 9).
75. ✅ **P2 Pakketten bijwerken met Dependabot:** één verzamelvoorstel per maand voor pakketten en één voor GitHub Actions; de build draait erop. Alleen samenvoegen als die groen is.
76. ⬜ **P2 Foutoverzicht.** *Wat:* een simpele weergave van `app_errors` gegroepeerd per fout, zodat je ziet wat testers raakt.
77. ⬜ **P3 Strengere analyse-regels** (bijv. `unawaited_futures`).
78. ⬜ **P3 Versie uit een git-tag** in plaats van het runnummer.

## J. Privacy en veiligheid

79. ✅ **P1 Supabase-adviezen nagelopen.** Alle tabellen hebben RLS; premium en gratis coachvragen zijn met een trigger afgeschermd. Open voor Sem: *Leaked password protection* aanzetten (Authentication → Policies/Passwords).
80. ✅ **P1 Limiet op edge functions.** route-generator 60 en street-photos 100 per gebruiker per dag. Code klaar; Sem: migratie 0027 uitvoeren en de functies live zetten.
81. ✅ **P1 Account verwijderen gecontroleerd:** alle 19 eigen tabellen, Strava-tokens en foto's worden gewist.
82. ✅ **P2 Foutmeldingen automatisch opruimen** na 60 dagen (zoals de privacyverklaring belooft). In migratie 0027.
83. ✅ **P2 Al je gegevens downloaden** (AVG-recht op inzage) als één bestand. *Bestond al: Ik → Mijn gegevens kopiëren (AVG).*
84. ✅ **P2 Geheimen-scan in GitHub Actions** (geheimen.yml) bij elke push.
85. ✅ **P2 Live-link: zichtbaar wanneer hij verloopt** en met één tik intrekken. *Bestond al: live delen stopt vanzelf na de gekozen tijd en heeft een stopknop die je locatie wist.*
86. ✅ **P3 Strava-runs via Health Connect herkend.** Runs die de Strava-app in Health Connect zet, gaan niet meer naar de AI-coach (ook eerder geïmporteerde worden gemarkeerd). RunWise-runs die RunWise zelf naar Health Connect schreef, komen niet meer dubbel terug.

## K. Play Store en lancering

87. 📄 **P1 Interne testtrack** (stappen in docs/play-store.md) in Play Console met 5–10 testers vóór openbare lancering.
88. 📄 **P1 Verklaring voor locatie op de achtergrond.** Tekst klaar in docs/play-store.md. *Waarom:* Google eist een uitleg en vaak een video voor een voorgrondservice met locatie. Zonder dit wordt de app afgewezen.
89. 📄 **P1 Health Connect-aanvraag** (redenen klaar in docs/play-store.md) bij Google indienen (verplicht voor gezondheidsdata).
90. 📄 **P1 Gegevensveiligheid-formulier** (ingevuld in docs/play-store.md) in Play Console invullen, gelijk aan de privacyverklaring.
91. ⬜ **P1 Privacyverklaring afmaken** (naam, plaats, e-mail, datum) en Pages aanzetten.
92. ✅ **P2 Store-afbeeldingen:** de schermtest maakt 6 Play Store-plaatjes (1080×1920) in `schermen-main/playstore/`, zonder uitlegballonnen. De feature graphic (1024×500) is nog ontwerpwerk.
93. ⬜ **P2 "Feedback sturen"-knop** voor testers, met appversie erbij.
94. ✅ **P2 Om een beoordeling vragen** na de 5e eigen opgenomen run, één keer (Google's eigen venster, alleen bij installatie via de Play Store).

## L. Focus en verdienmodel

95. ⬜ **P1 Meten welke functies gebruikt worden** (anoniem, met toestemming). *Waarom:* bij zoveel functies weet je niet wat mensen echt gebruiken.
96. ⬜ **P1 Ongebruikte functies verbergen of schrappen.** *Waarom:* elke functie is onderhoud en een kans op fouten.
97. ⬜ **P2 Premium in drie zinnen kunnen uitleggen.** *Wat:* nu is onduidelijk wat gratis is en wat niet; maak één duidelijke grens.
98. ⬜ **P2 Proefperiode zonder betaalgegevens.** *Wat:* 14 dagen alles, daarna kiezen.
99. ⬜ **P2 Wachtlijst laten werken** (formulier werkt niet op Pages; bijv. een Supabase-tabel).
100. ✅ **P3 Eén vaste plek "Nieuw in RunWise"** die alleen grote veranderingen toont, niet elke kleine verbetering. *Bestond al: "Nieuw in RunWise" verschijnt één keer per versie.*

---

## Wat ik bewust níet aanraad

- **Nog meer "luxe"-functies** voordat de app op een echte telefoon is getest. Er staan nu al 7+ ongeteste onderdelen open.
- **iOS** voordat Android stabiel in de Play Store staat. Dubbel testwerk.
- **Een sociaal netwerk / volgers.** Veel moderatie en privacywerk, weinig onderscheidend.

## Voorgestelde volgorde

1. Ronde 1 (✅): run nooit kwijt.
2. Telefoontest door Sem.
3. Ronde 2: lancering-blokkers (87–91) en beveiliging (79–81).
4. Ronde 3: stabiliteit (6, 52, 53, 62, 69–72).
5. Daarna pas de kern slimmer (11–18) en functies (21+).

## M. Extra inkomsten (op verzoek van Sem, 23-10-2026)

101. ✅ **Schoenen bij een hardloopspeciaalzaak.** Luxe kaart "Tijd voor nieuwe schoenen" op Vandaag en in Mijn schoenen: km-ring, advies, knop naar de winkel, afschrijven of later. Winkel en partnerlink instelbaar in Supabase (`model_config`: `shoe_shop_name`, `shoe_shop_url` met `{q}`, `shoe_shop_partner`). Zonder instelling: gewone zoeklink zonder commissie. Partnerlinks staan er eerlijk bij.
102. ✅ **Luxe-ontwerpen als losse aankoop.** 4 luxe posterstijlen (Goud, Marmer, Oceaan, Blauwdruk) en een gouden deelkaart; bekijken mag, delen/drukken vraagt ontgrendelen. Eenmalige aankoop via RevenueCat (`runwise_luxe_designs` / `luxe_designs`), gratis bij Premium. Sem: product aanmaken (zie docs/inkomsten.md).
103. ✅ **Routeposter bestellen in de app.** Formaat en adres kiezen, drukbestand tot 300 dpi, betalen via Stripe (iDEAL/kaart), webhook met handtekeningcontrole zet de bestelling bij Gelato (standaard als concept, dus testmodus), statusoverzicht in Ik → Mijn posters, drukbestanden na 90 dagen weg. Sem: Stripe, Gelato, migratie 0028 en geheimen (zie docs/inkomsten.md).

## N. Strava, badges en uitdagingen (op verzoek van Sem, 25-10-2026)

104. ✅ **Oude runs uit Strava.** Strava → Oude runs ophalen: alles van vóór het eerste jaar, in stappen van 200 met het weer van toen. Voortgang bewaard; als Strava te druk is gaat het na 15 minuten vanzelf verder.
105. ✅ **Routes uit Strava.** Kies welke hardlooproutes je importeert (ook vanuit het Routes-scherm). Privéroutes na opnieuw koppelen. Bij ontkoppelen verdwijnen ze weer (voorwaarden van Strava).
106. ✅ **Meer badges: van 23 naar 49.** Snelheid en records (5 km onder 30/25/20, 10 km onder 60/50, snelle km, halve onder 2 uur), weer en seizoen (tropen, pool, zonsopkomst, langste dag, kerst, oud en nieuw, vier seizoenen), volhouden (7 dagen, 26 weken, 12 maanden op rij, een jaar loper), ontdekken (10/25 routes, 5 plekken, op reis, bergloper) en 15 km/30 km/250 runs/2500 km. Badgescherm in groepen. Bestaande badges behouden hun id.
107. ✅ **Eigen uitdagingen met live voortgang.** Ik → Uitdagingen (en een kaart op Vandaag): maand-km (op jouw niveau), 12 runs, 10 uur, 1000 hoogtemeters, halve marathon, 4 weken 3× per week, plus seizoen (Adventsloop, Goed begin in januari, Zomer van 300 km). Tijdens de run een balkje met "nog 3,2 km" en de stem bij het halen; gouden medailles op het badgescherm. Bewaard op de telefoon.
108. ✅ **Uitdagingen samen met anderen (ranglijst).** Uitdagingen → Samen: zelf aanzetten met een bijnaam, ranglijsten voor kilometers en hoogtemeters per maand (plus Adventsloop en Zomer in het seizoen), Iedereen of alleen Vrienden, vrienden via een code van 6 tekens. Alleen bijnaam en totaal zijn zichtbaar; standen rekent de server uit (niet te vervalsen); runs uit Strava tellen niet mee. Stoppen verwijdert alles. *Nodig: migratie 0029 en de functie `community` live zetten.*
109. ✅ **Nieuwe naam en icoon: Kadans.** Alle teksten in de app, de coach, posters en Play Store-teksten heten nu Kadans. Nieuw icoon: twee geweven ringen met vaartlijnen, espresso op zand (ook adaptief en monochroom), nieuw logo en woordmerk. Het pakket (`nl.runwise…`), de deeplinks (`runwise://`) en de downloadlink blijven hetzelfde, zodat inloggen en updates blijven werken.
110. ✅ **App-icoon "Goudfolie".** Gouden ringen met vaartlijnen op warm bruin met een zachte gloed, en een lichte routelijn van links over de bovenkant (zoals het inlogscherm). Adaptief (achtergrond met lijn, voorgrond met gouden ringen) en monochroom voor Android 13+.
111. ✅ **Ondergrond: veel minder "onbekend".** Waar OpenStreetMap geen ondergrond noemt, schat Kadans hem uit het soort weg (straat/fietspad = verhard, stoep = tegels, bos-/boerenweg = halfverhard, pad = onverhard); korte gaten krijgen de soort van de buren. De kaart zegt eerlijk welk deel geschat is. *Nodig: functie `route-generator` opnieuw live zetten.*
112. ✅ **Verlichting en voorzieningen laden sneller.** Per vraag eerst de snelste server en pas na 4 seconden een reserve; lichtere vraag (minder punten, kleinere straal). Daarna 30 dagen bewaard op de telefoon.
113. ✅ **Route tekenen prominent.** Mijn routes begint met twee grote tegels: Route tekenen (goud) en Laten maken.
114. ✅ **Garmin zonder routes (zoals Vivoactive 5).** Eigen keuze bij "Welk horloge heb je?". Geen koersbestand (dat kan dit horloge niet openen), maar "Loop met afslagen op je pols": Kadans volgt de route op je telefoon en stuurt bij elke afslag een melding met trilling naar je Garmin, met alleen ← en → (basistekens die dit horloge zeker toont).
115. ✅ **App-icoon: ringen groter.** Ringen ~15% groter en vaartlijnen kleiner, binnen de veilige cirkel van Android (script: `tools/icoon_ringen_groter.py`, alleen op het originele icoon draaien).
116. ✅ **Rondleiding met vragen.** 7 schermen, elk over te slaan: uitleg, overzicht van alle functies, doel (gaat mee naar de coach), wanneer je loopt (vult de weekplanner) + dagelijkse melding, locatie, horloge, koppelen; bij doel "wedstrijd" meteen naar Wedstrijd toevoegen. Opnieuw te bekijken via Ik → Hulp. *Nodig: functie `coach` opnieuw live zetten voor het doel.*
117. ✅ **Live opdrachten tijdens je run.** Keuze "Live opdrachten" bij de start. Na 8 min/1,2 km inlopen om de 5 min: sprint 20 s, snelle minuut, km op tempo; bij een doelafstand een sterke finish. Doelen op je eigen gemiddelde tempo; stem, trilling en melding op je horloge; kaart met aftellen tijdens de opdracht. Niet naast intervallen, begeleide runs of loopband.
118. ✅ **Luxe uitnodiging.** "Vrienden uitnodigen" in Samen deelt een gouden kaart + link naar `site/vriend.html`, die de app opent (`runwise://app/vriend?code=…`) en de vriend meteen toevoegt (ook na eerst inloggen of meedoen). *Nodig: GitHub Pages aan; downloadknop wijst nu naar de APK, later naar de Play Store.*

## Ronde 26 oktober 2026 (vraag van Sem: shop, privacy, en 6 × 10 verbeteringen)

**Gevraagd**
119. ✅ **Privacyverklaring gaf een fout.** Oorzaak: GitHub Pages staat nog uit, dus de website bestond niet (404). Nu staat de verklaring ook ín de app (werkt altijd, ook offline), met een knop naar de website. *Nodig: Pages aanzetten.*
120. ✅ **Shop.** Eén winkel voor routeposters (je eigen routes als voorbeeld), Luxe-ontwerpen, Premium en schoenen. Gouden tegel in Ik, tasje op Vandaag en Routes, vindbaar via zoeken. "Mijn posters" zit nu in de shop.

**1. Gebruiksgemak**
121. ✅ Feedback sturen (Ik → Hulp), met appversie en toestel als je wilt.
122. ✅ Ronde-knop tijdens het lopen: rondetijd en tempo uitgesproken, rondes in het overzicht na je run (snelste in goud).
123. ✅ Vriend toevoegen: code of uitnodigingslink op het klembord wordt vanzelf ingevuld.
124. ✅ Uitnodigingslink kopiëren in Samen.
125. ✅ Rondleiding: terugknop, tikbare bolletjes en de Android-terugknop gaat een stap terug.
126. ✅ "Wat is nieuw" later terug te zien (Hulp) en bijgewerkt met deze ronde.
127. ✅ Live opdracht overslaan (bijv. bij een oversteek).
128. ✅ Zoeken in Ik vindt nu ook Shop, posterbestellingen, privacy, rondleiding, feedback en wat-is-nieuw.
129. ✅ "Laten maken" onthoudt je laatste keuze (afstand of tijd).
130. ✅ Android-terug in de rondleiding sluit niet meer meteen alles.

**2. Layout**
131. ✅ Records-kaart na je run: tekst was onleesbaar in het lichte thema.
132. ✅ Uurgrafiek: kleur volgt de score, score boven het gekozen en beste uur, korte uitleg eronder.
133. ✅ Hartslagzones in de huisstijl (zand, groen, goud, oranje, rood) i.p.v. blauw/grijs.
134. ✅ Premium: "binnenkort"-melding in donker-goud (was een licht vak op zwart); Luxe staat bij de voordelen.
135. ✅ Premium-regel in Ik brak lelijk af ("p/ j").
136. ✅ Per km: lege windkolom weg als er geen wind per km bekend is.
137. ✅ Korte routelijst: ideeën eronder (poster, rondje laten maken) i.p.v. een leeg scherm.
138. ✅ Loopprofiel: percentage boven elke staaf en temperatuurbereik eronder.
139. ✅ Weekoverzicht: cijfers krimpen bij grote letters (gaf een fout in de schermcontrole op maandag).
140. ✅ Hoogte per km inklapbaar (dubbelde met "Per kilometer").

**3. Opties**
141. ✅ Live opdrachten: rustig / normaal / pittig.
142. ✅ Live opdrachten: om de 3, 5 of 8 minuten.
143. ✅ Scherm aan tijdens je run.
144. ✅ Ronde-knop aan/uit.
145. ✅ Openen op Vandaag, Runs of Routes (Ik → Weergave).
146. ✅ Kledingadvies: snel koud / normaal / snel warm.
147. ✅ Hooikoorts: geen pollenmeldingen, normaal, of extra gevoelig.
148. ✅ Coach: korte, normale of uitgebreide antwoorden. *Nodig: functie `coach` live zetten.*
149. ✅ "Mijn doel" uit de rondleiding later te wijzigen in Ik.
150. ✅ "Alleen goede uren" blijft onthouden.

**4. Weer en advies**
151. ✅ Mist: waarschuwing over zicht.
152. ✅ Natte bladeren in oktober/november.
153. ✅ "Misschien een bui" bij een onzekere regenkans (30–60%).
154. ✅ Benauwd (warm en vochtig).
155. ✅ Eerste warme dag: je bent nog niet gewend aan warmte.
156. ✅ Koud: warming-up binnen.
157. ✅ Gure wind: voelt veel kouder dan het is.
158. ✅ Begin tegen de wind in (als je geen route volgt).
159. ✅ Bij hitte: hoe laat het koelste moment is.
160. ✅ Drinkadvies met hoeveelheden.

**5. Groei en inkomsten**
161. ✅ Route delen als link: webpagina met kaart en GPX, en "Opslaan in Kadans" via de app. Ook in de loopmaatje-uitnodiging.
162. ✅ Postertip na je 1e, 10e, 25e… keer op een route of na een record.
163. ✅ Lege vriendenranglijst: knop om vrienden uit te nodigen.
164. ✅ Gedeelde run bevat een link naar Kadans.
165. ✅ Wachtlijst via Supabase (tabel `waitlist`, alleen toevoegen). *Nodig: migratie 0030 + Pages aan.*
166. ✅ Website, live-pagina en bedankpagina in Kadans-stijl (naam, goud, logo).
167. ✅ Om een beoordeling vragen na een record (al vanaf run 3), het blije moment.
168. ✅ "Nieuw"-stipje op het shoptasje tot je de shop bekeek.
169. ✅ Vertel een vriend over Kadans (Ik).
170. ✅ Actiecode inwisselen in de shop (Google Play), voor influencer-acties.

**6. Betrouwbaarheid en onderhoud**
171. ✅ GitHub Actions bijgewerkt (Node 20-waarschuwingen weg).
172. ✅ Bouwserver vastgezet op Ubuntu 24.04 (geen verrassingen door de overstap naar 26).
173. ✅ Functies gaan vanzelf live bij een wijziging op main (zodra het token er is); zonder token een waarschuwing i.p.v. een fout.
174. ✅ Websitelinks werken nu op GitHub Pages (ze wezen naar de verkeerde map).
175. ✅ Privacyverklaring op één plek: de website is de bron, de app volgt bij elke build.
176. ✅ Foutoverzicht in Supabase: `select * from foutoverzicht;` (migratie 0031).
177. ✅ "Minder beweging": ook uurgrafiek en rondleiding zonder animatie.
178. ✅ Tests voor opdrachten, rondes-overslaan, routelink, vriendcode, nieuwe weerwaarschuwingen, kledingvoorkeur en beoordeling.
179. ✅ Nieuwe schermen in de schermcontrole (shop, privacy, rondleidingstappen).
180. ✅ Overdracht (CLAUDE.md) en dit overzicht bijgewerkt.

## Ronde 27 oktober 2026
181. ✅ **Eigen actiecodes en vouchers** (migratie 0032): gratis Premium, Luxe of alles; alleen als hash opgeslagen, max. gebruik, verloopdatum, 10 pogingen per dag. Inwisselen in de shop; onbekende code → Google Play. *Betaalde vouchers moeten via Google Play (regels).*
182. ✅ **Vertel een vriend**: gouden uitnodigingskaart (afbeelding) met link; `vriend.html` stuurt naar de Play Store zodra `PLAY_LIVE = true`, nu nog naar de APK.
183. ✅ **Privacyverklaring ingevuld** (Sem den Hartog, handelsnaam Kadans, Barneveld) en feedbackadres.
184. ✅ **Bronnen op één plek** (Ik → bronnen en licenties); namen van diensten uit de schermen, klein "bronnen"-linkje. Kaartvermeldingen blijven (licentie-eis).
185. ✅ **Community-tabblad** (migratie 0033): onderwerpen, berichten, reacties, duimpjes, melden (3× = verborgen), blokkeren, huisregels, filter op links/telefoonnummers/scheldwoorden, limieten per dag. Alleen tekst.
186. ✅ **Talen**: NL/EN/DE/FR/ES te kiezen op het beginscherm, in de rondleiding en in Ik. Vertaald: inloggen, rondleiding, onderbalk, Ik, shop, community. *Rest volgt per scherm.*
187. ✅ Datums in de gekozen taal.
188. ✅ Migraties 0030–0033 lokaal getest op Postgres 16 (alle 33 migraties, plus een test van codes en community).
189. ✅ Onderbalk met zes tabbladen: alleen het gekozen tabblad toont zijn naam.
190. ✅ Tabblad heet in de onderbalk **Forum** (Community brak af over twee regels); het scherm zelf heet nog Community. Bij "gaat binnenkort open" nu een knop Opnieuw proberen.
191. ✅ **Strava-archief importeren** (ook zonder koppeling): zip van Strava kiezen, alleen hardloopactiviteiten uit GPX/TCX/FIT (ook .gz), weer van toen erbij, dubbele runs overgeslagen. Bron blijft `strava` (niet naar coach/anderen). Eigen zip-lezer met zip64, eigen FIT-lezer (`domain/fit_parser.dart`). Losse import accepteert nu ook FIT.
192. ✅ **Nieuw logo: gouden K op zwart marmer.** Adaptief app-icoon (K in de veilige zone, ook rond en thema-icoon), gouden K op opstartscherm, inlogscherm en uitnodigingskaart, nieuw woordmerk KΛDΛNS, website (favicon, logo, deelplaatje) en Play Store-icoon (`docs/merk/`).
193. ✅ Icoon op het homescherm is nu **exact het originele logo** (met gouden rand en KADANS), zonder aanpassingen; geen thema-icoon (monochroom) meer, zodat Android het niet omkleurt.
194. ✅ Homescherm-icoon groter: de gouden rand van het logo vult nu de Samsung-vorm (was 56%, nu 72% van de laag).
195. ✅ Oorzaak te klein icoon gevonden: flutter_launcher_icons zet standaard 16% extra marge om de voorgrond. Nu 0, zodat de gouden rand echt tot de rand van het Samsung-icoon loopt.
196. ✅ Definitief logo: champagnegouden K + KADANS op zwarte tegel. Homescherm-icoon = dit logo met K en tekst 8% groter; de tegel sluit aan op de vorm van het icoon.
197. ✅ **Steunpagina** `site/steun.html`: doel €1.500 met eerlijke begroting (KvK, merk, Supabase, AI-coach, Apple, lancering), vier pakketten (1–2 jaar Premium, poster, lokale partner), toezeggen zonder betalen (naar de wachtlijst). Privacyverklaring aangevuld.

## Ronde 30 oktober 2026 – volgen en runs delen (zoals Strava)
198. ✅ **Volgen** (migratie 0034): lopers zoeken op bijnaam, volgen, terugvolgen, ontvolgen, volgers weghalen. Optie **"Volgers zelf goedkeuren"** met volgverzoeken (stipje bij het personen-icoon). Vriendcode = meteen goedgekeurd.
199. ✅ **Runs delen**: per run kiezen tussen *Volgers* (standaard) en *Iedereen*, eigen titel, **privacyzone** 200 m / 500 m / 1 km rond start én finish (ook als je halverwege langs huis loopt). Gedeeld wordt een kopie zonder hartslag en zonder tijdstip. Strava-runs kunnen niet gedeeld worden. Delen stoppen kan altijd.
200. ✅ **Community → Runs**: feed *Volgend* en *Iedereen*, kaart met de vorm van de route (tik = kaart), **applaus** en reacties, melden (3× = verborgen), blokkeren (haalt ook het volgen weg). *Gesprekken* = het bestaande forum. Tik op een naam → **profiel** met runs, volgers en volgend.
201. ✅ Privacyverklaring aangevuld (Samen/community en gedeelde runs). Migratie lokaal getest op Postgres 16 met een scenario van drie lopers.

## Ronde 30 oktober 2026 (2) – lessen uit Strava-klachten (`docs/concurrentie-strava.md`)
202. ✅ **Belofte "wat gratis is, blijft gratis"** + prijswijziging altijd vooraf + export altijd: op de Premium-pagina, in de shop, op de site en in de Play Store-tekst.
203. ✅ Feed Runs: label **"Op volgorde van tijd, zonder reclame"**.
204. ✅ **Pauzeknop** (Ik → Pauze nemen; balk op Vandaag): blessure, ziek, vakantie of rust, 3 dagen t/m "tot ik weer begin". Geen loopherinneringen (ook geen weekend-/weekseintje), reeks en badges "weken op rij" breken niet (pauzeweek = ≥4 dagen pauze), weekoverzicht zegt "Rustweek", de coach krijgt een vaste zin mee (geen trainingsdruk, bij blessure/ziek: arts of fysio). Alleen op de telefoon; privacyverklaring aangevuld.
205. ✅ **GPS-sprongen**: onder een run (niet bij Strava-runs) een kaartje als de GPS sneller ging dan lopen kan (> 25 km/u of ~2× je tempo, > 15 m te veel). Loper kiest per sprong: herstellen (rechte lijn, tijd blijft) of "Klopt wel". Nooit vanzelf aanpassen.
206. ✅ Beste vertrektijd blijft **op 5 minuten**: onderzocht, per minuut is schijnnauwkeurigheid (weer per kwartier, buienradar per 5 min).
207. ✅ Bijsnijden: tempo stond er als "5:30 /km /km".
