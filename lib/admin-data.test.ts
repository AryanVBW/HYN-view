import assert from "node:assert/strict";
import test from "node:test";
import { fleetFreshness, neverLinked, toFleetTrend } from "./admin-data.ts";

test("fleet trend buckets real samples and averages CPU and transfer rates", () => {
  const points = toFleetTrend([
    {
      ts: "2026-08-21T00:01:00.000Z",
      cpu_pct: 20,
      net_rx_bps: 1_000_000,
      net_tx_bps: 250_000,
    },
    {
      ts: "2026-08-21T00:20:00.000Z",
      cpu_pct: 40,
      net_rx_bps: 3_000_000,
      net_tx_bps: 750_000,
    },
  ]);

  assert.equal(points.length, 1);
  assert.equal(points[0].cpu, 30);
  assert.equal(points[0].down, 16);
  assert.equal(points[0].up, 4);
});

test("fleet trend ignores invalid timestamps and keeps missing CPU honest", () => {
  const points = toFleetTrend([
    { ts: "not-a-date", cpu_pct: 99, net_rx_bps: 10, net_tx_bps: 10 },
    {
      ts: "2026-08-21T01:05:00.000Z",
      cpu_pct: null,
      net_rx_bps: null,
      net_tx_bps: null,
    },
  ]);

  assert.equal(points.length, 1);
  assert.equal(points[0].cpu, null);
  assert.equal(points[0].down, 0);
  assert.equal(points[0].up, 0);
});

test("fleet freshness allows three configured check-ins before declaring a machine quiet", () => {
  const now = Date.parse("2026-08-23T12:00:00.000Z");
  const node = {
    revoked: false,
    status: "active" as const,
    last_seen_at: "2026-08-23T11:35:00.000Z",
    config: { cloud_push_min: "10" },
  };

  assert.deepEqual(fleetFreshness(node, now), {
    key: "reporting",
    label: "late 25m",
    tone: "text-[#e8a400]",
  });
  assert.equal(
    fleetFreshness({ ...node, last_seen_at: "2026-08-23T11:29:00.000Z" }, now).key,
    "quiet",
  );
});

test("fleet freshness keeps a safe minimum window for one-minute reporting", () => {
  const now = Date.parse("2026-08-23T12:00:00.000Z");
  const state = fleetFreshness({
    revoked: false,
    status: "active",
    last_seen_at: "2026-08-23T11:50:00.000Z",
    config: { cloud_push_min: "1" },
  }, now);
  assert.equal(state.key, "reporting");
});

test("heartbeat-capable agents go quiet after three missed one-minute heartbeats", () => {
  const now = Date.parse("2026-08-24T12:00:00.000Z");
  const base = {
    revoked: false,
    status: "active" as const,
    agent_version: "1.7.0",
    last_seen_at: "2026-08-24T11:59:30.000Z",
    last_heartbeat_at: "2026-08-24T11:57:31.000Z",
    config: { cloud_push_min: "10" },
  };
  assert.deepEqual(fleetFreshness(base, now), {
    key: "reporting",
    label: "delayed 2m",
    tone: "text-[#e8a400]",
  });
  assert.equal(
    fleetFreshness({ ...base, last_heartbeat_at: "2026-08-24T11:57:00.000Z" }, now).key,
    "quiet",
  );
});

test("a machine that never checked in is named as such, and demo data is not", () => {
  // The phantom this exists for: approving a pairing code creates the node row,
  // so a client who never finished `sudo hyn link` keeps a machine that will
  // never report. It must not be confused with one that has merely gone quiet,
  // and the seeded demo node must never be offered up for deletion as one.
  assert.equal(neverLinked({ is_demo: false, ever_connected: false }), true);
  assert.equal(neverLinked({ is_demo: false, ever_connected: true }), false);
  assert.equal(neverLinked({ is_demo: true, ever_connected: false }), false);
});
