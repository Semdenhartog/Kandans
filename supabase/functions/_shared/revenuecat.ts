// Pure logica voor de RevenueCat-webhook: welk abonnement hoort bij een event?
// Los van Deno/Supabase, zodat het te testen is met
//   node --experimental-strip-types supabase/functions/_shared/revenuecat.test.ts

/** Recht in RevenueCat dat Premium geeft (zelfde als BillingService.premiumEntitlement in de app). */
export const PREMIUM_ENTITLEMENT = "kadans_pro";

/** "Voor altijd" voor lifetime-aankopen. */
export const LIFETIME_END = new Date("2999-12-31T00:00:00Z");

export type Plan = "monthly" | "yearly" | "lifetime";
export type Status = "active" | "trialing" | "expired" | "cancelled";

export interface RcEvent {
  type: string;
  product_id?: string | null;
  entitlement_ids?: string[] | null;
  expiration_at_ms?: number | null;
  period_type?: string | null;
}

export interface Existing {
  plan: Plan;
  status: Status;
  current_period_end: string;
}

export type Decision =
  | { kind: "ignore"; reason: string }
  | { kind: "upsert"; plan: Plan; status: Status; periodEnd: Date };

export function planFor(productId: string): Plan {
  if (/lifetime|levenslang|forever/i.test(productId)) return "lifetime";
  if (/year|jaar|annual/i.test(productId)) return "yearly";
  return "monthly";
}

/** Gaat dit event over Premium? (Niet over bijv. de losse Luxe-ontwerpen.) */
export function isPremiumEvent(e: RcEvent): boolean {
  const ids = e.entitlement_ids;
  if (Array.isArray(ids) && ids.length > 0) return ids.includes(PREMIUM_ENTITLEMENT);
  // Oudere events zonder entitlement_ids: abonnementen waren altijd Premium.
  const pid = String(e.product_id ?? "");
  return e.type !== "NON_RENEWING_PURCHASE" || planFor(pid) === "lifetime";
}

function isActive(x: Existing | null, now: Date): boolean {
  return !!x && (x.status === "active" || x.status === "trialing") && new Date(x.current_period_end) > now;
}

export function decide(e: RcEvent, existing: Existing | null, now = new Date()): Decision {
  if (!isPremiumEvent(e)) return { kind: "ignore", reason: "not premium" };

  const plan = planFor(String(e.product_id ?? ""));
  const lifetime = plan === "lifetime";
  const trial = e.period_type === "TRIAL";

  // Lifetime gaat voor: een aflopend of opgezegd maand-/jaarabonnement mag hem niet wegzetten.
  if (!lifetime && existing?.plan === "lifetime" && isActive(existing, now)) {
    return { kind: "ignore", reason: "lifetime active" };
  }

  const periodEnd = lifetime ? LIFETIME_END : e.expiration_at_ms ? new Date(e.expiration_at_ms) : now;
  const stillRunning = periodEnd.getTime() > now.getTime();

  let status: Status;
  switch (e.type) {
    case "INITIAL_PURCHASE":
    case "NON_RENEWING_PURCHASE":
    case "RENEWAL":
    case "PRODUCT_CHANGE":
    case "UNCANCELLATION":
    case "SUBSCRIPTION_EXTENDED":
    case "TEMPORARY_ENTITLEMENT_GRANT":
    case "TRANSFER":
      status = trial ? "trialing" : "active";
      break;
    case "CANCELLATION":
      // Lifetime: alleen bij terugbetaling. Abonnement: verlengen staat uit, betaalde periode loopt door.
      if (lifetime) return { kind: "upsert", plan, status: "cancelled", periodEnd: now };
      status = stillRunning ? (trial ? "trialing" : "active") : "cancelled";
      break;
    case "BILLING_ISSUE":
      // Google geeft een respijtperiode; zolang die loopt houdt de gebruiker toegang.
      status = stillRunning ? "active" : "expired";
      break;
    case "EXPIRATION":
      status = "expired";
      break;
    default:
      return { kind: "ignore", reason: e.type };
  }
  return { kind: "upsert", plan, status, periodEnd };
}
