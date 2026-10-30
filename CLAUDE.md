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
    Repo heet nu `Semdenhartog/kandans` (gh-API alleen via `repos/Semdenhartog/kandans/...`, `-R Semdenhartog/kandans`). Fouten lezen: `gh api repos/Semdenhartog/kandans/check-runs/<job-id>/annotations` (max 10 per stap).
  - `screens.yml`: schermafbeeldingen (licht + `6x_donker_*`, ook grote letters) naar branch `schermen-<branch>`,
    incl. `screens.txt`; faalt op "overflowed by". Play Store-plaatjes in `playstore/`.
  - `supabase-functies.yml`: zet alle edge functions live, met de hand én vanzelf bij een push naar main die `supabase/functions/**` raakt
    (GitHub-secret `SUPABASE_ACCESS_TOKEN` is gezet en werkt sinds 26 okt; zonder token: waarschuwing, geen fout).
  - `geheimen.yml`: geheimen-scan.
  - `site.yml`: zet `site/` op GitHub Pages (**Pages staat aan** sinds 29 okt: https://semdenhartog.github.io/Kandans/ — let op de hoofdletter K) en vult
    `__SUPABASE_URL__`/`__SUPABASE_ANON_KEY__` in (wachtlijst). Links in `site/` zijn relatief (Pages draait op `/Kandans/`).
- Privacyverklaring: bron is `site/privacy.html`; `tools/privacy_naar_dart.py` maakt er `lib/features/profile/privacy_text.dart`
  van (draait in build.yml en screens.yml). In de app: `openPrivacy(context)`.
- Supabase-project `jdswennyfczpqblfkrxt`. RLS overal. Migraties t/m **0034** staan erin (0030 wachtlijst, 0031 foutoverzicht, 0032 actiecodes, 0033 community: **staan live sinds 27 okt**, eigenaarscode en moderator ook; 0034 volgen + runs delen **live sinds 30 okt** (via MCP in 5 delen 0034a–e: `apply_migration` met `drop` vraagt een bevestiging die kan verlopen, dus `drop` apart); lokaal getest met Postgres 16 + Supabase-stubs, zie /var/tmp/kadanspg als die er nog is) (`apply_migration` via MCP werkt sinds 27 okt; eerst lokaal testen, dan zelf toepassen).
- Edge-function-helpers in `supabase/functions/_shared/` zijn te testen met `node --experimental-strip-types`.
- Gratis kaartdata: PDOK-tegels, Overpass (verlichting, voorzieningen; per vraag eerst één server, na 4 s reserve),
  openrouteservice (routes, ondergrond met schatting uit wegtype), Open-Meteo (weer), Buienradar.

## Huisstijl
- Naam **Kadans**. Logo (28 okt, definitief): champagnegouden K + "KADANS" op een zwarte afgeronde tegel;
  origineel `docs/merk/kadans-logo-origineel.png`, met K en tekst 8% groter (wens van Sem) `docs/merk/kadans-logo-8procent.png`.
  App-icoon (homescherm) = die 8%-versie, verder **niets aanpassen**: de tegel sluit aan op de icoonvorm (98,5% van het zichtbare deel,
  op #050504), `adaptive_icon_foreground_inset: 0` is nodig (anders krimpt flutter_launcher_icons de voorgrond 16% per kant),
  geen monochroom. Maken: `tools/logo/3_app_icoon_minimaal.py`. Play Store-icoon: `docs/merk/play-store-icoon-512.png`.
  Eerder marmerlogo: `docs/merk/kadans-logo-marmer.png`. In de app nog: `assets/logo/k_goud.webp` (gouden K van het marmerlogo:
  opstartscherm, inloggen, uitnodigingskaart),
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
- Community-tab: `lib/features/community/`, databasefuncties `community_*` (migratie 0033). Bovenaan **Runs | Gesprekken**.
- Volgen + runs delen (0034, zoals Strava): functies `social_*`, tabellen `run_shares`/`run_kudos`/`run_comments`, `community_follows.status`
  (pending/accepted), `community_profiles.approve_followers`. App: `data/services/social_service.dart`, `community/shared_run_card.dart`,
  `runner_profile_screen.dart`, `people_screen.dart` (Lopers), `share_to_feed.dart` (knop "Delen met volgers" onder een run).
  Privacyzone in de app: `domain/privacy_zone.dart` (200/500/1000 m rond start én finish). Gedeeld = kopie zonder hartslag/tijdstip; Strava-runs geweigerd
  (ook in SQL). Vriendcode volgen = meteen goedgekeurd (edge `community`). Actiecodes: `redeem_promo`/`create_promo` (0032).
- Steunpagina: `site/steun.html` (doel €1.500, pakketten €25/€50/€75/€250, begroting). Toezeggingen gaan naar `waitlist` met
  `source` = `steun:<pakket>[:naam]` (overzicht: `select source, count(*) from waitlist group by 1`). Nog **geen betaling**: pas na KvK +
  betaallink. **Niet** vanuit de app naar deze pagina linken (Google Play-betaalregels). Beloofd en nog te bouwen: ledenkaart "Eerste loper",
  lijst "Eerste lopers" op de site; posters wachten op Stripe/Gelato.
- Kickstarter (concept, 29–30 okt): https://www.kickstarter.com/projects/941277233/819234441 (account "Kadans"). Ingevuld en gecontroleerd:
  titel/ondertitel, Technology → Apps, Nederland, 30 dagen, doel **€1.650** (≈ €1.500 netto), story + risico's, 5 beloningen
  (€5 Bedankt · €25 Supporter 1 jr Premium · €50 Eerste loper 2 jr + testversie + ledenkaart · €75 Met poster, max 50, NL €0 verzending ·
  €250 Lokale partner, max 10), levering maart 2027 (aanpassen als lancering later is), projectafbeelding (gouden K, zonder tekst) en avatar
  (app-logo), bio. Bronnen: `docs/merk/kickstarter/` (branch ai-coach). Campagnetekst: Claude-doc "Kickstarter-campagne Kadans"
  (https://claude.ai/artifact/ACypfYHUKJJ53A5TMTxKjd). Sem doet zelf: Payment (ID + bank), video, Submit for review **na KvK**.
  Bio staat verborgen ("Only show my name and avatar" aan). Kickstarter blokkeert de browser in de Claude-app (botcheck); Claude in Chrome werkt.
- Wachtlijst → Google Sheets: functie `waitlist-to-sheets` staat **alleen in Supabase** (niet in repo), header `x-waitlist-webhook-secret`,
  secrets `GOOGLE_SERVICE_ACCOUNT_JSON`, `GOOGLE_SHEETS_SPREADSHEET_ID`, `WAITLIST_WEBHOOK_SECRET` (Sem zet ze zelf). Problemen: Verify JWT staat
  aan (moet uit) en tabnaam is vast `"Sheet 1"`. Nog geen databasewebhook op `waitlist`. Wacht op Sems keuze (tabnaam A/B, JWT uit, functie in repo,
  privacyzin over Google).
- Plugins (30 okt): Agent Skills, Graphify en Ponytail als .plugin/.zip aan Sem gegeven; installeren doet Sem zelf (Customize → Plugins →
  Add marketplace `addyosmani/agent-skills`, `DietrichGebert/ponytail`; Graphify via upload). OmniRoute afgeraden (stuurt code/sleutels
  naar onbekende aanbieders). Laptop = Windows; device_bash is een Linux-VM en kan geen Windows-apps aanpassen.
- Bronnen: `lib/features/profile/sources_screen.dart` (`SourcesLink`); kaartvermelding blijft op kaarten (licentie).
- Overzicht van alles wat gebouwd is: `VERBETERPUNTEN.md` (t/m punt 197). Play Store-teksten: `docs/play-store.md`. Inkomsten: `docs/inkomsten.md`.

## Open punten voor Sem
- KvK-inschrijving (gepland november, met KOR-keuze) → daarna Kickstarter-betaalgegevens + Submit for review, betaallinks steunpagina.
- In de app staat nog de gouden K van het marmerlogo (opstartscherm, inloggen, uitnodiging); vervangen door de nieuwe K als Sem dat wil.
- Play Store live → `PLAY_LIVE = true` in `site/vriend.html`.
- Supabase Auth-mailtemplates zeggen nog "RunWise" → aanpassen (Authentication → Email Templates).
- Strava API-app hernoemen naar Kadans; Strava één keer opnieuw koppelen voor privéroutes.
- Merkcheck "Kadans" (TMview/BOIP) en domein; Kadans Science Partner (vastgoed) gebruikt dezelfde naam.
- Stripe, Gelato, RevenueCat, KvK/btw voor posters en Premium; feature graphic (1024×500) voor de Play Store.
- Testen op telefoon: licht/donker wisselen, Vivoactive 5-meldingen, Strava oude runs/routes, Samen.

## Agent skills

### Issue tracker

Taken en bugs staan in GitHub Issues van `Semdenhartog/Kandans` (via `gh`). See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: één `GLOSSARY.md` en `docs/adr/` in de root (worden pas gemaakt als ze nodig zijn). See `docs/agents/domain.md`.
