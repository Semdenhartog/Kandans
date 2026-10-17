# RunWise – Android-app (v1)

Flutter-app die de beste vertrektijd voor je loopje berekent op basis van het weer, de wind op je route en je eigen prestaties.

## Wat zit erin (v1, gratis versie)

| Tabblad | Functie |
|---|---|
| **Vandaag** | Beste vertrektijd voor de komende 36 uur, per type training (rustig, tempo, lang, herstel). Rekent met tegenwind op je route, temperatuur, regen, donker, UV en benauwdheid. Score per uur in een grafiek. |
| **Runs** | Runs toevoegen. Het weer van dat moment wordt automatisch opgehaald (Open-Meteo). Weekoverzicht. |
| **Routes** | GPX importeren (Strava, Garmin, Komoot…). Routevorm, hoogtemeters, looprichting per km en tegen-/rugwind nu. |
| **Wedstrijden** | Wedstrijddoelen met verwachte eindtijd (Riegel-formule op je beste recente run), weercorrectie vanaf ~15 dagen vooraf, en advies voor tempo, kleding en drinken. |
| **Ik** | Persoonlijk loopprofiel (na 8 runs): ideale temperatuur, windgevoeligheid, ochtend of avond. Privacyverklaring, gegevens kopiëren, account verwijderen. |

**Premium (in aanbouw):** AI-hardloopcoach achter een abonnement: eerste maand gratis, daarna €5 per maand of €40 per jaar (via Google Play + RevenueCat). Gratis gebruikers krijgen 3 proefvragen.

**Koppelingen:** runs komen automatisch binnen van je horloge via **Health Connect** (Fitbit, Samsung, Garmin, Polar …; de laatste 30 dagen en daarna alles nieuw) en via **Strava**. Ophalen gebeurt bij het openen van de app en bij vernieuwen in Runs. Strava-runs gaan niet naar de AI-coach (Strava-voorwaarden).

Bewust **nog niet**: pushmeldingen en ophalen terwijl de app dicht is.

## Mappen

```
lib/
  core/        thema, router, instellingen, opmaak van getallen
  data/        modellen, database (Supabase), weer (Open-Meteo), locatie
  domain/      rekenwerk: vertrektijdscore, wind op route, loopprofiel, GPX, wedstrijdvoorspelling
  features/    de schermen per tabblad
  shared/      herbruikbare onderdelen
test/          automatische tests
supabase/functions/delete-account/   server-functie voor account verwijderen
```

De database-migraties staan in `supabase/migrations` (0001 t/m 0011) en zijn al toegepast op het Supabase-project.
De publieke Supabase-instellingen (URL en publishable key) staan in `app_config.json`; die zijn bedoeld om openbaar te zijn.

---

## Installatie (na de geheugen-upgrade)

### 1. Flutter en Android Studio installeren (eenmalig)
1. Installeer **Android Studio**: https://developer.android.com/studio
   Open het één keer en laat de setup-wizard de Android SDK installeren.
2. Installeer **Flutter**: https://docs.flutter.dev/get-started/install/windows/mobile
   (Pak de zip uit in bijvoorbeeld `C:\flutter` en zet `C:\flutter\bin` in je PATH.)
3. Open een nieuwe PowerShell en controleer:
   ```powershell
   flutter doctor
   flutter doctor --android-licenses   # alles accepteren met y
   ```

### 2. Project klaarzetten
```powershell
cd "$HOME\Desktop\runwise_project\app"
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```
Het script maakt de Android-bestanden aan, voegt de rechten toe, downloadt de pakketten en controleert de code.
**Staan er fouten in `analyze.txt` of `tests.txt`? Stuur ze naar Claude**, dan worden ze opgelost.

### 3. Supabase instellen (gratis)
1. Maak een account op https://supabase.com en een **nieuw project** (regio: *West EU*).
2. Ga naar **SQL Editor** en voer de bestanden uit `Desktop\supabase\migrations` één voor één uit,
   **0001 t/m 0010** (sla `0000_init_auth_schema.sql` over, die is alleen voor lokale tests).
3. **Authentication → Sign In / Providers → Email**: zet *Confirm email* aan.
4. **Authentication → Emails → Confirm signup**: zet de code in de mail, bijvoorbeeld:
   ```html
   <h2>Welkom bij RunWise!</h2>
   <p>Je activatiecode is: <strong>{{ .Token }}</strong></p>
   ```
5. **Edge Functions → Deploy a new function → Via editor**: naam `delete-account`,
   plak de inhoud van `supabase/functions/delete-account/index.ts` en klik op *Deploy*.
6. **Project Settings → API**: kopieer de **Project URL** en de **anon / publishable key**
   naar `config.json`. Gebruik **nooit** de service-role key in de app.

### 3a. Strava-koppeling instellen
1. Ga naar https://www.strava.com/settings/api en maak een API-app aan (naam RunWise).
2. Vul bij **Authorization Callback Domain** in: `jdswennyfczpqblfkrxt.supabase.co`
3. Supabase → **Edge Functions → Secrets**: zet `STRAVA_CLIENT_ID` en `STRAVA_CLIENT_SECRET` (zelf invullen, niet in een chat plakken).
4. Let op: een nieuwe Strava-app kan eerst maar een beperkt aantal sporters koppelen; meer aanvragen kan bij Strava.

### 3b. AI-coach en Premium instellen

**AI-coach (server-functie `coach`)**
1. Maak een account op https://console.anthropic.com, zet er een paar euro tegoed op en maak een **API key**.
2. Supabase → **Edge Functions → Secrets**: voeg `ANTHROPIC_API_KEY` toe met die key.
   (Optioneel `COACH_MODEL`; standaard `claude-haiku-5-5`.)
3. Zet in de Anthropic Console een **maandlimiet** op je uitgaven, zodat de kosten nooit uit de hand lopen.
4. Limieten aanpassen kan in de tabel `model_config`: `coach_free_questions` (standaard 3) en `coach_premium_daily_limit` (standaard 30).

**Abonnement (Google Play + RevenueCat)**
1. Google Play Console → je app → **Monetiseren → Abonnementen**: maak twee abonnementen,
   `runwise_premium_monthly` (€5/maand) en `runwise_premium_yearly` (€40/jaar).
   Voeg bij beide een **aanbieding met gratis proefperiode van 1 maand** toe.
2. Maak een gratis account op https://www.revenuecat.com, koppel je Play-app en importeer de twee producten.
   Maak een *entitlement* `premium` en een *offering* (standaard) met een **Monthly**- en **Annual**-pakket.
3. RevenueCat → **Integrations → Webhooks**: URL `https://jdswennyfczpqblfkrxt.supabase.co/functions/v1/revenuecat-webhook`,
   en kies zelf een lang wachtwoord als *Authorization header*. Zet hetzelfde wachtwoord in Supabase Secrets als `REVENUECAT_WEBHOOK_SECRET`.
4. Zet de publieke RevenueCat **Android SDK-key** (begint met `goog_`) in `app_config.json` bij `REVENUECAT_ANDROID_KEY`.
   Zolang die leeg is, toont de app "Abonnementen zijn binnenkort beschikbaar".

### 4. Op je telefoon testen
1. Telefoon: *Instellingen → Over de telefoon* → 7× tikken op *Buildnummer* → *Ontwikkelaarsopties* → **USB-foutopsporing** aan.
2. Telefoon met USB aansluiten en toestaan.
3. Starten:
   ```powershell
   flutter run --dart-define-from-file=config.json
   ```

### 4b. Uploadsleutel voor de Play Store (eenmalig)
1. Voer op je laptop uit (in de map van de app):
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\maak-sleutel.ps1
   ```
2. Open `runwise-github-geheimen.txt` en zet de 4 waarden in GitHub:
   **Settings → Secrets and variables → Actions → New repository secret**.
3. Bewaar `runwise-upload-key.jks` en het wachtwoord veilig, en verwijder het tekstbestand.
4. Vanaf de volgende push bouwt GitHub naast de APK ook **runwise-playstore-aab**: dat bestand upload je in de Play Console.

### 4c. Health Connect en de Play Store
Google Play vraagt bij de eerste versie een **verklaring voor Health Connect**: RunWise leest alleen *trainingen*, *afstand* en *hartslag* om je runs automatisch te loggen en je loopprofiel te berekenen. Zet dit ook in de privacyverklaring:
> RunWise leest met jouw toestemming hardlooptrainingen, afstand en hartslag uit Health Connect om je runs automatisch toe te voegen. Deze gegevens worden alleen gebruikt voor jouw eigen overzicht, loopprofiel en coach, worden niet verkocht of gedeeld met adverteerders, en worden verwijderd als je je account verwijdert.

### 5. Later: publiceren in de Play Store
- Google Play-ontwikkelaarsaccount (eenmalig ca. $25).
- Gesloten test met **minimaal 12 testers gedurende 14 dagen**.
- Release-build: `flutter build appbundle --dart-define-from-file=config.json` (met een eigen ondertekeningssleutel; dat doen we samen als het zover is).
- Privacyverklaring online: `privacy.html` staat in de map `runwise-site`.
