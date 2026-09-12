import assert from "node:assert/strict";
import test from "node:test";
import { monitoringRevision, heartbeatTime, MONITORING_POLL_MS, MONITORING_FULL_REFRESH_MS, monitoringFullRefreshDue, newerHeartbeatAt, readingAge } from "./monitoring-state.ts";
import { mergeMonitoringHistory } from "./monitoring-data.ts";
import type { Metric } from "./types.ts";

test("heartbeats update freshness without triggering a chart download", () => {
  const node = {id: "node", status: "active", last_metric_at: "2026-09-12T12:00:00Z", config: {cloud_storage: "cloud"}};
  assert.equal(monitoringRevision(node), monitoringRevision({...node, last_heartbeat_at: "2026-09-12T12:00:24Z"}));
  assert.notEqual(monitoringRevision(node), monitoringRevision({...node, status: "paused"}));
  assert.notEqual(monitoringRevision(node), monitoringRevision({...node, last_metric_at: "2026-09-12T12:01:00Z"}));
  assert.notEqual(monitoringRevision(node), monitoringRevision({...node, config: {cloud_storage: "local"}}));
  assert.equal(heartbeatTime({...node, last_heartbeat_at: "beat", last_seen_at: "sample"}), "beat");
  assert.equal(MONITORING_POLL_MS, 15_000);
});

test("compact history always ends with the full newest snapshot without duplicate points", () => {
  const row = (ts: string, payload: Metric["payload"] = null) => ({ts, payload} as Metric);
  const latest = row("2026-09-12T12:01:00Z", {cpu: {pct: 80}});
  const history = [row(latest.ts), row("2026-09-12T11:55:00Z")];
  const rows = mergeMonitoringHistory(history, latest);
  assert.equal(rows.length, 2);
  assert.equal(rows[1], latest);
  assert.equal(rows[0].ts, "2026-09-12T11:55:00Z");
  assert.deepEqual(mergeMonitoringHistory([], null), []);
  assert.equal(mergeMonitoringHistory([...history, row("2026-09-12T12:02:00Z")], latest).at(-1), latest);
});

test("an unchanged node still reaches its bounded expiry refresh", () => {
  const start = Date.parse("2026-09-12T12:00:00Z");
  assert.equal(MONITORING_FULL_REFRESH_MS, 300_000);
  assert.equal(monitoringFullRefreshDue(start, start + 299_999), false);
  assert.equal(monitoringFullRefreshDue(start, start + 300_000), true);
  assert.equal(monitoringFullRefreshDue(start, start + 48 * 60 * 60_000), true);
  assert.equal(monitoringFullRefreshDue(start, start - 1), true);
});

test("reading age advances independently of a live heartbeat and honors configured cadence", () => {
  const ts = "2026-09-12T12:00:00Z", start = Date.parse(ts);
  assert.equal(readingAge(ts, start).label, "0s ago");
  assert.equal(readingAge(ts, start + 61_000).label, "1m 1s ago");
  assert.equal(readingAge(ts, start + 179_000).stale, false);
  assert.equal(readingAge(ts, start + 180_000).stale, true);
  assert.equal(readingAge(ts, start + 180_000, 10).stale, false);
  assert.equal(readingAge(ts, start + 30 * 60_000, "10").stale, true);
  assert.equal(readingAge(ts, start + 48 * 60 * 60_000).label, "2d 0h ago");
  assert.equal(readingAge(null, start).label, "not reported");
  assert.equal(readingAge("invalid", start).sampledAt, null);
  assert.equal(readingAge(ts, start - 60_000).label, "timestamp ahead of clock");
});

test("heartbeat selection accepts only the newest valid observation", () => {
  const old = "2026-09-12T12:00:00Z", fresh = "2026-09-12T12:00:24Z";
  assert.equal(newerHeartbeatAt(fresh, old), fresh);
  assert.equal(newerHeartbeatAt(old, fresh), fresh);
  assert.equal(newerHeartbeatAt(fresh, "invalid"), fresh);
  assert.equal(newerHeartbeatAt(null, fresh), fresh);
  assert.equal(newerHeartbeatAt(undefined, "invalid"), null);
});
