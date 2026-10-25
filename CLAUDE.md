# Kadans (voorheen RunWise) – overdracht voor Claude

Lees dit eerst. Daarna niets opnieuw uitzoeken wat hier staat.

## Wie en hoe
- Eigenaar: Sem. Antwoord **altijd in het Nederlands**, gemiddelde lengte, met lijstjes en stappen.
  Zeg eerlijk en direct als iets geen goed idee is.
- Sem test op een Android-telefoon (Samsung) en heeft een **Garmin Vivoactive 5**.
- Zuinig werken: bundel wijzigingen, bekijk alleen schermafbeeldingen die echt veranderd zijn,
  geen tientallen opties tenzij gevraagd.

## Vaste regels (van Sem)
1. Geheimen nooit in de code. Sem zet ze zelf in Supabase of GitHub Secrets. Claude vult nooit tokens/sleutels in.
2. Strava-data gaat **niet** naar de AI-coach en wordt **niet** aan andere gebruikers getoond
   (filter: `source <> 'strava'` én `external_id not like 'viastrava-%'`).
3. Na elke ronde: build groen → schermafbeeldingen bekijken → fouten zelf oplossen → main bijwerken →
   eerlijk melden wat wel en niet getest is. Niets is op een echte telefoon getest tenzij Sem het zegt.
4. Er werkt soms een tweede sessie op andere branches: **eerst `git fetch` + `origin/main` mergen** vóór je iets aanraakt.
   Conflicten waren tot nu toe alleen importregels: houd beide kanten.
5. Werk op branch `ai-coach`; merge naar `main` pas als de build groen is. Elke push naar main maakt een APK
   (release "laatste": https://github.com/Semdenhartog/Runwise/releases/download/laatste/runwise.apk).
   Sem wil pas een nieuwe APK als een wijziging af is.
6. Commit-regels eindigen met:
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` en
   `Claude-Session: https://claude.ai/code/session_01MLXfUJVt1jKLbSqk7u49hE`

## Techniek
- Flutter + Riverpod 3 (`Notifier`, `FutureProvider`, `Override` uit `flutter_riverpod/misc.dart`), go_router,
  supabase_flutter 2, RevenueCat. Android-map staat **niet** in de repo: `flutter create` in build.yml
  (pakket `nl.runwise…`, deeplink `runwise://` — **niet wijzigen**, anders breken inloggen en updates).
- Geen Flutter lokaal. Controle gaat via GitHub Actions:
  - `build.yml`: analyse (`--no-fatal-infos --no-fatal-warnings`), tests, APK. Bij falende tests staat de uitvoer op branch `testuitvoer-<branch>`.
    Fouten lezen: `gh api repos/Semdenhartog/Runwise/check-runs/<job-id>/annotations` (max 10 per stap).
  - `screens.yml`: schermafbeeldingen (licht + `6x_donker_*`, ook grote letters) naar branch `schermen-<branch>`,
    incl. `screens.txt`; faalt op "overflowed by". Play Store-plaatjes in `playstore/`.
  - `supabase-functies.yml`: zet alle edge functions live (**werkt pas als GitHub-secret `SUPABASE_ACCESS_TOKEN` bestaat** — nog niet gezet).
    Tot die tijd: losse functie live zetten via de Supabase-MCP `deploy_edge_function` (imports `../_shared/x` → `./_shared/x`).
  - `geheimen.yml`: geheimen-scan.
- Supabase-project `jdswennyfczpqblfkrxt`. RLS overal. Migraties t/m **0029** staan erin (Sem draait SQL zelf in de SQL Editor;
  `apply_migration` via MCP wordt in deze omgeving geannuleerd, `execute_sql` voor lezen werkt wel).
- Edge-function-helpers in `supabase/functions/_shared/` zijn te testen met `node --experimental-strip-types`.
- Gratis kaartdata: PDOK-tegels, Overpass (verlichting, voorzieningen; per vraag eerst één server, na 4 s reserve),
  openrouteservice (routes, ondergrond met schatting uit wegtype), Open-Meteo (weer), Buienradar.

## Huisstijl
- Naam **Kadans**. Icoon "Goudfolie": gouden geweven ringen met vaartlijnen op warm bruin, lichte routelijn
  (`assets/icon/*`, bronnen in /root/Runwise-iconen/kadans/gen*.py als die er nog zijn).
- Kleuren: `RwPalette` in `lib/core/theme.dart` met `rwZand` (licht, brons/espresso) en `rwZandAvond` (donker, champagne).
  `RwColors.*` en `RwText.*` zijn **getters** (wisselen mee): gebruik ze **nooit in `const`**. Weergave-keuze: Ik → Weergave
  (`lib/core/appearance.dart`). Premium, Luxe, ledenkaart, deelkaart en posters blijven altijd donker-goud (`rwZandAvond.*`).
- Lettertypes: Saira (koppen/cijfers), DM Sans (tekst).

## Belangrijkste functies (waar te vinden)
- Vandaag / beste moment: `lib/features/dashboard/` · Opnemen + navigatie: `lib/features/record/`, `lib/data/services/run_recorder_service.dart`
- Routes (tekenen, laten maken, ondergrond, verlichting, horloge): `lib/features/routes/`
- Horloges: `watch_export.dart`. `WatchBrand.garminBasic` = Garmin zonder koersen (Vivoactive 5):
  geen bestand, maar afslagmeldingen op de pols met alleen ← → (`simple_turn_arrows`).
- Strava: `supabase/functions/strava` (sync, history, routes, route), app: `profile/strava_history_screen.dart`, `routes/strava_routes_screen.dart`
- Uitdagingen + Samen (ranglijsten, vriendcode): `lib/features/challenges/`, functie `community`
- Coach: functie `coach` (logt `coach_usage` per vraag), app `lib/features/coach/`
- Posters (Stripe + Gelato): `poster-order`, `stripe-webhook` — **nog niet live**, wacht op Stripe/Gelato-geheimen.
- Overzicht van alles wat gebouwd is: `VERBETERPUNTEN.md` (t/m punt 118). Play Store-teksten: `docs/play-store.md`. Inkomsten: `docs/inkomsten.md`.

## Open punten voor Sem
- GitHub-secret `SUPABASE_ACCESS_TOKEN` zetten (dan kan alles met één klik live).
- Supabase Auth-mailtemplates zeggen nog "RunWise" → aanpassen (Authentication → Email Templates).
- Strava API-app hernoemen naar Kadans; Strava één keer opnieuw koppelen voor privéroutes.
- Merkcheck "Kadans" (TMview/BOIP) en domein; Kadans Science Partner (vastgoed) gebruikt dezelfde naam.
- Stripe, Gelato, RevenueCat, KvK/btw voor posters en Premium; feature graphic (1024×500) voor de Play Store.
- Testen op telefoon: licht/donker wisselen, Vivoactive 5-meldingen, Strava oude runs/routes, Samen.
