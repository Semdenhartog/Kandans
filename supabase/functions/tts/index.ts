// Edge Function: tts
// TESTFASE: zet een gesproken coachzin om in een ElevenLabs-stem (mp3). De app valt terug op de
// telefoonstem als dit niet lukt (geen sleutel, credits op, geen internet).
//
//   POST { text: "Kilometer drie. Tempo vijf minuut twaalf." }  -> audio (application/octet-stream, mp3)
//
// Geheimen (Supabase -> Edge Functions -> Secrets), door Sem zelf in te stellen:
//   ELEVENLABS_API_KEY    verplicht (zonder sleutel: 503 en de app gebruikt de telefoonstem)
//   ELEVENLABS_VOICE_ID   optioneel, standaard "Berend" (pb6qe8wKy786fK6M05tq)
//   ELEVENLABS_MODEL      optioneel, standaard eleven_flash_v2_5 (snel en zuinig)
//
// LET OP: het gratis ElevenLabs-plan is niet voor commercieel gebruik. Alleen voor testen;
// vóór de lancering een betaald plan of een andere stem.

import { createClient } from "jsr:@supabase/supabase-js@2";

const MAX_CHARS = 400;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const env = (k: string) => Deno.env.get(k) ?? "";

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Alleen POST is toegestaan." });

  const apiKey = env("ELEVENLABS_API_KEY");
  if (!apiKey) return json(503, { error: "De Kadans-stem is nog niet ingesteld." });

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json(401, { error: "Niet ingelogd." });
  const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY") || env("SUPABASE_SECRET_KEY"), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: auth, error: authErr } = await db.auth.getUser(jwt);
  if (authErr || !auth?.user) return json(401, { error: "Sessie ongeldig." });

  const body = await req.json().catch(() => ({}));
  const text = String(body.text ?? "").replace(/\s+/g, " ").trim();
  if (!text) return json(400, { error: "Geen tekst." });
  if (text.length > MAX_CHARS) return json(400, { error: "Tekst te lang." });

  const voice = env("ELEVENLABS_VOICE_ID") || "pb6qe8wKy786fK6M05tq";
  const model = env("ELEVENLABS_MODEL") || "eleven_flash_v2_5";
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voice)}?output_format=mp3_44100_64`, {
    method: "POST",
    headers: { "xi-api-key": apiKey, "Content-Type": "application/json", Accept: "audio/mpeg" },
    body: JSON.stringify({
      text,
      model_id: model,
      language_code: "nl",
      voice_settings: { stability: 0.55, similarity_boost: 0.75, speed: 1.0 },
    }),
  });
  if (!res.ok) {
    // Bijv. credits op (401/402/429): de app gebruikt dan de telefoonstem.
    const detail = (await res.text().catch(() => "")).slice(0, 200);
    console.error("elevenlabs", res.status, detail);
    return json(502, { error: "De Kadans-stem is even niet beschikbaar.", status: res.status });
  }
  const audio = new Uint8Array(await res.arrayBuffer());
  return new Response(audio, {
    status: 200,
    headers: { ...cors, "Content-Type": "application/octet-stream", "Cache-Control": "no-store" },
  });
});
