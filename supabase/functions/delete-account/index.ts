// Edge Function: delete-account
// Verwijdert het account van de ingelogde gebruiker definitief (AVG: recht op vergetelheid).
// Alle eigen data (profiel, runs, routes, wedstrijden) verdwijnt via "on delete cascade"; foto's bij runs
// worden eerst uit de opslag gewist.
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

  // Strava-koppeling intrekken (als die er is), zodat RunWise daar geen toegang meer heeft.
  try {
    const { data: tokens } = await admin.rpc("strava_get_tokens", { p_user: data.user.id });
    const access = (tokens as { access_token: string }[] | null)?.[0]?.access_token;
    if (access) {
      await fetch("https://www.strava.com/oauth/deauthorize", {
        method: "POST",
        headers: { Authorization: `Bearer ${access}` },
      });
    }
  } catch (_) {
    // Niet fataal: de tokens verdwijnen hoe dan ook met het account.
  }

  // Foto's bij runs verwijderen (map <user_id>/<activity_id>/...).
  try {
    const bucket = admin.storage.from("run-photos");
    const uid = data.user.id;
    const { data: folders } = await bucket.list(uid, { limit: 1000 });
    const paths: string[] = [];
    for (const f of folders ?? []) {
      const { data: files } = await bucket.list(`${uid}/${f.name}`, { limit: 1000 });
      for (const file of files ?? []) paths.push(`${uid}/${f.name}/${file.name}`);
    }
    for (let i = 0; i < paths.length; i += 100) {
      await bucket.remove(paths.slice(i, i + 100));
    }
  } catch (e) {
    console.error("delete-account photos", e instanceof Error ? e.message : e);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id);
  if (deleteError) {
    console.error("delete-account failed", deleteError.message);
    return json(500, { error: "Verwijderen is mislukt." });
  }
  return json(200, { deleted: true });
});
