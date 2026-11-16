# Verbeterpunten ronde 4 (16-11-2026)

50 aanpassingen aan wat er al is. **Geen nieuwe opties of schermen.** Niet herhaald uit `verbeterpunten-later.md` of `-ronde-3.md`.
Maat: S = klein, M = middel, L = groot. `(*)` = uit de telling of uit het geheugen, de code nog niet per geval nagelopen.

Cijfers uit de code van 16-11: 99 lege `catch (_) {}`, 64 teksten kleiner dan 11 px, 353 vaste `Color(0x…)`,
83 `IconButton`s (82 met tooltip), 20 bestanden met `TextEditingController()`, 8 bestanden met `Timer.periodic`.

## A. Fouten niet meer inslikken (betrouwbaarheid)
1. `disk_image_cache.dart` (6 lege catches): bij schijffout of vol toestel melden aan `ErrorReporter` (één keer per sessie) i.p.v. stil falen. (S)
2. `kadans_voice.dart` (5): stemfout wel loggen met reden (`_explain`-sleutel), nu verdwijnt hij soms. (S) (*)
3. `sync_service.dart` (4): mislukte sync onthouden en bij volgende start opnieuw proberen, met "laatst gelukt"-tijd. (M) (*)
4. `poi_service.dart` (4): als alle Overpass-servers falen "water/toilet niet geladen" tonen i.p.v. een lege lijst. (S)
5. `community_screen.dart` (4): foutmelding met "Opnieuw proberen" i.p.v. leeg scherm. (S) (*)
6. `first_tips.dart` (3): terugvallen is hier prima, maar de overige lege catches in `lib/shared` nalopen en elk één regel uitleg geven. (S)
7. Eén hulpfunctie `swallow(e, st, where)` die in debug logt en in release alleen telt; alle 99 plekken daarop zetten. (M)
8. Lint-regel `empty_catches` aanzetten als ratchet-test (aantal mag alleen dalen), net als de vertaal-ratchet. (S)
9. Timers nalopen op `cancel()` in `dispose` (run_recorder_service ×5, stride_sensor, strength, dashboard, live_share, hrr, poster_orders). (M) (*)
10. `TextEditingController`s in de 20 bestanden nalopen op `dispose()` (geheugenlek bij herhaald openen). (M) (*)

## B. Leesbaarheid en toegankelijkheid
11. 64 teksten onder 11 px: minimum 12 px behalve in de PDF; eerst `route_map.dart`, `dashboard_screen.dart`, `share_run_screen.dart`. (M)
12. Afkapregels (`maxLines` + `ellipsis`) bij titels op kaarten die bij letters 1,6× nu overlopen; schermtest met grote letters uitbreiden. (M) (*)
13. De ene `IconButton` zonder tooltip alsnog een tooltip geven (en tellen in een test). (S)
14. Tikdoelen < 48 px in `InkWell`/`GestureDetector` (60 + 26 plekken) nalopen, zoals bij Cloudy gedaan. (M) (*)
15. Alle `GestureDetector`s zonder `behavior` die op lege ruimte moeten reageren (zelfde fout als Cloudy) opsporen. (M) (*)
16. `Semantics`-labels op de weerbalkjes per uur: "16:35, beste moment, droog" i.p.v. alleen een staaf. (S)
17. Contrast van `RwColors.muted` op `rwZand` en op de foto-scène controleren (WCAG AA 4,5:1). (S) (*)
18. Tempolegenda in het runoverzicht: naast kleur ook een cijferreeks (bijv. "4:50–5:30") die altijd zichtbaar is. (S)
19. Focus-volgorde en "terug"-gedrag op `BackToTabScope` testen met TalkBack aan. (M) (*)
20. Animaties (Cloudy-wip, tellers, kantelen) overal laten stoppen bij "minder beweging"; tellen waar dat nog niet zo is. (M) (*)

## C. Huisstijl en consistentie
21. 353 vaste `Color(0x…)` terugbrengen naar `RwColors`/`RwPalette` (eerst de plekken die in donker mis zien). (L)
22. Ratchet-test op vaste kleuren, zodat het aantal niet stijgt (uitzondering: kunst in `shared/art`, posters, PDF). (S)
23. Alle plekken waar nog een pil om een knop staat (21× `999`) naar blok 8 of bewust laten staan met commentaar. (S)
24. Alle `Radius.circular(n)` met n buiten 8/16/24 naar `RwRadius`. (S) (*)
25. Dialogen en bladen die nog niet 24 px afronding hebben gelijktrekken. (S) (*)
26. Eén `RwSpacing` (4/8/12/16/24) i.p.v. losse getallen in nieuwe en aangeraakte bestanden. (M)
27. Laadtoestand: overal dezelfde spinner/skelet; nu per scherm verschillend (*). (M)
28. Lege toestand en foutstaat op dezelfde plek en met dezelfde toon in Samen, Logboek, Routes. (M) (*)
29. Emoji in 5 bestanden (unslop-restant) vervangen door eigen icoontjes of weglaten. (S)
30. Gloed bij Uitdagingen (unslop-restant) neutraal maken. (S)

## D. Snelheid en accu
31. `record_run_screen.dart` (3683 regels): bij elke GPS-tik herbouwt waarschijnlijk meer dan nodig; met `RepaintBoundary` en `select` op de cijfers beperken. (L) (*)
32. `dashboard_screen.dart` (1976): de landschapsscène niet opnieuw tekenen bij elke provider-wijziging (`RepaintBoundary` + `const`-kinderen). (M) (*)
33. `route_map.dart` (1144): tegels buiten beeld niet laten decoderen; `cacheWidth` op kleine tegels. (M) (*)
34. Foto's in Samen/fotomuur: `cacheWidth` meegeven zodat een 12 MP-foto niet vol in geheugen komt. (S) (*)
35. Weer-/Overpass-aanvragen met dezelfde sleutel binnen 60 s hergebruiken (nu per scherm eigen vraag). (S) (*)
36. Vandaag: bij terugkeren naar de tab niet opnieuw alles ophalen als de data < 5 min oud is. (S) (*)
37. Het wippen van Cloudy en de `_CountClock` laten stoppen als het tabblad niet zichtbaar is (`TickerMode`). (S)
38. Routevideo: voorbeeldscherm pauzeren zodra de app naar de achtergrond gaat. (S)
39. Grote lijsten (Logboek, Samen-feed) met `itemExtent`/`prototypeItem` waar de hoogte vast is. (S) (*)
40. Opstarttijd: zware init (`DiskImageCache`, stem prefetch, wedstrijdkalender) na de eerste frame uitvoeren. (M) (*)

## E. Bestaande schermen netter
41. Opnemen: bij pauze de knop "Hervat" op dezelfde plek als "Pauze", zodat je niet hoeft te zoeken met zweethanden. (S) (*)
42. Opnemen: na "Stop" bevestigen met een tik-en-houd i.p.v. een dialoog (minder per ongeluk beëindigen). (S) (*)
43. Samenvatting: notitieveld en schoenkeuze onthouden bij sluiten zonder opslaan (concept). (M) (*)
44. Coach: lange antwoorden inklappen na ~8 regels met "Lees verder"; chips blijven zichtbaar. (S)
45. Coach: bij geen internet meteen zeggen dat alleen kennis en eigen data werken, i.p.v. een algemene fout. (S) (*)
46. Samen → Wedstrijden: bij afstand tot 1 km "in jouw buurt" i.p.v. "0 km" (kommagetal netjes). (S) (*)
47. Routes: de kaartkleuren van gouden looppaden in donker iets dunner op uitzoomen, nu overheerst het (*) . (S)
48. Rondleiding: stap 3 (locatie) overslaan zonder dat het advies er daarna "kapot" uitziet (nette lege toestand). (S) (*)
49. Schema op maat: de waarschuwingsregels (te korte lange duurloop enz.) staan één keer bovenaan, niet verspreid per week. (S) (*)
50. Instellingen: "Ik → Hulp" toont versie + build-nummer + datum van de APK, zodat Sem bij een bugmelding weet welke build het was. (S)

## Advies voor een eerste ronde (~1 dag, één build)
- Eerst **7 + 8** (hulpfunctie + ratchet), dan **1–5** erop zetten: dit is de meeste winst voor het minste risico.
- Daarna **9 + 10** (timers en controllers), want een lek geeft pas na een uur lopen een probleem en dat vang je niet met testen op de telefoon.
- **11, 13, 22, 23, 24** zijn klein en zichtbaar.
- **31–33** pas na meten: zonder profiel (`flutter run --profile`) weet ik niet zeker dat dit de knelpunten zijn; Flutter staat niet lokaal, dus dat kan alleen Sem op de telefoon.
- Niet doen zonder overleg: **21** (353 kleuren) is groot en kan donker/licht breken; liever per scherm bij werk dat er toch gebeurt.
