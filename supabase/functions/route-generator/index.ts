// Edge Function: route-generator
// Maakt rondjes van een gewenste lengte vanaf een startpunt, via openrouteservice
// (gratis, op basis van OpenStreetMap). De app kiest daarna het rondje met de beste wind.
//
//   POST { lat, lon, distance_m, count? }  ->  { routes: [{ coordinates: [[lon,lat,ele]], distance_m, ascent_m }] }
//   POST { mode: "path", points: [[lat,lon], ...] }  ->  { route: { coordinates, distance_m, ascent_m } }
//        (zelf getekende route: volgt paden en wegen langs de punten die je tikt)
//
// Geheim (Supabase -> Edge Functions -> Secrets): ORS_API_KEY
// Routes © openrouteservice.org (HeiGIT) | kaartdata © OpenStreetMap-bijdragers.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

type OrsFeature = {
  geometry: { coordinates: number[][] };
  properties: { summary?: { distance?: number }; ascent?: number };
};

async function roundTrip(key: string, lat: number, lon: number, length: number, seed: number, points: number) {
  const res = await fetch("https://api.openrouteservice.org/v2/directions/foot-walking/geojson", {
    method: "POST",
    headers: { Authorization: key, "Content-Type": "application/json", Accept: "application/geo+json" },
    body: JSON.stringify({
      coordinates: [[lon, lat]],
      elevation: true,
      instructions: false,
      options: { round_trip: { length, points, seed } },
    }),
    signal: AbortSignal.timeout(20_000),
  });
  if (res.status === 429) throw new Error("rate_limit");
  if (!res.ok) {
    console.error("ors error", res.status, (await res.text()).slice(0, 300));
    return null;
  }
  const data = await res.json();
  const f = (data.features?.[0]) as OrsFeature | undefined;
  if (!f) return null;
  return {
    coordinates: f.geometry.coordinates,
    distance_m: Math.round(f.properties.summary?.distance ?? 0),
    ascent_m: Math.round(f.properties.ascent ?? 0),
  };
}

async function path(key: string, points: number[][]) {
  const res = await fetch("https://api.openrouteservice.org/v2/directions/foot-walking/geojson", {
    method: "POST",
    headers: { Authorization: key, "Content-Type": "application/json", Accept: "application/geo+json" },
    body: JSON.stringify({
      coordinates: points.map(([lat, lon]) => [lon, lat]),
      elevation: true,
      instructions: false,
      radiuses: points.map(() => 350),
    }),
    signal: AbortSignal.timeout(20_000),
  });
  if (res.status === 429) throw new Error("rate_limit");
  if (!res.ok) {
    console.error("ors path error", res.status, (await res.text()).slice(0, 300));
    return null;
  }
  const data = await res.json();
  const f = (data.features?.[0]) as OrsFeature | undefined;
  if (!f) return null;
  return {
    coordinates: f.geometry.coordinates,
    distance_m: Math.round(f.properties.summary?.distance ?? 0),
    ascent_m: Math.round(f.properties.ascent ?? 0),
  };
}

function readKey(): string {
  for (const n of ["ORS_API_KEY", "API_ROUTES", "api_routes", "api routes", "API routes", "Api routes"]) {
    try {
      const v = (Deno.env.get(n) ?? "").trim();
      if (v) return v;
    } catch (_) { /* ongeldige naam: overslaan */ }
  }
  return "";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Alleen POST is toegestaan." });

  const key = readKey();
  if (!key) return json(503, { error: "Routes maken is nog niet ingesteld op de server." });

  const body = await req.json().catch(() => ({}));

  if (body.mode === "path") {
    const pts = Array.isArray(body.points) ? body.points : [];
    const ok = pts.length >= 2 && pts.length <= 50 && pts.every((p: unknown) =>
      Array.isArray(p) && p.length >= 2 && Number.isFinite(Number(p[0])) && Number.isFinite(Number(p[1])) &&
      Math.abs(Number(p[0])) <= 90 && Math.abs(Number(p[1])) <= 180);
    if (!ok) return json(400, { error: "Tik minstens twee punten (hooguit 50)." });
    try {
      const r = await path(key, pts.map((p: unknown[]) => [Number(p[0]), Number(p[1])]));
      if (!r) return json(502, { error: "Hier kon geen pad gevonden worden. Zet het punt dichter bij een weg of pad." });
      return json(200, { route: r });
    } catch (e) {
      if (e instanceof Error && e.message === "rate_limit") {
        return json(429, { error: "Het is even druk. Probeer het over een minuut opnieuw." });
      }
      console.error("route-generator path failed", e instanceof Error ? e.message : e);
      return json(502, { error: "De route volgen is niet gelukt. Probeer het opnieuw." });
    }
  }

  const lat = Number(body.lat), lon = Number(body.lon), distance = Number(body.distance_m);
  const count = Math.min(Math.max(Number(body.count ?? 4), 1), 5);
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
    return json(400, { error: "Ongeldig startpunt." });
  }
  if (!Number.isFinite(distance) || distance < 1000 || distance > 50000) {
    return json(400, { error: "Kies een afstand tussen 1 en 50 km." });
  }

  // Verschillende vormen proberen: andere 'seed' en aantal tussenpunten.
  const base = Math.floor(Math.random() * 1000);
  try {
    const results = await Promise.all(
      Array.from({ length: count }, (_, i) => roundTrip(key, lat, lon, distance, base + i * 7, 3 + (i % 3))),
    );
    const routes = results.filter((r) => r && r.coordinates.length > 3);
    if (routes.length === 0) return json(502, { error: "Er konden hier geen rondjes worden gemaakt. Kies een ander startpunt." });
    return json(200, { routes });
  } catch (e) {
    if (e instanceof Error && e.message === "rate_limit") {
      return json(429, { error: "Het is even druk. Probeer het over een minuut opnieuw." });
    }
    console.error("route-generator failed", e instanceof Error ? e.message : e);
    return json(502, { error: "Routes maken is niet gelukt. Probeer het later opnieuw." });
  }
});
