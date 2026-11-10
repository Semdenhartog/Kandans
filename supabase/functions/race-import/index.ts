// Wedstrijdkalender ophalen uit officiële bekendmakingen (KOOP SRU, CC-0) → public.race_calendar.
//
// Wordt elke nacht gestart door de database (pg_cron → private.start_race_import(), migratie 0042b), met
// een eenmalige code in de header x-import-nonce. Zonder geldige code doet deze functie niets; zo is er
// geen extra geheime sleutel nodig. Met de hand starten: `select private.start_race_import();` in de SQL-editor.
//
// Geheimen (al aanwezig voor de coach):
//   ANTHROPIC_API_KEY   optioneel – titels netjes uitlezen. Zonder sleutel alleen titels met naam tussen
//                       aanhalingstekens én datum (liever niets dan onzin).
//   RACE_IMPORT_MODEL   optioneel – standaard claude-haiku-5-5

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  extractionPrompt, heuristicRaces, isCandidate, kindOf, parseExtraction, mergeRows, parseSru, sameRace, pointFromWkt, raceKey, withPlace,
  type RaceRow, sruUrl, STATUS_RANK, statusOf, type SruRecord,
} from "../_shared/race_import.ts";

const env = (k: string) => Deno.env.get(k) ?? "";
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const today = () => new Date().toISOString().slice(0, 10);
const daysAgo = (n: number) => new Date(Date.now() - n * 86400_000).toISOString().slice(0, 10);

async function fetchRecords(since: string): Promise<SruRecord[]> {
  const all: SruRecord[] = [];
  for (let start = 1; start <= 2000; start += 100) {
    const res = await fetch(sruUrl(since, start, 100), { signal: AbortSignal.timeout(30_000) });
    if (!res.ok) throw new Error(`SRU ${res.status}`);
    const { total, records } = parseSru(await res.text());
    all.push(...records);
    if (start + 100 > total || records.length === 0) break;
  }
  return all;
}

/** Midden van een gemeente via PDOK Locatieserver (gratis, open data), voor publicaties zonder locatie. */
const municipalityCache = new Map<string, { lat: number; lon: number } | null>();
async function municipalityPoint(name: string | null): Promise<{ lat: number; lon: number } | null> {
  if (!name) return null;
  if (municipalityCache.has(name)) return municipalityCache.get(name)!;
  let p: { lat: number; lon: number } | null = null;
  try {
    const url = `https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q=${encodeURIComponent(name)}&fq=type:gemeente&rows=1&fl=centroide_ll`;
    const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
    const doc = (await res.json())?.response?.docs?.[0];
    const m = String(doc?.centroide_ll ?? "").match(/POINT\(([-\d.]+) ([-\d.]+)\)/);
    if (m) p = { lon: Number(m[1]), lat: Number(m[2]) };
  } catch (_) { /* zonder plek: dan alleen zonder afstand tonen */ }
  municipalityCache.set(name, p);
  return p;
}

async function extract(items: SruRecord[]): Promise<Map<number, { name: string; date: string | null; place?: string | null }[]>> {
  const out = new Map<number, { name: string; date: string | null; place?: string | null }[]>();
  const key = env("ANTHROPIC_API_KEY");
  if (!key) {
    items.forEach((r, i) => out.set(i, heuristicRaces(r.title)));
    return out;
  }
  for (let from = 0; from < items.length; from += 40) {
    const batch = items.slice(from, from + 40).map((r, j) => ({ i: from + j, title: r.title, municipality: r.municipality }));
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: env("RACE_IMPORT_MODEL") || "claude-haiku-5-5",
        max_tokens: 4000,
        messages: [{ role: "user", content: extractionPrompt(batch, today()) }],
      }),
      signal: AbortSignal.timeout(60_000),
    }).catch(() => null);
    if (!res?.ok) {
      // AI even niet bereikbaar: deze reeks met de strenge reserve.
      batch.forEach((b) => out.set(b.i, heuristicRaces(b.title)));
      continue;
    }
    const result = await res.json();
    const u = result.usage ?? {};
    console.log(JSON.stringify({ race_import_usage: true, input: u.input_tokens, output: u.output_tokens }));
    const text = ((result.content ?? []) as { type: string; text?: string }[]).filter((c) => c.type === "text").map((c) => c.text).join("");
    for (const e of parseExtraction(text)) if (e.i >= from && e.i < from + batch.length) out.set(e.i, e.races);
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST" });
  const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY") || env("SUPABASE_SECRET_KEY"), {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Alleen met een eenmalige code die de database zelf net heeft aangemaakt.
  const nonce = req.headers.get("x-import-nonce") ?? "";
  const { data: ok } = await db.rpc("race_import_claim", { p_nonce: nonce });
  if (ok !== true) return json(401, { error: "Geen geldige start." });

  try {
    // Eerste keer een jaar terug, daarna drie weken (ruim, want gemeenten publiceren soms later).
    // Al verwerkte publicaties overslaan (en geen AI-kosten voor dubbel werk).
    const { data: firstRun } = await db.rpc("race_import_first_run");
    const since = firstRun === true ? daysAgo(365) : daysAgo(21);
    const records = (await fetchRecords(since)).filter(isCandidate);
    const { data: unseen } = await db.rpc("race_import_unseen", { p_ids: records.map((r) => r.id) });
    const todo = new Set((unseen ?? []) as string[]);
    const fresh = records.filter((r) => todo.has(r.id));

    const extracted = await extract(fresh);
    const rows = new Map<string, RaceRow>();
    for (const [i, races] of extracted) {
      const r = fresh[i];
      for (const race of races) {
        if (!race.date || race.date < today()) continue; // zonder datum of al geweest: niet tonen
        race.name = withPlace(race.name, race.place ?? r.municipality);
        const key = raceKey(race.name, race.date);
        const point = pointFromWkt(r.geometry) ?? (await municipalityPoint(r.municipality));
        const row: RaceRow = {
          key,
          name: race.name,
          race_date: race.date,
          municipality: r.municipality,
          place: race.place ?? null,
          lat: point?.lat ?? null,
          lon: point?.lon ?? null,
          kind: kindOf(race.name, r.title, races.length === 1),
          status: statusOf(r),
          source_id: r.id,
          source_url: r.url,
          source_title: r.title.slice(0, 500),
          published: r.modified || today(),
        };
        const prev = rows.get(key);
        if (!prev || STATUS_RANK[row.status] > STATUS_RANK[prev.status]) rows.set(key, row);
      }
    }

    // Dubbelingen samenvoegen (zelfde dag en gemeente, vergelijkbare naam), ook met wat er al staat.
    const { data: same } = await db.from("race_calendar").select("key,name,race_date,municipality,status")
      .in("race_date", [...new Set([...rows.values()].map((r) => r.race_date))]);
    for (const e of same ?? []) {
      for (const [k, r] of rows) {
        if (k !== e.key && r.race_date === e.race_date && r.municipality === e.municipality && sameRace(r.name, e.name)) {
          rows.delete(k);
          rows.set(e.key, { ...r, key: e.key, name: e.name.length >= r.name.length ? e.name : r.name });
        }
      }
    }
    const merged = mergeRows([...rows.values()]);
    rows.clear();
    for (const r of merged) rows.set(r.key, r);

    // Bestaande rijen: status nooit omlaag (een verlening blijft een verlening), plek alleen aanvullen.
    const keys = [...rows.keys()];
    if (keys.length) {
      const { data: existing } = await db.from("race_calendar").select("key,status,lat,lon,place").in("key", keys);
      for (const e of existing ?? []) {
        const row = rows.get(e.key)!;
        if (STATUS_RANK[e.status as keyof typeof STATUS_RANK] > STATUS_RANK[row.status]) row.status = e.status;
        if (row.lat == null && e.lat != null) (row.lat = e.lat), (row.lon = e.lon);
        if (!row.place && e.place) row.place = e.place;
      }
      const { error } = await db.from("race_calendar").upsert([...rows.values()].map((r) => ({ ...r, updated_at: new Date().toISOString() })));
      if (error) throw new Error(error.message);
    }
    // Alleen als de AI meelas als 'gezien' markeren: zonder AI elke nacht opnieuw (kost niets), zodat alles
    // alsnog netjes wordt uitgelezen zodra ANTHROPIC_API_KEY er staat.
    if (fresh.length && env("ANTHROPIC_API_KEY")) await db.rpc("race_import_mark_seen", { p_ids: fresh.map((r) => r.id) });
    const summary = { since, found: records.length, new_publications: fresh.length, races: rows.size, ai: !!env("ANTHROPIC_API_KEY") };
    console.log(JSON.stringify({ race_import: summary }));
    await db.rpc("race_import_log", { p_summary: summary });
    return json(200, summary);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("race_import failed", msg);
    await db.rpc("race_import_log", { p_summary: { error: msg.slice(0, 300) } });
    return json(500, { error: msg });
  }
});
