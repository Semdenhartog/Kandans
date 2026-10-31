// GPX maken van een Kadans-run (voor uploaden naar Strava). Los te testen met
//   node --experimental-strip-types supabase/functions/_shared/gpx.test.ts

export interface RunForGpx {
  name: string;
  startedAt: string; // ISO
  streams: Record<string, unknown>;
}

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

function nums(v: unknown): number[] | null {
  return Array.isArray(v) ? v.map((x) => (typeof x === "number" ? x : Number(x) || 0)) : null;
}

/** GPX 1.1 met tijd, hoogte en hartslag (Garmin TrackPointExtension). Null zonder GPS-punten. */
export function runToGpx(run: RunForGpx): string | null {
  const t = nums(run.streams["t"]);
  const ll = run.streams["ll"];
  if (!t || !Array.isArray(ll) || ll.length !== t.length || t.length < 2) return null;
  const alt = nums(run.streams["baro"]) ?? nums(run.streams["alt"]);
  const hr = nums(run.streams["hr"]);
  const cad = nums(run.streams["cad"]);
  const start = new Date(run.startedAt).getTime();
  const pts: string[] = [];
  for (let i = 0; i < t.length; i++) {
    const p = ll[i];
    if (!Array.isArray(p) || p.length < 2) continue;
    const time = new Date(start + t[i] * 1000).toISOString();
    const ext = [
      hr && hr[i] > 0 ? `<gpxtpx:hr>${Math.round(hr[i])}</gpxtpx:hr>` : "",
      // Strava verwacht cadans per been (omwentelingen), Kadans bewaart stappen per minuut.
      cad && cad[i] > 0 ? `<gpxtpx:cad>${Math.round(cad[i] / 2)}</gpxtpx:cad>` : "",
    ].join("");
    pts.push(
      `<trkpt lat="${Number(p[0]).toFixed(6)}" lon="${Number(p[1]).toFixed(6)}">` +
        (alt && alt.length === t.length ? `<ele>${alt[i].toFixed(1)}</ele>` : "") +
        `<time>${time}</time>` +
        (ext ? `<extensions><gpxtpx:TrackPointExtension>${ext}</gpxtpx:TrackPointExtension></extensions>` : "") +
        `</trkpt>`,
    );
  }
  if (pts.length < 2) return null;
  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Kadans" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
<metadata><time>${new Date(start).toISOString()}</time></metadata>
<trk><name>${esc(run.name)}</name><type>running</type><trkseg>
${pts.join("\n")}
</trkseg></trk>
</gpx>`;
}

/** Strava-runs die uit Kadans komen (geüpload) niet opnieuw importeren. */
export function isKadansUpload(externalId: unknown): boolean {
  return typeof externalId === "string" && externalId.startsWith("kadans-");
}
