import type { AlertEvent, Metric, Speedtest } from "./types";

// The agent's network counters come from /sys/class/net/*/statistics/*_bytes, so
// the "bps" fields are BYTES per second despite the name (that name is already
// part of the `hyn snapshot --json` contract, so it stays). Links are sold in
// bits, so convert once, here, rather than in each chart.
export function bytesPerSecToMbit(bytesPerSec: number | null): number {
  if (!bytesPerSec || bytesPerSec < 0) return 0;
  return Math.round(((bytesPerSec * 8) / 1_000_000) * 10) / 10;
}

export function formatBytes(bytes: number | null): string {
  if (bytes === null || bytes === undefined || bytes < 0) return "—";
  const units = ["B", "KiB", "MiB", "GiB", "TiB"];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return `${value >= 10 || unit === 0 ? Math.round(value) : value.toFixed(1)} ${units[unit]}`;
}

export function formatDuration(seconds: number | null): string {
  if (!seconds || seconds < 0) return "—";
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

export function formatRelative(iso: string | null): string {
  if (!iso) return "never";
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return "never";
  const secs = Math.max(0, Math.round((Date.now() - then) / 1000));
  if (secs < 90) return `${secs}s ago`;
  const mins = Math.round(secs / 60);
  if (mins < 90) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (hours < 36) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

function clockLabel(iso: string): string {
  const d = new Date(iso);
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

export type CpuPoint = { time: string; usage: number | null; mhz: number | null };
export type TempPoint = { time: string; celsius: number | null };
export type NetPoint = { time: string; down: number; up: number };
export type MemPoint = { time: string; memory: number | null; disk: number | null };
export type SpeedPoint = { time: string; download: number; upload: number };

// Metrics arrive oldest-first from the query, which is the order a chart wants.
export function toCpuSeries(rows: Metric[]): CpuPoint[] {
  return rows.map((r) => ({
    time: clockLabel(r.ts),
    usage: r.cpu_pct,
    mhz: r.cpu_mhz,
  }));
}

export function toTempSeries(rows: Metric[]): TempPoint[] {
  return rows.map((r) => ({ time: clockLabel(r.ts), celsius: r.cpu_temp_c }));
}

export function toNetSeries(rows: Metric[]): NetPoint[] {
  return rows.map((r) => ({
    time: clockLabel(r.ts),
    down: bytesPerSecToMbit(r.net_rx_bps),
    up: bytesPerSecToMbit(r.net_tx_bps),
  }));
}

export function toMemSeries(rows: Metric[]): MemPoint[] {
  return rows.map((r) => ({
    time: clockLabel(r.ts),
    memory: r.mem_pct,
    disk: r.disk_pct,
  }));
}

// Speed tests are stored newest-first; reverse so the x-axis runs forwards.
export function toSpeedSeries(rows: Speedtest[]): SpeedPoint[] {
  return [...rows].reverse().map((r) => ({
    time: clockLabel(r.ts),
    download: bytesPerSecToMbit(r.down_bps),
    upload: bytesPerSecToMbit(r.up_bps),
  }));
}

// True when at least one row carries a real reading. Used to decide between
// drawing a chart and saying the sensor is unavailable — a chart of 24 nulls
// looks like a broken chart, not like "this VM has no thermal sensor".
export function hasSeriesData<T extends Record<string, unknown>>(
  rows: T[],
  key: keyof T
): boolean {
  return rows.some((r) => r[key] !== null && r[key] !== undefined);
}

export function severityCount(events: AlertEvent[]) {
  return events.reduce(
    (acc, e) => {
      if (!e.resolved) acc[e.severity] += 1;
      return acc;
    },
    { info: 0, warn: 0, crit: 0 }
  );
}
