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
   Let op: staat een `[skip ci]`-commit **bovenaan** bij een merge naar main, dan wordt er géén APK gebouwd → zet er dan
   een lege commit zonder `[skip ci]` achter.
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
  - `site.yml`: zet `site/` op GitHub Pages, eigen domein **https://kadans.fit** (sinds 7-11-2026, Namecheap, privacy aan; oud adres
    semdenhartog.github.io/Kandans stuurt door). Domein-stap in site.yml controleert DNS. Vult
    `__SUPABASE_URL__`/`__SUPABASE_ANON_KEY__` in. Links in `site/` zijn relatief.
- Juridisch: `site/voorwaarden.html` (v1.0), `site/verwijderen.html` (Play Console-URL), privacy v1.6 (foto's + stappen). Aanmelden vraagt 16+ en akkoord (versies in user metadata).
  Gezondheidsgegevens alleen na `HealthConsent.ensure(context)` (`data/services/health_consent.dart`), intrekken via Ik → Gezondheidsgegevens.
  Site gebruikt eigen lettertypes (`site/fonts.css`) en Leaflet uit `site.yml` (geen Google Fonts/unpkg → geen cookiebanner nodig).
  Site-stijl (unslop-controle 2-11-2026, score 0): geen tekst met kleurverloop (effen goud), kleurverloop alleen op het CTA-blok,
  afrondingen 8/16/24 px, `button{font-family:inherit}`. **Voorpagina sinds 7-11-2026 in de stijl van integratedbio.com** (licht papier,
  groot beeld met ronde hoeken `site/beeld-hero.jpg`/`beeld-voet.jpg` uit `tools/maak_site_beeld.py`, typemachine-labels, knop = donker blok + goud vierkant,
  vlakken 01–03, galerij met echte app-schermen in telefoonlijsten `site/app/*.jpg` (uitsneden van Sems schermafbeeldingen), ledenkaart `site/app/ledenkaart.png`,
  donkere voet met groot logo `kadans-k-groot.png` + `kadans-adans-groot.png`). Foto's (7-11): zes gratis Unsplash-foto's in `site/foto/` (warm bijgekleurd;
  heide = hero, mist = fotoband, bos = app-blok, loper = nieuws, duin + boom = tweeluik), vermelding "Foto's Unsplash" in de voet. Bovenbalk scrolt op mobiel mee weg (8-11). Desktop en mobiel apart ingedeeld (7-11): desktop = hangende hero-telefoon, vlakken 01–03 over de mistfoto, § -labels; mobiel (≤900px) = compacter, vlakken/nieuws/tweeluik veegbaar, vaste wachtlijstknop `#ctabar`, tellende cijfers `[data-count]`. Subpagina's hebben nog de oude stijl. Alleen site gewijzigd → `[skip ci]` + `site.yml` met de hand starten (`gh workflow run site.yml --ref main`).
- Privacyverklaring: bron `site/privacy.html` → `tools/privacy_naar_dart.py` → `lib/features/profile/privacy_text.dart`. In de app: `openPrivacy(context)`.
- Supabase-project `jdswennyfczpqblfkrxt`. RLS overal. Migraties t/m **0040** staan live (0038 = profielen + stappen, 0039 = runtitel `activities.title`, 0040 = avatars-SELECT-regel + groepsagenda + emoji-reacties + @vermeldingen, 6-11-2026). Nieuwe migratie: eerst lokaal testen,
  dan zelf toepassen via MCP `apply_migration` (`drop` in een apart deel).
- Edge-function-helpers in `supabase/functions/_shared/` zijn te testen met `node --experimental-strip-types`.
- Migraties lokaal testen: Postgres 16 staat in de sessie (`su postgres -c '/usr/lib/postgresql/16/bin/initdb -D /tmp/pgt/data'`,
  starten met `-o '-p 5499 -k /tmp/pgt'`), met kleine stubs voor `auth.uid()`, `community_profiles` e.d.
- Bewuste keuzes: geen sms-rechten (Google Play staat ze voor valmeldingen niet toe), geen "Hey Google"-vragen in het Nederlands
  (niet mogelijk voor gewone apps; wel snelkoppeling), eigen profielfoto's in Samen mág sinds 6-11-2026 (Sems keuze) mét melden/blokkeren (na 3 meldingen verborgen).
- Gratis kaartdata: PDOK-tegels, Overpass (eerst één server, na 4 s reserve), openrouteservice, Open-Meteo, Buienradar.
- Plugins: `/plugin` werkt niet in cloud-sessies (alleen in de terminal-CLI). Voor cloud: `enabledPlugins` (+ marketplace) in `.claude/settings.json`.
  ECC (affaan-m/ECC) is **niet** geïnstalleerd: Sem wilde het, advies was eerst doorlichten (groot, hooks, botst met zuinig werken).

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
- **Navigatie (sinds 1-11-2026, zie `docs/herindeling.md`):** balk = Vandaag · Routes · ● Lopen (knop, lang drukken = snelmenu) · Logboek · Samen.
  Router-takken blijven 0 today, 1 runs (Logboek), 2 routes, 3 coach, 4 community (Samen), 5 me; plaats↔tak in `home_shell.dart`
  (`homeBranchForSlot`). Ik = `MeButton` rechtsboven, Coach = `CoachButton`; terug via `BackToTabScope`/`lastMainBranch` (`shared/nav_buttons.dart`).
  Vandaag: max 3 slimme kaarten (`_smartCards`) + "Deze week" (`planner/this_week_screen.dart`) + "Meer vandaag". Doelen: `challenges/goals_screen.dart`.
  Logboek-menu ontgrendelt vorm/records na 5 runs, heatmap/jaaroverzicht na 20. Rundetail: verdieping onder "Meer analyse".
- Vandaag: `lib/features/dashboard/` · Opnemen: `lib/features/record/`, `lib/data/services/run_recorder_service.dart`
- Routes: `lib/features/routes/` · Horloges: `watch_export.dart` (`WatchBrand.garminBasic` = Vivoactive 5, alleen ← → op de pols)
- Strava: `supabase/functions/strava`, app `profile/strava_history_screen.dart`, `routes/strava_routes_screen.dart`, archief-import `profile/strava_archive_screen.dart`
- Uitdagingen + Samen: `lib/features/challenges/`, functie `community` · Coach: functie `coach`, app `lib/features/coach/`
- Community: `lib/features/community/` (Runs | Gesprekken), SQL `community_*` (0033), volgen/delen `social_*` (0034),
  `data/services/social_service.dart`, privacyzone `domain/privacy_zone.dart`. Strava-runs worden geweigerd (ook in SQL).
- Sensoren: barometer `data/services/barometer_service.dart` (hoogtemeters, `domain/barometer.dart`), loopsensor BLE 0x1814
  `data/services/stride_sensor_service.dart` (koppelen in `profile/heart_rate_screen.dart`). Verloop-sleutels `cad`, `baro`, `marks`.
- Opnamescherm-indelingen `domain/record_layout.dart` + `record/record_layout_screen.dart`; markeringen `domain/run_markers.dart`,
  `activities/markers_card.dart`; tussentijden per afstand `splitsOf(s, every:)`. Herkomst OpenTracks: zie `NOTICE`.
- Rooster (ICS): `domain/roster.dart`, `data/services/roster_service.dart`, `planner/roster_screen.dart`; via `availabilityProvider` →
  `Availability.busy`. Zon: `domain/sun_position.dart` (waarschuwing 'sun'). Terugblik: `domain/hindsight.dart` + `activities/hindsight_card.dart`.
  Hartslagdrift: `domain/decoupling.dart`. Afspreken-momenten: `community/best_moments_text.dart`.
- Weerslim schema `domain/plan_swap.dart` (kaart in `planner/weather_smart_cards.dart`), vocht `domain/hydration.dart` + `activities/hydration_card.dart`, hond `dogModeProvider`
  (waarschuwingen 'dog'/'water' in `run_warnings.dart`), recordweer `domain/record_weather.dart` + `dashboard/record_weather_card.dart`.
- GPS-kunst is uit de app gehaald (werkte niet; `domain/gps_art.dart` staat nog); i.p.v. daarvan 'Rondje op afstand' met richting
  (N/O/Z/W → `route-generator` legt een driehoek, `_shared/directed_loop.ts`). Leeftijdsniveau `domain/age_grading.dart` +
  `data/services/age_grade_service.dart` (in `activities/records_screen.dart`), pijntjes `domain/pain_log.dart` + `profile/pain_screen.dart`
  (in notitie "Pijntje: <plek> <1-10>"), hartslagherstel `domain/hrr.dart` + `record/hrr_test_dialog.dart` + `data/services/hrr_store.dart`,
  Kadans-effect `data/services/kadans_effect_store.dart` + `activities/kadans_effect_row.dart` (badge 'wise').
- Weerzekerheid `domain/forecast_confidence.dart` + `data/services/forecast_confidence_service.dart` (ensemble + "klopte het?"),
  chip `dashboard/confidence_chip.dart`. Loop-bingo `domain/bingo.dart` + `dashboard/bingo_card.dart` (DashCard.bingo).
- Eigen Android-kanalen `android_extra/kotlin/KadansChannels.kt` (via build.yml in MainActivity): `kadans/calendar`
  (`data/services/phone_calendar_service.dart`, READ_CALENDAR) en `kadans/media` (oortjesknop, `media_button_service.dart`).
- Tekeningen/animaties (eigen, geen pakketten) in `lib/shared/art/`: landschap (seizoenen), weericonen, zonneboog, lopend figuur,
  oefenfiguren (`motionFor(naam)`), uitleg-animatie, seizoensplaatje, kantelen (`Tilt`). Avatars/omslag Samen: `community/runner_avatar.dart` (0036).
  Fotomuur `activities/photo_wall_screen.dart`. Play Store-plaatjes + promovideo: `.github/scripts/store_screens.py` / `store_video.sh`.
- **Glas-proef (alleen op branch `glas-proef`, niet op main):** `GlassPanel` in `lib/shared/glass.dart` (matglas met BackdropFilter, effen
  terugval bij "minder beweging"). Kaartpagina van Opnemen: kaart volle hoogte, cijfers + Markeren in glas (bottom 30, vrij van © Kadaster/PDOK).
  Schermtests `11g_glas_kaart` / `65g_donker_glas_kaart` (`_shot` heeft nu een `act:`-parameter om te vegen). Build + schermen groen.
  Advies: géén glas in de hele app (accu, leesbaarheid in de zon, huisstijl), alleen over kaarten/navigatiebalk.
- Valdetectie `domain/fall_detector.dart` + recorder (`fallCountdown`, `record/fall_alert.dart`); live-pagina toont `alert`, aanmoedigen
  via POST op functie `live-share` (`live_cheers`, 0037). Donker-route: `compareForDark` in `domain/lighting.dart`.
- Stukken `domain/segments.dart` + `data/services/segment_store.dart` + `activities/segments_screen.dart`. Runtitel `domain/run_title.dart`.
  Pijntjes-routine `domain/pain_routine.dart`. Samen-extra's (loopmaatjes, weddenschappen, loopgroepen): `community/together_screens.dart`,
  `data/services/together_service.dart`, SQL 0037. Snelkoppeling `runwise://app/moment` (`core/voice_shortcut.dart`, `android_extra/res/xml/shortcuts.xml`).
- Hoogtemeters: `cleanElevationGain` in `domain/zones.dart` (mediaan+gemiddelde gladstrijken, klim vanaf 4–5 m) voor GPS live,
  hoogtekaart en routeprofiel (`profileAscent`, alleen gladstrijken bij punten ≤ 150 m). Barometer ongewijzigd (stap 3 m).
- Overpass (`data/services/poi_service.dart`): 2 servers tegelijk, 3e na 3 s, max 2 vragen per server, dubbele vragen samengevoegd;
  verlichting vraagt alleen wegen mét `lit`-tag op.
- Profielen (0038): foto in bucket `avatars` (`<uid>/<tijd>.jpg`), bio/plaats/favoriete afstand, `social_avatars2`, `social_profile_extra`,
  melden `social_report_profile`, moderator `social_mod_photo`. App: `community/profile_edit_sheet.dart`, `runner_profile_screen.dart`.
- Stappen van de maand (0038, `steps_submit`/`steps_board`): `community/steps_contest_screen.dart`, Health Connect `READ_STEPS`
  (`SyncService.connectSteps/monthSteps`), alleen maandtotaal naar server. Ranglijst vrienden + per loopgroep.
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
- **App in site-stijl (7-11):** Vandaag = `_TodayScene` (eigen landschap + lucht, groet/advies in wit, lopertje dat meeleeft met weer:
  capuchon/muts/zweet, sterren 's nachts, regenstreepjes; params `rain/feels/runner/night` in `KadansLandscape`) met de advieskaart
  64 px eroverheen (`Transform.translate`), kaart kantelt licht mee (`_TiltCard`, `Tilt`), tijd telt op (`_CountClock`/`CountUpText`),
  feitenrij `_FactRow`, zonneboog ingeklapt (`_MoreDetails` "Zon en licht"), "§ 02 Deze week" als veegrij (`_WeekRow`).
  Gedeeld: `SectionLabel` (§-labels, lettertype `KadansMono` = DejaVu Sans Mono), `KadansButton` (donker blok + goud vierkant),
  papierkorrel in `RwAura` (`PaperGrainPainter`). Route in 3D is weer weggehaald (8-11, Sem).
  Ledenkaart kantelt ook met de telefoon mee. **Ronde 8-11:** weercijfer per uur (`DashCard.hours`, staafjes) staat weer vast
  onder de advieskaart (§ 02, schakelaar "Goede uren"), Deze week = § 03; lopertje weg (Sem vond het knullig: geen getekende lopertjes meer);
  Vandaag-beeld = sfeerfoto `assets/foto/heide.jpg` of `mist.jpg` (mist/buien/grijs, `_foggy`), 's nachts donkerder.
  Opnemen: vaste lettergroottes (hoofdcijfer, getallen 28, tekst 16, labels 13). Badges hebben niveaus `BadgeTier`
  (brons/zilver/goud/platina, `tierColor`, legenda `BadgeTierLegend`). Bluetooth (`FlutterReactiveBle`) is `late` in de services.
  Schermtests: echte Amsterdamse routes (Amsterdamse Bos = "Rondje bos", Vondelpark, Amstel; via BRouter) en echte PDOK-tegels
  (`.github/scripts/haal_tegels.py` in screens.yml → `test_screens/tegels`, `debugMapTiles` in `route_map.dart`), foto's/tegels
  laden alleen bij `images: true`; kaarttest `11c_opnemen_kaart` (`RecordRunScreen.debugSkipWarmUp`). Logboek-voorbeeld = ruim een jaar runs,
  coach-voorbeeld = schema laatste 3 weken halve marathon. `site/app/*.jpg` komen nu uit de schermtests (540×1199).
- Kadans delen: `profile/share_app_screen.dart` (3 kaarten, bericht 4:5 of verhaal 9:16, eigen tekstje; vanuit Ik → Vertel een vriend).
- Strava-upload: functie `strava` actie `upload` (GPX `_shared/gpx.ts`, external_id `kadans-<id>` wordt bij sync overgeslagen).
- **Kadans-stem:** edge function `tts` → **Google Cloud TTS, Chirp 3 HD (nl-NL)**, geheim `GOOGLE_TTS_KEY` (1 mln tekens/maand gratis;
  betalen moet aan staan, budgetgrens instellen). Zonder Google-sleutel: reserve ElevenLabs (`ELEVENLABS_API_KEY`; gratis plan kan géén
  bibliotheekstemmen via de API → reason `plan`). Stemmen `VOICES` in `tts` = `kadansVoices` in `data/services/kadans_voice.dart`:
  Daan (Charon, m, standaard), Bram (Puck, m), Emma (Kore, v), Fleur (Aoede, v). Oude sleutels (berend/jamie/marvin/sanne/anna/roos)
  worden omgezet naar hetzelfde geslacht (`ALIASES` + `choice()`). Terugval alleen binnen geslacht, anders telefoonstem.
  Keuze + voorbeeldknop: `shared/kadans_voice_chooser.dart` (introductie "Kies je coachstem" + Opnemen). Cache per zin én stem.
  Foutredenen → uitleg in `KadansVoice._explain` (key, api_off, billing, plan, quota, voice). Na een fout 2 min pauze.
  **Nooit twee stemmen tegelijk:** `speak(..., fallback, stopFallback)` zet flutter_tts stil vóór het afspelen.
- Marketing (buiten de repo): Instagram **@kadans.app**. Instagram-skills (`/ig-reel`, `/ig-caption`, `/ig-plan` enz.) en
  `frontend-design` en `unslop-ui` (controle op AI-look, scanner: `devibe_scan.py` uit JCarterJohnson/vibecoded-design-tells) zijn als skills beschikbaar in Claude (geen koppeling nodig). Profielfoto = alleen de gouden K.
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
- Strava API-app hernoemen naar Kadans; Strava één keer opnieuw koppelen voor privéroutes en uploaden (`activity:write`).
- Play Console → gegevensveiligheid: agenda (alleen op toestel, niet gedeeld) en afgeronde locatie voor loopmaatjes
  (alleen als de gebruiker het aanzet) toevoegen.
- Promovideo (`schermen-main/playstore/kadans_promo.mp4`) zelf op YouTube zetten ("niet vermeld") voor de Play Store.
- Merkcheck "Kadans" (TMview/BOIP) en domein; Kadans Science Partner (vastgoed) gebruikt dezelfde naam.
- Stripe, Gelato, RevenueCat, KvK/btw voor posters en Premium.
- Na KvK: bedrijfsgegevens (naam, adres, KvK-nummer) invullen in `site/voorwaarden.html` (en versie ophogen).
- Play Console → privacy-URL https://kadans.fit/privacy.html en verwijder-URL https://kadans.fit/verwijderen.html invullen.
- kadans.fit: auto-verlengen uit bij Namecheap ($45,98/jr); rond sept 2027 verhuizen naar Porkbun (± $26/jr).
- Instagram: link in bio zetten (via telefoon) en de oude €600-giveaway-posts archiveren.
- Google Cloud: project + betalen (budgetgrens €1) + "Cloud Text-to-Speech API" aan + API-sleutel (alleen die API) → Supabase-geheim `GOOGLE_TTS_KEY`.
- Play Console → gegevensveiligheid: stappen en profielfoto's toevoegen.
- Testen op telefoon (nieuw 8-11): sfeerfoto op Vandaag (licht/donker, mist), opnamescherm rustiger, badgekleuren, ledenkaart met grote getallen.
- Testen op telefoon (nieuw 7-11): nieuwe Vandaag (beeld, lopertje, kantelen, optellende tijd, veegrij), Kadans-knop, ledenkaart kantelen, weercijfer per uur onder het advies.
- Testen op telefoon (nieuw 6-11 nacht): profielfoto uploaden, vergrendelscherm tijdens run (aan/uit-knop), piep bij aftellen, tempo-alarm,
  route andersom + vlieg over, gedeelde route-link (hoogte op de site), recordfeest + delen, reacties/@vermelding (melding bij openen app),
  groepsagenda, trekken om te vernieuwen.
- Testen op telefoon (nieuw 6-11): stemkeuze + voorbeeld (Daan/Bram/Emma/Fleur, na GOOGLE_TTS_KEY), hoogtemeters, rondje met richting,
  stappen van de maand, profielfoto/bio/melden, Kadans delen, laadtijd water/toilet/verlichting, en de 17 verbeteringen van 6-11 avond
  (stemvolume, tussentijden-kleuren, kaart op tempo, runtitel, verhaal-deelkaart, introductie, melding bij ingehaald).
- Testen op telefoon: licht/donker, Vivoactive 5-meldingen, Strava oude runs/routes en upload, Samen (loopmaatjes, weddenschappen,
  loopgroepen, profielplaatje), valdetectie, oortjesknop, telefoonagenda, snelkoppeling "Wanneer lopen?", donker-route,
  stukken, live aanmoedigen, kantelen (landschap/medailles), widget, oefenfiguur (gouden tekenpop, schermtest `27b_oefenfiguren`).
- Unslop (6-11 grotendeels gedaan): nog over: 21× pil (999) nalopen, emoji in 5 bestanden, gloed bij uitdagingen.
- **Glas-proef: Sem kiest** → goed (meenemen in de unslop-ronde, + navigatiebalk en kaarten bij Routes), weggooien, of eerst als APK testen
  (tijdelijk naar main, daarna terugdraaien).

## Agent skills
- Issues: GitHub Issues van `Semdenhartog/Kandans` (via `gh`), zie `docs/agents/issue-tracker.md`.
- Domein: één `GLOSSARY.md` en `docs/adr/` in de root (pas maken als nodig), zie `docs/agents/domain.md`.
