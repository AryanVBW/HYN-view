import { bytesPerSecToMbit } from "./dashboard-data.ts";
import type { AdminTrendPoint, Metric } from "./types.ts";

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
