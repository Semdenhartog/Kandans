# Overdracht – archief (alleen openen als het nodig is)

Afgeronde zaken en achtergrond die uit `CLAUDE.md` zijn gehaald (30 okt 2026). Niet elke sessie nodig.

## Supabase-migraties – geschiedenis
- 0030 wachtlijst, 0031 foutoverzicht, 0032 actiecodes, 0033 community: live sinds 27 okt, eigenaarscode en moderator ook.
- 0034 volgen + runs delen: live sinds 30 okt, via MCP in 5 delen 0034a–e. `apply_migration` met `drop` vraagt een bevestiging
  die kan verlopen, dus `drop` apart. Lokaal getest met Postgres 16 + Supabase-stubs (/var/tmp/kadanspg, als die er nog is).
- `apply_migration` via MCP werkt sinds 27 okt. `SUPABASE_ACCESS_TOKEN` (GitHub-secret) werkt sinds 26 okt.

## Codekaart (graphify) – details
- `graaf.yml` maakt de kaart met graphify 0.9.97 (zonder AI, 0 tokens) en zet die op branch `graaf` (`graph.json`, `GRAPH_REPORT.md`,
  `COMMIT`; commit met `[skip ci]`).
- `GRAPH_REPORT.md` is groot (~12k tokens): niet in z'n geheel lezen, hooguit grep.
- SQL-migraties en Kotlin staan er alleen in als de workflow ze kon lezen.
- Status 30 okt: eerste kaart met de hand op `graaf` gezet (334 bestanden, 6.735 knopen, zonder SQL/Kotlin/PowerShell). Of `graaf.yml`
  groen draait was toen nog niet gezien. Faalt hij: workflow "Codekaart (graphify)" bekijken; kaart blijft dan de oude.
  Branch `graphify` is een overblijfsel en mag weg.
- PyPI is in Claude-sessies vaak geblokkeerd. `graaf.sh` haalt graphify als broncode van GitHub. Zelf een kaart **bouwen** kan alleen
  met tree-sitter uit broncode: py-tree-sitter (tag v0.25.2) + grammatica's met `python3 setup.py build_ext --inplace` en RapidFuzz met
  `RAPIDFUZZ_IMPLEMENTATION=python`, alles via `PYTHONPATH`. Meestal niet nodig: laat de workflow het doen.

## Logo en app-icoon – details
- Logo (28 okt, definitief): champagnegouden K + "KADANS" op een zwarte afgeronde tegel. Origineel `docs/merk/kadans-logo-origineel.png`,
  met K en tekst 8% groter (wens van Sem) `docs/merk/kadans-logo-8procent.png`.
- App-icoon = die 8%-versie, **niets aanpassen**: tegel sluit aan op de icoonvorm (98,5% van het zichtbare deel, op #050504),
  `adaptive_icon_foreground_inset: 0` is nodig (anders krimpt flutter_launcher_icons de voorgrond 16% per kant), geen monochroom.
  Maken: `tools/logo/3_app_icoon_minimaal.py`. Play Store-icoon: `docs/merk/play-store-icoon-512.png`.
- Eerder marmerlogo: `docs/merk/kadans-logo-marmer.png`. In de app nog `assets/logo/k_goud.webp` (gouden K van het marmerlogo:
  opstartscherm, inloggen, uitnodigingskaart). `mark.png`/`wordmark.png`/`logo.png` zijn witte silhouetten die de app inkleurt.
  Opnieuw maken: `tools/logo/1_uitsnijden.py` en `2_icoon_bouwen.py` (in een map met `src/origineel.png`).

## Steunpagina
- `site/steun.html` (doel €1.500, pakketten €25/€50/€75/€250, begroting). Toezeggingen gaan naar `waitlist` met
  `source` = `steun:<pakket>[:naam]` (overzicht: `select source, count(*) from waitlist group by 1`).
- Beloofd en nog te bouwen: ledenkaart "Eerste loper", lijst "Eerste lopers" op de site; posters wachten op Stripe/Gelato.

## Kickstarter (concept, 29–30 okt)
- https://www.kickstarter.com/projects/941277233/819234441 (account "Kadans"). Ingevuld en gecontroleerd: titel/ondertitel,
  Technology → Apps, Nederland, 30 dagen, doel **€1.650** (≈ €1.500 netto), story + risico's, 5 beloningen (€5 Bedankt ·
  €25 Supporter 1 jr Premium · €50 Eerste loper 2 jr + testversie + ledenkaart · €75 Met poster, max 50, NL €0 verzending ·
  €250 Lokale partner, max 10), levering maart 2027 (aanpassen als lancering later is), projectafbeelding (gouden K, zonder tekst),
  avatar (app-logo), bio (verborgen: "Only show my name and avatar" aan).
- Bronnen: `docs/merk/kickstarter/`. Campagnetekst: Claude-doc "Kickstarter-campagne Kadans"
  (https://claude.ai/artifact/ACypfYHUKJJ53A5TMTxKjd).
- Sem doet zelf: Payment (ID + bank), video, Submit for review **na KvK**.
- Kickstarter blokkeert de browser in de Claude-app (botcheck); Claude in Chrome werkt.

## Wachtlijst → Google Sheets
- Functie `waitlist-to-sheets` staat **alleen in Supabase** (niet in repo), header `x-waitlist-webhook-secret`, secrets
  `GOOGLE_SERVICE_ACCOUNT_JSON`, `GOOGLE_SHEETS_SPREADSHEET_ID`, `WAITLIST_WEBHOOK_SECRET` (Sem zet ze zelf).
- Problemen: Verify JWT staat aan (moet uit), tabnaam is vast `"Sheet 1"`. Nog geen databasewebhook op `waitlist`.
- Wacht op Sems keuze: tabnaam A/B, JWT uit, functie in repo, privacyzin over Google.

## Plugins (30 okt)
- Agent Skills en Ponytail als .plugin/.zip aan Sem gegeven; installeren doet Sem zelf (Customize → Plugins → Add marketplace
  `addyosmani/agent-skills`, `DietrichGebert/ponytail`). Graphify zit in de repo, plugin niet nodig.
- OmniRoute afgeraden (stuurt code/sleutels naar onbekende aanbieders).
- Laptop = Windows; device_bash is een Linux-VM en kan geen Windows-apps aanpassen.

## Functies – extra details
- Strava-archief-import zonder koppeling: `profile/strava_archive_screen.dart` + `domain/zip_reader.dart`, `fit_parser.dart`,
  `strava_archive.dart` (bron `strava`, external_id = Strava-id; testarchief via `tools/maak_strava_testarchief.py`).
- Volgen + runs delen (0034): tabellen `run_shares`/`run_kudos`/`run_comments`, `community_follows.status` (pending/accepted),
  `community_profiles.approve_followers`. App: `community/shared_run_card.dart`, `runner_profile_screen.dart`,
  `people_screen.dart` (Lopers), `share_to_feed.dart` (knop "Delen met volgers"). Gedeeld = kopie zonder hartslag/tijdstip.
  Vriendcode volgen = meteen goedgekeurd (edge `community`).
- Shop: tasje met "nieuw"-stip, gouden tegel in Ik. Uitnodiging: `site/vriend.html` → `/vriend?code=`.
- Bronnen-scherm: `lib/features/profile/sources_screen.dart` (`SourcesLink`); kaartvermelding blijft op kaarten (licentie).
- Talen: vertaald zijn inloggen, rondleiding, onderbalk, Ik, shop, community. Rest (Vandaag, opnemen, stemcoach, runs, routes) nog NL.
