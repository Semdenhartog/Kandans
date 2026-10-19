// Edge Function: street-photos
// Zoekt straatfoto's (Mapillary) langs een route, zodat je vooraf ziet waar je langs loopt.
//
//   POST { points: [[lat, lon, bearing?], ...] }  (max 24)
//     -> { photos: [{ index, id, url, thumb, lat, lon, captured_at, creator, pano }] }
//
// Geheim (Supabase -> Edge Functions -> Secrets): MAPILLARY_TOKEN  (client token "MLY|...")
// Foto's © Mapillary-bijdragers, licentie CC BY-SA 4.0.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

function readKey(): string {
  for (const n of ["MAPILLARY_TOKEN", "MAPILLARY_ACCESS_TOKEN", "MAPILLARY", "mapillary", "api mapillary", "Mapillary", "MAPILLARY_CLIENT_TOKEN"]) {
    try {
      const v = (Deno.env.get(n) ?? "").trim();
      if (v) return v;
    } catch (_) { /* ongeldige naam */ }
  }
  return "";
}

type MlyImage = {
  id: string;
  thumb_1024_url?: string;
  thumb_256_url?: string;
  computed_geometry?: { coordinates: number[] };
  geometry?: { coordinates: number[] };
  captured_at?: number;
  is_pano?: boolean;
  compass_angle?: number;
  computed_compass_angle?: number;
  creator?: { username?: string };
};

function angleDiff(a: number, b: number) {
  const d = Math.abs(((a - b) % 360 + 540) % 360 - 180);
  return d;
}

function dist(lat1: number, lon1: number, lat2: number, lon2: number) {
  const dx = (lon2 - lon1) * 111320 * Math.cos(lat1 * Math.PI / 180);
  const dy = (lat2 - lat1) * 110540;
  return Math.sqrt(dx * dx + dy * dy);
}

async function nearPoint(key: string, lat: number, lon: number, bearing: number | null): Promise<MlyImage | null> {
  // Vakje van ongeveer 90 x 90 m rond het punt.
  const dLat = 0.0004, dLon = 0.0006;
  const bbox = [lon - dLon, lat - dLat, lon + dLon, lat + dLat].map((v) => v.toFixed(6)).join(",");
  const fields = "id,thumb_1024_url,thumb_256_url,computed_geometry,geometry,captured_at,is_pano,compass_angle,computed_compass_angle,creator";
  const url = `https://graph.mapillary.com/images?access_token=${encodeURIComponent(key)}&fields=${fields}&bbox=${bbox}&limit=25`;
  const res = await fetch(url, { signal: AbortSignal.timeout(12_000) });
  if (res.status === 401 || res.status === 403) throw new Error("bad_token");
  if (res.status === 429) throw new Error("rate_limit");
  if (!res.ok) {
    console.error("mapillary", res.status, (await res.text()).slice(0, 200));
    return null;
  }
  const data = await res.json();
  const list = (data.data ?? []) as MlyImage[];
  let best: MlyImage | null = null;
  let bestScore = -Infinity;
  const now = Date.now();
  for (const im of list) {
    if (!im.thumb_1024_url) continue;
    const c = (im.computed_geometry ?? im.geometry)?.coordinates;
    if (!c) continue;
    const d = dist(lat, lon, c[1], c[0]);
    const years = im.captured_at ? (now - im.captured_at) / (365 * 24 * 3600 * 1000) : 8;
    const angle = im.computed_compass_angle ?? im.compass_angle;
    // Liefst: geen 360°-foto, dichtbij, recent en in de looprichting gefotografeerd.
    let score = -d / 10 - years * 1.5 + (im.is_pano ? -6 : 0);
    if (bearing != null && angle != null) score += angleDiff(angle, bearing) < 50 ? 6 : angleDiff(angle, bearing) > 130 ? -3 : 0;
    if (score > bestScore) {
      bestScore = score;
      best = im;
    }
  }
  return best;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Alleen POST is toegestaan." });

  const key = readKey();
  if (!key) return json(503, { error: "Straatfoto's zijn nog niet ingesteld op de server.", code: "not_configured" });

  const body = await req.json().catch(() => ({}));
  const raw = Array.isArray(body.points) ? body.points : [];
  const points = raw.slice(0, 24).map((p: unknown) => Array.isArray(p) ? p.map(Number) : [])
    .filter((p: number[]) => p.length >= 2 && Number.isFinite(p[0]) && Number.isFinite(p[1]) && Math.abs(p[0]) <= 90 && Math.abs(p[1]) <= 180);
  if (points.length === 0) return json(400, { error: "Geen punten ontvangen." });

  try {
    const out: Record<string, unknown>[] = [];
    const seen = new Set<string>();
    // In groepjes van 6 tegelijk.
    for (let i = 0; i < points.length; i += 6) {
      const batch = points.slice(i, i + 6);
      const found = await Promise.all(batch.map((p: number[]) =>
        nearPoint(key, p[0], p[1], p.length > 2 && Number.isFinite(p[2]) ? p[2] : null).catch((e) => {
          if (e instanceof Error && (e.message === "bad_token" || e.message === "rate_limit")) throw e;
          return null;
        })
      ));
      found.forEach((im, j) => {
        if (!im || seen.has(im.id)) return;
        seen.add(im.id);
        const c = (im.computed_geometry ?? im.geometry)!.coordinates;
        out.push({
          index: i + j,
          id: im.id,
          url: im.thumb_1024_url,
          thumb: im.thumb_256_url ?? im.thumb_1024_url,
          lat: c[1],
          lon: c[0],
          captured_at: im.captured_at ?? null,
          creator: im.creator?.username ?? null,
          pano: im.is_pano ?? false,
        });
      });
    }
    return json(200, { photos: out });
  } catch (e) {
    if (e instanceof Error && e.message === "bad_token") {
      return json(503, { error: "De Mapillary-sleutel op de server klopt niet.", code: "bad_token" });
    }
    if (e instanceof Error && e.message === "rate_limit") {
      return json(429, { error: "Het is even druk. Probeer het over een minuut opnieuw." });
    }
    console.error("street-photos failed", e instanceof Error ? e.message : e);
    return json(502, { error: "Straatfoto's ophalen is niet gelukt." });
  }
});
