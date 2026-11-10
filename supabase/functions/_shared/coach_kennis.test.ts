// node --experimental-strip-types supabase/functions/_shared/coach_kennis.test.ts
import assert from "node:assert/strict";
import {
  fmtTempo, kledingAntwoord, laatsteAntwoord, leesClaude, maandAntwoord, nlDag, runsVanWeek,
  tempoAntwoord, vandaagAntwoord, wedstrijdAntwoord, weekAntwoord, type Run,
} from "./coach_kennis.ts";

// Woensdag 11 november 2026, 12:00 Nederlandse tijd.
const nu = new Date("2026-11-11T11:00:00Z");
assert.equal(nlDag(nu).dag, "2026-11-11");
assert.equal(nlDag(nu).wd, 2);
// Zondagavond laat in NL is in UTC nog zondag; maandag 00:30 NL is zondag in UTC.
assert.equal(nlDag(new Date("2026-11-08T23:30:00Z")).dag, "2026-11-09");

const run = (dag: string, kmx: number, tempo = 330, hr?: number): Run => ({
  started_at: `${dag}T07:00:00Z`, distance_meters: kmx * 1000, moving_time_seconds: Math.round(kmx * tempo), average_heart_rate: hr ?? null,
});
const runs: Run[] = [
  run("2026-11-10", 8, 320, 150), run("2026-11-09", 5),       // deze week 13 km
  run("2026-11-07", 12, 360), run("2026-11-05", 6), run("2026-11-03", 5), // vorige week 23 km
  run("2026-10-29", 10), run("2026-10-27", 5), run("2026-10-20", 8), run("2026-10-22", 6),
];

assert.equal(runsVanWeek(runs, nu, 0).length, 2);
assert.equal(runsVanWeek(runs, nu, 1).length, 3);
const w = weekAntwoord(runs, nu)!;
assert.match(w, /13,0 km in 2 runs/);
assert.match(w, /43% minder dan vorige week \(23,0 km\)/);
assert.equal(weekAntwoord([], nu), null);

const l = laatsteAntwoord(runs)!;
assert.match(l, /8,0 km/);
assert.match(l, /5:20\/km/);
assert.match(l, /hartslag: 150/);

const m = maandAntwoord(runs, nu)!;
assert.match(m, /deze week: 13,0 km in 2 runs/);
assert.match(m, /vorige week: 23,0 km in 3 runs/);

const v = vandaagAntwoord(runs, [{ session_date: "2026-11-11", title: "Intervallen 6× 800 m" }], nu);
assert.match(v, /Intervallen 6× 800 m/);
const v2 = vandaagAntwoord([run("2026-11-10", 15), run("2026-11-08", 5), run("2026-11-06", 5)], [], nu);
assert.match(v2, /rustdag/);

const t = tempoAntwoord(runs)!;
assert.match(t, /5:30\/km/);
assert.equal(tempoAntwoord([run("2026-11-10", 5)]), null);

const wd = wedstrijdAntwoord([{ name: "Zevenheuvelenloop", race_date: "2026-11-15", distance_meters: 15000, goal_time_seconds: 4800 }], runs, nu)!;
assert.match(wd, /nog 4 dagen/);
assert.match(wd, /5:20\/km/);
assert.equal(wedstrijdAntwoord([], runs, nu), null);

const k = kledingAntwoord({ temp: 4, gevoel: 1, wind: 30, regen: 0 });
assert.match(k, /twee laagjes/);
assert.match(k, /winddicht/);
const k2 = kledingAntwoord({ temp: 26, gevoel: 27, wind: 5, regen: 0 });
assert.match(k2, /korte broek en een luchtig shirt/);
assert.match(k2, /zonnebrand/);

assert.equal(fmtTempo(359.7), "6:00/km");

const c = leesClaude('Hier: {"antwoord":"Doe dit.","soort":"antwoord","algemeen":"Algemeen advies voor iedereen die dit vraagt.","onderwerp":"Test","categorie":"Training","vragen":["Vraag 1?","x"],"trefwoorden":["a1","b2"]}');
assert.equal(c.soort, "antwoord");
assert.equal(c.categorie, "training");
assert.deepEqual(c.vragen, ["Vraag 1?"]);
const p = leesClaude('{"antwoord":"Je run was top.","soort":"persoonlijk","algemeen":"iets"}');
assert.equal(p.algemeen, null);
const kapot = leesClaude("Gewoon tekst zonder json");
assert.equal(kapot.antwoord, "Gewoon tekst zonder json");
assert.equal(kapot.algemeen, null);

console.log("coach_kennis: alle tests geslaagd");
