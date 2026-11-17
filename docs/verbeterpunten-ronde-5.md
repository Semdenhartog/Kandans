# Verbeterpunten ronde 5 (17-11-2026)

50 verbeteringen aan wat er al is (geen nieuwe opties of schermen), nieuw ten opzichte van `later`, `ronde-3` en `ronde-4`.
Maat: S = klein, M = middel, L = groot. `(*)` = uit een telling of uit mijn geheugen, nog niet per geval nagelopen.
Basis: telling op de code van 17-11 (main groen). Gecontroleerd: `app_errors` wordt al na 60 dagen opgeruimd (dus niet opgenomen);
de twee `<img alt="">` op de voorpagina zijn bewust leeg (versiering).

## A. Tests en betrouwbaarheid van het rekenwerk
1. `domain/fit_parser.dart`: geen enkele test importeert hem. Test met leeg, afgekapt en beschadigd bestand: nooit een crash, wel een nette melding. (S)
2. `domain/race_forecast.dart`: geen test; wedstrijdvoorspelling controleren op grenzen (kort/lang, geen data). (S)
3. `domain/run_goal.dart`: geen test; doel halen/net missen/geen runs. (S)
4. `domain/shoes.dart`: geen test; kilometers optellen, afgeschreven schoen, schoen verwijderen. (S)
5. `DateTime.now()` staat 233× in de code, ~10× in `domain/` (`start_time_scoring`, `forecast_confidence`, `club_calendar`, `roster`, `race_forecast`, `run_recorder`). Geef die functies een `now`-parameter zodat tests niet rond middernacht falen. (M)
6. Zomer-/wintertijd-test voor de weekindeling (ma–zo) van Schema op maat en het rooster. (S) (*)
7. Test op schrikkeljaar en jaarwisseling in `monthly_goal`, `year_recap`, `weekly_load`. (S) (*)
8. Test dat elke `tr('…')`-sleutel in `vertalingen.py` voorkomt (nu merk je een ontbrekende vertaling pas op het scherm). (M) (*)
9. Test voor `friendlyError`: bekende fouten (geen verbinding, 401, quota, time-out) geven de juiste Nederlandse zin. (S) (*)
10. Test die `HealthConsent.ensure` afdwingt vóór elke Health Connect-aanroep (zoals `strava_filter_guard_test`); nu 6 bestanden die stappen lezen. (M)

## B. Server en verbindingen
11. 18 plekken roepen een edge function aan (`.invoke(`), maar maar 7 hebben een time-out. Eén dunne aanroeper met standaard 20 s en een nette melding. (M)
12. `route_generator_service`: één herhaalpoging na 2 s bij een tijdelijke fout (502/504) voordat de gebruiker een foutmelding ziet. (S) (*)
13. Rate-limit van de server (vriendcode 20/dag, groepscode 15/dag, wachtlijst 5/uur) als eigen foutsoort tonen: "Morgen weer 20 pogingen" i.p.v. een algemene fout. (S) (*)
14. Migratietest uitbreiden met een controle dat **elke tabel in `public` row level security aan heeft** (nu alleen "alles draait"). Valt de test om, dan is het een lek. (S)
15. Dezelfde test: elke `security definer`-functie moet een vast `search_path` hebben. (S) (*)
16. `race_import_runs` en `private`-logtabellen: ouder dan 90 dagen opruimen in het nachtelijke werk (zoals `app_errors`). (S) (*)
17. Supabase-adviseurs (beveiliging + prestatie) doorlopen op ontbrekende indexen op kolommen die in `where`/`join` staan (wedstrijden, community_*). (M) (*)
18. Edge-function-helpers in `_shared/` hebben tests met `node --experimental-strip-types`; in CI laten draaien (nu alleen met de hand). (S) (*)

## C. Opslaan op het toestel
19. `SharedPreferences.getInstance()` staat 182× in de code (25× in `record_run_screen.dart`, 9× in `sync_service.dart`, 8× in `dashboard_providers.dart`). Eén gedeelde, eenmaal geladen instantie. (M)
20. Opnemen: alle instellingen die de start nodig heeft in één keer inlezen vóór de knop "Start" actief wordt, i.p.v. 25 losse leesbeurten. (M) (*)
21. Voorkeur-sleutels op één plek als constanten (nu losse tekstjes door de code: één typefout = stille reset). (M) (*)
22. Prefs met JSON (`share_studio_layout`, `route_anim_layout`, `custom_plan_wishes`): bij een kapotte waarde terugvallen op de standaard en één keer melden, niet crashen. (S) (*)
23. Bij uitloggen alle persoonlijke prefs wissen (nu worden vastgezette tegels wel gewist, de rest niet aantoonbaar). (S) (*)

## D. Structuur en onderhoud van de code
24. `record_run_screen.dart` (3683 regels) opsplitsen in kaartpagina, cijferpagina, bedieningsknoppen, waarschuwingen: begin met het stuk dat het vaakst verandert. (L)
25. `run_recorder_service.dart` (1314 regels, 5 timers): splitsen in GPS-stroom, pauze/auto-pauze, stem/meldingen en opslaan. (L)
26. `dashboard_screen.dart` (1979): de `_TodayScene`, `_HourBars` en `_WeekRow` naar eigen bestanden. (M)
27. `route_map.dart` (1146) en `activities_screen.dart` (1098): zelfde aanpak, per stuk één taak. (L)
28. `custom_plan_screen.dart` (1036) en `domain/custom_plan.dart` (857): scherm los van rekenregels, zodat een nieuwe vraag geen vier bestanden raakt. (M)
29. Navigatie: 65× `Navigator.push` naast 72× `context.push/go`. Schermen die via een link bereikbaar moeten zijn (route delen, moment, coach) alleen via go_router. (M) (*)
30. 125 losse `Duration(milliseconds: …)`: drie vaste snelheden (kort/normaal/lang) in één bestand, met "minder beweging" op één plek. (M)
31. `MediaQuery.of(context)` (7×) naar `MediaQuery.sizeOf`/`textScalerOf`: het scherm herbouwt dan alleen bij wat echt verandert. (S)
32. 11× een losse `SnackBar(` (`route_undo`, `activities_screen`, `home_shell`, `widgets`, `roster_screen`, `watch_export`) naar één gedeelde functie met dezelfde duur, vorm en TalkBack-melding. (S)
33. 76× `ListView(` met vaste kinderen; waar de lijst groeit (`community_feed_screen`, `together_screens`, `people_screen`) `ListView.builder`. (M) (*)
34. 6× `FutureBuilder` (`connections_card`, `segments_screen`, `hrr_card`, `hindsight_card`): ook een foutstaat tonen, nu waarschijnlijk alleen laden/klaar. (S) (*)
35. `DateTime.now()` in `build()`-methoden vervangen door één klok per scherm (voorkomt flikkeren rond het hele uur). (M) (*)

## E. Uitleg en overdracht
36. `CLAUDE.md` is 327 regels / 43 KB en wordt elke sessie gelezen (tegen "zuinig werken"). Afgeronde rondes en dagnotities (6-11 t/m 15-11) naar `docs/overdracht-archief.md`, het blad zelf onder ~15 KB. (M)
37. `VERBETERPUNTEN.md` (388 regels) en vier losse lijsten in `docs/`: één `docs/backlog.md` met status per punt (gedaan / niet / bewust niet). (M)
38. "Open punten voor Sem" in CLAUDE.md (±30 regels, veel van oude data): groeperen op onderwerp en afgeronde weghalen. (S)
39. De Codekaart-regels in CLAUDE.md met één voorbeeldcommando per soort vraag (`explain`, `path`) i.p.v. alleen uitleg. (S)
40. `docs/play-store.md`: een afvinklijst "vóór insturen" bovenaan (privacy-URL, gegevensveiligheid, screenshots, promovideo). (S) (*)

## F. Website (kadans.fit)
41. `robots.txt` en `sitemap.xml` ontbreken in `site/`. (S)
42. `og:image` staat op 2 van 11 pagina's; de rest deelt dus zonder voorbeeldplaatje in WhatsApp/Instagram. (S)
43. Subpagina's (privacy, voorwaarden, verwijderen, steun, vriend, contact) hebben nog de oude stijl; de voorpagina is al vernieuwd. Eén gedeelde `pagina.css` in de nieuwe stijl. (L)
44. Hero- en voetbeeld (140 kB / 96 kB) en de zes foto's (668 kB): WebP naast JPG met `<picture>`; scheelt op mobiele data. (M) (*)
45. `<link rel="preload">` voor de twee lettertypes die boven de vouw staan (Saira, DM Sans) tegen een flits van reservelettertype. (S) (*)
46. Wachtlijstformulier: na verzenden de knop uitzetten en bij een fout de ingevulde mail laten staan (nu mogelijk dubbele inzending / leeg veld). (S) (*)
47. `site.yml` controleert DNS; ook een snelle controle dat alle interne links en afbeeldingen bestaan (geen 404 live). (S)

## G. Bestaande schermen en teksten
48. Gebruik van `semanticLabel`: 84 `Semantics(`, maar slechts 4 afbeeldingen met label; kaartjes en foto's in Samen en Fotomuur krijgen een korte omschrijving. (S) (*)
49. Eén lettertype-voorlaad vóór het exporteren van deelkaart en routevideo, zodat de eerste export niet in een reservelettertype staat. (S) (*)
50. Wanneer de codekaart (`graaf`) ouder is dan `main`, toont `tools/graaf.sh` een waarschuwing met het aantal commits verschil (nu alleen "veranderd"). (S) (*)

## Advies voor een eerste ronde (één build, klein risico)
- **1–4 en 9, 10:** alleen tests, geen gedrag verandert; vangen fouten die nu pas op een telefoon opvallen.
- **14, 41, 42, 36–38:** CI-test, bestanden voor de site en een kleinere `CLAUDE.md`. Weinig risico, meteen merkbaar (schonere sessies).
- **19–21 en 32:** zichtbaar sneller en consistenter, maar raken veel bestanden: één groep per build.
- **24–28** (grote bestanden splitsen) alleen als je er toch in werkt; een split zonder toestel-test is risicovol.

## Stand 17-11
**Gedaan:** 1 (`fit_parser_test`), 4 (`shoes_test`), 9 (`friendly_error_test`), 10 (`health_consent_guard_test`), 14 + 15 (RLS- en search_path-controle in `tools/migraties_testen.sh`;
live gecontroleerd: nu 0 afwijkingen), 31 (`MediaQuery.sizeOf`/`disableAnimationsOf`), 32 (twee gewone meldingen via `showMessage`; de met "Ongedaan maken" blijven bewust een SnackBar),
36–38 (CLAUDE.md 43 → 37 KB: rondenotities en marketing naar het archief), 41 + 42 (`robots.txt`, `sitemap.xml`, `og:image` op alle openbare pagina's, `noindex` op beheer/bedankt),
47 (`tools/site_links.py` in `site.yml`, alleen waarschuwing), 50 (`graaf.sh` toont aantal commits en gewijzigde bestanden).
**Niet gedaan:** 2, 3 (nog geen test; ingang `adviseRace`/`RunGoal` vraagt eerst uitzoeken), 5–8, 11–13, 16–35 (behalve 31/32), 33–35, 39, 40, 43–46, 48, 49.
Reden: raken veel bestanden of zijn alleen op een toestel/in de database te controleren; liever per groep met controle.
