import assert from "node:assert/strict";
import test from "node:test";
import { buildAdminClientReport } from "./admin-report.ts";

test("admin report includes every active machine and all available measurements", () => {
  const report = buildAdminClientReport({
    clientLabel: "Owner <ops@example.com>",
    generatedAt: "2026-08-24T12:30:00.000Z",
    machines: [
      {
        id: "node-1",
        name: "edge <one>",
        hostname: "edge-01",
        os: "Ubuntu 24.04",
        agentVersion: "1.7.0",
        lastHeartbeatAt: "2026-08-24T12:29:45.000Z",
        lastSeenAt: "2026-08-24T12:20:00.000Z",
        alerts: [{ severity: "crit", message: "CPU <hot>" }],
        metric: {
          cpu_pct: 21.4,
          cpu_temp_c: 53.2,
          cpu_model: "AMD EPYC",
          cpu_cores: 8,
          mem_pct: 44,
          mem_total: 16_000_000_000,
          mem_used: 7_000_000_000,
          disk_pct: 62,
          net_iface: "eth0",
          net_rx_bps: 12_500_000,
          net_tx_bps: 2_500_000,
          net_link_mbps: 1000,
          sensors: { NVMe: 41 },
          payload: {
            network: { public_ip: "203.0.113.7", local_ip: "10.0.0.5", ssid: "Office WiFi" },
            highway: { present: 1, health: "healthy", units_active: 2, units_failed: 0 },
          },
        },
        speedtest: { down_bps: 100_000_000, up_bps: 20_000_000, latency_ms: 8.4 },
      },
      {
        id: "node-2",
        name: "relay-02",
        hostname: null,
        os: null,
        agentVersion: null,
        lastHeartbeatAt: null,
        lastSeenAt: null,
        alerts: [],
        metric: null,
        speedtest: null,
      },
    ],
  });

  assert.equal(report.subject, "Current HYN fleet report · Owner <ops@example.com>");
  assert.match(report.content, /2 active machines/);
  assert.match(report.content, /edge &lt;one&gt;/);
  assert.doesNotMatch(report.content, /edge <one>/);
  for (const expected of [
    "2026-08-24T12:29:45.000Z",
    "CPU &lt;hot&gt;",
    "21.4%",
    "53.2°C",
    "62.0%",
    "AMD EPYC",
    "203.0.113.7",
    "Office WiFi",
    "1,000 Mbps",
    "800.0 Mbps",
    "healthy",
    "relay-02",
    "Unavailable",
  ]) assert.match(report.content, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
});

test("admin report is explicit when a client has no active machines", () => {
  const report = buildAdminClientReport({
    clientLabel: "owner@example.com",
    generatedAt: "2026-08-24T12:30:00.000Z",
    machines: [],
  });
  assert.match(report.content, /No active linked machines were available/);
});
