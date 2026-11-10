// node --experimental-strip-types supabase/functions/_shared/race_import.test.ts
import assert from "node:assert/strict";
import {
  dateInTitle, heuristicExtract, heuristicRaces, isCandidate, withPlace, kindOf, parseExtraction, parseSru, pointFromWkt, raceKey, rdToWgs84,
  statusOf, type SruRecord, sameRace, mergeRows, type RaceRow,
} from "./race_import.ts";

const rec = (title: string, type = "evenementenvergunning", geometry: string | null = null): SruRecord => ({
  id: "gmb-x", title, municipality: "Test", type, modified: "2026-11-01", geometry, url: "u",
});

// RD → WGS84: Amersfoort (Onze Lieve Vrouwetoren) 155000/463000 = 52.1552, 5.3872; Dam Amsterdam ±121400/487400.
{
  const p = rdToWgs84(155000, 463000);
  assert.ok(Math.abs(p.lat - 52.15517) < 1e-4 && Math.abs(p.lon - 5.38721) < 1e-4);
  const dam = rdToWgs84(121400, 487400);
  assert.ok(Math.abs(dam.lat - 52.3731) < 0.002 && Math.abs(dam.lon - 4.8924) < 0.002, JSON.stringify(dam));
}
assert.deepEqual(pointFromWkt(null), null);
assert.ok(pointFromWkt("POINT (116455.849 481936.921)")!.lat > 52.2);
assert.ok(pointFromWkt("MULTIPOLYGON(((234781 448147,235152 447353)))")!.lon > 6.5);
assert.equal(pointFromWkt("POINT(5.1 52.1)"), null); // geen RD

// Kandidaten
const yes = [
  "Toestemming voor de hardloopwedstrijd ‘Kerstcross 2026’ op zaterdag 26 december 2026 met start- en eindpunt de kantine",
  "Toestemming voor de Oosterbos Trailrun op 7 maart 2027 aan Herenstreek 130 te Nieuw-Dordrecht",
  "Kennisgeving aanvraag Evenementenvergunning voor Halve Marathon Zoetermeer op 24 januari 2027, Scheglaan 12",
  "Harbour Run 2026",
  "Verleende evenementenvergunning voor het organiseren van het hardloopevenement ''De Beuningse Plasloop'' op zondag 4 oktober 2026",
];
for (const t of yes) assert.ok(isCandidate(rec(t)), t);
const no = [
  rec("Besluit maatregelen ASML Marathon en Marathon horecafeesten 2026"),
  rec("Aanvraag vergunning voor eerste marathon op natuurijs 2026/2027, Scholtenhagenweg 40c"),
  rec("Kennisgeving besluit op Evenementenvergunning - Run-Bike-Run Borne - 2026"),
  rec("Ontvangen melding over organiseren van een 2 daagse paardenrit door Endurance Marathon Someren"),
  rec("Uitstel beslissing op een aanvraag voor een omgevingsvergunning, de Run 5, 5684PW Best", "omgevingsvergunning"),
  rec("Toestemming voor de Halve Marathon", "verkeersbesluit of -mededeling"),
  rec("Gemeente Achtkarspelen - melding Besloten Sint Maarten optocht"),
];
for (const r of no) assert.ok(!isCandidate(r), r.title);

// Status en soort
assert.equal(statusOf(rec("Toestemming voor de Oosterbos Trailrun")), "verleend");
assert.equal(statusOf(rec("Melding hardloopwedstrijd ‘Rondje Beusichem’", "evenementmelding")), "melding");
assert.equal(statusOf(rec("Kennisgeving aanvraag Evenementenvergunning voor Halve Marathon Zoetermeer")), "aangevraagd");
assert.equal(kindOf("Halve Marathon Zoetermeer", ""), "halve");
assert.equal(kindOf("de Halve van Ell", ""), "halve");
assert.equal(kindOf("TCS Amsterdam Marathon", ""), "marathon");
assert.equal(kindOf("Oosterbos Trailrun", ""), "trail");
assert.equal(kindOf("Kerstcross", ""), "cross");
assert.equal(kindOf("Mosselloop", ""), "loop");

// Sleutel: zelfde wedstrijd uit aanvraag en verlening
assert.equal(raceKey("Olympisch Stadionloop 2026", "2026-11-08"), raceKey("de Olympisch Stadionloop", "2026-11-08"));
assert.notEqual(raceKey("Mosselloop", "2026-11-07"), raceKey("Mosselloop", "2027-11-06"));

// Datums en reserve zonder AI
assert.equal(dateInTitle("Halve Marathon Zoetermeer op 24 januari 2027, Scheglaan"), "2027-01-24");
assert.equal(dateInTitle("Gewoon Coop Loop hardloopwedstrijd op 24-01-2027"), "2027-01-24");
assert.equal(dateInTitle("CrossDuathlon, NightTrail en Trailrun van 12 t/m 13 dec 2026."), "2026-12-13"); // eerste volledige datum
assert.equal(dateInTitle("Urban Trail Rotterdam 2026"), null);
assert.deepEqual(heuristicExtract("Toestemming voor de hardloopwedstrijd ‘Kerstcross 2026’ op zaterdag 26 december 2026"), {
  name: "Kerstcross",
  date: "2026-12-26",
});
assert.equal(heuristicExtract("Harbour Run 2026"), null);

// AI-antwoord streng lezen
const ex = parseExtraction('Hier: [{"i":0,"races":[{"name":"Samancross","date":"2027-01-23","place":"Burgh-Haamstede"},{"name":"x","date":"2027-13-01"}]},{"i":1,"races":[]},{"oops":1}]');
assert.equal(ex.length, 2);
assert.equal(ex[0].races[0].name, "Samancross");
assert.equal(ex[0].races[1], undefined); // naam te kort → weg
assert.deepEqual(parseExtraction("geen json"), []);

// SRU-XML lezen
const xml = `<sru:numberOfRecords>2</sru:numberOfRecords><sru:record><dcterms:identifier>gmb-2026-523965</dcterms:identifier>
<dcterms:title>Toestemming voor de Oosterbos Trailrun op 7 maart 2027 aan Herenstreek 130 te Nieuw-Dordrecht</dcterms:title>
<dcterms:type scheme="OVERHEIDop.Rubriek">evenementenvergunning</dcterms:type><dcterms:creator scheme="OVERHEID.Gemeente">Emmen</dcterms:creator>
<dcterms:modified>2026-11-10</dcterms:modified><overheidwetgeving:locatiepunt><overheidwetgeving:geometrie>POINT(262323.027 530538.428)</overheidwetgeving:geometrie></overheidwetgeving:locatiepunt>
<gzd:preferredUrl>https://zoek.officielebekendmakingen.nl/gmb-2026-523965.html</gzd:preferredUrl></sru:record>
<sru:record><dcterms:identifier>gmb-2</dcterms:identifier><dcterms:title>Light &amp;amp; Kids Run</dcterms:title></sru:record>`;
const parsed = parseSru(xml);
assert.equal(parsed.total, 2);
assert.equal(parsed.records[0].municipality, "Emmen");
assert.equal(parsed.records[0].type, "evenementenvergunning");
assert.ok(parsed.records[0].geometry!.startsWith("POINT"));
assert.equal(parsed.records[1].title, "Light & Kids Run");

// Herkenning zonder AI op echte titels
const names = (t: string) => heuristicRaces(t).map((r) => `${r.name}|${r.date}`);
assert.deepEqual(names("Toestemming voor de Oosterbos Trailrun op 7 maart 2027 aan Herenstreek 130 te Nieuw-Dordrecht"), ["Oosterbos Trailrun|2027-03-07"]);
assert.deepEqual(names("Kennisgeving aanvraag Evenementenvergunning voor Halve Marathon Zoetermeer op 24 januari 2027, Scheglaan 12"), ["Halve Marathon Zoetermeer|2027-01-24"]);
assert.deepEqual(names("Besluit Evenementenvergunning Cross for the Crocus 2027 op 21-02-2027"), ["Cross for the Crocus|2027-02-21"]);
assert.deepEqual(names("Ontvangst melding voor recreatieve loop Achtje van Atledo 25-10-2026 op locatie Kanovijver"), ["Achtje van Atledo|2026-10-25"]);
assert.deepEqual(names("Kennisgeving ontvangst aanvraag NIGHT TRAIL ENSCHEDE op 10 december 2026, Willem Wilminkplein"), ["Night Trail Enschede|2026-12-10"]);
assert.deepEqual(names("Gemeente Haarlem, ingekomen aanvraag, 0392-2026-0155397, het evenement Urban Trail Leiden, op 08-11-2026 08:00 t/m 14:00"), ["Urban Trail Leiden|2026-11-08"]);
assert.deepEqual(names("Op 06-07-2026 00:00 hebben wij een aanvraag ontvangen voor het houden van een evenement (Cross Country op 19 en 20 september 2026 )"), ["Cross Country|2026-09-20"]);
assert.deepEqual(
  names("Verleende evenementenvergunning: Diverse hardloopwedstrijden van AV Delta Sport op Samancross 23 januari 2027, Pannenkoekenmolenloop 13 maart 2027 en Mosselloop 6 november 2027"),
  ["Samancross|2027-01-23", "Pannenkoekenmolenloop|2027-03-13", "Mosselloop|2027-11-06"],
);
assert.deepEqual(names("Ontvangen aanvraag vergunning, het organiseren van hardloopevenement op 8 november 2026, Voorhof 2"), []);
assert.equal(withPlace("Halve Marathon", "Nieuwkoop"), "Halve Marathon Nieuwkoop");
assert.equal(withPlace("Oosterbos Trailrun", "Emmen"), "Oosterbos Trailrun");

assert.equal(kindOf("Mosselloop", "… Halve marathon …", false), "loop");
assert.equal(kindOf("Run Scherpenzeel", "hardloopevenement halve marathon", true), "halve");
assert.ok(sameRace("Amersfoort Night Run", "Amersoort Night Run"));
assert.ok(sameRace("Olympisch Stadionloop", "de Olympisch Stadionloop"));
assert.ok(!sameRace("Santa Run Gouda", "Night Run Gouda"));
assert.deepEqual(names("Aanvraag evenementenvergunning Hang-On Run. Voor meer info op 21 november 2026"), ["Hang-On Run|2026-11-21"]);
const row = (name: string, status: "aangevraagd" | "verleend"): RaceRow => ({ key: name, name, race_date: "2026-11-13", municipality: "Amersfoort", place: null, lat: 1, lon: 1, kind: "loop", status, source_id: "x", source_url: "u", source_title: "t", published: "2026-11-01" });
const m = mergeRows([row("Amersfoort Night Run", "aangevraagd"), row("Amersoort Night Run", "verleend")]);
assert.equal(m.length, 1);
assert.equal(m[0].status, "verleend");
assert.equal(m[0].name, "Amersfoort Night Run");

console.log("race_import: alle tests geslaagd");
