import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { MonitoringLog } from "../components/dashboard/monitoring-log";
import { ServerDetailsPanel } from "../components/dashboard/server-details";
import type { Metric, Node } from "../lib/types";

const node = { name: "Server", hostname: "fixture", os: "Ubuntu", agent_version: "1.12.0", created_at: "2026-09-01T00:00:00Z", last_seen_at: null } as Node;
const latest = { cpu_model: "CPU", cpu_cores: 8, mem_total: 8589934592, net_iface: "eth0", payload: null } as Metric;

test("platform details preserve system metrics and distinguish container resource limits", () => {
  const html = renderToStaticMarkup(<ServerDetailsPanel node={node} latest={{ ...latest, payload: { platform: {
    provider: "gcp", provider_confidence: "inferred", provider_source: "dmi",
    virtualization: "docker", environment: "container", cgroup_version: 2,
    cpu_limit_cores: 1.5, memory_limit_bytes: 1073741824, memory_current_bytes: 0, cpu_throttled_periods: 3,
  } } }} />);
  for (const label of ["Google Cloud (inferred)", "Container · Docker", "System CPU cores", "System memory", "Workload CPU limit", "1.5 cores", "Workload memory limit", "CPU throttling periods", "cumulative count"]) assert.ok(html.includes(label), label);
  assert.match(html, /System CPU cores<\/dt><dd[^>]*>8<\/dd>/);
  assert.match(html, /wider view/);
});

test("old agents and absent limits do not render invented workload readings", () => {
  const old = renderToStaticMarkup(<ServerDetailsPanel node={node} latest={latest} />);
  assert.doesNotMatch(old, /Workload CPU limit|Cloud provider/);
  const empty = renderToStaticMarkup(<ServerDetailsPanel node={node} latest={{ ...latest, payload: { platform: { cgroup_version: 2, virtualization: "microsoft" } } }} />);
  assert.match(empty, /Not identified/);
  assert.doesNotMatch(empty, /Microsoft Azure|0 cores/);
  assert.equal(empty.match(/No finite limit reported/g)?.length, 4); // title and visible value for two limits
});

test("monitoring empty state does not claim the server is healthy or expose a zero count", () => {
  const html = renderToStaticMarkup(<MonitoringLog payload={null} />);
  assert.match(html, /No monitoring summary has been reported/);
  assert.doesNotMatch(html, /All healthy|Count: 0|Nothing has fired/);
});

test("monitoring summaries label severity and sample counts without exposing raw messages", () => {
  const html = renderToStaticMarkup(<MonitoringLog payload={{ monitoring_logs: [
    { ts: "2026-09-12T12:00:00Z", code: "service_failed", level: "crit", count: 2, message: "raw-secret-text" },
    { ts: "2026-09-12T12:00:00Z", code: "agent_restarts", level: "warn", count: 4 },
    { ts: "2026-09-12T12:00:00Z", code: "unrecognized", level: "info", count: 1 },
  ] }} />);
  for (const text of ["Failed services reported", "Critical", "Count: 2", "Service restarts reported", "Count: 4", "2026-09-12 12:00:00", "not new events per refresh"]) assert.ok(html.includes(text), text);
  assert.doesNotMatch(html, /raw-secret-text|unrecognized/);
  assert.equal(html.match(/<li /g)?.length, 2);
  assert.match(html, /<time dateTime="2026-09-12T12:00:00.000Z"/);
});
