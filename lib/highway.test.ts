import assert from "node:assert/strict";
import test from "node:test";
import { servicesVerdict, unitTone, type HighwayState, type HighwayUnit } from "./highway.ts";

// Minimal HighwayState builder: every test only cares about `present`,
// `tracked` and `units`, so the rest is filled with the "nothing readable"
// defaults servicesVerdict never inspects.
function state(units: HighwayUnit[], overrides: Partial<HighwayState> = {}): HighwayState {
  return {
    tracked: true,
    present: true,
    health: "unknown",
    healthWhy: null,
    version: null,
    versionSrc: null,
    latest: null,
    updateAvailable: false,
    binPath: null,
    binSize: null,
    binMtime: null,
    unitsTotal: null,
    unitsActive: null,
    unitsFailed: null,
    units,
    pid: null,
    cpuPct: null,
    rss: null,
    threads: null,
    fds: null,
    procUptime: null,
    meshIface: null,
    meshRxBps: null,
    meshTxBps: null,
    meshRxTotal: null,
    meshTxTotal: null,
    meshDrops: null,
    qdisc: null,
    qdiscDrops: null,
    congestion: null,
    nftTables: null,
    journalErr: null,
    journalWarn: null,
    journalTail: [],
    legacyAgent: false,
    ...overrides,
  };
}

function unit(name: string, partial: Partial<HighwayUnit>): HighwayUnit {
  return { name, state: null, sub: null, restarts: null, memory: null, activeFor: null, ...partial };
}

test("no highway node, or node tracking off, is idle rather than red", () => {
  assert.equal(servicesVerdict(null).tone, "idle");
  assert.equal(servicesVerdict(state([], { present: false })).tone, "idle");
  assert.equal(servicesVerdict(state([], { tracked: false })).tone, "idle");
});

test("present with no unit rows falls back to whether the process itself is running", () => {
  assert.equal(servicesVerdict(state([])).tone, "crit");
  assert.equal(servicesVerdict(state([])).label, "Not running");
  assert.equal(servicesVerdict(state([], { pid: 4821 })).tone, "warn");
});

test("an inactive unit -- one deliberately not needed -- never turns the verdict red", () => {
  const v = servicesVerdict(
    state([unit("hway-relayer.service", { state: "active" }), unit("mosaic-extra.service", { state: "inactive" })])
  );
  assert.equal(v.tone, "ok");
  assert.equal(v.activeCount, 1);
  assert.equal(v.inactiveCount, 1);
  assert.equal(v.failedCount, 0);
});

test("any failed unit turns the whole verdict red, even alongside healthy ones", () => {
  const v = servicesVerdict(
    state([
      unit("hway-relayer.service", { state: "active" }),
      unit("hway-logrotate.service", { state: "failed" }),
      unit("nebula.service", { state: "inactive" }),
    ])
  );
  assert.equal(v.tone, "crit");
  assert.equal(v.failedCount, 1);
  assert.equal(v.label, "1 service failed");
});

test("a crash-looping unit (active, restarts >= 3) is amber, not red, when nothing has failed", () => {
  const v = servicesVerdict(state([unit("hway-monitor.service", { state: "active", restarts: 5 })]));
  assert.equal(v.tone, "warn");
  assert.match(v.label, /restarting repeatedly/);
});

test("all active, no failures, no crash loops reads as one clean green verdict", () => {
  const v = servicesVerdict(
    state([
      unit("hway-relayer.service", { state: "active", restarts: 0 }),
      unit("hway-otel-agent.service", { state: "active", restarts: 1 }),
    ])
  );
  assert.equal(v.tone, "ok");
  assert.equal(v.label, "All running services are okay");
  assert.equal(v.activeCount, 2);
});

// servicesVerdict's per-unit classification must stay identical to the one
// the advanced HighwayPanel table colours each row with -- this is the
// contract the aggregator is built on, not just a coincidence.
test("servicesVerdict's active/failed/looping/idle buckets match unitTone exactly", () => {
  const units = [
    unit("a", { state: "failed" }),
    unit("b", { state: "active", restarts: 3 }),
    unit("c", { state: "active", restarts: 0 }),
    unit("d", { state: "inactive" }),
  ];
  assert.deepEqual(
    units.map(unitTone),
    ["crit", "warn", "ok", "idle"]
  );
  const v = servicesVerdict(state(units));
  assert.equal(v.tone, "crit"); // the failed unit dominates
  assert.equal(v.failedCount, 1);
});
