export const TELEMETRY_HOURS = 48;
export const MONITORING_POLL_MS = 15_000;
export const MONITORING_FULL_REFRESH_MS = 5 * 60_000;
export const MONITORING_EVENT = "hyn-monitoring-state";

export type MonitoringState = {
  id: string;
  status: string;
  revoked?: boolean;
  telemetry_mode?: string;
  last_metric_at?: string | null;
  last_seen_at?: string | null;
  last_heartbeat_at?: string | null;
  last_config_pull_at?: string | null;
  agent_version?: string | null;
  config?: Record<string, unknown>;
};

// Heartbeats change the small live indicator, not the whole chart payload.
export function monitoringRevision(node: MonitoringState): string {
  return JSON.stringify([node.id, node.status, node.revoked ?? false, node.telemetry_mode,
    node.last_metric_at ?? null, node.agent_version ?? null, node.config ?? {}]);
}

export function heartbeatTime(node: MonitoringState): string | null {
  return node.last_heartbeat_at ?? node.last_config_pull_at ?? node.last_seen_at ?? null;
}

// A fresh server render can contain a newer beat than the last small poll.
// Neither an older poll nor an invalid timestamp may move that clock backward.
export function newerHeartbeatAt(first: string | null | undefined, second: string | null | undefined): string | null {
  const a = typeof first === "string" ? Date.parse(first) : NaN;
  const b = typeof second === "string" ? Date.parse(second) : NaN;
  if (!Number.isFinite(a)) return Number.isFinite(b) ? second! : null;
  return Number.isFinite(b) && b > a ? second! : first!;
}

// Clock corrections must not postpone cleanup of an already-visible snapshot.
export function monitoringFullRefreshDue(lastRefresh: number, now: number): boolean {
  return !Number.isFinite(lastRefresh) || !Number.isFinite(now)
    || now < lastRefresh || now - lastRefresh >= MONITORING_FULL_REFRESH_MS;
}

export function readingAge(sampleAt: string | null | undefined, now: number, intervalMinutes: unknown = 1): {
  label: string; stale: boolean; sampledAt: string | null;
} {
  const timestamp = typeof sampleAt === "string" ? Date.parse(sampleAt) : NaN;
  if (!Number.isFinite(timestamp) || !Number.isFinite(now)) return {label: "not reported", stale: false, sampledAt: null};
  const sampledAt = new Date(timestamp).toISOString();
  if (timestamp > now + 5_000) return {label: "timestamp ahead of clock", stale: false, sampledAt};
  const age = Math.max(0, Math.floor((now - timestamp) / 1_000));
  const interval = typeof intervalMinutes === "number" || typeof intervalMinutes === "string" ? Number(intervalMinutes) : NaN;
  const expected = Number.isInteger(interval) && interval >= 1 && interval <= 1440 ? interval : 1;
  let label: string;
  if (age < 60) label = `${age}s ago`;
  else if (age < 3600) label = `${Math.floor(age / 60)}m ${age % 60}s ago`;
  else if (age < 86400) label = `${Math.floor(age / 3600)}h ${Math.floor(age % 3600 / 60)}m ago`;
  else label = `${Math.floor(age / 86400)}d ${Math.floor(age % 86400 / 3600)}h ago`;
  return {label, stale: age >= Math.max(180, expected * 180), sampledAt};
}
