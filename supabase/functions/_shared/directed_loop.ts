// Tussenpunten voor een rondje dat een gekozen kant op gaat (noord, oost, ...).
// openrouteservice' round_trip kent geen richting; daarom leggen we zelf een driehoek met de punt bij de start
// en laten we ORS de echte paden langs die punten zoeken (mode "path").

/** Hoeveel langer een looproute over paden is dan de rechte lijnen tussen de punten (ervaringsgetal). */
export const ROAD_FACTOR = 1.3;

/** Punt op [meters] afstand van (lat, lon) in richting [bearingDeg] (0 = noord, 90 = oost). */
export function offset(lat: number, lon: number, meters: number, bearingDeg: number): [number, number] {
  const r = 6371000;
  const b = (bearingDeg * Math.PI) / 180;
  const p1 = (lat * Math.PI) / 180, l1 = (lon * Math.PI) / 180, d = meters / r;
  const p2 = Math.asin(Math.sin(p1) * Math.cos(d) + Math.cos(p1) * Math.sin(d) * Math.cos(b));
  const l2 = l1 + Math.atan2(Math.sin(b) * Math.sin(d) * Math.cos(p1), Math.cos(d) - Math.sin(p1) * Math.sin(p2));
  return [(p2 * 180) / Math.PI, (l2 * 180) / Math.PI];
}

/**
 * Start → A → B → start. A en B liggen op gelijke afstand van de start, [spreadDeg] uit elkaar rond [bearingDeg].
 * De zijden zijn zo gekozen dat het rondje over paden ongeveer [distance] meter wordt.
 */
export function directedLoopWaypoints(
  lat: number,
  lon: number,
  distance: number,
  bearingDeg: number,
  spreadDeg = 60,
): [number, number][] {
  const half = ((spreadDeg / 2) * Math.PI) / 180;
  const side = distance / (ROAD_FACTOR * 2 * (1 + Math.sin(half)));
  const a = offset(lat, lon, side, bearingDeg - spreadDeg / 2);
  const b = offset(lat, lon, side, bearingDeg + spreadDeg / 2);
  return [[lat, lon], a, b, [lat, lon]];
}

/** Hemelsbrede lengte van een reeks [lat, lon]-punten (m). */
export function straightMeters(pts: [number, number][]): number {
  let m = 0;
  for (let i = 1; i < pts.length; i++) {
    const [la1, lo1] = pts[i - 1], [la2, lo2] = pts[i];
    const x = ((lo2 - lo1) * Math.PI / 180) * Math.cos(((la1 + la2) / 2) * Math.PI / 180);
    const y = (la2 - la1) * Math.PI / 180;
    m += Math.sqrt(x * x + y * y) * 6371000;
  }
  return m;
}
