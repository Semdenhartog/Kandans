// Edge Function: tts
// Zet een gesproken coachzin om in een natuurlijke Nederlandse stem (mp3). De app bewaart elke zin op het toestel
// en valt terug op de telefoonstem als dit niet lukt (geen sleutel, limiet op, geen internet).
//
//   POST { text: "Kilometer drie. Tempo vijf minuut twaalf.", voice: "emma" }  -> audio (application/octet-stream, mp3)
//
// Stemmen: Google Cloud Text-to-Speech, Chirp 3 HD (nl-NL). Eerste 1 miljoen tekens per maand gratis.
// `voice` is een sleutel uit VOICES (geen vrije stemnaam). Lukt de gekozen stem niet, dan een andere van hetzelfde
// geslacht; nooit ineens een man i.p.v. een vrouw.
//
// Geheimen (Supabase -> Edge Functions -> Secrets), door Sem zelf in te stellen:
//   GOOGLE_TTS_KEY        API-sleutel van Google Cloud (alleen "Cloud Text-to-Speech API" toestaan)
//   ELEVENLABS_API_KEY    optioneel, reserve als er (nog) geen Google-sleutel is (gratis plan: alleen eigen stemmen)

import { createClient } from "jsr:@supabase/supabase-js@2";

const MAX_CHARS = 400;

type Voice = { google: string; gender: "m" | "v"; eleven: string };

// Sleutels moeten gelijk zijn aan `KadansVoiceOption.key` in de app.
const VOICES: Record<string, Voice> = {
  daan: { google: "nl-NL-Chirp3-HD-Charon", gender: "m", eleven: "YxbOqEAPD1TsKmU3TFJz" },
  bram: { google: "nl-NL-Chirp3-HD-Puck", gender: "m", eleven: "XWw6BayktH5jsnELw9Bc" },
  emma: { google: "nl-NL-Chirp3-HD-Kore", gender: "v", eleven: "8B6lPskx1bcErhNkFdqo" },
  fleur: { google: "nl-NL-Chirp3-HD-Aoede", gender: "v", eleven: "7qdUFMklKPaaAVMsBTBt" },
};

// Oude sleutels uit eerdere versies van de app (zelfde geslacht).
const ALIASES: Record<string, string> = { berend: "daan", jamie: "daan", marvin: "bram", sanne: "emma", anna: "emma", roos: "fleur" };

/** Gekozen stem, dan de andere van hetzelfde geslacht. */
function voiceChain(key: string): Voice[] {
  const chosen = VOICES[ALIASES[key] ?? key] ?? VOICES.daan;
  return [chosen, ...Object.values(VOICES).filter((v) => v.gender === chosen.gender && v !== chosen)];
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

type Result = { audio: Uint8Array } | { status: number; detail: string; stop: boolean };

async function google(key: string, voice: Voice, text: string): Promise<Result> {
  const res = await fetch(`https://texttospeech.googleapis.com/v1/text:synthesize?key=${encodeURIComponent(key)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      input: { text },
      voice: { languageCode: "nl-NL", name: voice.google },
      audioConfig: { audioEncoding: "MP3", sampleRateHertz: 24000 },
    }),
    signal: AbortSignal.timeout(9_000),
  });
  if (!res.ok) {
    const detail = (await res.text().catch(() => "")).slice(0, 300);
    // Sleutel fout, API uit of limiet op: een andere stem helpt niet.
    return { status: res.status, detail, stop: res.status === 401 || res.status === 403 || res.status === 429 };
  }
  const data = await res.json().catch(() => ({}));
  const b64 = String(data.audioContent ?? "");
  if (!b64) return { status: 502, detail: "geen audioContent", stop: false };
  return { audio: Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)) };
}

async function eleven(key: string, voice: Voice, text: string): Promise<Result> {
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice.eleven}?output_format=mp3_44100_64`, {
    method: "POST",
    headers: { "xi-api-key": key, "Content-Type": "application/json", Accept: "audio/mpeg" },
    body: JSON.stringify({
      text,
      model_id: env("ELEVENLABS_MODEL") || "eleven_flash_v2_5",
      language_code: "nl",
      voice_settings: { stability: 0.55, similarity_boost: 0.75, speed: 1.0 },
    }),
    signal: AbortSignal.timeout(9_000),
  });
  if (!res.ok) {
    const detail = (await res.text().catch(() => "")).slice(0, 300);
    return { status: res.status, detail, stop: [401, 402, 429].includes(res.status) || /quota|credits|paid_plan/i.test(detail) };
  }
  return { audio: new Uint8Array(await res.arrayBuffer()) };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Alleen POST is toegestaan." });

  const googleKey = env("GOOGLE_TTS_KEY");
  const elevenKey = env("ELEVENLABS_API_KEY");
  if (!googleKey && !elevenKey) return json(503, { error: "De Kadans-stem is nog niet ingesteld." });

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

  const provider = googleKey ? "google" : "elevenlabs";
  let last: { status: number; detail: string } = { status: 0, detail: "" };
  for (const voice of voiceChain(String(body.voice ?? "").toLowerCase())) {
    let r: Result;
    try {
      r = provider === "google" ? await google(googleKey, voice, text) : await eleven(elevenKey, voice, text);
    } catch (e) {
      r = { status: 504, detail: e instanceof Error ? e.message : "fout", stop: false };
    }
    if ("audio" in r) {
      return new Response(r.audio, {
        status: 200,
        headers: { ...cors, "Content-Type": "application/octet-stream", "Cache-Control": "no-store" },
      });
    }
    last = r;
    console.error(provider, provider === "google" ? voice.google : voice.eleven, r.status, r.detail);
    if (r.stop) break;
  }

  let reason = "unknown";
  if (last.status === 402 || /paid_plan/i.test(last.detail)) reason = "plan";
  else if (last.status === 403 && /SERVICE_DISABLED|has not been used|disabled/i.test(last.detail)) reason = "api_off";
  else if (last.status === 403 && /billing/i.test(last.detail)) reason = "billing";
  else if (last.status === 401 && /missing_permissions|permission/i.test(last.detail)) reason = "permissions";
  else if (last.status === 401 || last.status === 403 || /API key not valid|API_KEY_INVALID/i.test(last.detail)) reason = "key";
  else if (last.status === 429 || /quota|credits|RESOURCE_EXHAUSTED/i.test(last.detail)) reason = "quota";
  else if (/voice/i.test(last.detail)) reason = "voice";
  return json(502, { error: "De Kadans-stem is even niet beschikbaar.", status: last.status, reason, provider });
});
