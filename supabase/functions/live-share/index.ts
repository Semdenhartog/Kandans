// Edge Function: live-share
// Publiek leesadres voor "live locatie delen". De kijker heeft alleen het geheime
// token uit de link; zonder token is niets op te vragen.
//
//   GET ?t=<token>  ->  { name, active, started_at, expires_at, ended_at, last, trail }
//
// Schrijven doet de app zelf (met Row Level Security). Deze functie leest alleen.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "GET") return json(405, { error: "Alleen GET is toegestaan." });

  const token = new URL(req.url).searchParams.get("t") ?? "";
  if (!/^[A-Za-z0-9]{24,64}$/.test(token)) return json(404, { error: "Deze link bestaat niet (meer)." });

  const { data: share, error } = await db
    .from("live_shares")
    .select("id, display_name, started_at, expires_at, ended_at, last_lat, last_lon, last_accuracy, last_at")
    .eq("token", token)
    .maybeSingle();
  if (error) {
    console.error("live-share read failed", error.message);
    return json(500, { error: "Even niet bereikbaar. Probeer het zo opnieuw." });
  }
  if (!share) return json(404, { error: "Deze link bestaat niet (meer)." });

  const now = Date.now();
  const ended = share.ended_at ? Date.parse(share.ended_at) : null;
  const expired = Date.parse(share.expires_at) < now;
  // Na afloop nog 2 uur laten zien dát de run voorbij is, daarna niets meer.
  const lastMoment = ended ?? Date.parse(share.expires_at);
  if (now - lastMoment > 2 * 3600_000) return json(404, { error: "Deze link is verlopen." });

  const active = !ended && !expired;
  let trail: number[][] = [];
  if (active) {
    const { data: pts } = await db
      .from("live_share_points")
      .select("lat, lon, recorded_at")
      .eq("share_id", share.id)
      .order("recorded_at", { ascending: true })
      .limit(1500);
    trail = (pts ?? []).map((p) => [p.lat, p.lon, Date.parse(p.recorded_at)]);
  }

  return json(200, {
    name: share.display_name ?? "Een RunWise-loper",
    active,
    started_at: share.started_at,
    expires_at: share.expires_at,
    ended_at: share.ended_at,
    last: active && share.last_lat != null
      ? { lat: share.last_lat, lon: share.last_lon, accuracy: share.last_accuracy, at: share.last_at }
      : null,
    trail,
  });
});
