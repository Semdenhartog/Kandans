# Kadans (voorheen RunWise) – overdracht voor Claude

Lees dit eerst. Achtergrond en afgeronde zaken: `docs/overdracht-archief.md` (alleen openen als het nodig is).

## Wie en hoe
- Eigenaar: Sem. Antwoord **altijd in het Nederlands**, gemiddelde lengte, met lijstjes en stappen.
  Zeg eerlijk en direct als iets geen goed idee is.
- Sem test op een Android-telefoon (Samsung) en heeft een **Garmin Vivoactive 5**.
- **Zuinig werken:**
  - Vraag Sem eerst of schermafbeeldingen echt nodig zijn; bekijk daarna alleen schermen die echt veranderd zijn.
  - Bundel wijzigingen in één ronde (één build + één controle), niet na elke kleine aanpassing.
  - Geen tientallen opties tenzij gevraagd. Zoek eerst via de codekaart, lees dan alleen de nodige regels.

## Vaste regels (van Sem)
1. Geheimen nooit in de code. Sem zet ze zelf in Supabase of GitHub Secrets. Claude vult nooit tokens/sleutels in.
2. Strava-data gaat **niet** naar de AI-coach en wordt **niet** aan andere gebruikers getoond
   (filter: `source <> 'strava'` én `external_id not like 'viastrava-%'`).
3. Na elke ronde: build groen → (schermafbeeldingen, als Sem dat wil) → fouten zelf oplossen → main bijwerken →
   eerlijk melden wat wel en niet getest is. Niets is op een echte telefoon getest tenzij Sem het zegt.
4. Er werkt soms een tweede sessie op andere branches: **eerst `git fetch` + `origin/main` mergen** vóór je iets aanraakt.
   Conflicten waren tot nu toe alleen importregels: houd beide kanten.
5. Werk op branch `ai-coach`; merge naar `main` pas als de build groen is. Elke push naar main maakt een APK
   (release "laatste": https://github.com/Semdenhartog/Runwise/releases/download/laatste/runwise.apk).
   Sem wil pas een nieuwe APK als een wijziging af is. Alleen tekst/docs: commit met `[skip ci]`.
6. Commit-regels eindigen met `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` en de
   `Claude-Session:`-link van de **huidige** sessie.

## Techniek
- Flutter + Riverpod 3 (`Notifier`, `FutureProvider`, `Override` uit `flutter_riverpod/misc.dart`), go_router,
  supabase_flutter 2, RevenueCat. Android-map staat **niet** in de repo: `flutter create` in build.yml
  (pakket `nl.runwise…`, deeplink `runwise://` — **niet wijzigen**, anders breken inloggen en updates).
- Geen Flutter lokaal. Controle via GitHub Actions (repo `Semdenhartog/kandans`; gh: `repos/Semdenhartog/kandans/...`, `-R Semdenhartog/kandans`):
  - `build.yml`: analyse (`--no-fatal-infos --no-fatal-warnings`), tests, APK. Falende tests: uitvoer op branch `testuitvoer-<branch>`.
    Fouten lezen: `gh api repos/Semdenhartog/kandans/check-runs/<job-id>/annotations` (max 10 per stap).
  - `screens.yml`: schermafbeeldingen (licht + `6x_donker_*`, ook grote letters) naar branch `schermen-<branch>`, incl. `screens.txt`;
    faalt op "overflowed by". Play Store-plaatjes in `playstore/`.
  - `supabase-functies.yml`: zet edge functions live (met de hand én bij push naar main die `supabase/functions/**` raakt).
  - `geheimen.yml`: geheimen-scan.
  - `site.yml`: zet `site/` op GitHub Pages (https://semdenhartog.github.io/Kandans/ — hoofdletter K), vult
    `__SUPABASE_URL__`/`__SUPABASE_ANON_KEY__` in. Links in `site/` zijn relatief.
- Privacyverklaring: bron `site/privacy.html` → `tools/privacy_naar_dart.py` → `lib/features/profile/privacy_text.dart`. In de app: `openPrivacy(context)`.
- Supabase-project `jdswennyfczpqblfkrxt`. RLS overal. Migraties t/m **0035** staan live. Nieuwe migratie: eerst lokaal testen,
  dan zelf toepassen via MCP `apply_migration` (`drop` in een apart deel).
- Edge-function-helpers in `supabase/functions/_shared/` zijn te testen met `node --experimental-strip-types`.
- Gratis kaartdata: PDOK-tegels, Overpass (eerst één server, na 4 s reserve), openrouteservice, Open-Meteo, Buienradar.

## Codekaart (graphify) – eerst kijken, dan pas bestanden lezen
- Branch **`graaf`** (wordt na elke push naar main bijgewerkt door `graaf.yml`).
- `tools/graaf.sh` (ophalen, meldt of code sindsdien veranderd is), dan `tools/graaf.sh explain <bestand.dart of pad::Symbool>`
  of `tools/graaf.sh path <A> <B>`. Daarna **alleen** de nodige regels lezen (Read met offset/limit).
- `query "vrije tekst"` geeft veel ruis. `GRAPH_REPORT.md` niet in z'n geheel lezen.
- Kaart is alleen van **main**; op een branch kloppen nieuwe/gewijzigde bestanden niet — dan zelf lezen.

## Huisstijl
- Naam **Kadans**. Logo en app-icoon zijn definitief: **niets aanpassen** (details in het archief).
- Kleuren: `RwPalette` in `lib/core/theme.dart` met `rwZand` (licht) en `rwZandAvond` (donker). `RwColors.*` en `RwText.*` zijn
  **getters**: **nooit in `const`**. Weergave: `lib/core/appearance.dart`. Premium, Luxe, ledenkaart, deelkaart en posters altijd donker-goud.
- Lettertypes: Saira (koppen/cijfers), DM Sans (tekst).
- Talen: `lib/core/i18n.dart` (`tr()`, `trf()` met {invulplekken}), vertalingen in `tools/vertalingen.py` →
  `python3 tools/maak_vertalingen.py`. Nieuw scherm: `python3 tools/tr_codemod.py <bestand>`, daarna vertalingen aanvullen.

## Waar staat wat
- Vandaag: `lib/features/dashboard/` · Opnemen: `lib/features/record/`, `lib/data/services/run_recorder_service.dart`
- Routes: `lib/features/routes/` · Horloges: `watch_export.dart` (`WatchBrand.garminBasic` = Vivoactive 5, alleen ← → op de pols)
- Strava: `supabase/functions/strava`, app `profile/strava_history_screen.dart`, `routes/strava_routes_screen.dart`, archief-import `profile/strava_archive_screen.dart`
- Uitdagingen + Samen: `lib/features/challenges/`, functie `community` · Coach: functie `coach`, app `lib/features/coach/`
- Community: `lib/features/community/` (Runs | Gesprekken), SQL `community_*` (0033), volgen/delen `social_*` (0034),
  `data/services/social_service.dart`, privacyzone `domain/privacy_zone.dart`. Strava-runs worden geweigerd (ook in SQL).
- Premium/RevenueCat: `docs/revenuecat.md` (recht `kadans_pro`, paywall + Customer Center via `purchases_ui_flutter`)
- Shop: `lib/features/shop/` · Route delen: `domain/route_share.dart`, `site/route.html`, deeplink `runwise://app/route-delen?n=&p=`
- Posters (Stripe + Gelato): `poster-order`, `stripe-webhook` — **nog niet live**. Actiecodes: `redeem_promo`/`create_promo` (0032).
- Steunpagina `site/steun.html`: **niet** vanuit de app naar linken (Google Play-betaalregels). Nog geen betaling tot KvK.
- Alles wat gebouwd is: `VERBETERPUNTEN.md`. Play Store: `docs/play-store.md`. Inkomsten: `docs/inkomsten.md`.

## Open punten voor Sem
- KvK (november, KOR-keuze) → Kickstarter-betaalgegevens + Submit for review, betaallinks steunpagina.
- Wachtlijst → Google Sheets: wacht op Sems keuzes (zie archief).
- Gouden K van het marmerlogo in de app vervangen door de nieuwe K, als Sem dat wil.
- Play Store live → `PLAY_LIVE = true` in `site/vriend.html`.
- Strava API-app hernoemen naar Kadans; Strava één keer opnieuw koppelen voor privéroutes.
- Merkcheck "Kadans" (TMview/BOIP) en domein; Kadans Science Partner (vastgoed) gebruikt dezelfde naam.
- Stripe, Gelato, RevenueCat, KvK/btw voor posters en Premium.
- Testen op telefoon: licht/donker, Vivoactive 5-meldingen, Strava oude runs/routes, Samen.

## Agent skills
- Issues: GitHub Issues van `Semdenhartog/Kandans` (via `gh`), zie `docs/agents/issue-tracker.md`.
- Domein: één `GLOSSARY.md` en `docs/adr/` in de root (pas maken als nodig), zie `docs/agents/domain.md`.
