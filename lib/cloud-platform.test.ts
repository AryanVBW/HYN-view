import assert from "node:assert/strict";
import test from "node:test";
import { readCloudPlatform, readMonitoringLogs } from "./cloud-platform.ts";

test("missing and malformed platform values remain unavailable", () => {
  for (const payload of [null, undefined, [], "provider", {}, { platform: [] }]) {
    assert.equal(readCloudPlatform(payload), null);
  }
  const unknown = readCloudPlatform({ platform: {} });
  assert.equal(unknown?.providerLabel, "Not identified");
  assert.equal(unknown?.hostMemoryBytes, null);
  assert.equal(unknown?.cpuLimitCores, null);
});

test("provider names require bounded local evidence and stay explicitly inferred", () => {
  for (const [provider, label] of Object.entries({ aws: "Amazon Web Services", gcp: "Google Cloud", azure: "Microsoft Azure", oracle: "Oracle Cloud", digitalocean: "DigitalOcean", hetzner: "Hetzner" })) {
    const platform = readCloudPlatform({ platform: { provider, provider_source: "dmi", provider_confidence: "inferred" } });
    assert.equal(platform?.providerLabel, label);
    assert.equal(platform?.providerInferred, true);
  }
  assert.equal(readCloudPlatform({ platform: { provider: "gcp", provider_source: "device-tree", provider_confidence: "inferred" } })?.providerLabel, "Google Cloud");
  for (const provider of ["__proto__", "constructor", "customer-cloud", {}, null]) {
    assert.equal(readCloudPlatform({ platform: { provider, provider_source: "dmi", provider_confidence: "inferred" } })?.providerLabel, "Not identified");
  }
  assert.equal(readCloudPlatform({ platform: { provider: "azure", virtualization: "microsoft" } })?.providerInferred, false);
  assert.equal(readCloudPlatform({ platform: { provider: "aws", provider_source: "metadata-token", provider_confidence: "verified" } })?.providerLabel, "Not identified");
});

test("system resources and workload limits are distinct and fractional quota survives", () => {
  const p = readCloudPlatform({ platform: {
    environment: "container", virtualization: "docker", cgroup_version: "2",
    host_cpu_count: 8, host_memory_bytes: 8589934592,
    cpu_limit_cores: "1.500", memory_limit_bytes: "1073741824",
    memory_current_bytes: 0, cpu_throttled_usec: 12500, cpu_throttled_periods: 3,
  } });
  assert.equal(p?.environment, "container");
  assert.equal(p?.virtualizationLabel, "Docker");
  assert.equal(p?.cgroupVersion, 2);
  assert.equal(p?.hostCpuCount, 8);
  assert.equal(p?.cpuLimitCores, 1.5);
  assert.equal(p?.hostMemoryBytes, 8589934592);
  assert.equal(p?.memoryLimitBytes, 1073741824);
  assert.equal(p?.memoryCurrentBytes, 0);
  assert.equal(p?.cpuThrottledPeriods, 3);
});

test("invalid, negative and unsafe readings do not become resource zeros", () => {
  for (const bad of [null, undefined, "", " ", false, true, [], {}, -1, Infinity, NaN, "1e9", "0x10", Number.MAX_SAFE_INTEGER + 1]) {
    const p = readCloudPlatform({ platform: { host_cpu_count: bad, cpu_limit_cores: bad, memory_limit_bytes: bad, memory_current_bytes: bad } });
    assert.equal(p?.hostCpuCount, null, String(bad));
    assert.equal(p?.cpuLimitCores, null, String(bad));
    assert.equal(p?.memoryLimitBytes, null, String(bad));
    assert.equal(p?.memoryCurrentBytes, null, String(bad));
  }
  assert.equal(readCloudPlatform({ platform: { cgroup_version: 3, environment: "baremetal", virtualization: "<script>" } })?.cgroupVersion, null);
});

const event = { ts: "2026-09-12T12:00:00.123456+0530", code: "sample_collected", level: "info", count: 1 };

test("monitoring summaries accept the current agent codes and normalize sample time", () => {
  const entries = readMonitoringLogs({ monitoring_logs: [event, { ...event, code: "agent_restarts", level: "warn", count: "4" }] });
  assert.equal(entries.length, 2);
  assert.equal(entries[0].ts, "2026-09-12T06:30:00.123Z");
  assert.equal(entries[0].label, "Reading collected");
  assert.equal(entries[1].label, "Service restarts reported");
  assert.equal(entries[1].count, 4);
});

test("all agent operational codes are supported without arbitrary log text", () => {
  const codes = ["sample_collected", "heartbeat_ok", "heartbeat_failed", "cloud_upload_ok", "cloud_upload_failed", "cloud_upload_paused", "cloud_upload_suspended", "agent_restarts", "service_failed", "service_warning", "service_error", "alerts_active"];
  const entries = readMonitoringLogs({ monitoring_logs: codes.map(code => ({ ...event, code, message: "raw-secret-text" })) });
  assert.deepEqual(entries.map(entry => entry.code), codes);
  assert.equal(JSON.stringify(entries).includes("raw-secret-text"), false);
});

test("malformed monitoring entries are rejected", () => {
  const bad = [null, [], "event", { ...event, code: "custom-log-message" }, { ...event, code: "constructor" },
    { ...event, level: "debug" }, { ...event, ts: "yesterday" }, { ...event, ts: "2026-99-99T00:00:00Z" },
    { ...event, ts: "2026-09-12T00:00:00" }, { ...event, count: true }, { ...event, count: 0 },
    { ...event, count: -1 }, { ...event, count: 1.5 }, { ...event, count: Infinity }, { ...event, count: 1_000_000_000 }];
  assert.deepEqual(readMonitoringLogs({ monitoring_logs: bad }), []);
  for (const value of [null, [], "logs", {}, { monitoring_logs: {} }]) assert.deepEqual(readMonitoringLogs(value), []);
});

test("monitoring parsing bounds source scanning and visible rows", () => {
  assert.equal(readMonitoringLogs({ monitoring_logs: Array(100).fill(event) }).length, 16);
  assert.equal(readMonitoringLogs({ monitoring_logs: [...Array(64).fill(null), event] }).length, 0);
});
