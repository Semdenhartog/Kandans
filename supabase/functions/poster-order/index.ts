// Edge Function: poster-order
// Maakt een posterbestelling aan en geeft een Stripe-betaalpagina (iDEAL, kaart, ...) terug.
//
//   POST { product_id, title, style, file_path, shipping: { name, street, house_number, postcode, city, country, email } }
//   ->   { order_id, checkout_url }
//
// De prijs komt uit de tabel poster_products (nooit uit de app). Na betalen zet de functie
// stripe-webhook de bestelling door naar Gelato.
//
// Geheimen (Supabase -> Edge Functions -> Secrets), NOOIT in de code:
//   STRIPE_SECRET_KEY   sk_test_... om te testen, later sk_live_...
// Optioneel:
//   POSTER_RETURN_URL   standaard <SUPABASE_URL>/functions/v1/stripe-webhook (stuurt terug naar de app)

import { createClient } from "jsr:@supabase/supabase-js@2";
import { checkQuota } from "../_shared/quota.ts";
import { cleanShipping } from "../_shared/poster.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Alleen POST is toegestaan." });

  const stripeKey = (Deno.env.get("STRIPE_SECRET_KEY") ?? "").trim();
  if (!stripeKey) return json(503, { error: "Posters bestellen is nog niet ingesteld.", code: "not_configured" });

  const quota = await checkQuota(req, "poster-order", 10);
  if (!quota.ok) return json(quota.status, { error: quota.error });

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth } = await admin.auth.getUser(jwt);
  const user = auth?.user;
  if (!user) return json(401, { error: "Log opnieuw in." });

  const body = await req.json().catch(() => ({}));
  const shipping = cleanShipping(body.shipping);
  if (typeof shipping === "string") return json(400, { error: shipping });
  const title = String(body.title ?? "").trim().slice(0, 80) || "Mijn route";
  const style = String(body.style ?? "").trim().slice(0, 24);
  const filePath = String(body.file_path ?? "");
  if (!filePath.startsWith(`${user.id}/`) || filePath.includes("..") || !filePath.endsWith(".png")) {
    return json(400, { error: "Het drukbestand ontbreekt. Probeer het opnieuw." });
  }

  const { data: product } = await admin.from("poster_products")
    .select("id, label, price_cents, active").eq("id", String(body.product_id ?? "")).maybeSingle();
  if (!product || !product.active) return json(400, { error: "Dit formaat is niet (meer) te bestellen." });

  // Bestaat het drukbestand echt?
  const folder = filePath.split("/").slice(0, -1).join("/");
  const fileName = filePath.split("/").pop()!;
  const { data: files } = await admin.storage.from("poster-files").list(folder, { search: fileName, limit: 1 });
  if (!files || !files.some((f) => f.name === fileName)) return json(400, { error: "Het drukbestand ontbreekt. Probeer het opnieuw." });

  const { data: order, error: insErr } = await admin.from("poster_orders").insert({
    user_id: user.id,
    product_id: product.id,
    price_cents: product.price_cents,
    title,
    style,
    file_path: filePath,
    shipping,
  }).select("id").single();
  if (insErr || !order) {
    console.error("poster_orders insert", insErr?.message);
    return json(500, { error: "De bestelling kon niet worden aangemaakt." });
  }

  const back = (Deno.env.get("POSTER_RETURN_URL") ?? `${url}/functions/v1/stripe-webhook`).replace(/\/$/, "");
  const form = new URLSearchParams({
    mode: "payment",
    locale: "nl",
    success_url: `${back}?return=ok&order=${order.id}`,
    cancel_url: `${back}?return=cancel&order=${order.id}`,
    client_reference_id: order.id,
    customer_email: shipping.email,
    "metadata[order_id]": order.id,
    "payment_intent_data[metadata][order_id]": order.id,
    "line_items[0][quantity]": "1",
    "line_items[0][price_data][currency]": "eur",
    "line_items[0][price_data][unit_amount]": String(product.price_cents),
    "line_items[0][price_data][product_data][name]": `RunWise-poster ${product.label}`,
    "line_items[0][price_data][product_data][description]": `${title} · inclusief verzending`,
  });
  const res = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: { Authorization: `Bearer ${stripeKey}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
    signal: AbortSignal.timeout(20_000),
  }).catch(() => null);
  if (!res || !res.ok) {
    console.error("stripe checkout", res?.status, res ? await res.text() : "geen antwoord");
    await admin.from("poster_orders").update({ status: "mislukt", error: "Stripe-betaalpagina maken mislukt" }).eq("id", order.id);
    return json(502, { error: "Betalen is even niet mogelijk. Probeer het later opnieuw." });
  }
  const session = await res.json();
  await admin.from("poster_orders").update({ stripe_session_id: session.id }).eq("id", order.id);
  return json(200, { order_id: order.id, checkout_url: session.url });
});
