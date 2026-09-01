import assert from "node:assert/strict";
import test from "node:test";
import { readSensors } from "./dashboard-data.ts";

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
