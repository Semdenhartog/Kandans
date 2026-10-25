// Losse onderdelen voor de ranglijsten (zonder netwerk, zodat ze te testen zijn).

export type BoardDef = {
  key: string; // bijv. "km-2026-11", "advent-2026"
  title: string;
  unit: "km" | "m" | "dagen";
  start: string; // YYYY-MM-DD (Nederlandse tijd), inclusief
  end: string; // YYYY-MM-DD, exclusief
  kind: "km" | "climb" | "days";
};

export type RunRow = { started_at: string; distance_meters: number | string; elevation_gain_meters: number | string | null };

const MONTHS = ["januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus", "september", "oktober", "november", "december"];

const dayFmt = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Amsterdam", year: "numeric", month: "2-digit", day: "2-digit" });

/** Datum (YYYY-MM-DD) in Nederlandse tijd. */
export function nlDay(d: Date): string {
  return dayFmt.format(d);
}

function ymd(y: number, m: number, d: number): string {
  const date = new Date(Date.UTC(y, m - 1, d));
  return date.toISOString().slice(0, 10);
}

/** Ranglijsten die nu lopen. */
export function boardsFor(now: Date): BoardDef[] {
  const [y, m, d] = nlDay(now).split("-").map(Number);
  const mm = String(m).padStart(2, "0");
  const month = MONTHS[m - 1];
  const out: BoardDef[] = [
    { key: `km-${y}-${mm}`, title: `Kilometers in ${month}`, unit: "km", start: ymd(y, m, 1), end: ymd(y, m + 1, 1), kind: "km" },
    { key: `climb-${y}-${mm}`, title: `Hoogtemeters in ${month}`, unit: "m", start: ymd(y, m, 1), end: ymd(y, m + 1, 1), kind: "climb" },
  ];
  if ((m === 12 && d <= 24) || (m === 11 && d >= 15)) {
    out.push({ key: `advent-${y}`, title: "Adventsloop (dagen op rij)", unit: "dagen", start: ymd(y, 12, 1), end: ymd(y, 12, 25), kind: "days" });
  }
  if (m >= 6 && m <= 8) {
    out.push({ key: `summer-${y}`, title: "Zomer van 300 km", unit: "km", start: ymd(y, 6, 1), end: ymd(y, 9, 1), kind: "km" });
  }
  return out;
}

/** Stand op een ranglijst uit je runs (al zonder Strava-runs). */
export function boardValue(b: BoardDef, runs: RunRow[]): number {
  const inside = runs.filter((r) => {
    const day = nlDay(new Date(r.started_at));
    return day >= b.start && day < b.end;
  });
  if (b.kind === "km") return Math.round(inside.reduce((s, r) => s + Number(r.distance_meters), 0) / 100) / 10;
  if (b.kind === "climb") return Math.round(inside.reduce((s, r) => s + Number(r.elevation_gain_meters ?? 0), 0));
  // Dagen op rij vanaf de start met minstens 1 km (een gemiste dag stopt de telling).
  const perDay = new Map<string, number>();
  for (const r of inside) {
    const day = nlDay(new Date(r.started_at));
    perDay.set(day, (perDay.get(day) ?? 0) + Number(r.distance_meters));
  }
  let days = 0;
  for (let t = Date.parse(`${b.start}T12:00:00Z`); new Date(t).toISOString().slice(0, 10) < b.end; t += 86_400_000) {
    if ((perDay.get(new Date(t).toISOString().slice(0, 10)) ?? 0) < 1000) break;
    days++;
  }
  return days;
}

// Basisfilter voor bijnamen. Sem kan dit uitbreiden; ongepaste namen kan hij ook in Supabase verwijderen.
const BLOCKED = ["kut", "lul", "neuk", "hoer", "kanker", "tering", "tyfus", "fuck", "shit", "bitch", "admin", "moderator", "runwise", "kadans", "strava"];

/** Foutmelding als de bijnaam niet mag, anders null. */
export function nicknameError(raw: unknown): string | null {
  const s = String(raw ?? "").trim();
  if (s.length < 2 || s.length > 24) return "Kies een bijnaam van 2 tot 24 tekens.";
  if (!/^[\p{L}\p{N} ._-]+$/u.test(s)) return "Gebruik alleen letters, cijfers, spaties, punten, streepjes of liggende streepjes.";
  const plain = s.toLowerCase().replace(/[^a-z0-9]/g, "");
  if (BLOCKED.some((w) => plain.includes(w))) return "Kies een andere bijnaam.";
  if (/@|https?:|www\./i.test(s)) return "Geen e-mailadres of website in je bijnaam.";
  return null;
}

const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // zonder 0/O en 1/I

function cryptoRandom(): number {
  const a = new Uint32Array(1);
  crypto.getRandomValues(a);
  return a[0] / 2 ** 32;
}

/** Willekeurige vriendcode van 6 tekens. */
export function friendCode(rand: () => number = cryptoRandom): string {
  let out = "";
  for (let i = 0; i < 6; i++) out += CODE_CHARS[Math.floor(rand() * CODE_CHARS.length)];
  return out;
}
