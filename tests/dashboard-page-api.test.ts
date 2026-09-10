import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import { mock, test } from "node:test";
import { createElement, cloneElement, isValidElement, type ReactNode, type ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import type { Metric, Node } from "../lib/types";
import { normalizeRelayer, SOURCE_STALE_S, type RelayerReading } from "../lib/relayer";

// Styles are built by Next; the server-render regression checks use real components.
registerHooks({ load(url, context, nextLoad) {
  if (url.endsWith(".css")) return {format: "module", source: "export default {};", shortCircuit: true};
  return nextLoad(url, context);
} });
let role = "monitor";
let mode = "simple";
let query = new URLSearchParams();
let haveMetrics = true;
let haveNodes = true;
let allowRelayers = true;
const bandwidthReads: unknown[] = [];
const server: Node = {
  id: "server", owner: "account", name: "My linked server", hostname: "gateway", os: "Ubuntu",
  agent_version: "1.11.0", is_demo: false, revoked: false, created_at: "2026-09-10T00:00:00Z",
  last_seen_at: "2026-09-11T08:00:00Z", status: "active", paused_until: null, status_reason: null,
  config: {}, last_config_pull_at: null, last_heartbeat_at: null, telemetry_mode: "cloud",
};
const metric: Metric = {
  id: 1, node_id: "server", ts: "2026-09-11T08:00:00Z", cpu_pct: 23, mem_pct: 30,
  disk_pct: 20, cpu_temp_c: 48, net_rx_bps: 1024, net_tx_bps: 512, uptime_s: 300, payload: null,
  cpu_mhz: null, cpu_model: null, cpu_steal: null, cpu_iowait: null, cpu_cores: null,
  load1: null, mem_total: null, mem_used: null, swap_used: null, net_iface: null,
  net_retrans_pm: null, latency_ms: null, net_link_mbps: null, psi_cpu: null,
  psi_mem: null, psi_io: null, tcp_estab: null, conntrack_pct: null, proc_count: null, sensors: null,
};
mock.module("next/headers", {namedExports: {cookies: async () => ({get: () => ({value: mode})})}});
mock.module("next/navigation", {namedExports: {
  redirect: (path: string) => { throw new Error(`redirect:${path}`); },
  useSearchParams: () => query,
  usePathname: () => "/dashboard",
  useRouter: () => ({refresh() {}, push() {}, replace() {}}),
}});
mock.module("../lib/supabase/config.ts", {namedExports: {isSupabaseConfigured: true, SUPABASE_URL: "https://example.test", SUPABASE_ANON_KEY: "fixture-only"}});
mock.module("../lib/supabase/server.ts", {namedExports: {
  createClient: async () => ({
    auth: {getUser: async () => ({data: {user: {id: "account", email: "test@example.test"}}})},
    rpc: async (name: string, args: unknown) => {
      if (name === "hyn_dashboard_accounts") return {data: [{id: "account", name: "My account", own: true, relayers: allowRelayers}]};
      assert.equal(name, "hyn_bandwidth_report");
      bandwidthReads.push(args);
      return {data: {sampled_at: "2026-09-11T08:00:00Z", since: "2026-09-01", iface: "eth0", ingress_bytes: "1024", egress_bytes: "2048", days: []}, error: null};
    },
    from: (table: string) => {
      const result = () => ({data: table === "profiles" ? {role, status: "active"} : table === "nodes" ? (haveNodes ? [server] : []) : table === "metrics" ? (haveMetrics ? [metric] : []) : [], error: null});
      const builder = {
        select: () => builder, eq: () => builder, gte: () => builder, order: () => builder, limit: () => builder,
        maybeSingle: async () => result(),
        then: (resolve: (result: unknown) => unknown) => Promise.resolve(resolve(result())),
      };
      return builder;
    },
  }),
}});
const dashboard = import("../app/dashboard/page");

async function resolveServerComponents(node: ReactNode): Promise<ReactNode> {
  if (Array.isArray(node)) return Promise.all(node.map(resolveServerComponents));
  if (!isValidElement(node)) return node;
  const element = node as ReactElement<{children?: ReactNode}>;
  if (typeof element.type === "function" && element.type.constructor.name === "AsyncFunction") {
    return resolveServerComponents(await (element.type as (props: unknown) => Promise<ReactNode>)(element.props));
  }
  if (element.props.children) {
    const children = await resolveServerComponents(element.props.children);
    return Array.isArray(children) ? cloneElement(element, {}, ...children) : cloneElement(element, {}, children);
  }
  return element;
}
async function render(params: Record<string, string> = {}) {
  query = new URLSearchParams(params);
  const page = await (await dashboard).default({searchParams: Promise.resolve(params)});
  return renderToStaticMarkup(createElement("div", {}, await resolveServerComponents(page)));
}

test("Simple and Advanced dashboards retain monitoring but never mount admin reporting or configuration", async () => {
  for (role of ["viewer", "monitor", "admin", "super_admin"]) {
    for (mode of ["simple", "dash"]) {
      bandwidthReads.length = 0;
      const html = await render();
      assert.match(html, /My linked server/);
      assert.doesNotMatch(html, /your workspace|Overall data usage|Request a relayer|Connect a Highway relayer|Server settings and automatic operation|Show consumption|Check &amp; update CLI/);
      assert.equal(html.includes("Total transferred"), mode === "dash");
      assert.equal(html.includes("Assigned Highway relayers"), mode === "simple");
      assert.equal(bandwidthReads.length, mode === "dash" ? 1 : 0);
      if (mode === "dash") assert.deepEqual(bandwidthReads[0], {p_node: "server", p_days: 7});
      assert.equal(html.includes("Refresh reading"), role === "monitor" || role === "super_admin");
    }
  }
});

test("relayers have their own section, including old relayer links and accounts without servers", async () => {
  role = "monitor";
  bandwidthReads.length = 0;
  const relayerLinks: Record<string, string>[] = [{section: "relayers"}, {relayer: "457"}];
  for (const params of relayerLinks) {
    const html = await render(params);
    assert.match(html, /Highway relayer dashboard/);
    assert.doesNotMatch(html, /My linked server|Total transferred|Connect a Highway relayer|Request a relayer/);
  }
  haveNodes = false;
  assert.match(await render({section: "relayers"}), /Highway relayer dashboard/);
  assert.match(await render(), /No server is linked yet/);
  haveNodes = true;
  allowRelayers = false;
  const blocked = await render({section: "relayers"});
  assert.doesNotMatch(blocked, /Highway relayer dashboard/);
  assert.match(blocked, /No relayers are shared/);
  mode = "simple";
  assert.match(await render(), /Assigned Highway relayers/);
  const serverRelay = await render({ section: "relayers", node: "server", relayScope: "server" });
  assert.match(serverRelay, /Highway relayer dashboard/);
  assert.doesNotMatch(serverRelay, /No relayers are shared/);
  allowRelayers = true;
  assert.equal(bandwidthReads.length, 0);
});

test("Advanced usage remains available while waiting for the first telemetry reading", async () => {
  mode = "dash";
  haveMetrics = false;
  const html = await render();
  assert.match(html, /has not reported yet/);
  assert.match(html, /3\.00 KiB/);
  haveMetrics = true;
});

test("the Highway summary shows the owner's assigned relay, four of five checks and heartbeat age", async () => {
  const { RelayerSummary } = await import("../components/dashboard/relayer-dashboard");
  const now = Date.parse("2026-09-11T08:00:00Z");
  const at = (seconds: number) => new Date(now - seconds * 1000).toISOString();
  const reading: RelayerReading = {
    assignment: { id: "assigned-relay", owner: "account", relayer_id: 457, relayer_name: "Gateway relay", created_at: at(86400) },
    relayer: normalizeRelayer({
      chainRelayerId: 457, onChainName: "Gateway relay", tier: "Standard",
      flags: { registered: true, online: true, heartbeating: true },
      lastCheckinAt: at(20), lastHeartbeatAt: at(45),
    }),
    chain: {
      observedAt: at(0), block: 123, epoch: 4, registered: true, authorized: true, inActiveSet: false,
      earningWeight: null, rewardsBalance: null, managerBalance: null, managerExists: null,
      tokenSymbol: "MOS", rewardsWallet: null, managerWallet: null, operationalKeys: [], blsKey: null, p2pKey: null,
    },
    sourceAt: at(0), fetchedAt: at(0), providerLatencyMs: 40, error: null, chainError: null,
  };
  const other: RelayerReading = {
    ...reading,
    assignment: { ...reading.assignment, id: "other-assignment", owner: "other-account", relayer_id: 999, relayer_name: "Other account relay" },
    relayer: null,
  };
  const renderSummary = (readings: RelayerReading[], clock = now) => renderToStaticMarkup(
    createElement(RelayerSummary, { data: { readings, error: null }, ownerId: "account", now: clock }),
  );
  const html = renderSummary([reading, other]);
  assert.match(html, /Gateway relay/);
  assert.match(html, /#457/);
  assert.match(html, /4 of 5 relay health checks passed/);
  assert.match(html, /4\/5/);
  assert.match(html, /45s ago/);
  assert.match(html, /20s ago/);
  assert.match(html, /Needs attention/);
  assert.match(html, /owner=account/);
  assert.match(html, /relayer=457/);
  assert.doesNotMatch(html, /Other account relay|#999/);

  const stale = renderSummary([reading], now + (SOURCE_STALE_S + 1) * 1000);
  assert.match(stale, /0 of 5 relay health checks passed/);
  assert.match(stale, /Awaiting verification/);
  assert.match(stale, /Last readings are stale/);
  assert.doesNotMatch(stale, />Healthy</);

  const missing = renderSummary([{ ...reading, relayer: null, chain: null, sourceAt: null }]);
  assert.match(missing, /Gateway relay/);
  assert.match(missing, /Not reported/);
  assert.match(missing, /Awaiting verification/);
  assert.match(renderSummary([]), /No relayer assigned to this account yet/);
  const linked = renderToStaticMarkup(createElement(RelayerSummary, {
    data: { readings: [reading], error: null }, nodeId: "server", now,
  }));
  assert.match(linked, /Linked to this server/);
  assert.match(linked, /node=server/);
  assert.match(linked, /relayScope=server/);
  assert.doesNotMatch(linked, /owner=account/);
  const unlinked = renderToStaticMarkup(createElement(RelayerSummary, {
    data: { readings: [], error: null }, nodeId: "server", now,
  }));
  assert.match(unlinked, /No relayer linked to this server yet/);
});
