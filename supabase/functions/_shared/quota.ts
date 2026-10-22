// Daglimiet per gebruiker voor functies die betaalde of gelimiteerde API's gebruiken.
// Werkt "fail-open": staat de teller (migratie 0027) nog niet in de database, of is de
// service-key er niet, dan gaat de aanvraag gewoon door. Zo breekt er niets.

import { createClient } from "jsr:@supabase/supabase-js@2";

export type QuotaResult = { ok: true } | { ok: false; status: number; error: string };

export async function checkQuota(req: Request, fn: string, maxPerDay: number): Promise<QuotaResult> {
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY");
  if (!url || !serviceKey) return { ok: true };
  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data, error } = await admin.auth.getUser(jwt);
  if (error || !data?.user) return { ok: false, status: 401, error: "Log opnieuw in om dit te gebruiken." };
  try {
    const { data: allowed, error: rpcError } = await admin.rpc("bump_function_usage", {
      p_user: data.user.id,
      p_fn: fn,
      p_max: maxPerDay,
    });
    if (rpcError) return { ok: true }; // Migratie nog niet uitgevoerd.
    if (allowed === false) {
      return { ok: false, status: 429, error: "Je hebt het maximum voor vandaag bereikt. Morgen kan het weer." };
    }
  } catch (_) {
    // Teller niet bereikbaar: niet blokkeren.
  }
  return { ok: true };
}
