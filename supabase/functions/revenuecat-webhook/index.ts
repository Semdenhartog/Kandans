// Edge Function: revenuecat-webhook
// RevenueCat meldt hier elke aankoop, verlenging, opzegging en verloop.
// Wij houden daarmee public.subscriptions bij; een trigger zet profiles.is_premium.
//
// Instellen in RevenueCat -> Project -> Integrations -> Webhooks:
//   URL:                  https://<project>.supabase.co/functions/v1/revenuecat-webhook
//   Authorization header: dezelfde waarde als het geheim REVENUECAT_WEBHOOK_SECRET
//
// Deploy met "Verify JWT" UIT: RevenueCat heeft geen RunWise-login.
// De app logt bij RevenueCat in met de Supabase user-id, dus app_user_id = user_id.

import { createClient } from "jsr:@supabase/supabase-js@2";

const env = (k: string) => Deno.env.get(k) ?? "";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function ok(body: Record<string, unknown> = { ok: true }, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/** Constant-time vergelijking van het geheim. */
function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return ok({ error: "POST only" }, 405);

  const secret = env("REVENUECAT_WEBHOOK_SECRET");
  const given = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!secret || !safeEqual(given, secret)) return ok({ error: "unauthorized" }, 401);

  const payload = await req.json().catch(() => null);
  const e = payload?.event;
  if (!e?.type) return ok({ error: "no event" }, 400);
  if (e.type === "TEST") return ok({ test: true });

  // Bij TRANSFER staat de nieuwe eigenaar in transferred_to.
  const candidates: string[] = [
    e.app_user_id, e.original_app_user_id, ...(e.aliases ?? []), ...(e.transferred_to ?? []),
  ].filter((x: unknown): x is string => typeof x === "string" && UUID.test(x));
  const userId = candidates[0];
  if (!userId) {
    // Anonieme RevenueCat-gebruiker: niets te koppelen. 200 zodat RevenueCat niet blijft herhalen.
    console.warn("revenuecat event without supabase user id", e.type);
    return ok({ skipped: "no user" });
  }

  const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY") || env("SUPABASE_SECRET_KEY"), {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const productId = String(e.product_id ?? "");
  const plan = /year|jaar|annual/i.test(productId) ? "yearly" : "monthly";
  const periodEnd = e.expiration_at_ms ? new Date(e.expiration_at_ms) : new Date();
  const trial = e.period_type === "TRIAL";

  let status: "active" | "trialing" | "expired" | "cancelled";
  switch (e.type) {
    case "INITIAL_PURCHASE":
    case "RENEWAL":
    case "PRODUCT_CHANGE":
    case "UNCANCELLATION":
    case "SUBSCRIPTION_EXTENDED":
    case "TEMPORARY_ENTITLEMENT_GRANT":
    case "TRANSFER":
      status = trial ? "trialing" : "active";
      break;
    case "CANCELLATION":
      // Automatisch verlengen staat uit, maar de betaalde periode loopt nog door.
      status = periodEnd.getTime() > Date.now() ? (trial ? "trialing" : "active") : "cancelled";
      break;
    case "BILLING_ISSUE":
      // Google geeft een respijtperiode; zolang die loopt houdt de gebruiker toegang.
      status = periodEnd.getTime() > Date.now() ? "active" : "expired";
      break;
    case "EXPIRATION":
      status = "expired";
      break;
    default:
      return ok({ ignored: e.type });
  }

  const { error } = await db.from("subscriptions").upsert({
    user_id: userId,
    provider: "revenuecat",
    plan,
    status,
    current_period_end: periodEnd.toISOString(),
  }, { onConflict: "user_id,provider" });

  if (error?.code === "23503") {
    // Account bestaat niet (meer), bijvoorbeeld na verwijderen. Niet blijven herhalen.
    return ok({ skipped: "unknown user" });
  }
  if (error) {
    console.error("subscriptions upsert failed", error.message);
    // 500 -> RevenueCat probeert het later opnieuw.
    return ok({ error: "db" }, 500);
  }
  return ok({ status });
});
