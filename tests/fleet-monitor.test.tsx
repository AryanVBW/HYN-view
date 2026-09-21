import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { AppRouterContext } from "next/dist/shared/lib/app-router-context.shared-runtime.js";
import { FleetMonitor } from "../components/maintainer/fleet-monitor";
import { toFleetServers } from "../lib/fleet-monitor";
import type { AlertEvent, Metric, Node } from "../lib/types";

const router = {
  back() {}, forward() {}, refresh() {}, hmrRefresh() {},
  push() {}, replace() {}, prefetch() {},
};
const render = (child: React.ReactNode) =>
  renderToStaticMarkup(<AppRouterContext.Provider value={router}>{child}</AppRouterContext.Provider>);

const NOW = Date.parse("2026-09-21T12:00:00Z");
const ago = (seconds: number) => new Date(NOW - seconds * 1000).toISOString();
const node = (over: Partial<Node> & { id: string }): Node => ({
  owner: "owner-1", name: over.id, hostname: `${over.id}.local`, os: "Ubuntu 24.04",
  agent_version: "1.10.0", is_demo: false, revoked: false, created_at: ago(86400),
  last_seen_at: ago(30), status: "active", paused_until: null, status_reason: null,
  config: {}, last_config_pull_at: ago(30), last_heartbeat_at: ago(30), ...over,
} as Node);
const metric = (nodeId: string, over: Partial<Metric> = {}): Metric => ({
  id: 1, node_id: nodeId, ts: ago(30), cpu_pct: 12, cpu_temp_c: 44, mem_pct: 38,
  disk_pct: 41, net_rx_bps: 1_000_000, net_tx_bps: 250_000, ...over,
} as Metric);

test("the fleet view shows every server with its own send controls", () => {
  const servers = toFleetServers({
    nodes: [node({ id: "alpha" }), node({ id: "beta" })],
    metrics: [metric("alpha"), metric("beta")],
    speedtests: [], alerts: [], bytesByNode: { alpha: 2_000_000_000 }, now: NOW,
  });
  const html = render(<FleetMonitor servers={servers} />);
  assert.match(html, /alpha/);
  assert.match(html, /beta/);
  assert.match(html, /every server \(2\)/);
  // A per-server notify and report control each, for both servers, is the
  // requirement -- the aria-labels name the server so they are distinguishable.
  assert.match(html, /Send a notification for alpha/);
  assert.match(html, /Send a report for alpha/);
  assert.match(html, /Send a notification for beta/);
  assert.match(html, /Send a report for beta/);
  assert.match(html, /2\.0 GB/);
});

test("a healthy fleet does not invent work, and unmeasured values are not zero", () => {
  const servers = toFleetServers({
    nodes: [node({ id: "alpha" })], metrics: [metric("alpha")], speedtests: [], alerts: [], now: NOW,
  });
  const html = render(<FleetMonitor servers={servers} />);
  assert.match(html, /Nothing needs action right now/);
  // No speed test and no bandwidth recorded for this server.
  assert.match(html, /—/);
  assert.doesNotMatch(html, /0 Mbps \/ 0 Mbps/);
});

test("a quiet server and a critical alert are surfaced with the reason", () => {
  const alerts: AlertEvent[] = [
    { id: 1, node_id: "hot", ts: ago(60), rule: "disk", severity: "crit", message: "disk full", resolved: false },
  ];
  const servers = toFleetServers({
    nodes: [node({ id: "hot" }), node({ id: "gone", last_heartbeat_at: ago(3600), last_seen_at: ago(3600) })],
    metrics: [metric("hot", { disk_pct: 97 }), metric("gone")],
    speedtests: [], alerts, now: NOW,
  });
  const html = render(<FleetMonitor servers={servers} />);
  assert.match(html, /needs attention \(2\)/);
  assert.match(html, /quiet/);
  assert.match(html, /1 critical alert/);
  assert.match(html, /disk 97%/);
});

test("an empty fleet explains itself instead of rendering a bare table", () => {
  const html = render(<FleetMonitor servers={[]} />);
  assert.match(html, /No servers are visible to this account yet/);
  assert.match(html, /Nothing needs action right now/);
});
