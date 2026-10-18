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

Bewust **nog niet** in v1: AI-coach, abonnementen, pushmeldingen, Strava-synchronisatie en Garmin. Die komen later.

## App-icoon

Het icoon staat in `assets/icon/` (limegroene klok met snelheidsstreepjes op donkergroen, in de stijl van de website). `play_store_512.png` is de versie voor de Play Store. Bij elke build wordt het icoon automatisch ingesteld.

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

### 4. Op je telefoon testen
1. Telefoon: *Instellingen → Over de telefoon* → 7× tikken op *Buildnummer* → *Ontwikkelaarsopties* → **USB-foutopsporing** aan.
2. Telefoon met USB aansluiten en toestaan.
3. Starten:
   ```powershell
   flutter run --dart-define-from-file=config.json
   ```

### 5. Later: publiceren in de Play Store
- Google Play-ontwikkelaarsaccount (eenmalig ca. $25).
- Gesloten test met **minimaal 12 testers gedurende 14 dagen**.
- Release-build: `flutter build appbundle --dart-define-from-file=config.json` (met een eigen ondertekeningssleutel; dat doen we samen als het zover is).
- Privacyverklaring online: `privacy.html` staat in de map `runwise-site`.
