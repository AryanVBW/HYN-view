import assert from "node:assert/strict";
import test from "node:test";
import { toFleetTrend } from "./admin-data.ts";

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
