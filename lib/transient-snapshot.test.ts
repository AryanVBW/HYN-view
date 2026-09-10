import test from "node:test";
import assert from "node:assert/strict";
import {
  acceptTransientSnapshot, readTransientSnapshot, SNAPSHOT_MAX_BYTES,
  SNAPSHOT_TTL_MS, snapshotMetric, storeTransientSnapshot,
} from "./transient-snapshot.ts";

test("requested telemetry is authorized with metadata only and never passed to the DB", async () => {
  const payload = { agent_version: "1.10.0", processes: { secret: "private process detail" } };
  let saved = false;
  const result = await acceptTransientSnapshot({ p_node_token: "node-secret", p_payload: payload }, async (name, args) => {
    assert.equal(name, "hyn_local_heartbeat");
    assert.deepEqual(args, { p_node_token: "node-secret", p_agent_version: "1.10.0" });
    return { data: { node_id: "node-a", node_status: "active" }, error: null };
  }, (id, value) => { assert.equal(id, "node-a"); assert.equal(value, payload); saved = true; });
  assert.equal(result.status, 200);
  assert.equal(saved, true);
});

test("invalid, revoked and suspended credentials never enter the transient store", async () => {
  for (const status of ["paused", "suspended", "revoked"]) {
    const result = await acceptTransientSnapshot({ p_node_token: "token", p_payload: {} }, async () => ({
      data: { node_id: "node-a", node_status: status }, error: null,
    }), () => assert.fail("unauthorized payload was cached"));
    assert.equal(result.status, 403);
  }
  const result = await acceptTransientSnapshot({ p_node_token: "invalid", p_payload: {} }, async () => ({
    data: null, error: { message: "invalid node token" },
  }), () => assert.fail("invalid token was accepted"));
  assert.equal(result.status, 401);
});

test("oversized payload is rejected before any database query", async () => {
  const result = await acceptTransientSnapshot({ p_payload: { data: "x".repeat(SNAPSHOT_MAX_BYTES) } }, async () => {
    assert.fail("oversized payload caused a database query");
  });
  assert.equal(result.status, 413);
});

test("transient snapshots are isolated, replaced, and expire without durable fallback", () => {
  storeTransientSnapshot("a", { value: 1 }, 1000);
  storeTransientSnapshot("b", { value: 2 }, 1000);
  assert.deepEqual(readTransientSnapshot("a", 1001), { value: 1 });
  assert.equal(readTransientSnapshot("unknown", 1001), null);
  storeTransientSnapshot("a", { value: 3 }, 2000);
  assert.deepEqual(readTransientSnapshot("a", 2001), { value: 3 });
  assert.deepEqual(readTransientSnapshot("b", 2001), { value: 2 });
  assert.equal(readTransientSnapshot("a", 2000 + SNAPSHOT_TTL_MS), null);
});

test("snapshot cache evicts older readings at its memory budget", () => {
  const payload = { data: "x".repeat(200_000) };
  for (let i = 0; i < 50; i++) storeTransientSnapshot(`budget-${i}`, payload, 10_000);
  assert.equal(readTransientSnapshot("budget-0", 10_001), null);
  assert.deepEqual(readTransientSnapshot("budget-49", 10_001), payload);
});

test("snapshot conversion preserves missing sensors and measured values", () => {
  const metric = snapshotMetric("node", { cpu: { pct: 42 }, network: { rx_bps: 125 }, sensors: { cpu: null }, memory: { pct: 0 } });
  assert.equal(metric.cpu_pct, 42);
  assert.equal(metric.mem_pct, 0);
  assert.equal(metric.cpu_temp_c, null);
  assert.equal(metric.net_rx_bps, 125);
  assert.deepEqual(metric.sensors, { cpu: null });
});
