// Edge Function: strava
// Koppelt een RunWise-account aan Strava en haalt de runs op.
//
//   POST  { action: "connect" }     -> geeft de Strava-inloglink terug
//   GET   /strava/callback          -> Strava stuurt de gebruiker hierheen na toestemming
//   POST  { action: "sync" }        -> haalt nieuwe runs op (met het weer van dat moment)
//   POST  { action: "disconnect" }  -> ontkoppelt en verwijdert de Strava-runs
//   POST  { action: "streams", activity_id } -> tijden per km en grafiek van één run
//
// Geheimen (Supabase -> Edge Functions -> Secrets):
//   STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET
// De tokens staan in het afgeschermde schema "private" en komen nooit in de app.
//
// Deploy met "Verify JWT" UIT: Strava roept /callback aan zonder RunWise-login.
// De POST-acties controleren de login zelf.

import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const APP_RETURN_URL = "runwise://app/strava-connected";
const STRAVA = "https://www.strava.com";
const FIRST_SYNC_DAYS = 365;
const MAX_PAGES_PER_SYNC = 3; // 3 x 100 activiteiten; de rest volgt bij de volgende sync
const RUN_TYPES = new Set(["Run", "TrailRun"]); // geen loopband (VirtualRun): weer doet daar niet mee

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function backToApp(status: string) {
  return new Response(null, {
    status: 302,
    headers: { Location: `${APP_RETURN_URL}?status=${encodeURIComponent(status)}` },
  });
}

const env = (k: string) => Deno.env.get(k) ?? "";

function admin(): SupabaseClient {
  const key = env("SUPABASE_SERVICE_ROLE_KEY") || env("SUPABASE_SECRET_KEY");
  return createClient(env("SUPABASE_URL"), key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

function callbackUrl() {
  return `${env("SUPABASE_URL")}/functions/v1/strava/callback`;
}

// ---------------------------------------------------------------- tokens

type Tokens = {
  athlete_id: number;
  access_token: string;
  refresh_token: string;
  expires_at: string;
  scope: string | null;
};

class ReconnectNeeded extends Error {}

async function tokenRequest(params: Record<string, string>) {
  const res = await fetch(`${STRAVA}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env("STRAVA_CLIENT_ID"),
      client_secret: env("STRAVA_CLIENT_SECRET"),
      ...params,
    }),
  });
  const body = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, body };
}

/** Geeft een geldige access token; ververst hem als hij (bijna) verlopen is. */
async function accessToken(db: SupabaseClient, userId: string): Promise<string> {
  const { data, error } = await db.rpc("strava_get_tokens", { p_user: userId });
  if (error) throw error;
  const t = (data as Tokens[] | null)?.[0];
  if (!t) throw new ReconnectNeeded();

  if (new Date(t.expires_at).getTime() - Date.now() > 10 * 60 * 1000) {
    return t.access_token;
  }
  const r = await tokenRequest({ grant_type: "refresh_token", refresh_token: t.refresh_token });
  if (!r.ok) {
    if (r.status === 400 || r.status === 401) throw new ReconnectNeeded();
    throw new Error(`Strava token refresh ${r.status}`);
  }
  await db.rpc("strava_save_tokens", {
    p_user: userId,
    p_athlete: t.athlete_id,
    p_access: r.body.access_token,
    p_refresh: r.body.refresh_token,
    p_expires: new Date(r.body.expires_at * 1000).toISOString(),
    p_scope: null,
  });
  return r.body.access_token;
}

async function forgetConnection(db: SupabaseClient, userId: string, message: string | null) {
  await db.rpc("strava_delete_tokens", { p_user: userId });
  if (message) {
    await db.from("external_connections")
      .update({ sync_status: "error", last_error: message })
      .eq("user_id", userId).eq("provider", "strava");
  } else {
    await db.from("external_connections").delete().eq("user_id", userId).eq("provider", "strava");
  }
}

// ---------------------------------------------------------------- weer

type Weather = {
  temperature_celsius: number | null;
  feels_like_celsius: number | null;
  wind_speed_kmh: number | null;
  wind_direction_degrees: number | null;
  humidity_pct: number | null;
};

const weatherCache = new Map<string, Promise<Record<string, unknown> | null>>();

function isoDate(d: Date) {
  return d.toISOString().slice(0, 10);
}

/** Weer van het uur waarin de run startte (Open-Meteo, gratis). */
async function weatherAt(lat: number, lon: number, startUtc: Date): Promise<Weather | null> {
  const hourly = "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_direction_10m";
  const daysAgo = (Date.now() - startUtc.getTime()) / 86_400_000;
  const la = lat.toFixed(2), lo = lon.toFixed(2);
  let url: string;
  if (daysAgo <= 6) {
    url = `https://api.open-meteo.com/v1/forecast?latitude=${la}&longitude=${lo}&hourly=${hourly}&timezone=GMT&past_days=7&forecast_days=1`;
  } else {
    const day = isoDate(startUtc);
    url = `https://archive-api.open-meteo.com/v1/archive?latitude=${la}&longitude=${lo}&hourly=${hourly}&timezone=GMT&start_date=${day}&end_date=${day}`;
  }
  if (!weatherCache.has(url)) {
    weatherCache.set(url, (async () => {
      try {
        const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
        return res.ok ? await res.json() : null;
      } catch {
        return null;
      }
    })());
  }
  const data = await weatherCache.get(url)!;
  const h = (data as { hourly?: Record<string, (number | string | null)[]> } | null)?.hourly;
  if (!h?.time) return null;

  const target = startUtc.toISOString().slice(0, 13); // "2026-10-17T14"
  const i = (h.time as string[]).findIndex((t) => t.startsWith(target));
  if (i < 0) return null;
  const v = (k: string) => (h[k]?.[i] as number | null | undefined) ?? null;
  if (v("temperature_2m") === null) return null;
  return {
    temperature_celsius: v("temperature_2m"),
    feels_like_celsius: v("apparent_temperature"),
    wind_speed_kmh: v("wind_speed_10m"),
    wind_direction_degrees: v("wind_direction_10m"),
    humidity_pct: v("relative_humidity_2m"),
  };
}

async function mapLimit<T, R>(items: T[], limit: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i]);
    }
  }));
  return out;
}

// ---------------------------------------------------------------- acties

async function connect(db: SupabaseClient, userId: string) {
  if (!env("STRAVA_CLIENT_ID") || !env("STRAVA_CLIENT_SECRET")) {
    return json(503, { error: "De Strava-koppeling is nog niet ingesteld op de server." });
  }
  const state = crypto.randomUUID();
  const { error } = await db.rpc("strava_save_state", { p_state: state, p_user: userId });
  if (error) throw error;

  const url = new URL(`${STRAVA}/oauth/mobile/authorize`);
  url.searchParams.set("client_id", env("STRAVA_CLIENT_ID"));
  url.searchParams.set("redirect_uri", callbackUrl());
  url.searchParams.set("response_type", "code");
  url.searchParams.set("approval_prompt", "auto");
  url.searchParams.set("scope", "read,activity:read_all");
  url.searchParams.set("state", state);
  return json(200, { url: url.toString() });
}

async function callback(req: Request) {
  const params = new URL(req.url).searchParams;
  if (params.get("error")) return backToApp("denied"); // gebruiker klikte op Annuleren

  const state = params.get("state") ?? "";
  const code = params.get("code") ?? "";
  const scope = params.get("scope") ?? "";
  if (!state || !code) return backToApp("error");

  const db = admin();
  const { data: userId, error } = await db.rpc("strava_take_state", { p_state: state });
  if (error || !userId) return backToApp("expired");

  if (!scope.includes("activity:read")) return backToApp("scope");

  const r = await tokenRequest({ grant_type: "authorization_code", code });
  if (!r.ok) {
    console.error("strava token exchange failed", r.status);
    return backToApp("error");
  }
  const athlete = r.body.athlete ?? {};
  await db.rpc("strava_save_tokens", {
    p_user: userId,
    p_athlete: athlete.id,
    p_access: r.body.access_token,
    p_refresh: r.body.refresh_token,
    p_expires: new Date(r.body.expires_at * 1000).toISOString(),
    p_scope: scope,
  });
  const name = [athlete.firstname, athlete.lastname].filter(Boolean).join(" ") || null;
  const { error: upErr } = await db.from("external_connections").upsert({
    user_id: userId,
    provider: "strava",
    provider_athlete_id: String(athlete.id),
    athlete_name: name,
    connected_at: new Date().toISOString(),
    sync_status: "idle",
    last_error: null,
  }, { onConflict: "user_id,provider" });
  if (upErr) {
    console.error("external_connections upsert failed", upErr.message);
    return backToApp("error");
  }
  return backToApp("ok");
}

type StravaActivity = {
  id: number;
  sport_type?: string;
  type?: string;
  start_date: string;
  distance: number;
  moving_time: number;
  total_elevation_gain?: number;
  average_heartrate?: number;
  trainer?: boolean;
  manual?: boolean;
  start_latlng?: [number, number] | [];
  map?: { summary_polyline?: string | null };
};

/// Runs die al vóór deze versie waren opgehaald hebben nog geen GPS-spoor.
/// Eenmalig ophalen (max. 3 pagina's per sync), zodat ook oude runs aan routes gekoppeld kunnen worden.
async function backfillTracks(db: SupabaseClient, userId: string, token: string): Promise<number> {
  const { data: missing } = await db.from("activities")
    .select("id, external_id, started_at")
    .eq("user_id", userId).eq("source", "strava").is("track_polyline", null)
    .order("started_at", { ascending: true })
    .limit(300);
  if (!missing || missing.length === 0) return 0;

  const oldest = new Date(missing[0].started_at as string).getTime();
  const after = Math.floor((oldest - 3600_000) / 1000);
  const tracks = new Map<string, string>();
  let complete = true;
  for (let page = 1; page <= MAX_PAGES_PER_SYNC; page++) {
    const res = await fetch(
      `${STRAVA}/api/v3/athlete/activities?after=${after}&per_page=100&page=${page}`,
      { headers: { Authorization: `Bearer ${token}` } },
    );
    if (!res.ok) {
      complete = false;
      break;
    }
    const list = (await res.json()) as StravaActivity[];
    for (const a of list) tracks.set(String(a.id), a.map?.summary_polyline ?? "");
    if (list.length < 100) break;
    if (page === MAX_PAGES_PER_SYNC) complete = false;
  }

  let updated = 0;
  await mapLimit(missing, 6, async (m) => {
    const t = tracks.get(m.external_id as string);
    // Niet gevonden en we hebben alles bekeken: geen spoor meer op te halen.
    if (t === undefined && !complete) return;
    const { error } = await db.from("activities").update({ track_polyline: t ?? "" }).eq("id", m.id);
    if (!error) updated++;
  });
  return updated;
}

/// Dezelfde run kan via het horloge (Health Connect) én via Strava binnenkomen.
/// De Strava-versie is rijker (GPS-spoor), dus die houden we. Een koppeling met
/// een route of schoen van de horlogeversie nemen we over.
async function removeWatchDuplicates(db: SupabaseClient, userId: string): Promise<number> {
  const since = new Date(Date.now() - (FIRST_SYNC_DAYS + 30) * 86_400_000).toISOString();
  const cols = "id, started_at, distance_meters, route_id, route_link_locked, shoe_id, feel, note";
  const [{ data: watch }, { data: strava }] = await Promise.all([
    db.from("activities").select(cols).eq("user_id", userId).eq("source", "health_connect").gte("started_at", since),
    db.from("activities").select(cols).eq("user_id", userId).eq("source", "strava").gte("started_at", since),
  ]);
  if (!watch?.length || !strava?.length) return 0;
  let removed = 0;
  for (const w of watch) {
    const wt = new Date(w.started_at as string).getTime();
    const wd = Number(w.distance_meters);
    const twin = strava.find((s) => {
      const dt = Math.abs(new Date(s.started_at as string).getTime() - wt);
      const sd = Number(s.distance_meters);
      return dt < 20 * 60_000 && Math.abs(sd - wd) <= Math.max(300, 0.15 * Math.max(sd, wd));
    });
    if (!twin) continue;
    // Wat je bij de horlogeversie invulde (route, schoen, gevoel) gaat mee naar de Strava-versie.
    const carry: Record<string, unknown> = {};
    if (w.route_id && !twin.route_id) {
      carry.route_id = w.route_id;
      carry.route_link_locked = w.route_link_locked;
    }
    if (w.shoe_id && !twin.shoe_id) carry.shoe_id = w.shoe_id;
    if (w.feel && !twin.feel) carry.feel = w.feel;
    if (w.note && !twin.note) carry.note = w.note;
    if (Object.keys(carry).length > 0) {
      await db.from("activities").update(carry).eq("id", twin.id);
    }
    const { error } = await db.from("activities").delete().eq("id", w.id).eq("user_id", userId);
    if (!error) removed++;
  }
  return removed;
}

async function sync(db: SupabaseClient, userId: string) {
  const { data: conn } = await db.from("external_connections")
    .select("last_synced_at, sync_status, connected_at")
    .eq("user_id", userId).eq("provider", "strava").maybeSingle();
  if (!conn) return json(409, { error: "Strava is niet gekoppeld." });

  await db.from("external_connections").update({ sync_status: "syncing" })
    .eq("user_id", userId).eq("provider", "strava");

  try {
    const token = await accessToken(db, userId);

    // Vanaf de vorige sync (met een uur overlap), de eerste keer een jaar terug.
    const since = conn.last_synced_at
      ? new Date(new Date(conn.last_synced_at).getTime() - 3600_000)
      : new Date(Date.now() - FIRST_SYNC_DAYS * 86_400_000);
    const after = Math.floor(since.getTime() / 1000);

    const fetched: StravaActivity[] = [];
    for (let page = 1; page <= MAX_PAGES_PER_SYNC; page++) {
      const res = await fetch(
        `${STRAVA}/api/v3/athlete/activities?after=${after}&per_page=100&page=${page}`,
        { headers: { Authorization: `Bearer ${token}` } },
      );
      if (res.status === 401) throw new ReconnectNeeded();
      if (res.status === 429) {
        if (fetched.length > 0) break; // wat we al hebben gewoon opslaan
        throw new Error("rate_limit");
      }
      if (!res.ok) throw new Error(`Strava activities ${res.status}`);
      const list = (await res.json()) as StravaActivity[];
      fetched.push(...list);
      if (list.length < 100) break;
    }

    const runs = fetched.filter((a) =>
      RUN_TYPES.has(a.sport_type ?? a.type ?? "") && !a.trainer && a.distance > 500 && a.moving_time > 0
    );

    // Handmatig ingevoerde runs rond hetzelfde tijdstip niet dubbel opslaan.
    const { data: manual } = await db.from("activities").select("started_at")
      .eq("user_id", userId).eq("source", "manual")
      .gte("started_at", new Date(since.getTime() - 86_400_000).toISOString());
    const manualTimes = (manual ?? []).map((m) => new Date(m.started_at as string).getTime());
    const isDuplicate = (t: number) => manualTimes.some((m) => Math.abs(m - t) < 20 * 60_000);

    const fresh = runs.filter((a) => !isDuplicate(new Date(a.start_date).getTime()));

    const rows = await mapLimit(fresh, 6, async (a) => {
      const start = new Date(a.start_date);
      const ll = a.start_latlng && a.start_latlng.length === 2 ? a.start_latlng : null;
      const w = ll ? await weatherAt(ll[0], ll[1], start) : null;
      return {
        user_id: userId,
        source: "strava",
        external_id: String(a.id),
        started_at: start.toISOString(),
        distance_meters: a.distance,
        moving_time_seconds: a.moving_time,
        average_pace_seconds_per_km: Math.round((a.moving_time / (a.distance / 1000)) * 100) / 100,
        average_heart_rate: a.average_heartrate ? Math.round(a.average_heartrate) : null,
        elevation_gain_meters: a.total_elevation_gain ?? null,
        temperature_celsius: w?.temperature_celsius ?? null,
        feels_like_celsius: w?.feels_like_celsius ?? null,
        wind_speed_kmh: w?.wind_speed_kmh ?? null,
        wind_direction_degrees: w?.wind_direction_degrees ?? null,
        humidity_pct: w?.humidity_pct ?? null,
        // GPS-spoor (vereenvoudigd) om de run aan een route te koppelen. "" = geen spoor.
        track_polyline: a.map?.summary_polyline ?? "",
      };
    });

    if (rows.length > 0) {
      const { error } = await db.from("activities")
        .upsert(rows, { onConflict: "user_id,source,external_id" });
      if (error) throw error;
    }

    const deduped = await removeWatchDuplicates(db, userId).catch((e) => {
      console.error("dedupe failed", e instanceof Error ? e.message : e);
      return 0;
    });

    const backfilled = await backfillTracks(db, userId, token).catch((e) => {
      console.error("track backfill failed", e instanceof Error ? e.message : e);
      return 0;
    });

    const newest = fetched.reduce(
      (max, a) => Math.max(max, new Date(a.start_date).getTime()),
      conn.last_synced_at ? new Date(conn.last_synced_at).getTime() : since.getTime(),
    );
    await db.from("external_connections").update({
      sync_status: "idle",
      last_error: null,
      last_synced_at: new Date(Math.max(newest, since.getTime())).toISOString(),
    }).eq("user_id", userId).eq("provider", "strava");

    return json(200, { imported: rows.length, skipped_duplicates: runs.length - fresh.length, tracks_added: backfilled, duplicates_removed: deduped });
  } catch (e) {
    if (e instanceof ReconnectNeeded) {
      await forgetConnection(db, userId, "Strava-toegang is ingetrokken. Koppel opnieuw.");
      return json(409, { error: "Strava-toegang is verlopen of ingetrokken. Koppel Strava opnieuw.", reconnect: true });
    }
    const rateLimited = e instanceof Error && e.message === "rate_limit";
    console.error("strava sync failed", e instanceof Error ? e.message : e);
    await db.from("external_connections").update({
      sync_status: "error",
      last_error: rateLimited ? "Strava is even druk. Probeer het over 15 minuten opnieuw." : "Synchroniseren is mislukt.",
    }).eq("user_id", userId).eq("provider", "strava");
    return json(rateLimited ? 429 : 502, {
      error: rateLimited
        ? "Strava is even druk. Probeer het over 15 minuten opnieuw."
        : "Runs ophalen bij Strava is mislukt. Probeer het later opnieuw.",
    });
  }
}

/// Verloop van één run (tijd, afstand, hoogte, hartslag, positie) voor tijden per km en de grafiek.
/// Eenmalig ophalen bij Strava en bewaren; daarna uit de database.
async function streams(db: SupabaseClient, userId: string, activityId: string) {
  const { data: act } = await db.from("activities")
    .select("id, external_id, source, streams")
    .eq("id", activityId).eq("user_id", userId).maybeSingle();
  if (!act) return json(404, { error: "Run niet gevonden." });
  if (act.source !== "strava" || !act.external_id) return json(400, { error: "Alleen beschikbaar voor runs uit Strava." });
  if (act.streams) return json(200, { streams: act.streams });

  const token = await accessToken(db, userId);
  const res = await fetch(
    `${STRAVA}/api/v3/activities/${act.external_id}/streams?keys=time,distance,altitude,heartrate,latlng&key_by_type=true`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  if (res.status === 401) throw new ReconnectNeeded();
  if (res.status === 429) return json(429, { error: "Strava is even druk. Probeer het over 15 minuten opnieuw." });
  if (res.status === 404) return json(404, { error: "Deze run heeft geen gegevens per seconde in Strava." });
  if (!res.ok) return json(502, { error: "Ophalen bij Strava is mislukt." });
  const raw = await res.json() as Record<string, { data: unknown[] }>;
  const time = (raw.time?.data ?? []) as number[];
  const dist = (raw.distance?.data ?? []) as number[];
  if (time.length < 2 || dist.length !== time.length) return json(404, { error: "Deze run heeft te weinig gegevens." });
  const alt = (raw.altitude?.data ?? []) as number[];
  const hr = (raw.heartrate?.data ?? []) as number[];
  const ll = (raw.latlng?.data ?? []) as [number, number][];

  // Terugbrengen tot hooguit ~600 punten (elke ~10 m bij een 6 km-run): genoeg voor splits en grafiek.
  const step = Math.max(1, Math.ceil(time.length / 600));
  const keep: number[] = [];
  for (let i = 0; i < time.length; i += step) keep.push(i);
  if (keep[keep.length - 1] !== time.length - 1) keep.push(time.length - 1);
  const pick = <T>(arr: T[], f: (v: T) => unknown) => arr.length === time.length ? keep.map((i) => f(arr[i])) : null;
  const compact = {
    t: keep.map((i) => time[i]),
    d: keep.map((i) => Math.round(dist[i] * 10) / 10),
    alt: pick(alt, (v) => Math.round(Number(v) * 10) / 10),
    hr: pick(hr, (v) => Math.round(Number(v))),
    ll: pick(ll, (v) => [Math.round(v[0] * 1e5) / 1e5, Math.round(v[1] * 1e5) / 1e5]),
  };
  await db.from("activities").update({ streams: compact }).eq("id", act.id);
  return json(200, { streams: compact });
}

async function disconnect(db: SupabaseClient, userId: string) {
  try {
    const token = await accessToken(db, userId);
    await fetch(`${STRAVA}/oauth/deauthorize`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
    });
  } catch {
    // Al ingetrokken of verlopen: lokaal opruimen is genoeg.
  }
  await forgetConnection(db, userId, null);
  // Strava-gegevens bewaren we niet na ontkoppelen.
  await db.from("activities").delete().eq("user_id", userId).eq("source", "strava");
  return json(200, { disconnected: true });
}

// ---------------------------------------------------------------- router

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const path = new URL(req.url).pathname;
  if (req.method === "GET" && path.endsWith("/callback")) {
    try {
      return await callback(req);
    } catch (e) {
      console.error("strava callback crashed", e instanceof Error ? e.message : e);
      return backToApp("error");
    }
  }
  if (req.method !== "POST") return json(405, { error: "Alleen POST is toegestaan." });

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json(401, { error: "Niet ingelogd." });
  const db = admin();
  const { data, error } = await db.auth.getUser(jwt);
  if (error || !data?.user) return json(401, { error: "Sessie ongeldig. Log opnieuw in." });
  const userId = data.user.id;

  const body = await req.json().catch(() => ({}));
  try {
    switch (body.action) {
      case "connect": return await connect(db, userId);
      case "sync": return await sync(db, userId);
      case "disconnect": return await disconnect(db, userId);
      case "streams": return await streams(db, userId, String(body.activity_id ?? ""));
      default: return json(400, { error: "Onbekende actie." });
    }
  } catch (e) {
    console.error("strava action failed", body.action, e instanceof Error ? e.message : e);
    return json(500, { error: "Er ging iets mis. Probeer het later opnieuw." });
  }
});
