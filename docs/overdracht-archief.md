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

## Verplaatst uit CLAUDE.md (17-11)
Deze notities stonden in CLAUDE.md; ze zijn afgerond en worden niet elke sessie meer gelezen.

- Ronde 6-11 (17 verbeteringen): stem vooraf laden (`KadansVoice.prefetch/commonPhrases`) + `volume()`; `whyNotNow` (verdict.dart) +
  `typicalRunMinutes` (dashboard onthoudt `plan_duration_minutes`); route-generator stelt rondjes >5% bij; tekenscherm toont ondergrond
  (`routes/surface_bar.dart`, path-modus geeft `surface` mee); tussentijden groen/oranje t.o.v. gemiddelde; kaart op tempo/hartslag
  (`valueSegments`/`relativeScale`, `RouteMap.colorSegments`); runtitel wijzigen (`setActivityTitle`, 0039); run-deelkaart ook als verhaal 9:16;
  route naar bekend horloge in één tik (`sendRouteToWatch(full:)`); profiel-voortgang; applaus-pop + dubbel tikken; stappen: vandaag,
  afstand tot volgende, `StepsSync` (bij openen app, melding bij inhalen); lege Samen-schermen met uitnodigen; introductie 5 stappen;
  unslop deels: `RwRadius.s/m/l` overal, `ShineText` effen zonder eigen kleuren, gouden gloed neutraal (emoji nog niet nagelopen).
- Ronde 6-11 nacht (11 punten + fotofix): vergrendelscherm tijdens run (kanaal `kadans/screen` in `KadansChannels.kt`,
  `data/services/lock_screen_service.dart`, chip onder "Meer opties"); aftellen 3-2-1 met piep (`SoundService.beep`, `toneWav`) + tril;
  tempo-alarm met bandbreedte (`PaceCoach.band`, pref `rec_pace_band`); route andersom (`domain/route_reverse.dart`); vlieg over de route
  (`routes/route_flyover_screen.dart`, schuin via Transform); deel-link met `h=` (hoogtemeters) en `e=` (profiel) → `site/route.html`;
  recordfeest + deelkaart (`record/record_celebration_screen.dart`, vanzelf na de samenvatting); reacties 👏🔥💪 (`social_react`,
  `social_comments_of2`) en @vermeldingen (`social_mentions`, `MentionSync` bij openen app, melding kanaal 'samen'); groepsagenda
  (`group_runs_*` in 0040, `TogetherService.groupRuns`, kaart AGENDA in `GroupScreen`); trekken om te vernieuwen in groepen, lopers, Doelen, Logboek.
  Profielfoto-fout was: upsert zonder SELECT-regel op `storage.objects` → nu upsert uit + regel `avatars_own_select`, grens 2 MB.
- **Ronde 9-11 nacht:** clubevenementen in Samen → Runs (`community/club_events_strip.dart`, `ClubEventsStrip`/`ClubEventsScreen`, datumtegel `DateTile`):
  groepsruns uit al je loopgroepen + clubagenda's via iCal-link (`domain/club_calendar.dart`, `data/services/club_events_service.dart`, max 5 links,
  op toestel, elke 6 u ververst). Kaarten: donkerder blauwgrijs (`_darkMap`), gouden looppaden uit OSM (`domain/run_paths.dart`,
  `routes/run_paths_layer.dart`, `PoiService.runPaths`, vak 0,03°, 30 dagen bewaard, knop `RunPathsButton`, standaard aan) in LiveTrackMap en DrawRouteMap.
  Opnemen vóór start = kaart + `_GpsPill` (bij < 300 px ruimte de oude compacte weergave). Runoverzicht: grote kaart gekleurd op tempo
  (`coloredRunSegments` + `PaceLegend` in `splits_card.dart`). Wedstrijdkalender: nog geen bron; mail om toestemming (running.life/Atletiekunie) ligt bij Sem.
- Marketing (buiten de repo): Instagram **@kadans.app**. Instagram-skills (`/ig-reel`, `/ig-caption`, `/ig-plan` enz.) en
  `frontend-design` en `unslop-ui` (controle op AI-look, scanner: `devibe_scan.py` uit JCarterJohnson/vibecoded-design-tells) zijn als skills beschikbaar in Claude (geen koppeling nodig). Profielfoto = alleen de gouden K.
  **Instagram-stijl (9-11, Sems keuze na proefronde):** vaste reeks **"Zelfde rondje."**: dia 1 = zelfde foto gesplitst (links regen,
  koel, rechts droog, warm goud), gouden middenlijn, label "45 MIN LATER", grote tijden 15:50 / 16:35 (klopt met `site/app/vandaag.jpg`).
  Dia 2 = weerbalk per kwartier op papier, dia 3 = echt Vandaag-scherm in strak getekend toestel + gouden kader "Beste moment",
  dia 4 = heide + "Jouw rondje. Beter moment." + knop "STUUR WEER" + "Nu voor Android". Maken met `tools/insta/dia1_split.py` en
  `dia2_4.py` (PIL, vanuit de repo-root, echte foto's `site/foto/`). Analyse (500 vragen): `docs/insta-500-vragen.md`.
  **Niet doen** (Sem vond het amateuristisch): AI-handen, AI-telefoons met geplakt scherm, schoenen, stockfoto's met tip-tekst,
  zware kop over het onderwerp. AI-beelden alleen voor weer/landschap/straat. Beeldgenerator: HF-koppeling "Hugging face beelden"
  (`gr1_flux_1_krea_dev_infer`, gratis ZeroGPU, daglimiet snel op). ElevenLabs-beelden kosten Sems tegoed (alleen na "ja, ElevenLabs").
  Captions: nuchter/droge humor, herkenbare looperszinnen ("Het is maar regen, je smelt niet", "Ik heb geen zin", "Ga gewoon"),
  eerste zin < 125 tekens, één vraag, max 5 hashtags, CTA "Stuur WEER". Doel: 100 testers. Eerste 5 captions staan in de chat van 9-11
  (rondje, wind, donker, kou, gewoonte). Nog te doen: posten + alt-tekst, contentmaakster echte split-foto's laten maken (zelfde plek, 2 momenten).
- **Ronde 14-11 (nacht):** hartslagalarm (`domain/hr_alarm.dart`, pref `hr_alarm_zone`, kaart in `profile/heart_rate_screen.dart`, spreekt via `RunRecorderService.say`),
  "Waarom dit moment?" op de advieskaart (`_showWhySheet` in `dashboard_screen.dart`), sectie AFGELOPEN bij Uitdagingen (`_OverCard`),
  migratietest `tools/migraties_testen.sh` + workflow `migraties.yml` (nepversies van auth/storage/pg_cron/pg_net; alle 46 migraties groen),
  ratchet-test `test/untranslated_ratchet_test.dart` (onvertaalde teksten, nu 550, mag alleen dalen), lijst `docs/verbeterpunten-later.md`.
  Bestond al (niet opnieuw bouwen): herstel na crash (`RecordingStore`, `_offerRestore`), foutrapporten (`ErrorReporter` → `app_errors`), GPS-gaten (`GpsQuality`),
  slaap/herstel (`readiness.dart`), Dependabot gegroepeerd, widget/melding kijken ook naar morgen.
