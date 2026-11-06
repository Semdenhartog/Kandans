// Edge Function: tts
// TESTFASE: zet een gesproken coachzin om in een ElevenLabs-stem (mp3). De app valt terug op de
// telefoonstem als dit niet lukt (geen sleutel, credits op, geen internet).
//
//   POST { text: "Kilometer drie. Tempo vijf minuut twaalf.", voice: "roos" }  -> audio (application/octet-stream, mp3)
//
// `voice` is een sleutel uit VOICES (geen vrije stem-id, zodat niemand andere stemmen op ons account gebruikt).
// Lukt de gekozen stem niet, dan een andere stem van hetzelfde geslacht; nooit ineens een man i.p.v. een vrouw.
//
// Geheimen (Supabase -> Edge Functions -> Secrets), door Sem zelf in te stellen:
//   ELEVENLABS_API_KEY    verplicht (zonder sleutel: 503 en de app gebruikt de telefoonstem)
//   ELEVENLABS_MODEL      optioneel, standaard eleven_flash_v2_5 (snel en zuinig)
//
// LET OP: het gratis ElevenLabs-plan is niet voor commercieel gebruik. Alleen voor testen;
// vóór de lancering een betaald plan of een andere stem.

import { createClient } from "jsr:@supabase/supabase-js@2";

const MAX_CHARS = 400;

// Vaste Nederlandse stemmen (ElevenLabs). Sleutels moeten gelijk zijn aan `KadansVoiceOption.key` in de app.
// Bibliotheekstemmen werken op het gratis plan alleen als ze in "My Voices" van het account staan.
const VOICES: Record<string, { id: string; gender: "m" | "v" }> = {
  jamie: { id: "YxbOqEAPD1TsKmU3TFJz", gender: "m" },
  marvin: { id: "XWw6BayktH5jsnELw9Bc", gender: "m" },
  roos: { id: "7qdUFMklKPaaAVMsBTBt", gender: "v" },
  anna: { id: "8B6lPskx1bcErhNkFdqo", gender: "v" },
};

/// Volgorde om te proberen: gekozen stem, dan de andere(n) van hetzelfde geslacht.
// Oude sleutels uit eerdere versies van de app.
const ALIASES: Record<string, string> = { berend: "jamie", sanne: "anna" };

function voiceChain(key: string): string[] {
  const chosen = VOICES[ALIASES[key] ?? key];
  if (!chosen) return [VOICES.jamie.id, VOICES.marvin.id]; // onbekende sleutel: Jamie
  const same = Object.values(VOICES).filter((v) => v.gender === chosen.gender && v.id !== chosen.id).map((v) => v.id);
  return [chosen.id, ...same];
}

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

  // Eerst de gekozen stem; lukt die niet (bijv. bibliotheekstem niet in het account op het gratis plan),
  // dan een andere Nederlandse stem van hetzelfde geslacht. Geen Engelse noodstem meer.
  const voices = voiceChain(String(body.voice ?? "").toLowerCase());
  const model = env("ELEVENLABS_MODEL") || "eleven_flash_v2_5";
  let res: Response | null = null;
  let lastStatus = 0;
  let lastDetail = "";
  for (const voice of [...new Set(voices)]) {
    res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voice)}?output_format=mp3_44100_64`, {
      method: "POST",
      headers: { "xi-api-key": apiKey, "Content-Type": "application/json", Accept: "audio/mpeg" },
      body: JSON.stringify({
        text,
        model_id: model,
        language_code: "nl",
        voice_settings: { stability: 0.55, similarity_boost: 0.75, speed: 1.0 },
      }),
    });
    if (res.ok) break;
    lastStatus = res.status;
    lastDetail = (await res.text().catch(() => "")).slice(0, 300);
    console.error("elevenlabs", voice, res.status, lastDetail);
    // Sleutel ongeldig of credits op: een andere stem helpt niet.
    if (res.status === 401 || res.status === 429 || /quota|credits/i.test(lastDetail)) break;
    res = null;
  }
  if (!res || !res.ok) {
    let reason = "unknown";
    if (lastStatus === 401 && /missing_permissions|permission/i.test(lastDetail)) reason = "permissions";
    else if (lastStatus === 401) reason = "key";
    else if (lastStatus === 429 || /quota|credits/i.test(lastDetail)) reason = "quota";
    else if (/voice/i.test(lastDetail)) reason = "voice";
    return json(502, { error: "De Kadans-stem is even niet beschikbaar.", status: lastStatus, reason });
  }
  const audio = new Uint8Array(await res.arrayBuffer());
  return new Response(audio, {
    status: 200,
    headers: { ...cors, "Content-Type": "application/octet-stream", "Cache-Control": "no-store" },
  });
});
