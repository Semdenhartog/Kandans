# Kadans herindeling – voorstel (1 november 2026)

Status: **voorstel, nog niets gebouwd.** Sem kiest; daarna bouwen in 3 rondes.
Gebaseerd op de code (router, home_shell, dashboard_layout, profile_screen, help_screen) en de schermen op `schermen-main`.
Niet getest met echte gebruikers: de "tests" hieronder zijn een doordenkoefening.

---

## 1. Inventaris (nu)

**6 tabs:** Vandaag · Runs · Routes · Coach · Forum · Ik

**Vandaag** heeft 5 vaste blokken (moment, Jij vandaag, wedstrijd-aftellen, weekrapport, jaarverhaal) plus **19 kaarten die standaard allemaal aan staan**:
Nog een keer, Waarschuwingen, Recordweer, Nieuwe schoenen, Uitdagingen, Aantrekken, Buien, Per uur, Wind op je route, Beste route, Weekplanner, Maanduitdaging, Loop-bingo, Veilig onderweg, Gouden uur, Weekend, Op deze dag, Jaardoel.
→ Tot **24 blokken** onder elkaar. Daar zit het grootste deel van de rommel.

**Ik** heeft ~35 regels in 4 groepen (Training, Apparaten, Meldingen en veiligheid, Account), met daarin ook instellingen (regen, hond, pollen, kleding).

**Run-detail** heeft 12 kaarten: splits, hoogte, terugblik, vocht, markeringen, foto's, stukken, hartslagherstel, gevoel, GPS-sprong, coach-samenvatting, Kadans-effect.

### Op 3 of meer plekken (dubbel)

| functie | plekken |
| --- | --- |
| Shop | icoon op Vandaag, icoon op Routes, tegel in Ik |
| Uitdagingen | kaart op Vandaag, tegel in Ik, ranglijst in Forum |
| Vriend uitnodigen | knop op Vandaag, tegel in Ik, kaart in Forum |
| Schoenen | kaart op Vandaag, Ik → Mijn schoenen, filter bij Runs |
| Planning | Weekplanner (Vandaag), Trainingsschema (Ik), Weekend-kaart, Recordweer-kaart |
| Doel/spel | Jaardoel, Maanduitdaging, Bingo, Uitdagingen, Badges, Weddenschappen (6 vormen) |
| Terugkijken | Jaarverhaal (Vandaag + Runs), Op deze dag, Kalender, Heatmap, Fotomuur, Records |

### Verstopt (belangrijk!)

- **Werkrooster** is alleen te vinden via de zoeklijst in Hulp. Juist dé functie voor jouw doelgroep (wisseldiensten).
- Loopmaatjes, weddenschappen en loopgroepen zitten als chips in Forum.
- 25 bestemmingen zijn alleen via zoeken in Hulp te vinden.

### Woorden door elkaar

Forum / Samen / community · Fitheid / vorm / Klaar-score · punten / score · run / training / activiteit.

---

## 2. Het verhaal van een loopdag

Elke functie krijgt één thuis:

| moment | wat hoort hier |
| --- | --- |
| **Plannen** | beste moment van de week, trainingsschema, wedstrijden, rooster/agenda, weerslim schema, weekend, recordweer |
| **Gaan** | het moment van vandaag, buien, aantrekken, waarschuwingen, wind op je route, beste route nu, nog een keer, wekker |
| **Lopen** | opnemen, intervallen, schermindeling, live delen + valdetectie, hartslag, oortjesknop, markeringen |
| **Terugkijken** | runs, run-detail, records, vorm, badges, jaarverhaal, schoenen, pijntjes, export |
| **Samen** | volgen, runs delen, gesprekken, uitdagingen, ranglijsten, loopmaatjes, groepen, uitnodigen |
| *(Ik)* | account, Premium, shop, koppelingen, instellingen, veiligheid, privacy, hulp |

**Past nergens goed:** Loop-bingo, Gouden uur, Op deze dag, GPS-kunst, Weddenschappen, Kadans-effect-badge, Heatmap.

---

## 3. Vier tests

**Nachtdienst-test** (7:00, moe, één hand)
- Nu: het moment staat bovenaan, dat is goed. Maar daaronder volgen 20+ kaarten, en het rooster kent hij alleen als hij het via Hulp heeft gevonden.
- Moet: "Eerst slapen. Beste moment: 13:25" + één knop **Wekker 13:10**. Klaar.
- ✅ Kan met de bestaande code (rooster + moment), mits het rooster zichtbaar is.

**Eerste-30-seconden-test**
- Begrijpt: grote tijd, "Later lopen", weer.
- Snapt niet: "97 Top", "15 punten beter", "Klaar-score 57", 6 tabs waarvan "Forum" niet bij een loopapp lijkt te horen.
- Oplossing: woorden in plaats van punten ("Veel beter dan nu: minder wind"), score alleen als klein label.

**Schrap-de-helft-test** — als er maar de helft mocht blijven:
- Blijft: moment, buien, wind/route, aantrekken, waarschuwingen, opnemen, runs + detail, routes (maken, importeren, horloge), schema + wedstrijden, rooster, coach, volgen + delen, één soort uitdaging, schoenen, live delen + valdetectie, Premium.
- Gaat (verbergen of samenvoegen): bingo, gouden uur, op deze dag, recordweer (→ weekplanner), weekend (→ weekplanner), heatmap/kalender/fotomuur (→ één weergaveknop in Logboek), weddenschappen (→ uitdagingen), jaardoel + maanduitdaging (→ Doelen), Kadans-effect-badge.
- Eerlijk: **zes spelvormen is te veel.** Eén systeem "Doelen" (deze maand + badges) is sterker dan zes losse.

**Ontgrendel-test** — tonen pas als het nodig is:

| functie | verschijnt wanneer |
| --- | --- |
| Rooster-kaart | bij de start gevraagd "Werk je in diensten?" → ja |
| Wind op je route / Beste route | na je eerste route |
| Vorm, records | na 5 runs |
| Heatmap, jaarverhaal | na 20 runs |
| Wedstrijd-aftellen | als je een wedstrijd toevoegt |
| Schoenen-kaart | als je schoenen toevoegt én ze bijna op zijn (90% van hun grens, standaard 700 km) |
| Pijntjes | als je na een run "pijntje" aantikt |
| Doelen/uitdagingen | na 2 weken gebruik |
| Loopmaatjes, groepen | als je 3 lopers volgt |
| Hond-waarschuwingen | als je "ik loop met mijn hond" aanzet |

Bovenaan Vandaag een klein bericht als er iets nieuws vrijkomt: "Nieuw voor jou: je records 🏅".

---

## 4. Nieuwe opbouw: 4 tabs + één grote knop

```
┌──────────────────────────────────────┐
│  Goedemiddag, Sem.            (S) ←Ik│
│                                      │
│  NIET NU · OM 13:25                  │
│  Droog, weinig wind, wind mee terug  │
│  [ Wekker 13:10 ]   [ Toch nu ]      │
│                                      │
│  ▸ Buien: droog tot 15:00            │  ← max 3 slimme kaarten
│  ▸ Aantrekken: lange mouw            │    (kiest zelf wat nu telt)
│  ▸ Vandaag: rustige duurloop 45 min  │
│                                      │
│  Deze week ›   Meer vandaag ›        │
├──────────────────────────────────────┤
│ Vandaag  Routes  (● LOPEN)  Logboek  Samen │
└──────────────────────────────────────┘
```

| tab | in één zin |
| --- | --- |
| **Vandaag** | Wanneer ga ik lopen, en wat moet ik weten voor ik ga? (Plannen + Gaan) |
| **Routes** | Waar ga ik lopen? Maken, tekenen, importeren, naar je horloge. |
| **● Lopen** | Grote ronde knop in het midden: direct opnemen. Geen tab, een actie. |
| **Logboek** | Wat heb ik gelopen? Runs, vorm, records, doelen, schoenen. |
| **Samen** | Lopen met anderen: volgen, delen, gesprekken, uitdagingen. |

- **Ik** = je avatar rechtsboven op elk tabblad (profiel, Premium, shop, koppelingen, instellingen, veiligheid, privacy, hulp). Eén plek.
- **Coach** = geen tab meer, maar een vaste knop "Vraag de coach" op Vandaag, in het Logboek en onder elke run. Hij komt waar de vraag ontstaat (en de paywall dus ook).
- **"Deze week"** = weekplanner + schema + rooster + wedstrijden in één scherm.
- **"Meer vandaag"** = de overige kaarten (per uur, gouden uur, live delen enz.), zelf aan/uit te zetten zoals nu.

**Run-detail:** bovenaan 3 cijfers + 1 zin ("Rustig gelopen, 12 s/km sneller dan bij dit weer normaal"). Daaronder drie kopjes om open te klappen: Tempo en hartslag · Route en foto's · Hoe ging het (gevoel, pijntje, coach).

**Ik in 4 groepen:** Mijn account · Koppelingen (Strava, Health Connect, band, horloge) · Instellingen (weergave, meldingen, taal, hond, pollen, regen, kleding) · Veiligheid en privacy.

### Gelijke patronen

- Elke kaart: icoon + titel + één zin + één actie rechts. Lang indrukken = "Niet meer tonen".
- Primaire actie altijd onderaan het scherm, op dezelfde plek.
- Lege toestand altijd met één zin + één knop ("Nog geen routes. Maak er een").

### Woordenlijst

| gebruik | niet meer |
| --- | --- |
| Samen | Forum, community |
| Run | activiteit, training (training alleen voor schema) |
| Moment | vertrektijd, loopmoment door elkaar |
| Vorm | fitheid, klaar-score (score blijft als getal) |
| beter / minder goed | punten |
| Doelen | uitdagingen + badges + bingo + jaardoel |
| Logboek | Runs (als tabnaam) |

---

## 5. Oud → nieuw

| functie | nu | nieuw | actie |
| --- | --- | --- | --- |
| Beste moment | Vandaag | Vandaag (hero) | tonen |
| Buien, aantrekken, waarschuwingen | Vandaag-kaarten | Vandaag, slimme 3 | tonen (automatisch gekozen) |
| Per uur, gouden uur | Vandaag | Meer vandaag | verbergen |
| Weekplanner, weekend, recordweer | 3 kaarten op Vandaag | Deze week | samenvoegen |
| Trainingsschema, wedstrijden | Ik | Deze week | verhuizen |
| Werkrooster | alleen via Hulp-zoeken | Deze week + vraag bij start | **zichtbaar maken** |
| Wind op route, beste route, nog een keer | Vandaag | Vandaag (na 1e route) | ontgrendelen |
| Veilig onderweg (live) | Vandaag-kaart | startscherm van Lopen | verhuizen |
| Opnemen | knoppen op 9 plekken | grote ● Lopen-knop (+ bestaande knoppen) | tonen |
| Routes, maken, tekenen, horloge | Routes | Routes | blijft |
| GPS-kunst | knop in Tekenen | Routes → Tekenen → "Vorm" | blijft, minder zichtbaar |
| Runs, records, vorm, badges | Runs + Ik | Logboek | samenvoegen |
| Jaarverhaal, op deze dag | Vandaag + Runs | Logboek (na 20 runs) | samenvoegen |
| Kalender, heatmap, fotomuur | Runs-menu | Logboek: één weergaveknop | samenvoegen |
| Schoenen | 3 plekken | Logboek + slimme kaart als ze bijna op zijn | samenvoegen |
| Pijntjes | Ik | na-run vraag + Logboek | verhuizen |
| Jaardoel, maanduitdaging, bingo, uitdagingen, badges | 5 plekken | Logboek → Doelen | **samenvoegen (akkoord nodig)** |
| Weddenschappen | Forum-chip | Samen → Uitdagingen ("1-op-1") | samenvoegen |
| Loopmaatjes, loopgroepen | Forum-chips | Samen (na 3 gevolgd) | ontgrendelen |
| Coach | tab | knop op Vandaag, Logboek, run-detail | **tab weg (akkoord nodig)** |
| Shop, posters, Luxe | 3 plekken | Ik → Shop (+ "Poster maken" bij een route) | samenvoegen |
| Vriend uitnodigen | 3 plekken | Samen + Ik | 2 plekken |
| Kadans-effect-badge | rundetail | in de 1 zin bovenaan | samenvoegen |
| Instellingen hond/pollen/regen/kleding | Ik → Training | Ik → Instellingen | verhuizen |
| Zoeklijst in Hulp | 25 bestemmingen | blijft als zoekfunctie in Ik | blijft |

Niets wordt verwijderd: alles wat "samenvoegen" of "verbergen" heet, blijft in de code en is terug te zetten.

---

## 6. Plan in 3 rondes

**Ronde 1 – Vandaag rustig (veilig, meteen zichtbaar)**
- Nieuwe gebruikers: standaard alleen moment + max 3 slimme kaarten + "Meer vandaag". Wie zelf al iets heeft ingedeeld, houdt zijn indeling.
- Weekplanner + weekend + recordweer → "Deze week", met rooster en schema erin.
- Bij de rondleiding: "Werk je in diensten?" → rooster koppelen.
- Woorden: Forum → Samen, punten → woorden.
- Build + schermafbeeldingen van alleen Vandaag en Deze week.

**Ronde 2 – Navigatie (na jouw akkoord)**
- 6 → 4 tabs + ● Lopen-knop; Ik via avatar; Coach als knop.
- Runs heet Logboek; records/vorm/badges/schoenen erin.
- Ik in 4 groepen. Deeplinks (`runwise://app/...`) en paden blijven werken.
- Build + schermafbeeldingen van de tabbalk, Logboek en Ik.

**Ronde 3 – Ontgrendelen en Doelen (na jouw akkoord)**
- Functies verschijnen pas als ze nodig zijn (tabel bij test 4) + "Nieuw voor jou"-bericht.
- Eén Doelen-scherm in plaats van zes spelvormen.
- Run-detail: samenvatting + drie open te klappen kopjes.
- Build + schermafbeeldingen van Doelen en run-detail.

---

## Beslissingen voor Sem

1. **Coach als knop in plaats van tab?** (Ik: ja. Minder tabs en de coach staat waar de vraag ontstaat.)
2. **Zes spelvormen samenvoegen tot Doelen?** (Ik: ja. Bingo en weddenschappen gaan dan op in Doelen.)
3. **Ronde 1 meteen bouwen?** (Veilig: er verdwijnt niets, alleen standaard minder in beeld.)
