// node --experimental-strip-types supabase/functions/_shared/revenuecat.test.ts
import assert from "node:assert/strict";
import { decide, LIFETIME_END, planFor } from "./revenuecat.ts";

const now = new Date("2026-11-01T12:00:00Z");
const later = Date.parse("2026-12-01T12:00:00Z");
const earlier = Date.parse("2026-10-01T12:00:00Z");

assert.equal(planFor("monthly"), "monthly");
assert.equal(planFor("yearly"), "yearly");
assert.equal(planFor("kadans_premium:yearly"), "yearly");
assert.equal(planFor("lifetime"), "lifetime");

// Maandabonnement met proefmaand
let d = decide({ type: "INITIAL_PURCHASE", product_id: "monthly", entitlement_ids: ["kadans_pro"], period_type: "TRIAL", expiration_at_ms: later }, null, now);
assert.deepEqual(d, { kind: "upsert", plan: "monthly", status: "trialing", periodEnd: new Date(later) });

// Lifetime: eenmalig, geen einddatum
d = decide({ type: "NON_RENEWING_PURCHASE", product_id: "lifetime", entitlement_ids: ["kadans_pro"], expiration_at_ms: null }, null, now);
assert.deepEqual(d, { kind: "upsert", plan: "lifetime", status: "active", periodEnd: LIFETIME_END });

// Luxe-ontwerpen (ander recht) raken Premium niet
d = decide({ type: "NON_RENEWING_PURCHASE", product_id: "runwise_luxe_designs", entitlement_ids: ["luxe_designs"] }, null, now);
assert.equal(d.kind, "ignore");
d = decide({ type: "NON_RENEWING_PURCHASE", product_id: "runwise_luxe_designs" }, null, now);
assert.equal(d.kind, "ignore");

// Oud abonnement-event zonder entitlement_ids telt nog als Premium
d = decide({ type: "RENEWAL", product_id: "runwise_yearly", expiration_at_ms: later }, null, now);
assert.equal(d.kind, "upsert");

// Aflopend maandabonnement mag een actieve lifetime niet wegzetten
const life = { plan: "lifetime" as const, status: "active" as const, current_period_end: LIFETIME_END.toISOString() };
d = decide({ type: "EXPIRATION", product_id: "monthly", entitlement_ids: ["kadans_pro"], expiration_at_ms: earlier }, life, now);
assert.deepEqual(d, { kind: "ignore", reason: "lifetime active" });

// Terugbetaalde lifetime zet Premium uit
d = decide({ type: "CANCELLATION", product_id: "lifetime", entitlement_ids: ["kadans_pro"] }, life, now);
assert.deepEqual(d, { kind: "upsert", plan: "lifetime", status: "cancelled", periodEnd: now });

// Opgezegd jaarabonnement loopt door tot de einddatum
d = decide({ type: "CANCELLATION", product_id: "yearly", entitlement_ids: ["kadans_pro"], expiration_at_ms: later }, null, now);
assert.equal(d.kind === "upsert" && d.status, "active");

// Onbekend event
assert.equal(decide({ type: "SUBSCRIBER_ALIAS", entitlement_ids: ["kadans_pro"] }, null, now).kind, "ignore");

console.log("revenuecat: alle tests geslaagd");
