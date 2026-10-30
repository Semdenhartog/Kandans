# RevenueCat instellen voor Kadans Premium

De app is klaar. Wat nog in het dashboard moet, in deze volgorde.

## Hoe het in elkaar zit
- Recht (entitlement): **`kadans_pro`** = Premium. Losse Luxe-ontwerpen blijven apart: `luxe_designs`.
- Producten: **`monthly`**, **`yearly`** (abonnementen) en **`lifetime`** (eenmalig, niet-verbruikbaar).
- Offering **`default`** (current) met de packages Monthly, Annual en Lifetime.
- App: `lib/data/services/billing_service.dart` (paywall, Customer Center, terugzetten, foutmeldingen),
  scherm `lib/features/coach/paywall_screen.dart` (route `/premium`).
- Server: webhook `supabase/functions/revenuecat-webhook` → tabel `subscriptions` → `profiles.is_premium`.
  Logica + tests: `supabase/functions/_shared/revenuecat.ts`. Lifetime = plan `lifetime` tot 2999 (migratie 0035).

## Stappen in RevenueCat (app.revenuecat.com)
1. **Entitlement**: Product catalog → Entitlements → New → identifier `kadans_pro`.
2. **Producten**: Product catalog → Products → voeg `monthly`, `yearly` en `lifetime` toe
   (eerst bij de Test Store; later dezelfde id's bij de Google Play-app).
   Koppel alle drie aan `kadans_pro`. Lifetime als **Non-consumable** instellen.
3. **Offering**: Offerings → `default` (Make current) → packages: `$rc_monthly` → monthly,
   `$rc_annual` → yearly, `$rc_lifetime` → lifetime.
4. **Paywall**: Paywalls → New paywall voor offering `default`. Tip: zwart met goud, zoals de Premium-pagina.
   Teksten in NL/EN/DE/FR/ES (de paywall volgt de taal van de telefoon).
5. **Customer Center**: Customer Center → aanzetten. Hier kies je wat gebruikers kunnen (opzeggen, terugzetten, vragen).
6. **Webhook**: Integrations → Webhooks → URL `https://jdswennyfczpqblfkrxt.supabase.co/functions/v1/revenuecat-webhook`,
   Authorization = zelfde waarde als Supabase-geheim `REVENUECAT_WEBHOOK_SECRET`.

## Sleutels (nooit in de code)
- **`test_…` (Test Store)**: nep-aankopen. Zet hem in GitHub Secrets als **`REVENUECAT_TEST_KEY`**.
  Elke build van main maakt dan ook een testversie (debug-APK) die náást de gewone app staat:
  naam "Kadans test", pakket `nl.runwise.runwise.test`.
  Link: https://github.com/Semdenhartog/Kandans/releases/download/laatste/kadans-test.apk
  - Niet als `REVENUECAT_ANDROID_KEY` gebruiken: in een release-APK laat RevenueCat de app bewust crashen;
    de app zet Premium dan op "nog niet beschikbaar".
  - Nep-aankopen gaan ook via de webhook: je eigen account wordt dan op de server ook Premium (tot de testaankoop verloopt).
  - Inloggen met e-mail en wachtwoord werkt. Links die de app openen (`runwise://`, zoals Strava-terugkeer)
    vragen welke van de twee apps je wilt gebruiken.
- **`goog_…` (Google Play)**: voor de echte APK en de Play Store. Zet hem in GitHub → Settings → Secrets →
  `REVENUECAT_ANDROID_KEY`.

## In Google Play Console (na KvK)
- Abonnementen `monthly` (€5, 1 maand gratis) en `yearly` (€40, 1 maand gratis), in-app-product `lifetime`.
- Service-account koppelen aan RevenueCat (Project settings → Google Play), anders ziet RevenueCat de aankopen niet.
