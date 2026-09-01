import { bytesPerSecToMbit, compareVersions } from "./dashboard-data.ts";
import { heartbeatState } from "./heartbeat.ts";
import type { AdminNode, AdminTrendPoint, Metric } from "./types.ts";

// A machine whose agent never once reached the portal. Approving a pairing code
// creates the row, so a client who never finished `sudo hyn link` keeps a machine
// on their dashboard that will never report anything -- and which otherwise reads
// as "quiet since it was created", sending someone to look at a box that was
// never talking in the first place.
export function neverLinked(node: Pick<AdminNode, "is_demo" | "ever_connected">): boolean {
  return !node.is_demo && !node.ever_connected;
}

type FleetMetric = Pick<Metric, "ts" | "cpu_pct" | "net_rx_bps" | "net_tx_bps">;

type Bucket = {
  ts: number;
  cpuTotal: number;
  cpuCount: number;
  downTotal: number;
  downCount: number;
  upTotal: number;
  upCount: number;
};

const HALF_HOUR = 30 * 60 * 1000;

type FreshnessNode = {
  revoked: boolean;
  status: "active" | "paused" | "suspended";
  last_seen_at: string | null;
  last_heartbeat_at?: string | null;
  agent_version?: string | null;
  config?: Record<string, unknown> | null;
};

export type FleetFreshness = {
  key: "reporting" | "quiet" | "paused" | "suspended" | "revoked";
  label: string;
  tone: string;
};

function pushIntervalMinutes(config: Record<string, unknown> | null | undefined) {
  const value = Number(config?.cloud_push_min ?? 10);
  return Number.isInteger(value) && value >= 1 && value <= 1440 ? value : 10;
}

export function fleetFreshness(node: FreshnessNode, now = Date.now()): FleetFreshness {
  if (node.revoked) return { key: "revoked", label: "revoked", tone: "text-muted-foreground" };
  if (node.status === "suspended") return { key: "suspended", label: "suspended", tone: "text-destructive" };
  if (node.status === "paused") return { key: "paused", label: "paused", tone: "text-[#e8a400]" };
  if (node.agent_version && compareVersions(node.agent_version, "1.7.0") >= 0) {
    const heartbeat = heartbeatState(node.last_heartbeat_at, now);
    if (heartbeat.key === "connected") {
      return { key: "reporting", label: "reporting", tone: "text-primary" };
    }
    if (heartbeat.key === "delayed") {
      return {
        key: "reporting",
        label: `delayed ${Math.max(1, Math.floor((heartbeat.ageSeconds ?? 0) / 60))}m`,
        tone: "text-[#e8a400]",
      };
    }
    return {
      key: "quiet",
      label: heartbeat.ageSeconds === null ? "never heartbeated" : `quiet ${Math.round(heartbeat.ageSeconds / 60)}m`,
      tone: heartbeat.ageSeconds === null ? "text-muted-foreground" : "text-destructive",
    };
  }
  if (!node.last_seen_at) return { key: "quiet", label: "never reported", tone: "text-muted-foreground" };

  const seenAt = new Date(node.last_seen_at).getTime();
  if (!Number.isFinite(seenAt)) return { key: "quiet", label: "invalid check-in", tone: "text-destructive" };
  const minutes = Math.max(0, (now - seenAt) / 60_000);
  const interval = pushIntervalMinutes(node.config);
  const quietAfter = Math.max(15, interval * 3);
  const lateAfter = Math.max(8, interval * 1.5);
  if (minutes > quietAfter) {
    return { key: "quiet", label: `quiet ${Math.round(minutes)}m`, tone: "text-destructive" };
  }
  if (minutes > lateAfter) {
    return { key: "reporting", label: `late ${Math.round(minutes)}m`, tone: "text-[#e8a400]" };
  }
  return { key: "reporting", label: "reporting", tone: "text-primary" };
}

function clockLabel(timestamp: number): string {
  const date = new Date(timestamp);
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}

// Fleet samples do not arrive on the same second, so charting raw rows would
// produce a comb of unrelated machines. Thirty-minute buckets turn them into
// an honest fleet trend: average utilization and observed transfer rate across
// every reading in that window.
export function toFleetTrend(rows: FleetMetric[]): AdminTrendPoint[] {
  const buckets = new Map<number, Bucket>();

  for (const row of rows) {
    const stamp = new Date(row.ts).getTime();
    if (!Number.isFinite(stamp)) continue;
    const ts = Math.floor(stamp / HALF_HOUR) * HALF_HOUR;
    const bucket = buckets.get(ts) ?? {
      ts,
      cpuTotal: 0,
      cpuCount: 0,
      downTotal: 0,
      downCount: 0,
      upTotal: 0,
      upCount: 0,
    };

    if (row.cpu_pct !== null && Number.isFinite(Number(row.cpu_pct))) {
      bucket.cpuTotal += Number(row.cpu_pct);
      bucket.cpuCount += 1;
    }
    if (row.net_rx_bps !== null && Number(row.net_rx_bps) >= 0) {
      bucket.downTotal += Number(row.net_rx_bps);
      bucket.downCount += 1;
    }
    if (row.net_tx_bps !== null && Number(row.net_tx_bps) >= 0) {
      bucket.upTotal += Number(row.net_tx_bps);
      bucket.upCount += 1;
    }
    buckets.set(ts, bucket);
  }

  return [...buckets.values()]
    .sort((a, b) => a.ts - b.ts)
    .map((bucket) => ({
      time: clockLabel(bucket.ts),
      cpu:
        bucket.cpuCount > 0
          ? Math.round((bucket.cpuTotal / bucket.cpuCount) * 10) / 10
          : null,
      down: bytesPerSecToMbit(
        bucket.downCount > 0 ? bucket.downTotal / bucket.downCount : 0
      ),
      up: bytesPerSecToMbit(
        bucket.upCount > 0 ? bucket.upTotal / bucket.upCount : 0
      ),
    }));
}
