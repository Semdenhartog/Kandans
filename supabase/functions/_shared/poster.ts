// Gedeelde, losse onderdelen voor posterbestellingen (zonder netwerk, zodat ze te testen zijn).

const COUNTRIES = new Set(["NL", "BE", "DE", "LU"]);

export type Shipping = {
  name: string;
  street: string;
  house_number: string;
  postcode: string;
  city: string;
  country: string;
  email: string;
};

/** Controleert en schoont het adres. Geeft een foutmelding (tekst) of het adres terug. */
export function cleanShipping(raw: unknown): Shipping | string {
  if (typeof raw !== "object" || raw === null) return "Vul je adres in.";
  const r = raw as Record<string, unknown>;
  const s = (k: string, max: number) => String(r[k] ?? "").trim().slice(0, max);
  const out: Shipping = {
    name: s("name", 80),
    street: s("street", 80),
    house_number: s("house_number", 12),
    postcode: s("postcode", 10).toUpperCase(),
    city: s("city", 60),
    country: s("country", 2).toUpperCase(),
    email: s("email", 120).toLowerCase(),
  };
  if (out.name.split(/\s+/).length < 2) return "Vul je voor- en achternaam in.";
  if (!out.street || !out.house_number || !out.city) return "Vul straat, huisnummer en plaats in.";
  if (!COUNTRIES.has(out.country)) return "We versturen alleen naar Nederland, België, Duitsland en Luxemburg.";
  if (out.country === "NL" && !/^[1-9][0-9]{3} ?[A-Z]{2}$/.test(out.postcode)) return "Deze postcode klopt niet (bijv. 3771 AB).";
  if (out.country !== "NL" && !/^[0-9A-Z -]{4,8}$/.test(out.postcode)) return "Deze postcode klopt niet.";
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(out.email)) return "Dit e-mailadres klopt niet.";
  return out;
}


function hex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Controleert de Stripe-Signature (HMAC-SHA256 over "<t>.<body>"), met 5 minuten speling. */
export async function validStripeSignature(payload: string, header: string, secret: string, nowSec = Date.now() / 1000): Promise<boolean> {
  const parts = Object.fromEntries(header.split(",").map((p) => p.split("=", 2) as [string, string]));
  const t = Number(parts["t"]);
  const signatures = header.split(",").filter((p) => p.startsWith("v1=")).map((p) => p.slice(3));
  if (!t || signatures.length === 0 || Math.abs(nowSec - t) > 300) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const expected = hex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${t}.${payload}`)));
  // Vergelijken zonder vroeg te stoppen (geen timing-lek).
  return signatures.some((s) => {
    if (s.length !== expected.length) return false;
    let diff = 0;
    for (let i = 0; i < s.length; i++) diff |= s.charCodeAt(i) ^ expected.charCodeAt(i);
    return diff === 0;
  });
}

