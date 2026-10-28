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
  - `supabase-functies.yml`: zet alle edge functions live, met de hand én vanzelf bij een push naar main die `supabase/functions/**` raakt
    (GitHub-secret `SUPABASE_ACCESS_TOKEN` is gezet en werkt sinds 26 okt; zonder token: waarschuwing, geen fout).
  - `geheimen.yml`: geheimen-scan.
  - `site.yml`: zet `site/` op GitHub Pages (**Pages staat nog uit** → Settings → Pages → Source: GitHub Actions) en vult
    `__SUPABASE_URL__`/`__SUPABASE_ANON_KEY__` in (wachtlijst). Links in `site/` zijn relatief (Pages draait op `/Runwise/`).
- Privacyverklaring: bron is `site/privacy.html`; `tools/privacy_naar_dart.py` maakt er `lib/features/profile/privacy_text.dart`
  van (draait in build.yml en screens.yml). In de app: `openPrivacy(context)`.
- Supabase-project `jdswennyfczpqblfkrxt`. RLS overal. Migraties t/m **0033** staan erin (0030 wachtlijst, 0031 foutoverzicht, 0032 actiecodes, 0033 community: **staan live sinds 27 okt**, eigenaarscode en moderator ook; lokaal getest met Postgres 16 + Supabase-stubs, zie /var/tmp/kadanspg als die er nog is) (`apply_migration` via MCP werkt sinds 27 okt; eerst lokaal testen, dan zelf toepassen).
- Edge-function-helpers in `supabase/functions/_shared/` zijn te testen met `node --experimental-strip-types`.
- Gratis kaartdata: PDOK-tegels, Overpass (verlichting, voorzieningen; per vraag eerst één server, na 4 s reserve),
  openrouteservice (routes, ondergrond met schatting uit wegtype), Open-Meteo (weer), Buienradar.

## Huisstijl
- Naam **Kadans**. Logo (28 okt): gouden K op zwart marmer met goudaders; origineel in `docs/merk/kadans-logo-origineel.png`,
  Play Store-icoon `docs/merk/play-store-icoon-512.png`. App-icoon (homescherm) = **exact het originele logo, geen aanpassingen** (wens van Sem):
  `assets/icon/icon.png` is het origineel geschaald; adaptief = het hele origineel op 72% op zwart (gouden rand vult de Samsung-vorm; in een rond masker vallen de hoeken van de rand net weg); `adaptive_icon_foreground_inset: 0` is nodig, anders krimpt flutter_launcher_icons de voorgrond nog 16% per kant, geen monochroom. In de app: `assets/logo/k_goud.webp` (gouden K in kleur: opstartscherm, inloggen, uitnodigingskaart),
  `mark.png`/`wordmark.png`/`logo.png` zijn witte silhouetten (K en "KΛDΛNS") die de app inkleurt. Opnieuw maken:
  `tools/logo/1_uitsnijden.py` en `2_icoon_bouwen.py` (draaien in een map met `src/origineel.png`).
- Kleuren: `RwPalette` in `lib/core/theme.dart` met `rwZand` (licht, brons/espresso) en `rwZandAvond` (donker, champagne).
  `RwColors.*` en `RwText.*` zijn **getters** (wisselen mee): gebruik ze **nooit in `const`**. Weergave-keuze: Ik → Weergave
  (`lib/core/appearance.dart`). Premium, Luxe, ledenkaart, deelkaart en posters blijven altijd donker-goud (`rwZandAvond.*`).
- Lettertypes: Saira (koppen/cijfers), DM Sans (tekst).
- Talen: `lib/core/i18n.dart` (`tr('Nederlandse tekst')`, `trf()` met {invulplekken}), vertalingen in `tools/vertalingen.py`
  → `python3 tools/maak_vertalingen.py` maakt `lib/core/i18n_strings.dart` en meldt wat ontbreekt. Nieuw scherm vertalen:
  `python3 tools/tr_codemod.py <bestand>` (zet Text('…') om en haalt const weg), daarna vertalingen aanvullen.
  Vertaald: inloggen, rondleiding, onderbalk, Ik, shop, community. Rest (Vandaag, opnemen, stemcoach, runs, routes) nog NL.

## Belangrijkste functies (waar te vinden)
- Vandaag / beste moment: `lib/features/dashboard/` · Opnemen + navigatie: `lib/features/record/`, `lib/data/services/run_recorder_service.dart`
- Routes (tekenen, laten maken, ondergrond, verlichting, horloge): `lib/features/routes/`
- Horloges: `watch_export.dart`. `WatchBrand.garminBasic` = Garmin zonder koersen (Vivoactive 5):
  geen bestand, maar afslagmeldingen op de pols met alleen ← → (`simple_turn_arrows`).
- Strava: `supabase/functions/strava` (sync, history, routes, route), app: `profile/strava_history_screen.dart`, `routes/strava_routes_screen.dart`.
  Archief-import zonder koppeling: `profile/strava_archive_screen.dart` + `domain/zip_reader.dart`, `fit_parser.dart`, `strava_archive.dart`
  (bron `strava`, external_id = Strava-id; testarchief via `tools/maak_strava_testarchief.py`).
- Uitdagingen + Samen (ranglijsten, vriendcode): `lib/features/challenges/`, functie `community`
- Coach: functie `coach` (logt `coach_usage` per vraag), app `lib/features/coach/`
- Posters (Stripe + Gelato): `poster-order`, `stripe-webhook` — **nog niet live**, wacht op Stripe/Gelato-geheimen.
- Shop: `lib/features/shop/` (`/shop`, tasje met "nieuw"-stip, gouden tegel in Ik). Route delen: `domain/route_share.dart`,
  `site/route.html`, deeplink `runwise://app/route-delen?n=&p=` → `RouteImportScreen`. Uitnodiging: `site/vriend.html` → `/vriend?code=`.
- Community-tab: `lib/features/community/`, databasefuncties `community_*` (migratie 0033). Actiecodes: `redeem_promo`/`create_promo` (0032).
- Bronnen: `lib/features/profile/sources_screen.dart` (`SourcesLink`); kaartvermelding blijft op kaarten (licentie).
- Overzicht van alles wat gebouwd is: `VERBETERPUNTEN.md` (t/m punt 195). Play Store-teksten: `docs/play-store.md`. Inkomsten: `docs/inkomsten.md`.

## Open punten voor Sem
- GitHub Pages aanzetten. Play Store live → `PLAY_LIVE = true` in `site/vriend.html`.
- Supabase Auth-mailtemplates zeggen nog "RunWise" → aanpassen (Authentication → Email Templates).
- Strava API-app hernoemen naar Kadans; Strava één keer opnieuw koppelen voor privéroutes.
- Merkcheck "Kadans" (TMview/BOIP) en domein; Kadans Science Partner (vastgoed) gebruikt dezelfde naam.
- Stripe, Gelato, RevenueCat, KvK/btw voor posters en Premium; feature graphic (1024×500) voor de Play Store.
- Testen op telefoon: licht/donker wisselen, Vivoactive 5-meldingen, Strava oude runs/routes, Samen.
