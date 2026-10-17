// Edge Function: delete-account
// Verwijdert het account van de ingelogde gebruiker definitief (AVG: recht op vergetelheid).
// Alle eigen data (profiel, runs, routes, wedstrijden) verdwijnt via "on delete cascade".
//
// Deze functie gebruikt de service-role key. Die staat automatisch als geheime
// omgevingsvariabele klaar in Supabase Edge Functions en komt NOOIT in de app.

import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Alleen POST is toegestaan." });

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return json(401, { error: "Niet ingelogd." });

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY");
  if (!url || !serviceKey) return json(500, { error: "Server is niet goed ingesteld." });

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Controleer wie de aanvraag doet aan de hand van zijn eigen inlogtoken.
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data?.user) return json(401, { error: "Sessie ongeldig. Log opnieuw in." });

  const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id);
  if (deleteError) {
    console.error("delete-account failed", deleteError.message);
    return json(500, { error: "Verwijderen is mislukt." });
  }
  return json(200, { deleted: true });
});
