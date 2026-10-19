// Edge Function: coach
// AI-hardloopcoach. Alleen voor premium (met een paar gratis proefvragen).
//
//   POST { message: "..." }  -> { reply, premium, free_left }
//
// Geheimen (Supabase -> Edge Functions -> Secrets):
//   ANTHROPIC_API_KEY   verplicht
//   COACH_MODEL         optioneel, standaard claude-haiku-5-5
//
// Strava-runs gaan bewust NIET mee naar de AI (Strava-voorwaarden over AI).

import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const MAX_MESSAGE_CHARS = 1500;
const HISTORY_MESSAGES = 16;
const RUNS_WEEKS = 8;

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

const env = (k: string) => Deno.env.get(k) ?? "";

const SYSTEM_PROMPT = `Je bent de RunWise Coach: een ervaren, nuchtere hardlooptrainer in de RunWise-app.

Taal en stijl
- Antwoord in het Nederlands, kort en concreet. Gebruik lijstjes en stappen waar dat helpt.
- Spreek de loper aan met "je". Wees eerlijk: als een plan niet verstandig is, zeg dat direct en leg kort uit waarom.
- Gebruik de gegevens van de loper hieronder. Verzin geen runs, tijden of weer die er niet staan. Ontbreekt iets, vraag ernaar of zeg wat je aanneemt.

Waar je mee helpt
- Trainingsweken en schema's, tempo's (rustig, tempo, interval, lange duurloop), opbouw van omvang, taperen voor wedstrijden.
- Wedstrijdstrategie, pacing, kleding en drinken bij het verwachte weer.
- Herstel, slaap en algemene voeding rond het hardlopen.

Veiligheid
- Je bent geen arts of fysiotherapeut. Bij pijn, blessures, duizeligheid, pijn op de borst, hartklachten of andere gezondheidsklachten: geef geen diagnose of behandeling, maar raad aan om te stoppen met trainen en een huisarts of (sport)fysiotherapeut te raadplegen. Bij acute klachten: 112.
- Geef geen extreme of gevaarlijke adviezen (crashdiëten, uitdrogen om gewicht te verliezen, middelen, trainen met koorts).
- Bouw omvang geleidelijk op (vuistregel: niet meer dan ongeveer 10% per week).
- Vragen die niets met hardlopen, sport of gezondheid rond het lopen te maken hebben: zeg vriendelijk dat je daar niet voor bent.`;

function fmtPace(secPerKm: number) {
  const m = Math.floor(secPerKm / 60);
  const s = Math.round(secPerKm % 60);
  return `${m}:${String(s).padStart(2, "0")}/km`;
}

function fmtDuration(sec: number) {
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}` : `${m}:${String(s).padStart(2, "0")}`;
}

function amsterdamDate(d: Date) {
  return d.toLocaleString("nl-NL", {
    timeZone: "Europe/Amsterdam",
    weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit",
  });
}

/** Maakt een korte samenvatting van de loper voor de AI. */
async function buildContext(db: SupabaseClient, userId: string, profile: Record<string, unknown>) {
  const since = new Date(Date.now() - RUNS_WEEKS * 7 * 86_400_000).toISOString();
  const [{ data: runs }, { data: races }, { data: perf }] = await Promise.all([
    db.from("activities")
      .select("started_at, distance_meters, moving_time_seconds, average_heart_rate, elevation_gain_meters, temperature_celsius, wind_speed_kmh, feel, note")
      .eq("user_id", userId).neq("source", "strava").gte("started_at", since)
      .order("started_at", { ascending: false }).limit(60),
    db.from("race_events")
      .select("name, race_date, distance_meters, goal_time_seconds, predicted_finish_seconds")
      .eq("user_id", userId).gte("race_date", new Date().toISOString().slice(0, 10))
      .order("race_date").limit(5),
    db.from("performance_profile").select("*").eq("user_id", userId).maybeSingle(),
  ]);

  const lines: string[] = [];
  lines.push(`Vandaag: ${amsterdamDate(new Date())}`);
  const name = (profile.first_name as string) || (profile.full_name as string) || null;
  if (name) lines.push(`Naam: ${name}`);

  // Weekoverzicht
  const list = runs ?? [];
  if (list.length === 0) {
    lines.push(`Runs laatste ${RUNS_WEEKS} weken: geen gelogd.`);
  } else {
    const weeks = new Map<number, { km: number; n: number; longest: number }>();
    for (const r of list) {
      const w = Math.floor((Date.now() - new Date(r.started_at).getTime()) / (7 * 86_400_000));
      const km = Number(r.distance_meters) / 1000;
      const cur = weeks.get(w) ?? { km: 0, n: 0, longest: 0 };
      weeks.set(w, { km: cur.km + km, n: cur.n + 1, longest: Math.max(cur.longest, km) });
    }
    lines.push(`Weekomvang (week 0 = afgelopen 7 dagen):`);
    for (let w = 0; w < RUNS_WEEKS; w++) {
      const x = weeks.get(w);
      lines.push(`- week ${w}: ${x ? `${x.km.toFixed(1)} km in ${x.n} runs, langste ${x.longest.toFixed(1)} km` : "geen runs"}`);
    }
    lines.push(`Laatste runs:`);
    for (const r of list.slice(0, 12)) {
      const km = Number(r.distance_meters) / 1000;
      const pace = Number(r.moving_time_seconds) / km;
      const extra = [
        r.average_heart_rate ? `hartslag ${r.average_heart_rate}` : null,
        r.elevation_gain_meters ? `${Math.round(Number(r.elevation_gain_meters))} hm` : null,
        r.temperature_celsius != null ? `${Math.round(Number(r.temperature_celsius))}°C` : null,
        r.wind_speed_kmh != null ? `wind ${Math.round(Number(r.wind_speed_kmh))} km/u` : null,
        r.feel ? `voelde ${["", "zwaar", "oké", "top"][Number(r.feel)] ?? ""}` : null,
        r.note ? `notitie: "${String(r.note).slice(0, 200).replace(/\s+/g, " ")}"` : null,
      ].filter(Boolean).join(", ");
      lines.push(`- ${amsterdamDate(new Date(r.started_at))}: ${km.toFixed(2)} km in ${fmtDuration(Number(r.moving_time_seconds))} (${fmtPace(pace)})${extra ? `, ${extra}` : ""}`);
    }
  }

  if (perf && (perf.sample_size ?? 0) >= 8) {
    lines.push(`Loopprofiel (${perf.sample_size} runs): snelst tussen ${perf.optimal_temp_min_celsius}–${perf.optimal_temp_max_celsius}°C` +
      (perf.preferred_time_of_day ? `, voorkeur ${perf.preferred_time_of_day}` : ""));
  }

  if ((races ?? []).length > 0) {
    lines.push(`Geplande wedstrijden:`);
    for (const r of races!) {
      const pred = r.predicted_finish_seconds ? `, verwacht ${fmtDuration(r.predicted_finish_seconds)}` : "";
      lines.push(`- ${r.race_date}: ${r.name}, ${(Number(r.distance_meters) / 1000).toFixed(1)} km, doel ${fmtDuration(r.goal_time_seconds)}${pred}`);
    }
  } else {
    lines.push(`Geplande wedstrijden: geen.`);
  }

  // Weer komende 3 dagen (Open-Meteo, gratis)
  const lat = (profile.home_latitude as number) ?? 52.1404;
  const lon = (profile.home_longitude as number) ?? 5.5847;
  try {
    const res = await fetch(
      `https://api.open-meteo.com/v1/forecast?latitude=${lat.toFixed(2)}&longitude=${lon.toFixed(2)}` +
        `&daily=temperature_2m_min,temperature_2m_max,precipitation_sum,wind_speed_10m_max&timezone=Europe%2FAmsterdam&forecast_days=3`,
      { signal: AbortSignal.timeout(6000) },
    );
    if (res.ok) {
      const d = (await res.json()).daily;
      lines.push(`Weer komende dagen:`);
      for (let i = 0; i < (d?.time?.length ?? 0); i++) {
        lines.push(`- ${d.time[i]}: ${Math.round(d.temperature_2m_min[i])}–${Math.round(d.temperature_2m_max[i])}°C, ${d.precipitation_sum[i]} mm regen, wind max ${Math.round(d.wind_speed_10m_max[i])} km/u`);
      }
    }
  } catch {
    // Weer is een extraatje; zonder gaat het ook.
  }

  return lines.join("\n");
}

async function isPremium(db: SupabaseClient, userId: string) {
  const { data } = await db.from("subscriptions").select("status, current_period_end")
    .eq("user_id", userId);
  return (data ?? []).some((s) =>
    (s.status === "active" || s.status === "trialing" || s.status === "cancelled") &&
    new Date(s.current_period_end).getTime() > Date.now()
  );
}

async function config(db: SupabaseClient) {
  const { data } = await db.from("model_config").select("key, value")
    .in("key", ["coach_free_questions", "coach_premium_daily_limit"]);
  const m = new Map((data ?? []).map((r) => [r.key, Number(r.value)]));
  return {
    free: m.get("coach_free_questions") ?? 3,
    daily: m.get("coach_premium_daily_limit") ?? 30,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Alleen POST is toegestaan." });

  const apiKey = env("ANTHROPIC_API_KEY");
  if (!apiKey) return json(503, { error: "De coach is nog niet ingesteld op de server." });

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json(401, { error: "Niet ingelogd." });

  const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY") || env("SUPABASE_SECRET_KEY"), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: auth, error: authErr } = await db.auth.getUser(jwt);
  if (authErr || !auth?.user) return json(401, { error: "Sessie ongeldig. Log opnieuw in." });
  const userId = auth.user.id;

  const body = await req.json().catch(() => ({}));
  const message = String(body.message ?? "").trim();
  if (!message) return json(400, { error: "Typ eerst een vraag." });
  if (message.length > MAX_MESSAGE_CHARS) {
    return json(400, { error: `Je vraag is te lang (maximaal ${MAX_MESSAGE_CHARS} tekens).` });
  }

  const { data: profile } = await db.from("profiles").select("*").eq("id", userId).single();
  if (!profile) return json(404, { error: "Profiel niet gevonden." });

  const premium = await isPremium(db, userId);
  const limits = await config(db);
  const freeUsed = Number(profile.coach_free_questions_used ?? 0);

  if (!premium) {
    if (freeUsed >= limits.free) {
      return json(402, { error: "Je gratis vragen zijn op. Start je gratis proefmaand voor onbeperkt coachen.", paywall: true, free_left: 0 });
    }
  } else {
    const startOfDay = new Date();
    startOfDay.setUTCHours(0, 0, 0, 0);
    const { count } = await db.from("coach_messages").select("id", { count: "exact", head: true })
      .eq("user_id", userId).eq("role", "user").gte("created_at", startOfDay.toISOString());
    if ((count ?? 0) >= limits.daily) {
      return json(429, { error: `Je hebt vandaag al ${limits.daily} vragen gesteld. Morgen kun je weer verder.` });
    }
  }

  // Eerdere berichten zodat de coach het gesprek kent.
  const { data: history } = await db.from("coach_messages").select("role, content")
    .eq("user_id", userId).order("created_at", { ascending: false }).limit(HISTORY_MESSAGES);
  const past = (history ?? []).reverse();
  // De API wil afwisselend user/assistant, beginnend met user.
  while (past.length && past[0].role !== "user") past.shift();
  const messages: { role: string; content: string }[] = [];
  for (const m of past) {
    if (messages.length && messages[messages.length - 1].role === m.role) {
      messages[messages.length - 1].content += `\n\n${m.content}`;
    } else {
      messages.push({ role: m.role, content: m.content });
    }
  }
  if (messages.length && messages[messages.length - 1].role === "user") messages.pop();
  messages.push({ role: "user", content: message });

  const context = await buildContext(db, userId, profile);

  const ai = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: env("COACH_MODEL") || "claude-haiku-5-5",
      max_tokens: 900,
      system: `${SYSTEM_PROMPT}\n\nGegevens van de loper (uit RunWise):\n${context}`,
      messages,
    }),
    signal: AbortSignal.timeout(60_000),
  }).catch((e) => {
    console.error("anthropic fetch failed", e?.message ?? e);
    return null;
  });

  if (!ai || !ai.ok) {
    console.error("anthropic error", ai?.status, ai ? await ai.text() : "");
    return json(502, { error: "De coach is even niet bereikbaar. Probeer het zo opnieuw." });
  }
  const result = await ai.json();
  const reply = ((result.content ?? []) as { type: string; text?: string }[])
    .filter((c) => c.type === "text").map((c) => c.text).join("\n").trim();
  if (!reply) return json(502, { error: "De coach gaf geen antwoord. Probeer het opnieuw." });

  const now = Date.now();
  const { error: insErr } = await db.from("coach_messages").insert([
    { user_id: userId, role: "user", content: message, created_at: new Date(now).toISOString() },
    { user_id: userId, role: "assistant", content: reply.slice(0, 8000), created_at: new Date(now + 1).toISOString() },
  ]);
  if (insErr) console.error("coach_messages insert failed", insErr.message);

  let freeLeft: number | null = null;
  if (!premium) {
    await db.from("profiles").update({ coach_free_questions_used: freeUsed + 1 }).eq("id", userId);
    freeLeft = Math.max(0, limits.free - freeUsed - 1);
  }

  return json(200, { reply, premium, free_left: freeLeft });
});
