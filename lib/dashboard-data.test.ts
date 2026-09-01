import assert from "node:assert/strict";
import test from "node:test";
import { nearestSampleIndex, readSensors } from "./dashboard-data.ts";

test("readSensors sorts hottest first and drops unreadable entries", () => {
  const sensors = readSensors({
    sensors: { nvme: 68, cpu_package: 74, chipset: "n/a", core_0: 71 },
  });
  assert.deepEqual(sensors, [
    { label: "cpu_package", celsius: 74 },
    { label: "core_0", celsius: 71 },
    { label: "nvme", celsius: 68 },
  ]);
});

test("readSensors yields nothing for a missing or malformed sensors key", () => {
  assert.deepEqual(readSensors(null), []);
  assert.deepEqual(readSensors({}), []);
  assert.deepEqual(readSensors({ sensors: "not an object" }), []);
});

test("hovering a trace reads the nearest sample, including across a gap", () => {
  // Samples plotted at 0, 100, 400: the 100-400 span is a gap where the machine
  // sent nothing. A pointer inside it must read one of the two real readings.
  const xs = [0, 100, 400];
  assert.equal(nearestSampleIndex(xs, 0), 0);
  assert.equal(nearestSampleIndex(xs, 104), 1);   // just past a sample reads it
  assert.equal(nearestSampleIndex(xs, 240), 1);   // inside the gap, nearer 100
  assert.equal(nearestSampleIndex(xs, 260), 2);   // inside the gap, nearer 400
  assert.equal(nearestSampleIndex(xs, 999), 2);   // clamped to the last reading
});
