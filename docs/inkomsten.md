# Extra inkomsten – wat Sem moet instellen

Alles is gebouwd. Hieronder staat wat jij nog moet aanmaken of invullen. De code werkt ook als het
er (nog) niet is: dan zie je "Binnenkort te koop" of een gewone zoeklink.

> Dit is geen juridisch of fiscaal advies. Twijfel je, vraag het na bij de KvK of een boekhouder.

---

## 1. Schoenen bij een hardloopspeciaalzaak

**Wat er al is:** de kaart "Tijd voor nieuwe schoenen" (op Vandaag en in Mijn schoenen) zodra een
schoen 90% van zijn km-grens heeft. De knop opent nu een gewone zoekopdracht naar het schoenmodel.

**Wat jij doet:**
1. Kies een hardloopspeciaalzaak met een affiliate-programma. Speciaalzaken zitten meestal bij een
   netwerk als Daisycon, TradeTracker of Awin. Meld je daar aan met RunWise als "app".
2. Haal bij het netwerk een **zoek- of deeplink** op waarin het zoekwoord past, en zet `{q}` op de
   plek van het zoekwoord. Voorbeeld van de vorm (niet echt):
   `https://winkel.example/zoeken?q={q}&utm_source=runwise&partner=12345`
3. Zet het in Supabase (SQL Editor):

   ```sql
   insert into public.model_config (key, value) values
     ('shoe_shop_name', 'Naam van de winkel'),
     ('shoe_shop_url', 'https://.../zoeken?q={q}&partner=...'),
     ('shoe_shop_partner', 'true')
   on conflict (key) do update set value = excluded.value;
   ```

   Alleen `https://`-links met `{q}` worden gebruikt. Met `shoe_shop_partner = true` staat er onder
   de knop: "Partnerlink: RunWise krijgt een kleine vergoeding als je iets koopt."

---

## 2. Luxe-ontwerpen (eenmalige aankoop, gratis bij Premium)

**Wat er al is:** 4 luxe posterstijlen (Goud, Marmer, Oceaan, Blauwdruk) en een gouden deelkaart.
Iedereen kan ze bekijken; delen of laten drukken vraagt om ontgrendelen.

**Wat jij doet:**
1. **Play Console** → je app → Monetiseren → Producten → **In-app-producten** → Product maken:
   - Product-ID: `runwise_luxe_designs` (precies zo)
   - Naam: "Luxe-ontwerpen", prijs bijv. € 2,99 → Activeren.
2. **RevenueCat** → Products → product `runwise_luxe_designs` toevoegen.
3. **RevenueCat** → Entitlements → nieuw: `luxe_designs` (precies zo) → product eraan koppelen.
4. Zorg dat het GitHub-geheim `REVENUECAT_ANDROID_KEY` er is (dat ontbreekt nu nog; zonder deze
   sleutel zie je "Binnenkort te koop").

---

## 3. Routeposter laten drukken (Stripe + Gelato)

**Hoe het werkt:** route → "Deel als poster" → stijl kiezen → **Laten drukken** → formaat en adres →
betalen bij Stripe (iDEAL/kaart) → Stripe meldt de betaling → de server zet de bestelling bij
Gelato → Gelato drukt en verstuurt. In de app: Ik → **Mijn posters** toont de status.

**Veilig testen:** zolang `GELATO_ORDER_TYPE` niet op `order` staat, maakt de server bij Gelato alleen
een **concept** (er wordt niets gedrukt of gefactureerd). In de app staat dan "Klaargezet (testmodus)".

### Eerst regelen (buiten de app)
- **KvK en btw:** fysieke producten verkopen is ondernemen. Check of je je moet inschrijven en btw
  moet afdragen (de prijzen in de app zijn inclusief btw).
- **Algemene voorwaarden** op je site (betaling, levering, klachten). Persoonlijk gemaakte producten
  vallen niet onder het herroepingsrecht; dat staat al in de app, maar hoort ook in je voorwaarden.
- **Privacyverklaring:** Stripe en Gelato staan er al in. Vul ook [NAAM] enz. nog in.

### Stap voor stap
1. **Migratie 0028** uitvoeren: Supabase → SQL Editor → inhoud van `supabase/migrations/0028_poster_orders.sql` → Run.
2. **Stripe-account** (stripe.com, Nederland). Zet iDEAL aan bij Betaalmethoden.
   Developers → API keys → kopieer de **test**-sleutel `sk_test_...`.
3. **Supabase → Edge Functions → Secrets:**
   - `STRIPE_SECRET_KEY` = `sk_test_...`
4. **Stripe → Developers → Webhooks → Add endpoint:**
   - URL: `https://jdswennyfczpqblfkrxt.supabase.co/functions/v1/stripe-webhook`
   - Events: `checkout.session.completed`, `checkout.session.async_payment_succeeded`,
     `checkout.session.async_payment_failed`, `checkout.session.expired`
   - Kopieer de **Signing secret** (`whsec_...`) → Supabase-secret `STRIPE_WEBHOOK_SECRET`.
5. **Gelato-account** (gelato.com) → Developers → API keys → Supabase-secret `GELATO_API_KEY`.
6. **Productcodes controleren:** in Gelato → Products → Posters → kies formaat en papier → kopieer de
   "Product UID". Zet die in Supabase → Table Editor → `poster_products` → kolom `gelato_product_uid`.
   (De codes die er nu staan zijn een voorbeeld en kunnen afwijken.)
7. **Prijzen kiezen** in `poster_products` → `price_cents` (2495 = € 24,95, inclusief btw en verzending).
   Reken: verkoopprijs − 21% btw − Gelato (druk + verzending) − Stripe-kosten = jouw marge.
   Gelato toont de kostprijs per formaat en land in hun dashboard.
8. **Functies live zetten:** GitHub → Actions → "Supabase-functies live zetten" → Run workflow.
9. **Testen:** bestel in de app een poster en betaal met Stripe-testkaart `4242 4242 4242 4242`
   (willekeurige toekomstige datum en CVC). Controleer:
   - Stripe → Payments: betaling staat er.
   - Supabase → `poster_orders`: status `concept`.
   - Gelato → Orders: concept-bestelling met jouw poster en adres.
10. **Live gaan:** Stripe-secret vervangen door `sk_live_...`, een live-webhook toevoegen (stap 4
    opnieuw, nu in live-modus, nieuw `whsec_...`) en `GELATO_ORDER_TYPE` = `order` zetten.

### Als er iets misgaat
- Status `mislukt` in `poster_orders`: kolom `error` zegt wat (bijv. verkeerde Gelato-productcode).
  De klant heeft dan wel betaald: zet hem handmatig door in Gelato of betaal terug via Stripe.
- Logboeken: Supabase → Edge Functions → `stripe-webhook` of `poster-order` → Logs.
