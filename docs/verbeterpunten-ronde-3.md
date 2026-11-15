# Verbeterronde van 50 punten – verbeteringen op wat er al is (15-11-2026)

Alleen aanpassingen van bestaande onderdelen, niet de eerdere lijst (`docs/verbeterpunten-later.md`) herhalen.
Maat: **S** = uurtje, **M** = halve dag, **L** = grote klus. `(*)` = uit de codekaart/geheugen, vóór bouwen eerst in de code controleren.
Alles is nog niet op een telefoon getest; punten met "meten" kunnen alleen op Sems Samsung.

## A. Routevideo (nieuw, 14-11)
1. Foto verschuiven en inzoomen in het voorbeeld; nu altijd midden bijgesneden, dus een gezicht kan wegvallen. (M)
2. Hulplijnen bij het verslepen: klik naar midden en naar de marge, zodat tekst netjes uitlijnt. (S)
3. Tekst en logo ook kleiner/groter maken (knijpen), net als in de deelstudio. (M)
4. Eigen titel typen boven de video; nu alleen de runtitel of datum. (S)
5. De route zelf verplaatsen en schalen; `routeBox` staat vast, een foto met onderwerp in het midden bijt de lijn. (M)
6. De echte foutreden van de encoder tonen (nu altijd "niet gelukt") en terugvallen op lagere bitrate/24 fps bij falen. (M)
7. Keuze 720p of 1080p (nu vast 720×1280, 5 Mbps). (S)
8. Lengte van de video kiezen (nu vast 6–8 s). (S)
9. Maken op de achtergrond met voortgang in de melding, zodat het scherm niet open hoeft. (L)
10. Schermtest voor de routevideo met foto in `screens.yml` (foutjes met leesbaarheid zie je dan zonder telefoon). (M)

## B. Deelstudio en delen
11. Foto kiezen, wisselen en bijsnijden is nu dubbel gebouwd (deelstudio + routevideo): één gedeeld onderdeel in `lib/shared/`. (M)
12. Hulplijnen en "ongedaan maken" in de deelstudio (nu geen undo). (M)
13. Meerdere bewaarde indelingen met naam ("Story", "Bericht"); nu één indeling in prefs. (M)
14. Deelkaart: bij te lange runtitel netjes afkappen met "…", en testen met grote letters. (S)
15. Na delen een korte bevestiging dat de kaart in de galerij staat (nu onduidelijk of het gelukt is). (S)

## C. Offline kaarten
16. Download hervatten na het sluiten of doden van de app (nu begint hij opnieuw). (M)
17. Per route tonen hoeveel MB is opgeslagen en per pakket kunnen verwijderen. (S)
18. Automatisch downloaden voor favoriete routes, alleen op wifi en met laden. (M)
19. Bij een route buiten Nederland duidelijk melden dat offline daar niet kan (alleen PDOK), i.p.v. een knop die niets doet. (S)
20. Meten of vliegtuigstand echt de vastgezette tegels toont op Sems telefoon, inclusief opnemen met GPS. (S, alleen op toestel)

## D. Opnemen en alarmen
21. Hartslagalarm: tijdens interval/herstel uitschakelen, anders piept hij op de snelle stukken. (S)
22. Hartslagalarm: aantal keren afgegaan in de samenvatting van de run. (S)
23. Vergrendelscherm-chip beter vindbaar (staat onder "Meer opties"); eenmalige tip bij de eerste run. (S)
24. Aftellen 3-2-1: pauze toestaan bij een inkomend gesprek. (*) (S)
25. Tempo-alarm en hartslagalarm delen één cooldown, zodat er niet twee meldingen vlak achter elkaar komen. (S)
26. `record_run_screen.dart` (3683 regels) opsplitsen per onderdeel; dit is de grootste risicoplek. (L)

## E. Vandaag en advies
27. "Waarom dit moment?" ook tonen op de widget en in de melding, niet alleen op het scherm. (M)
28. Bij het advies het alternatief erbij: "1 uur later: 12% meer regen". Past in dezelfde sheet. (M)
29. Weer-uur kiezen door te slepen (staat er al) ook als tikje op een staaf met uitleg in woorden voor TalkBack. (S)
30. Cloudy aan/uit in Ik (voor wie het mascotte-tintje niet wil); nu staat hij op Vandaag en lege schermen vast. (S)
31. `dashboard_screen.dart` (1978 regels) opsplitsen: advieskaart, uren, Deze week elk eigen bestand. (L)

## F. Coach
32. "Ja" herkennen in meer varianten ("ja graag", "doe maar", "ok") en ook zonder hoofdletters/leestekens. (*) (S)
33. Vervolgvraag-chips: maximaal drie tonen en de volgorde bepalen op relevantie, niet op volgorde in het bestand. (*) (S)
34. Schema-in-gesprek: een "terug"-knop voor de laatste vraag (nu alleen "stop"). (M)
35. Schema-in-gesprek: tekst als "veertig" of "2 uur" begrijpen bij km en tijd. (M)
36. Kennisantwoorden met een "laatst nagekeken"-datum, zodat oude feiten (regels, tijden) opvallen in het beheer. (M)
37. Zoekdrempel 0,45 per categorie meten met de onbeantwoorde vragen i.p.v. één getal voor alles. (M)

## G. Schema op maat en wedstrijden
38. Bij een gemiste week het schema herrekenen in plaats van gewoon doorschuiven. (L)
39. PDF-check: Sems laatste feedback na de nieuwe APK verwerken (open punt 11-11). (S)
40. Wedstrijdkalender: gekozen straal en soort onthouden. (*) (S)
41. Herinnering een week en een dag voor een wedstrijd in "Mijn wedstrijden". (M)

## H. Voortgang en beloning
42. Badges met niveau: "nog 2 km tot zilver" tonen. (S)
43. Uitleg bij leeftijdsniveau (age grading) in gewone woorden, nu alleen een getal. (S)
44. Hoogtemeters: tonen of de waarde van barometer of GPS komt (twee bronnen, andere nauwkeurigheid). (S)

## I. Privacy en veiligheid
45. Privacyzone voor de routevideo koppelen aan de eigen instelling in plaats van vaste 300 m. (S)
46. Test in CI die controleert dat elke query naar coach en Samen het Strava-filter bevat (`source <> 'strava'` én `external_id not like 'viastrava-%'`). Dit is vaste regel 2 en nu alleen afspraak. (M)
47. Overzichtsscherm "Welke gezondheidsgegevens gebruikt Kadans nu" onder Ik → Gezondheidsgegevens, met per bron intrekken. (M)

## J. Kwaliteit en onderhoud
48. Ratchet-test voor bestandsgrootte: bestanden boven 300 regels mogen niet groeien (net als de vertaal-ratchet). (S)
49. Vertaal-ratchet elke ronde 50 omlaag (nu 550); hier 550 → 500 als vaste afspraak. (S)
50. Smoke-test voor `RouteAnimPainter` en `RouteAnimFx` (tekent een beeld met en zonder foto zonder fouten) naast de bestaande domeintests. (S)

## Advies voor de volgorde
Eerst goedkope punten met direct effect: 1, 2, 4, 21, 22, 32, 33, 45, 46, 48. Daarna 11 (voorkomt dubbel werk), 6 en 16.
Grote opsplitsingen (26, 31) apart plannen: één bestand per ronde, anders loopt de build-controle uit de hand.

## Stand 15-11 (nacht)
Gedaan: 1, 2, 4, 6 (alleen reden tonen, geen lagere-bitrate-terugval), 40, 46 (bewaking van de filters, geen volledige querycontrole), 48, 50.
Al aanwezig, dus geen werk: 17 (MB per route + verwijderen), 19 (knop is al verborgen buiten Nederland), 32 (`isJa` herkent "ja graag", "doe maar", "oké").
Niet gedaan: de rest. Reden: alleen op de telefoon te testen (20, 39), te groot voor deze ronde (9, 26, 31, 38) of eerst controleren in de code `(*)`.
