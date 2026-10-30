# Strava: wat lopers missen of irritant vinden (en wat Kadans ermee doet)

Gemaakt 30 okt 2026, alleen uit openbare bronnen (reviews, nieuws, fora, Strava-helppagina's). **Geen** reverse engineering
van de Strava-app: dat verbiedt Strava in de gebruiksvoorwaarden en het kan onze Strava-API-koppeling kosten.

## Waar Strava sterk in is (niet tegen proberen te concurreren)
- Het netwerk: iedereen zit er al, vrienden, clubs, segmenten. Dat haal je niet in.
- Daarom: Kadans is **geen tweede Strava**, maar de app die zegt *wanneer en waar* je het beste loopt. Strava blijft gekoppeld.

## Klachten over Strava, met de kans voor Kadans

| # | Klacht (bron) | Kadans nu | Kans / actie |
|---|---|---|---|
| 1 | **Gratis functies verdwijnen achter de betaalmuur** (segmenten, delen van je eigen trainingslog). Grootste ergernis in 1–3-sterrenreviews; prijsverhogingen tot ~50% met slechte uitleg (Unstar, road.cc, BikeRadar). | Premium €5/mnd of €40/jr, 1 mnd gratis. | **Belofte "wat gratis is, blijft gratis"** in de Play Store-tekst, op de site en in de shop. Kost niets, raakt de grootste ergernis. Prijs nooit stil verhogen: altijd vooraf en duidelijk melden. |
| 2 | **Feed op algoritme** i.p.v. op tijd; vol met reclame, gesponsorde uitdagingen, wandelingetjes en "spiermannetjes" (TrainerRoad-forum, Reddit, Lemmy). | Feed "Volgend" staat al **op volgorde van tijd**, geen reclame, alleen runs. | Zichtbaar maken: klein label "Op volgorde van tijd, zonder reclame". Nooit gesponsorde uitdagingen in de feed. |
| 3 | **Privacy-schrik**: juni 2025 zette Strava in een test privé-trainingsnotities (Garmin, Runna, TrainingPeaks) zonder waarschuwing openbaar; na kritiek teruggedraaid (Advnture). | Delen alleen per run en zelf gekozen, standaard "Volgers", privacyzone 500 m, geen hartslag/tijdstip. | Marketing: "Kadans deelt nooit iets wat jij niet zelf deelt." Regel voor onszelf: geen stille wijzigingen aan wat anderen zien. |
| 4 | **GPS-fouten en spookafstand** (27% van de slechte reviews over alle loopapps); echte runs worden soms als "met de auto" gemarkeerd zonder uitleg (Unstar, Trustpilot). | Er is GPS-kwaliteitscontrole (`gps_quality`), run bijsnijden. | Bij een rare GPS-piek: tonen *welk stuk* niet klopt en laten kiezen (weghalen / houden), in plaats van stil afkeuren. |
| 5 | **Geschiedenis kwijt** na update of nieuwe telefoon; "mijn data gegijzeld" (Unstar). | Alles staat in de cloud; export van alle runs (CSV/GPX) bestaat in Ik. | Export laten zien bij de Premium-uitleg: "Je runs zijn van jou, ook zonder Premium." |
| 6 | **Druk en schuldgevoel**: meldingen over je reeks terwijl je geblesseerd bent; app voelt als "opscheppen" i.p.v. beter worden (Reddit). | Badges met "volhouden" per week. | **Pauzeknop** (blessure/vakantie): reeksen en herinneringen staan stil, de coach past het schema aan. Klein om te bouwen. |
| 7 | **AI-samenvatting voelt nutteloos/te positief** ("pointless", altijd juichend) (Cycling Weekly, Fortune, Reddit). | AI-coach met weer, schema en eerlijk advies. | Coach blijft **eerlijk en concreet** (wat ging mis, wat morgen anders), niet alleen complimenten. Alleen tonen als je erom vraagt. |
| 8 | **Weer zit niet in routeplanning**; lopers gebruiken er losse apps voor (Medium-UX-studie, Reddit, losse weer-apps). | **Kern van Kadans**: beste moment, wind per stuk van de route. | Dit is het verkooppunt. In elke uiting: "Strava laat zien wat je liep. Kadans zegt wanneer je het best kunt lopen." |
| 9 | **Routes naar het horloge** is lastig/alleen betaald; turn-by-turn ontbreekt of is beperkt (Reddit, Kimola-reviews). | Routes naar Garmin, afslagmeldingen op de Vivoactive 5. | Noemen in de Play Store-tekst; gratis houden. |
| 10 | **Slechte support**: weken geen antwoord, ook voor ontwikkelaars (Reddit, Trustpilot). | Feedbackadres in de app. | Klein voordeel: snel en persoonlijk antwoorden zolang Kadans klein is. |

## Wat we bewust NIET doen
- Strava-look nadoen (kleuren, "kudos", segmenten-KOM's). Strava vraagt API-gebruikers expliciet om dat niet te doen.
- Strava-runs aan anderen tonen of naar de AI-coach sturen (API-regels; staat al zo in de code en de database).
- Segmenten/ranglijsten per straatstuk: dat is Strava's terrein (en hun patenten).

## Mogelijke volgende bouwstappen (kort)
1. Belofte "wat gratis is, blijft gratis" in Play Store-tekst, site en shop (tekst).
2. Label "Op volgorde van tijd, zonder reclame" boven de feed (klein).
3. Pauzeknop blessure/vakantie (reeksen + herinneringen stil, coach weet het).
4. GPS-piek: laat zien welk stuk afwijkt en laat de loper kiezen.

## Bronnen
- Unstar, 1–3-sterrenreviews van 5 loopapps (2026): https://unstar.app/blog/nike-run-club-strava-runkeeper-mapmyrun-adidas-running-apps-ranked-2026
- Prijsverhoging en kritiek: https://www.bikeperfect.com/news/strava-faces-backlash-as-platform-increases-monthly-subscription-price-by-25-percent , https://road.cc/content/news/strava-apologises-price-hike-controversy-298843
- Feed op algoritme: https://www.trainerroad.com/forum/t/anyone-else-switching-off-from-strava/8695.md?page=3
- Privacytest juni 2025: https://www.advnture.com/tech/watches-wearable-tech/a-violation-of-privacy-and-also-intellectual-property-strava-users-left-stunned-after-previously-private-garmin-runna-and-trainingpeaks-stats-reportedly-made-public-without-warning
- Athlete Intelligence-kritiek: https://cyclingweekly.com/news/strava-says-its-new-ai-feature-is-not-a-novelty-but-i-think-its-pointless
- Reddit r/Strava (reeksen, spiermannetjes, replay): via archief reddit.sentinel-team.org
- Strava-voorwaarden (verbod op reverse engineering): https://conductatlas.com/platform/strava/strava-terms-of-service/provision/CA-P-034646/prohibition-on-reverse-engineering-services/
- API-regels look-and-feel: https://www.cyclingnews.com/news/strava-plan-to-restrict-third-party-apps-has-users-in-an-uproar
