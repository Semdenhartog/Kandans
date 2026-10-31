import assert from "node:assert/strict";
import { isKadansUpload, runToGpx } from "./gpx.ts";

const gpx = runToGpx({
  name: "Ochtendrun <Kadans>",
  startedAt: "2026-10-31T07:00:00Z",
  streams: { t: [0, 10, 20], ll: [[52.1, 5.6], [52.1001, 5.6], [52.1002, 5.6]], alt: [10, 11, 12], hr: [120, 130, 0], cad: [170, 172, 0] },
})!;
assert.ok(gpx.includes('<trkpt lat="52.100000" lon="5.600000"><ele>10.0</ele><time>2026-10-31T07:00:00.000Z</time>'));
assert.ok(gpx.includes("<time>2026-10-31T07:00:10.000Z</time>"));
assert.ok(gpx.includes("<gpxtpx:hr>130</gpxtpx:hr><gpxtpx:cad>86</gpxtpx:cad>"));
assert.ok(gpx.includes("Ochtendrun &lt;Kadans&gt;"));
assert.equal((gpx.match(/<trkpt/g) ?? []).length, 3);
assert.equal(runToGpx({ name: "x", startedAt: "2026-10-31T07:00:00Z", streams: { t: [0, 10], d: [0, 30] } }), null);
assert.ok(isKadansUpload("kadans-123"));
assert.ok(!isKadansUpload("garmin_456"));
assert.ok(!isKadansUpload(null));
console.log("gpx: alle tests geslaagd");
