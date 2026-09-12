import type { Metric } from "./types";

// History contains compact five-minute chart points; only the newest reading
// carries full details. The last point must always be the actual newest sample.
export function mergeMonitoringHistory(history: Metric[], latest: Metric | null): Metric[] {
  // Separate queries can straddle an ingest. Do not end with a newer compact
  // row lacking details if history arrived after the latest-snapshot query.
  const rows = new Map(history.filter(row => !latest || Date.parse(row.ts) <= Date.parse(latest.ts)).map(row => [row.ts, row]));
  if (latest) rows.set(latest.ts, latest);
  return [...rows.values()].sort((a, b) => Date.parse(a.ts) - Date.parse(b.ts));
}
