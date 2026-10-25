// Ondergrond langs een route uit openrouteservice, met een schatting waar OpenStreetMap niets zegt.
// Los van het netwerk, zodat het te testen is.

/** ORS surface-waarde -> onze soort (null = onbekend). */
export const SURFACE: Record<number, string | null> = {
  1: "verhard", 3: "verhard", 4: "verhard", 6: "verhard",
  5: "klinkers", 14: "klinkers", 18: "klinkers",
  8: "halfverhard", 9: "halfverhard", 10: "halfverhard",
  2: "onverhard", 11: "onverhard", 12: "onverhard", 15: "onverhard", 16: "onverhard", 17: "onverhard", 7: "onverhard",
  0: null, 13: null,
};

/** ORS waytype -> waarschijnlijke ondergrond in Nederland (null = geen idee). */
export const FROM_WAYTYPE: Record<number, string | null> = {
  1: "verhard", // rijksweg
  2: "verhard", // weg
  3: "verhard", // straat
  6: "verhard", // fietspad: in Nederland bijna altijd asfalt of beton
  8: "verhard", // trap
  7: "klinkers", // voetpad/stoep: meestal tegels of klinkers
  5: "halfverhard", // boeren- of bosweg (track)
  4: "onverhard", // pad: meestal bospad, zand of gras
  0: null, 9: null, 10: null,
};

/** Google-polyline (precisie 5) naar [lat, lon]. */
export function decodePolyline(s: string): [number, number][] {
  const out: [number, number][] = [];
  let i = 0, lat = 0, lon = 0;
  while (i < s.length) {
    for (const which of [0, 1]) {
      let shift = 0, result = 0, b: number;
      do {
        b = s.charCodeAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      const d = (result & 1) ? ~(result >> 1) : (result >> 1);
      if (which === 0) lat += d; else lon += d;
    }
    out.push([lat / 1e5, lon / 1e5]);
  }
  return out;
}

function meters(a: [number, number], b: [number, number]): number {
  const R = 6371000, toR = Math.PI / 180;
  const dLat = (b[0] - a[0]) * toR, dLon = (b[1] - a[1]) * toR;
  const x = Math.sin(dLat / 2) ** 2 + Math.cos(a[0] * toR) * Math.cos(b[0] * toR) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}

type Range = [number, number, number]; // [van-index, tot-index, waarde]

/**
 * Per stukje van de route: bekende ondergrond, anders geschat uit het soort weg,
 * anders (korte stukjes) de soort van de buren. Geeft per soort meters en hoeveel daarvan geschat is.
 */
export function inferSurface(geometry: [number, number][], surface: Range[], waytype: Range[]) {
  const n = geometry.length;
  if (n < 2) return [];
  const segLen = new Array(n - 1).fill(0).map((_, i) => meters(geometry[i], geometry[i + 1]));
  const known: (string | null)[] = new Array(n - 1).fill(null);
  const guess: (string | null)[] = new Array(n - 1).fill(null);
  for (const [a, b, v] of surface) for (let i = a; i < b && i < n - 1; i++) known[i] = SURFACE[v] ?? null;
  for (const [a, b, v] of waytype) for (let i = a; i < b && i < n - 1; i++) guess[i] = FROM_WAYTYPE[v] ?? null;

  const type: (string | null)[] = known.map((k, i) => k ?? guess[i]);
  const guessed: boolean[] = known.map((k, i) => k == null && guess[i] != null);

  // Nog onbekend: korte stukjes (tot 400 m aaneen) krijgen de soort van de buren.
  let i = 0;
  while (i < n - 1) {
    if (type[i] != null) { i++; continue; }
    let j = i, len = 0;
    while (j < n - 1 && type[j] == null) { len += segLen[j]; j++; }
    const before = i > 0 ? type[i - 1] : null;
    const after = j < n - 1 ? type[j] : null;
    const fill = len <= 400 ? (before ?? after) : null;
    if (fill) for (let k = i; k < j; k++) { type[k] = fill; guessed[k] = true; }
    i = j;
  }

  const out = new Map<string, { meters: number; guessed: number }>();
  for (let k = 0; k < n - 1; k++) {
    const t = type[k] ?? "onbekend";
    const e = out.get(t) ?? { meters: 0, guessed: 0 };
    e.meters += segLen[k];
    if (guessed[k]) e.guessed += segLen[k];
    out.set(t, e);
  }
  return [...out.entries()].map(([t, e]) => ({ type: t, meters: Math.round(e.meters), guessed: Math.round(e.guessed) }));
}
