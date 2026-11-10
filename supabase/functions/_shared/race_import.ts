// Wedstrijdkalender uit officiële bekendmakingen (KOOP SRU, CC-0). Pure functies, te testen met
// `node --experimental-strip-types supabase/functions/_shared/race_import.test.ts`.

export type SruRecord = {
  id: string; // gmb-2026-498017
  title: string;
  municipality: string | null;
  type: string; // dcterms:type, bv. evenementenvergunning
  modified: string; // YYYY-MM-DD
  geometry: string | null; // WKT in RD (EPSG:28992)
  url: string;
};

export type RaceRow = {
  key: string;
  name: string;
  race_date: string; // YYYY-MM-DD
  municipality: string | null;
  place: string | null;
  lat: number | null;
  lon: number | null;
  kind: Kind;
  status: Status;
  source_id: string;
  source_url: string;
  source_title: string;
  published: string;
};

export type Kind = "marathon" | "halve" | "trail" | "cross" | "loop" | "estafette";
export type Status = "aangevraagd" | "melding" | "verleend";

const SRU = "https://repository.overheid.nl/sru";

/** Woorden in de titel waarmee we zoeken (SRU `any`: één van deze woorden). */
export const SEARCH_WORDS = [
  "hardloopwedstrijd", "hardloopwedstrijden", "hardloopevenement", "hardlopen", "marathon", "trailrun", "trail",
  "loop", "run", "cross", "loopwedstrijd", "stratenloop", "estafetteloop", "veldloop", "bosloop",
];

export function sruUrl(since: string, start = 1, max = 100): string {
  const q = `(c.product-area==officielepublicaties AND dt.title any "${SEARCH_WORDS.join(" ")}" AND dt.modified>="${since}")`;
  return `${SRU}?maximumRecords=${max}&startRecord=${start}&sortKeys=dt.modified,,0&query=${encodeURIComponent(q)}`;
}

const unescapeXml = (s: string) =>
  s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, "&")
    .replace(/&amp;/g, "&"); // soms dubbel geëscaped ("&amp;amp;")

function tag(x: string, name: string): string | null {
  const m = x.match(new RegExp(`<${name}(?:\\s[^>]*)?>([^<]*)</${name}>`));
  return m ? unescapeXml(m[1]).trim() : null;
}

export function parseSru(xml: string): { total: number; records: SruRecord[] } {
  const total = Number(xml.match(/<sru:numberOfRecords>(\d+)/)?.[1] ?? 0);
  const records: SruRecord[] = [];
  for (const x of xml.split("<sru:record>").slice(1)) {
    const id = tag(x, "dcterms:identifier");
    const title = tag(x, "dcterms:title");
    if (!id || !title) continue;
    // Liefst het locatiepunt, anders de eerste geometrie.
    const point = x.match(/<overheidwetgeving:locatiepunt[^>]*>[\s\S]*?<overheidwetgeving:geometrie>([^<]+)/)?.[1];
    const geom = point ?? x.match(/<overheidwetgeving:geometrie>([^<]+)/)?.[1] ?? null;
    records.push({
      id,
      title: title.replace(/\s+/g, " "),
      municipality: tag(x, "dcterms:creator"),
      type: (tag(x, "dcterms:type") ?? "").toLowerCase(),
      modified: tag(x, "dcterms:modified") ?? "",
      geometry: geom,
      url: tag(x, "gzd:preferredUrl") ?? `https://zoek.officielebekendmakingen.nl/${id}.html`,
    });
  }
  return { total, records };
}

const TYPES = new Set([
  "evenementenvergunning", "evenementmelding", "andere vergunning", "andere melding", "andere beschikking",
  "omgevingsvergunning", "exploitatievergunning",
]);

/** Duidelijk géén hardloopwedstrijd (of geen bruikbare publicatie). */
const NOT_RUNNING = new RegExp(
  [
    "verkeersbesluit", "verkeersmaatregel", "parkeerverbod", "alcoholwet", "drank", "horeca", "beleidsregel",
    "schaats", "natuurijs", "paardenrit", "paarden", "wielren", "fietstocht", "toertocht", "mtb", "mountainbike",
    "triathlon", "duathlon", "run[- ]bike[- ]run", "optocht", "carnaval", "kermis", "survival run baan",
    "uitstel beslissing", "verlenging termijn", "kamervragen", "marathon feesten", "horecafeest", "wandeltocht",
    "avondvierdaagse", "wandel ?vierdaagse",
  ].join("|"),
  "i",
);

/** Hardloopwoord als los woord of als einde van een naam (Mosselloop, Hooilandrun, Kerstcross). */
const RUNNING = /hardloop|hardlopen|marathon|trail|cross\b|cross country|\w*loop\b|\w*run\b|\bhalve van\b|\bde \d+ van\b|veldloop|estafette/i;

export function isCandidate(r: SruRecord): boolean {
  if (!TYPES.has(r.type)) return false;
  if (NOT_RUNNING.test(r.title)) return false;
  if (/\bomloop\b|\bverloop\b|\bdoorloop\b|\bloopbrug\b/i.test(r.title) && !/hardloop/i.test(r.title)) return false;
  return RUNNING.test(r.title);
}

export function statusOf(r: SruRecord): Status {
  const t = r.title.toLowerCase();
  if (/verleend|toegekend|toestemming|besluit evenementenvergunning|geaccepteerde melding|vergunning verleend|meerjarige/.test(t)) return "verleend";
  if (r.type.includes("melding") || /\bmelding\b/.test(t)) return "melding";
  return "aangevraagd";
}

export const STATUS_RANK: Record<Status, number> = { aangevraagd: 0, melding: 1, verleend: 2 };

export function kindOf(name: string, title: string): Kind {
  const s = `${name} ${title}`.toLowerCase();
  if (/halve marathon|halve van|\bhalve\b/.test(s)) return "halve";
  if (/marathon/.test(s)) return "marathon";
  if (/trail|ultra/.test(s)) return "trail";
  if (/cross/.test(s)) return "cross";
  if (/estafette/.test(s)) return "estafette";
  return "loop";
}

/** RD (Rijksdriehoek, EPSG:28992) naar WGS84 – benaderingsformules (Schreutelkamp/Strang van Hees), ±1 m. */
export function rdToWgs84(x: number, y: number): { lat: number; lon: number } {
  const dX = (x - 155000) * 1e-5;
  const dY = (y - 463000) * 1e-5;
  const lat =
    52.15517440 +
    (3235.65389 * dY - 32.58297 * dX * dX - 0.2475 * dY * dY - 0.84978 * dX * dX * dY - 0.0655 * dY ** 3 -
      0.01709 * dX * dX * dY * dY - 0.00738 * dX + 0.0053 * dX ** 4 - 0.00039 * dX * dX * dY ** 3 +
      0.00033 * dX ** 4 * dY - 0.00012 * dX * dY) / 3600;
  const lon =
    5.38720621 +
    (5260.52916 * dX + 105.94684 * dX * dY + 2.45656 * dX * dY * dY - 0.81885 * dX ** 3 + 0.05594 * dX * dY ** 3 -
      0.05607 * dX ** 3 * dY + 0.01199 * dY - 0.00256 * dX ** 3 * dY * dY + 0.00128 * dX * dY ** 4 +
      0.00022 * dY * dY - 0.00022 * dX * dX + 0.00026 * dX ** 5) / 3600;
  return { lat, lon };
}

/** Eerste coördinaat uit WKT (POINT/LINESTRING/POLYGON/MULTI…), omgerekend. Alleen binnen Nederland. */
export function pointFromWkt(wkt: string | null): { lat: number; lon: number } | null {
  if (!wkt) return null;
  const m = wkt.match(/(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)/);
  if (!m) return null;
  const x = Number(m[1]), y = Number(m[2]);
  if (!(x > -10000 && x < 300000 && y > 280000 && y < 630000)) return null; // geen RD-coördinaat
  const p = rdToWgs84(x, y);
  return { lat: Math.round(p.lat * 1e5) / 1e5, lon: Math.round(p.lon * 1e5) / 1e5 };
}

/** Sleutel voor dubbelingen: naam zonder jaartal/lidwoord/leestekens + datum. */
export function raceKey(name: string, date: string): string {
  const n = name
    .toLowerCase()
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/\b20\d\d\b/g, "")
    .replace(/\b(de|het|the|een)\b/g, "")
    .replace(/[^a-z0-9]+/g, "");
  return `${n}|${date}`;
}

// ---------------------------------------------------------------- AI-uitlezing

export type Extracted = { i: number; races: { name: string; date: string | null; place?: string | null }[] };

export function extractionPrompt(items: { i: number; title: string; municipality: string | null }[], today: string): string {
  return [
    `Vandaag is ${today}. Hieronder staan titels van Nederlandse gemeentelijke bekendmakingen (evenementenvergunningen en meldingen).`,
    "Haal er HARDLOOPWEDSTRIJDEN en hardloopevenementen uit (ook trail, cross, marathon, obstacle run, fun run).",
    "Géén wandeltochten, fietsen, schaatsen, triathlon/duathlon, optochten of bouwplannen.",
    "Geef per titel de evenementen met: name (de eigen naam van het evenement, kort, zonder 'hardloopwedstrijd' ervoor als dat geen deel van de naam is, zonder jaartal), date (YYYY-MM-DD; alleen als de datum in de titel staat, anders null; bij meerdere dagen de eerste), place (plaats, of null).",
    "Een titel kan meerdere evenementen bevatten; geef ze dan allemaal. Is het geen hardloopevenement, geef dan een lege lijst.",
    'Antwoord ALLEEN met JSON: [{"i":0,"races":[{"name":"…","date":"2027-01-24","place":"…"}]}, …]',
    "",
    ...items.map((x) => `${x.i}. ${x.title}${x.municipality ? ` [gemeente ${x.municipality}]` : ""}`),
  ].join("\n");
}

const DATE = /^\d{4}-\d{2}-\d{2}$/;

/** Leest het AI-antwoord streng: alleen geldige namen en datums. */
export function parseExtraction(text: string): Extracted[] {
  const json = text.slice(text.indexOf("["), text.lastIndexOf("]") + 1);
  let arr: unknown;
  try {
    arr = JSON.parse(json);
  } catch {
    return [];
  }
  if (!Array.isArray(arr)) return [];
  const out: Extracted[] = [];
  for (const it of arr) {
    if (typeof it !== "object" || it === null) continue;
    const o = it as Record<string, unknown>;
    if (typeof o.i !== "number" || !Array.isArray(o.races)) continue;
    const races = [];
    for (const r of o.races as Record<string, unknown>[]) {
      const name = typeof r?.name === "string" ? r.name.trim().replace(/\s+/g, " ") : "";
      if (name.length < 2 || name.length > 120) continue;
      const date = typeof r.date === "string" && DATE.test(r.date) && !isNaN(Date.parse(r.date)) ? r.date : null;
      const place = typeof r.place === "string" && r.place.trim() ? r.place.trim().slice(0, 80) : null;
      races.push({ name, date, place });
    }
    out.push({ i: o.i, races });
  }
  return out;
}

// ---------------------------------------------------------------- reserve zonder AI

const MONTHS: Record<string, number> = {
  jan: 1, januari: 1, feb: 2, februari: 2, mrt: 3, maart: 3, apr: 4, april: 4, mei: 5, jun: 6, juni: 6, jul: 7, juli: 7,
  aug: 8, augustus: 8, sep: 9, sept: 9, september: 9, okt: 10, oktober: 10, nov: 11, november: 11, dec: 12, december: 12,
};
const pad = (n: number) => String(n).padStart(2, "0");

/** Eerste datum in een titel ("24 januari 2027", "24-01-2027"), of null. */
export function dateInTitle(title: string): string | null {
  const a = title.match(/\b(\d{1,2})\s+(januari|februari|maart|april|mei|juni|juli|augustus|september|oktober|november|december|jan|feb|mrt|apr|jun|jul|aug|sept?|okt|nov|dec)\.?\s+(20\d\d)\b/i);
  if (a) return `${a[3]}-${pad(MONTHS[a[2].toLowerCase()])}-${pad(Number(a[1]))}`;
  const b = title.match(/\b(\d{1,2})-(\d{1,2})-(20\d\d)\b/);
  if (b) return `${b[3]}-${pad(Number(b[2]))}-${pad(Number(b[1]))}`;
  return null;
}

/** Zonder AI: alleen titels met een naam tussen aanhalingstekens én een datum. Liever niets dan onzin. */
export function heuristicExtract(title: string): { name: string; date: string } | null {
  const date = dateInTitle(title);
  const name = title.match(/[‘'"“]([^’'"”]{3,60})[’'"”]/)?.[1]?.trim();
  return date && name ? { name: name.replace(/\s+20\d\d$/, ""), date } : null;
}
