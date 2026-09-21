import assert from "node:assert/strict";
import test from "node:test";
import { concernsFor, formatBytes, summariseFleet, toFleetServers } from "./fleet-monitor.ts";
import type { AlertEvent, Metric, Node, Speedtest } from "./types.ts";

const NOW = Date.parse("2026-09-21T12:00:00Z");
const ago = (seconds: number) => new Date(NOW - seconds * 1000).toISOString();

function node(over: Partial<Node> & { id: string }): Node {
  return {
    owner: "owner-1", name: over.id, hostname: `${over.id}.local`, os: "Ubuntu 24.04",
    agent_version: "1.10.0", is_demo: false, revoked: false, created_at: ago(86400),
    last_seen_at: ago(30), status: "active", paused_until: null, status_reason: null,
    config: {}, last_config_pull_at: ago(30), last_heartbeat_at: ago(30), ...over,
  } as Node;
}
function metric(nodeId: string, over: Partial<Metric> = {}): Metric {
  return { id: 1, node_id: nodeId, ts: ago(30), cpu_pct: 10, cpu_temp_c: 45, mem_pct: 40,
    disk_pct: 50, net_rx_bps: 1_000_000, net_tx_bps: 500_000, ...over } as Metric;
}

test("a healthy fleet reports no concerns and aggregates live throughput", () => {
  const nodes = [node({ id: "a" }), node({ id: "b" })];
  const servers = toFleetServers({
    nodes,
    metrics: [metric("a"), metric("b")],
    speedtests: [],
    alerts: [],
    bytesByNode: { a: 2_000_000_000, b: 1_000_000_000 },
    now: NOW,
  });
  const summary = summariseFleet(servers);
  assert.equal(summary.total, 2);
  assert.equal(summary.reporting, 2);
  assert.equal(summary.attention.length, 0, "a healthy fleet must not manufacture work");
  // 1.5 MB/s combined down => 12 Mbit/s. Aggregate, not per-server.
  assert.equal(summary.downMbps, 16);
  assert.equal(summary.bytes, 3_000_000_000);
  assert.equal(summary.hottestC, 45);
});

test("only the newest reading per server is used", () => {
  const servers = toFleetServers({
    nodes: [node({ id: "a" })],
    metrics: [metric("a", { ts: ago(600), cpu_temp_c: 90 }), metric("a", { ts: ago(30), cpu_temp_c: 41 })],
    speedtests: [
      { id: 1, node_id: "a", ts: ago(900), down_bps: 1, up_bps: 1, latency_ms: 9, note: null } as Speedtest,
      { id: 2, node_id: "a", ts: ago(60), down_bps: 99, up_bps: 9, latency_ms: 5, note: null } as Speedtest,
    ],
    alerts: [],
    now: NOW,
  });
  assert.equal(servers[0].metric?.cpu_temp_c, 41, "a stale hot reading must not outrank the newest one");
  assert.equal(servers[0].speedtest?.down_bps, 99);
});

test("a quiet server outranks a merely warm one, and each says why", () => {
  const quiet = node({ id: "quiet", last_heartbeat_at: ago(1200), last_seen_at: ago(1200) });
  const hot = node({ id: "hot" });
  const servers = toFleetServers({
    nodes: [hot, quiet],
    metrics: [metric("hot", { disk_pct: 91, cpu_temp_c: 84 }), metric("quiet")],
    speedtests: [],
    alerts: [],
    now: NOW,
  });
  const summary = summariseFleet(servers);
  assert.equal(summary.quiet, 1);
  assert.equal(summary.notReporting, 1);
  assert.equal(summary.attention[0].server.node.id, "quiet", "silence is the worst signal and must lead");
  const labels = summary.attention.map((row) => row.concerns.map((c) => c.label).join(","));
  assert.match(labels[0], /quiet/);
  assert.match(labels[1], /disk 91%/);
  assert.match(labels[1], /84°C/);
});

test("resolved alerts are not open work, and criticals are counted separately", () => {
  const alerts: AlertEvent[] = [
    { id: 1, node_id: "a", ts: ago(60), rule: "disk", severity: "crit", message: "full", resolved: false },
    { id: 2, node_id: "a", ts: ago(60), rule: "mem", severity: "warn", message: "high", resolved: false },
    { id: 3, node_id: "a", ts: ago(60), rule: "old", severity: "crit", message: "cleared", resolved: true },
  ];
  const servers = toFleetServers({ nodes: [node({ id: "a" })], metrics: [metric("a")], speedtests: [], alerts, now: NOW });
  const summary = summariseFleet(servers);
  assert.equal(summary.openAlerts, 2);
  assert.equal(summary.criticalAlerts, 1);
  assert.deepEqual(
    concernsFor(servers[0]).map((c) => c.label),
    ["1 critical alert", "1 warning"],
  );
});

test("suspended and revoked machines are stated, not silently dropped", () => {
  const servers = toFleetServers({
    nodes: [node({ id: "s", status: "suspended" }), node({ id: "r", revoked: true })],
    metrics: [], speedtests: [], alerts: [], now: NOW,
  });
  const summary = summariseFleet(servers);
  assert.equal(summary.total, 2);
  assert.equal(summary.attention.length, 2);
  const all = summary.attention.flatMap((row) => row.concerns.map((c) => c.label));
  assert.ok(all.includes("suspended"));
  assert.ok(all.includes("credential revoked"));
});

test("an absent reading is never rendered as zero", () => {
  const servers = toFleetServers({ nodes: [node({ id: "a" })], metrics: [], speedtests: [], alerts: [], now: NOW });
  const summary = summariseFleet(servers);
  assert.equal(summary.hottestC, null);
  assert.equal(summary.peakCpuPct, null);
  assert.equal(summary.bytes, null);
  assert.equal(formatBytes(null), "—");
  assert.equal(formatBytes(1_500_000_000), "1.5 GB");
  assert.equal(formatBytes(999), "999 B");
});
