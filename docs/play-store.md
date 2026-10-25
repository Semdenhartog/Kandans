# Play Store – klaar om te plakken

Alles wat Google vraagt voordat Kadans in de Play Store mag. Gemaakt uit de echte rechten
en diensten in de code (22-10-2026). Klopt er iets niet meer na een wijziging, pas dit bestand dan ook aan.

## 0. Volgorde

1. Privacyverklaring afmaken (site/privacy.html) en GitHub Pages aanzetten → link werkt.
2. App bundle bouwen (maak-sleutel.ps1 + 4 geheimen in GitHub, zie README).
3. Play Console → app maken → **Interne tests** → bundle uploaden → 5–10 testers toevoegen.
4. Onderstaande formulieren invullen (stap 1–4).
5. Health Connect-aanvraag indienen (stap 5). Dit duurt bij Google vaak 1–3 weken: begin hier vroeg mee.
6. Pas na een week zonder grote fouten naar **Gesloten test** of **Productie**.

Let op: nieuwe persoonlijke ontwikkelaarsaccounts moeten eerst een gesloten test draaien
met minimaal 12 testers gedurende 14 dagen voordat productie mag. Controleer dit in je Play Console.

## 1. Rechten voor voorgrondservice (locatie)

Play Console → App-content → **Voorgrondservicerechten** → `FOREGROUND_SERVICE_LOCATION`.

**Taak:** Gebruiker gestarte activiteit (fitness/hardlopen).

**Beschrijving (plakken):**
> Kadans neemt een hardloopronde op die de gebruiker zelf start met de knop "Start run". Tijdens de opname
> gebruikt de app GPS om afstand, tempo, kilometertijden en de route te meten. De gebruiker legt de telefoon
> meestal in een zak of armband met het scherm uit; daarom draait de opname als voorgrondservice met een
> zichtbare, doorlopende melding ("Run bezig"). De service stopt zodra de gebruiker de run afrondt of pauzeert
> en weggooit. Er wordt geen locatie verzameld als er geen run wordt opgenomen.

**Video:** neem een schermopname (Android: snelinstellingen → Schermrecorder) van: app openen → Start run →
melding zichtbaar → scherm uit/aan → Run afronden → melding weg. 30–60 seconden is genoeg. Zet hem als
"Niet vermeld" op YouTube en plak de link.

Er is **geen** `ACCESS_BACKGROUND_LOCATION` nodig; vink bij "Locatie op de achtergrond" *Nee* aan.

## 2. Gegevensveiligheid (Data safety)

**Worden gegevens verzameld of gedeeld?** Ja, verzameld. Niet gedeeld met derden voor hun eigen doeleinden.
**Versleuteld tijdens verzending?** Ja (HTTPS). **Kan de gebruiker verwijdering aanvragen?** Ja, in de app (Ik → Account verwijderen).

| Gegevenstype (Play-categorie) | Verzameld | Waarom | Optioneel? |
|---|---|---|---|
| Locatie → Precieze locatie | Ja | App-functionaliteit (runs opnemen, weer voor je plek, routes) | Ja |
| Persoonsgegevens → Naam | Ja | Accountbeheer | Ja |
| Persoonsgegevens → E-mailadres | Ja | Accountbeheer | Nee |
| Persoonsgegevens → Adres | Ja | Accountbeheer (alleen als je het invult) | Ja |
| Persoonsgegevens → Andere info (geboortedatum, geslacht) | Ja | Personalisatie (hartslagzones, voorspellingen) | Ja |
| Gezondheid en fitness → Gezondheidsinfo (hartslag, rusthartslag, HRV, slaap) | Ja | App-functionaliteit, personalisatie | Ja |
| Gezondheid en fitness → Fitnessinfo (runs, afstand, tempo) | Ja | App-functionaliteit | Nee |
| Foto's en video's → Foto's | Ja | App-functionaliteit (foto's bij een run) | Ja |
| Berichten → Andere berichten in de app (coachvragen) | Ja | App-functionaliteit | Ja |
| App-activiteit → Andere door gebruiker gegenereerde content (notities, gevoel) | Ja | App-functionaliteit | Ja |
| App-info en prestaties → Crashlogs / Diagnostiek | Ja | Analyse (foutmeldingen, max. 60 dagen) | Nee |
| Financiële info → Aankoopgeschiedenis | Ja | Abonnement (via Google Play/RevenueCat) | Ja |

**Verwerkers (geen "delen" volgens Google, maar wel noemen in de privacyverklaring):**
Supabase (database, EU), Anthropic (AI-coach, alleen bij een coachvraag; geen Strava-data),
Open-Meteo en Buienradar (weer; alleen coördinaten), OpenRouteService en PDOK (routes, adressen),
Mapillary (straatfoto's; coördinaten van de route), RevenueCat (abonnement), Strava (alleen als je koppelt).

## 3. Overige App-content-formulieren

- **Doelgroep:** 18+ (of 16+). Niet voor kinderen.
- **Advertenties:** Nee.
- **Toegang tot de app:** inloggen nodig → maak een testaccount voor Google en vul e-mail + wachtwoord in
  (gebruik niet je eigen account).
- **Gezondheidsapps-verklaring:** categorie "Fitness en activiteit". Geen medisch hulpmiddel.
- **Overheid / Financieel / Nieuws:** Nee.

## 4. Gevoelige rechten die Google kan navragen

| Recht | Waarom (plakken) |
|---|---|
| `USE_BIOMETRIC` | Optionele vingerafdrukvergrendeling van de app. |
| `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` | Koppelen van een hartslagband (Bluetooth). Geen locatie afgeleid (`neverForLocation`). |
| `SET_ALARM` | Wekker zetten voor het beste vertrekmoment, alleen na een tik van de gebruiker. |
| `RECEIVE_BOOT_COMPLETED` | Herinneringen na herstart van de telefoon opnieuw inplannen. |
| `POST_NOTIFICATIONS` | Melding tijdens de run en herinneringen voor het beste moment. |

## 5. Health Connect

Play Console → App-content → **Health Connect**. Per recht een reden:

| Recht | Reden (plakken) |
|---|---|
| READ_EXERCISE, READ_DISTANCE | Runs van je horloge (Garmin, Fitbit, Samsung …) automatisch in Kadans zetten. |
| READ_HEART_RATE | Gemiddelde hartslag bij een run tonen en hartslagzones berekenen. |
| READ_RESTING_HEART_RATE, READ_HEART_RATE_VARIABILITY, READ_SLEEP | Dagelijkse klaar-score: is vandaag geschikt voor een zware of lichte training. |
| WRITE_EXERCISE, WRITE_DISTANCE, WRITE_TOTAL_CALORIES_BURNED | In Kadans opgenomen runs terugschrijven, zodat andere apps ze zien (alleen als de gebruiker dit aanzet). |

De privacyverklaring moet een kopje over Health Connect bevatten: welke gegevens, waarvoor, en dat ze niet
worden verkocht of voor advertenties gebruikt. Controleer dit in site/privacy.html.

## 6. Winkelvermelding

- **Korte beschrijving (max. 80 tekens):** Loop op het beste moment: weer, wind en jouw route in één advies.
- **Schermafbeeldingen:** staan klaar in de branch `schermen-main`, map `playstore/` (1080×1920, in de
  goede volgorde genummerd). Ze worden bij elke schermtest opnieuw gemaakt met voorbeeldgegevens.
  Download: GitHub → branch `schermen-main` → map `playstore` → bestand → "Download raw file".
- **Feature graphic (1024×500):** nog niet gemaakt; dat is ontwerpwerk (logo + slogan). Kan in Claude Design of Canva.
- **Contact-e-mail:** apart adres aanbevolen (niet je persoonlijke Gmail).
