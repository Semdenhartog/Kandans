# RunWise – 100 verbeterpunten

Gemaakt op 22-10-2026 na het doorlezen van de code (±38.000 regels Dart, 7 edge functions).

**Let op:** bij het nalopen bleken 10 punten al (grotendeels) in de app te zitten; die staan op ✅ met "Bestond al".

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
7. ⬜ **P2 GPS-gat overbruggen.** *Waarom:* onder een viaduct of in een tunnel valt GPS weg. *Wat:* bij een gat < 2 min de rechte lijn meetellen en in het rundetail markeren.
8. ⬜ **P2 GPS-kwaliteit per run.** *Wat:* in het rundetail "GPS: goed / 2 gaten / 4 sprongen weggefilterd". Helpt jou en mij bij het opsporen van fouten.
9. ⬜ **P2 Nep-GPS-modus voor testen.** *Waarom:* opnemen is nu alleen te testen door echt te lopen. *Wat:* een verborgen testmodus die een route afspeelt. Ook bruikbaar in de schermafbeeldingen-workflow.
10. ⬜ **P3 Weggooien ongedaan maken.** *Wat:* na "Weggooien" bij een onderbroken run 10 s een knop "Toch bewaren".

## B. De kern: beste vertrektijd

11. ✅ **P1 Uitleg in één zin:** "11 punten beter dan nu: minder warm en droger." Vergelijkt het beste moment met nu, per soort weer. *Waarom:* een score zonder reden voelt willekeurig. *Wat:* "18:00 wint van 17:00: minder tegenwind op de terugweg".
12. ⬜ **P1 Voorspelling achteraf controleren.** *Wat:* na de run vergelijken wat voorspeld was met het echte weer; zo zie je of het model klopt ("8 van de 10 keer goed").
13. ⬜ **P2 Leren van wanneer je echt loopt.** *Wat:* loop je steeds rond 7:00, dan weegt die tijd zwaarder mee in het advies.
14. ⬜ **P2 KNMI-weeralarm meenemen.** *Wat:* bij code oranje/rood een duidelijke waarschuwing bovenaan Vandaag.
15. ⬜ **P2 Onzekerheid tonen.** *Wat:* "regen om 18:00 – onzeker" als de weermodellen het oneens zijn.
16. ⬜ **P2 Hitte-gewenning.** *Wat:* de eerste warme dagen van het jaar zwaarder wegen dan dezelfde temperatuur in juli.
17. ⬜ **P2 Eén schuif "regen vind ik niet erg".** *Wat:* simpele voorkeuren in plaats van een ingewikkeld profiel.
18. ⬜ **P2 Ochtendmelding alleen als het uitmaakt.** *Wat:* alleen melden als het beste moment duidelijk beter is dan je gewone tijd, anders stil.
19. ⬜ **P3 Ideale temperatuur per seizoen.** *Wat:* het loopprofiel apart voor zomer en winter.
20. ⬜ **P3 Diensten uit je agenda lezen.** *Waarom:* met wisseldiensten verschuift je vrije tijd elke week. *Wat:* bezette blokken uit de agenda automatisch overslaan in het advies.

## C. Tijdens de run

21. ⬜ **P1 Pauzeren met de knop van je oortjes.** *Wat:* play/pauze op de koptelefoon pauzeert de run.
22. ✅ **P2 Alleen trillen, geen stem.** *Wat:* stille modus met trilpatronen per km en bij zones. *Bestond al: knop Trillen op het opnamescherm.*
23. ⬜ **P2 Minimaal scherm.** *Wat:* twee enorme cijfers (tijd en afstand), verder niets.
24. ⬜ **P2 Handmatige ronde.** *Wat:* een "ronde"-knop voor baantraining of eigen intervallen.
25. ✅ **P2 Drinkherinnering bij warm weer.** *Wat:* boven 22 °C elke 20 min een seintje. *Bestond al als drink- en gelherinnering voor lange runs (nog niet weerafhankelijk).*
26. ⬜ **P2 Stilstand-alarm voor je noodcontact.** *Wat:* sta je 5 min stil zonder pauze, dan vraagt de app "Alles goed?"; geen antwoord = sms met locatie. *Let op:* goed testen, vals alarm is erger dan geen alarm.
27. ⬜ **P3 Tempo-doel per km.** *Wat:* "houd 5:30 aan" met seintjes bij te snel/te langzaam (los van intervallen).
28. ✅ **P3 Zelfde route, vorige keer.** *Wat:* tijdens het lopen "12 s sneller dan vorige keer op dit punt". *Bestond al: tegen je vorige keer lopen (ghost).*

## D. Na de run

29. ✅ **P1 Run bijsnijden.** Knop in het rundetail van eigen opnames; schuif begin en eind, zie de nieuwe afstand/tijd/tempo en kaart. *Waarom:* vergeten te stoppen is de meest voorkomende ergernis. *Wat:* begin en eind wegknippen, afstand en tijd rekenen opnieuw.
30. ⬜ **P2 Runs splitsen en samenvoegen.**
31. ⬜ **P2 Gevoel op schaal 1–10.** *Waarom:* zwaar/oké/top is te grof voor trainingsbelasting. *Wat:* optionele schuif, de drie knoppen blijven.
32. ⬜ **P2 Eigen runs naar Strava sturen.** *Wat:* opgenomen RunWise-runs uploaden naar Strava (mag volgens de voorwaarden, wij zijn dan de bron).
33. ⬜ **P2 Notitie inspreken.** *Wat:* microfoonknop bij "hoe voelde het".
34. ⬜ **P2 Weer-gecorrigeerd tempo in de lijst.** *Wat:* "5:24 (≈5:12 zonder wind)" bij elke run.
35. ✅ **P3 Vergelijken met dezelfde route.** *Wat:* grafiek van al je tijden op een route. *Bestond al: tijden per route en "je 19e keer op deze route".*
36. ⬜ **P3 Foto bij de deelkaart als achtergrond.**

## E. Coach en training

37. ⬜ **P1 AI-kosten per gebruiker bewaken.** *Waarom:* bij €5/maand moet de coach goedkoper blijven dan wat hij oplevert. *Wat:* kosten per gebruiker loggen, context inkorten, veelgestelde vragen hergebruiken.
38. ⬜ **P1 Schema past zich aan na gemiste training.** *Wat:* een training overgeslagen? De week schuift slim, zonder twee zware dagen achter elkaar.
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

52. ✅ **P1 Grotere tekst:** limiet van 135% naar 160%. Schermtests op 160%; de workflow Schermen wordt nu rood als er iets uit beeld valt (drie plekken gevonden en opgelost: hartslagregel, km-ring met afslag, "bij ideaal weer"). 200% vraagt een herontwerp van de grote cijfers; nog open.
53. ✅ **P1 Schermlezer (TalkBack).** Nagelopen: bijna alle icoonknoppen hadden al een naam; de laatste 4 en de uur-staafjes op Vandaag ("18:00, score 86, top, beste moment") toegevoegd. *Echt testen met TalkBack aan op de telefoon blijft nodig.* *Waarom:* maar ±40 Semantics-labels op ±100 schermen. *Wat:* labels voor grafieken, kaarten en icoonknoppen.
54. ⬜ **P2 Licht thema.** *Wat:* nu alleen donker (zonmodus is alleen voor opnemen).
55. ⬜ **P2 Kleurenblind-veilig.** *Wat:* scores niet alleen met rood/groen, ook met vorm of tekst.
56. ⬜ **P2 Instellingen doorzoekbaar.** *Waarom:* er zijn er inmiddels erg veel.
57. ⬜ **P2 Engelse taal.** *Wat:* teksten naar een vertaalbestand. Groot werk, pas zinvol voor buitenlandse lancering.
58. ⬜ **P2 Lege schermen met één duidelijke actie** (geen runs, geen routes).
59. ⬜ **P2 Onboarding inkorten** tot max. 3 schermen; de rest uitleggen op het moment dat je het nodig hebt.
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
72. ⬜ **P1 Widgettests.** *Waarom:* `widget_test.dart` bevat 0 tests. *Wat:* minimaal starten, opnemen-stoppen-opslaan en inloggen.
73. ⬜ **P2 Schermafbeeldingen vergelijken.** *Wat:* screens.yml laat een verschil zien t.o.v. de vorige ronde, zodat onbedoelde wijzigingen opvallen.
74. ⬜ **P2 Integratietest op een emulator in GitHub Actions** met nep-GPS (koppelt aan punt 9).
75. ⬜ **P2 Pakketten automatisch bijwerken** (Dependabot) met build als controle.
76. ⬜ **P2 Foutoverzicht.** *Wat:* een simpele weergave van `app_errors` gegroepeerd per fout, zodat je ziet wat testers raakt.
77. ⬜ **P3 Strengere analyse-regels** (bijv. `unawaited_futures`).
78. ⬜ **P3 Versie uit een git-tag** in plaats van het runnummer.

## J. Privacy en veiligheid

79. ✅ **P1 Supabase-adviezen nagelopen.** Alle tabellen hebben RLS; premium en gratis coachvragen zijn met een trigger afgeschermd. Open voor Sem: *Leaked password protection* aanzetten (Authentication → Policies/Passwords).
80. ✅ **P1 Limiet op edge functions.** route-generator 60 en street-photos 100 per gebruiker per dag. Code klaar; Sem: migratie 0027 uitvoeren en de functies live zetten.
81. ✅ **P1 Account verwijderen gecontroleerd:** alle 19 eigen tabellen, Strava-tokens en foto's worden gewist.
82. ✅ **P2 Foutmeldingen automatisch opruimen** na 60 dagen (zoals de privacyverklaring belooft). In migratie 0027.
83. ⬜ **P2 Al je gegevens downloaden** (AVG-recht op inzage) als één bestand.
84. ✅ **P2 Geheimen-scan in GitHub Actions** (geheimen.yml) bij elke push.
85. ⬜ **P2 Live-link: zichtbaar wanneer hij verloopt** en met één tik intrekken.
86. ⬜ **P3 Strava-runs die via Health Connect binnenkomen herkennen**, zodat die ook niet naar de coach gaan.

## K. Play Store en lancering

87. 📄 **P1 Interne testtrack** (stappen in docs/play-store.md) in Play Console met 5–10 testers vóór openbare lancering.
88. 📄 **P1 Verklaring voor locatie op de achtergrond.** Tekst klaar in docs/play-store.md. *Waarom:* Google eist een uitleg en vaak een video voor een voorgrondservice met locatie. Zonder dit wordt de app afgewezen.
89. 📄 **P1 Health Connect-aanvraag** (redenen klaar in docs/play-store.md) bij Google indienen (verplicht voor gezondheidsdata).
90. 📄 **P1 Gegevensveiligheid-formulier** (ingevuld in docs/play-store.md) in Play Console invullen, gelijk aan de privacyverklaring.
91. ⬜ **P1 Privacyverklaring afmaken** (naam, plaats, e-mail, datum) en Pages aanzetten.
92. ⬜ **P2 Store-afbeeldingen uit screens.yml** maken (formaat Play Store).
93. ⬜ **P2 "Feedback sturen"-knop** voor testers, met appversie erbij.
94. ⬜ **P2 Om een beoordeling vragen** na de 5e geslaagde run (niet eerder).

## L. Focus en verdienmodel

95. ⬜ **P1 Meten welke functies gebruikt worden** (anoniem, met toestemming). *Waarom:* bij zoveel functies weet je niet wat mensen echt gebruiken.
96. ⬜ **P1 Ongebruikte functies verbergen of schrappen.** *Waarom:* elke functie is onderhoud en een kans op fouten.
97. ⬜ **P2 Premium in drie zinnen kunnen uitleggen.** *Wat:* nu is onduidelijk wat gratis is en wat niet; maak één duidelijke grens.
98. ⬜ **P2 Proefperiode zonder betaalgegevens.** *Wat:* 14 dagen alles, daarna kiezen.
99. ⬜ **P2 Wachtlijst laten werken** (formulier werkt niet op Pages; bijv. een Supabase-tabel).
100. ⬜ **P3 Eén vaste plek "Nieuw in RunWise"** die alleen grote veranderingen toont, niet elke kleine verbetering.

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
