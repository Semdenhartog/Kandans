// Edge Function: stripe-webhook
// 1) POST van Stripe (webhook): na betalen de posterbestelling doorzetten naar Gelato.
// 2) GET ?return=ok|cancel&order=<id>: na de betaalpagina terug naar de app (runwise://app/poster-besteld).
//
// Live zetten zonder login-controle door Supabase (--no-verify-jwt): Stripe belt zelf.
// De handtekening van Stripe wordt hieronder gecontroleerd; zonder geldige handtekening gebeurt er niets.
//
// Geheimen (Supabase -> Edge Functions -> Secrets), NOOIT in de code:
//   STRIPE_WEBHOOK_SECRET  whsec_... (Stripe -> Developers -> Webhooks -> dit adres -> Signing secret)
//   GELATO_API_KEY         Gelato -> Developers -> API keys
// Optioneel:
//   GELATO_ORDER_TYPE      "draft" (standaard: Gelato drukt nog NIETS, om te testen) of "order" (echt drukken)

import { createClient } from "jsr:@supabase/supabase-js@2";
import { validStripeSignature } from "../_shared/poster.ts";

const APP_RETURN = "runwise://app/poster-besteld";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

function text(status: number, body: string) {
  return new Response(body, { status, headers: { "Content-Type": "text/plain; charset=utf-8" } });
}

type Order = {
  id: string;
  user_id: string | null;
  product_id: string;
  file_path: string;
  status: string;
  shipping: { name: string; street: string; house_number: string; postcode: string; city: string; country: string; email: string };
};

async function sendToGelato(order: Order): Promise<{ id?: string; error?: string; draft: boolean }> {
  const key = (Deno.env.get("GELATO_API_KEY") ?? "").trim();
  const orderType = (Deno.env.get("GELATO_ORDER_TYPE") ?? "draft").trim() === "order" ? "order" : "draft";
  if (!key) return { error: "GELATO_API_KEY ontbreekt", draft: orderType === "draft" };

  const { data: product } = await db.from("poster_products").select("gelato_product_uid").eq("id", order.product_id).maybeSingle();
  if (!product) return { error: "Product niet gevonden", draft: orderType === "draft" };
  // Gelato haalt het bestand zelf op; de link is 7 dagen geldig.
  const { data: signed } = await db.storage.from("poster-files").createSignedUrl(order.file_path, 7 * 24 * 3600);
  if (!signed?.signedUrl) return { error: "Drukbestand niet gevonden", draft: orderType === "draft" };

  const [firstName, ...rest] = order.shipping.name.split(/\s+/);
  const res = await fetch("https://order.gelatoapis.com/v4/orders", {
    method: "POST",
    headers: { "X-API-KEY": key, "Content-Type": "application/json" },
    body: JSON.stringify({
      orderType,
      orderReferenceId: order.id,
      customerReferenceId: order.user_id ?? "verwijderd",
      currency: "EUR",
      items: [{
        itemReferenceId: order.id,
        productUid: product.gelato_product_uid,
        files: [{ type: "default", url: signed.signedUrl }],
        quantity: 1,
      }],
      shippingAddress: {
        firstName,
        lastName: rest.join(" "),
        addressLine1: `${order.shipping.street} ${order.shipping.house_number}`,
        city: order.shipping.city,
        postCode: order.shipping.postcode,
        country: order.shipping.country,
        email: order.shipping.email,
      },
    }),
    signal: AbortSignal.timeout(30_000),
  }).catch((e) => {
    console.error("gelato fetch", e?.message ?? e);
    return null;
  });
  if (!res || !res.ok) {
    const detail = res ? (await res.text()).slice(0, 500) : "geen antwoord";
    console.error("gelato order", res?.status, detail);
    return { error: `Gelato ${res?.status ?? "-"}: ${detail}`, draft: orderType === "draft" };
  }
  const out = await res.json();
  return { id: String(out.id ?? ""), draft: orderType === "draft" };
}

async function handlePaid(orderId: string) {
  const { data: order } = await db.from("poster_orders")
    .select("id, user_id, product_id, file_path, status, shipping").eq("id", orderId).maybeSingle();
  if (!order) {
    console.error("stripe-webhook: bestelling niet gevonden", orderId);
    return;
  }
  // Stripe kan een gebeurtenis vaker sturen: alleen een nieuwe bestelling doorzetten.
  const { data: claimed } = await db.from("poster_orders")
    .update({ status: "betaald" }).eq("id", orderId).eq("status", "nieuw").select("id");
  if (!claimed || claimed.length === 0) return;

  const r = await sendToGelato(order as Order);
  if (r.error) {
    await db.from("poster_orders").update({ status: "mislukt", error: r.error }).eq("id", orderId);
  } else {
    await db.from("poster_orders").update({ status: r.draft ? "concept" : "in_productie", gelato_order_id: r.id, error: null }).eq("id", orderId);
  }
}

/** Drukbestanden ouder dan 90 dagen verwijderen (zoals de privacyverklaring belooft). */
async function cleanupOldFiles() {
  const before = new Date(Date.now() - 90 * 86_400_000).toISOString();
  const { data: old } = await db.from("poster_orders")
    .select("id, file_path").lt("created_at", before).neq("file_path", "verwijderd").limit(100);
  if (!old || old.length === 0) return;
  await db.storage.from("poster-files").remove(old.map((o) => o.file_path));
  await db.from("poster_orders").update({ file_path: "verwijderd" }).in("id", old.map((o) => o.id));
}

/** Werk op de achtergrond afmaken, zodat Stripe meteen antwoord krijgt (anders: gewoon wachten). */
async function background(p: Promise<unknown>) {
  const rt = (globalThis as { EdgeRuntime?: { waitUntil(p: Promise<unknown>): void } }).EdgeRuntime;
  if (rt) rt.waitUntil(p.catch((e) => console.error("stripe-webhook achtergrond", e)));
  else await p;
}

Deno.serve(async (req) => {
  // Terug naar de app na de betaalpagina.
  if (req.method === "GET") {
    const u = new URL(req.url);
    const status = u.searchParams.get("return") === "ok" ? "ok" : "cancel";
    const order = (u.searchParams.get("order") ?? "").replace(/[^0-9a-f-]/gi, "").slice(0, 36);
    return new Response(null, { status: 302, headers: { Location: `${APP_RETURN}?status=${status}&order=${order}` } });
  }
  if (req.method !== "POST") return text(405, "Alleen POST");

  const secret = (Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "").trim();
  if (!secret) return text(503, "Niet ingesteld");
  const payload = await req.text();
  if (!(await validStripeSignature(payload, req.headers.get("Stripe-Signature") ?? "", secret))) {
    return text(400, "Ongeldige handtekening");
  }

  let event: { type?: string; data?: { object?: Record<string, unknown> } };
  try {
    event = JSON.parse(payload);
  } catch {
    return text(400, "Geen JSON");
  }
  const obj = event.data?.object ?? {};
  const orderId = String((obj.metadata as Record<string, string> | undefined)?.order_id ?? obj.client_reference_id ?? "");
  if (!orderId) return text(200, "Geen bestelling");

  switch (event.type) {
    case "checkout.session.completed":
      if (obj.payment_status === "paid") await background(handlePaid(orderId));
      break;
    case "checkout.session.async_payment_succeeded":
      await background(handlePaid(orderId));
      break;
    case "checkout.session.expired":
    case "checkout.session.async_payment_failed":
      await db.from("poster_orders").update({ status: "geannuleerd" }).eq("id", orderId).eq("status", "nieuw");
      break;
  }
  await background(cleanupOldFiles());
  return text(200, "ok");
});
