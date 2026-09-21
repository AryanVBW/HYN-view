import { bytesPerSecToMbit } from "./dashboard-data.ts";
import { fleetFreshness, type FleetFreshness } from "./admin-data.ts";
import type { AlertEvent, Metric, Node, Speedtest } from "./types.ts";

export type FleetServer = {
  node: Node;
  metric: Metric | null;
  speedtest: Speedtest | null;
  openAlerts: AlertEvent[];
  /** Bytes moved in the retained window, or null when nothing was recorded. */
  bytes: number | null;
  freshness: FleetFreshness;
};

// What counts as worth a maintainer's attention, and why each number.
// Deliberately conservative: a 24/7 list that flags everything is a list nobody
// reads, which is the same failure mode as the email flood this release removed.
export const attentionThresholds = {
  diskPct: 85,
  memPct: 92,
  tempC: 80,
  /** A filling disk matters sooner than a busy CPU, so CPU is only notable when sustained high. */
  cpuPct: 95,
} as const;

export type Concern = { label: string; severity: "crit" | "warn" };

// One server's reasons for being on the list, worst first. Returning the reasons
// rather than a boolean is what lets the dashboard say *why* a box is listed --
// "quiet 6m" and "disk 91%" need different actions from the person on duty.
export function concernsFor(server: FleetServer): Concern[] {
  const out: Concern[] = [];
  const { node, metric, freshness, openAlerts } = server;
  if (node.revoked) out.push({ label: "credential revoked", severity: "crit" });
  if (node.status === "suspended") out.push({ label: "suspended", severity: "crit" });
  if (node.status === "paused") out.push({ label: "monitoring paused", severity: "warn" });
  // A machine that stopped talking is the one thing hyn cannot diagnose from
  // inside itself, so it leads.
  if (freshness.key === "quiet") out.push({ label: freshness.label, severity: "crit" });
  const crit = openAlerts.filter((alert) => alert.severity === "crit").length;
  const warn = openAlerts.filter((alert) => alert.severity === "warn").length;
  if (crit) out.push({ label: `${crit} critical alert${crit === 1 ? "" : "s"}`, severity: "crit" });
  if (warn) out.push({ label: `${warn} warning${warn === 1 ? "" : "s"}`, severity: "warn" });
  const num = (value: number | null | undefined) =>
    value !== null && value !== undefined && Number.isFinite(Number(value)) ? Number(value) : null;
  const disk = num(metric?.disk_pct);
  const mem = num(metric?.mem_pct);
  const temp = num(metric?.cpu_temp_c);
  const cpu = num(metric?.cpu_pct);
  if (disk !== null && disk >= attentionThresholds.diskPct) {
    out.push({ label: `disk ${Math.round(disk)}%`, severity: disk >= 95 ? "crit" : "warn" });
  }
  if (mem !== null && mem >= attentionThresholds.memPct) out.push({ label: `memory ${Math.round(mem)}%`, severity: "warn" });
  if (temp !== null && temp >= attentionThresholds.tempC) {
    out.push({ label: `${Math.round(temp)}°C`, severity: temp >= 90 ? "crit" : "warn" });
  }
  if (cpu !== null && cpu >= attentionThresholds.cpuPct) out.push({ label: `cpu ${Math.round(cpu)}%`, severity: "warn" });
  return out.sort((a, b) => (a.severity === b.severity ? 0 : a.severity === "crit" ? -1 : 1));
}

export type FleetSummary = {
  total: number;
  reporting: number;
  quiet: number;
  notReporting: number;
  openAlerts: number;
  criticalAlerts: number;
  /** Aggregate observed throughput right now, across every reporting server. */
  downMbps: number;
  upMbps: number;
  /** Total bytes recorded in the retained window; null when nothing was recorded. */
  bytes: number | null;
  hottestC: number | null;
  peakCpuPct: number | null;
  peakDiskPct: number | null;
  attention: { server: FleetServer; concerns: Concern[] }[];
};

const sum = (values: (number | null)[]) => {
  const present = values.filter((value): value is number => value !== null && Number.isFinite(value));
  return present.length ? present.reduce((total, value) => total + value, 0) : null;
};
const max = (values: (number | null | undefined)[]) => {
  const present = values
    .map((value) => (value === null || value === undefined ? null : Number(value)))
    .filter((value): value is number => value !== null && Number.isFinite(value));
  return present.length ? Math.max(...present) : null;
};

export function summariseFleet(servers: FleetServer[]): FleetSummary {
  const live = servers.filter((server) => server.freshness.key === "reporting");
  const attention = servers
    .map((server) => ({ server, concerns: concernsFor(server) }))
    .filter((row) => row.concerns.length > 0)
    // Critical first, then by how many things are wrong: the box with three
    // problems is a worse morning than the one with a single warning.
    .sort((a, b) => {
      const critA = a.concerns.filter((c) => c.severity === "crit").length;
      const critB = b.concerns.filter((c) => c.severity === "crit").length;
      return critB - critA || b.concerns.length - a.concerns.length;
    });
  return {
    total: servers.length,
    reporting: live.length,
    quiet: servers.filter((server) => server.freshness.key === "quiet").length,
    notReporting: servers.filter((server) => server.freshness.key !== "reporting").length,
    openAlerts: servers.reduce((total, server) => total + server.openAlerts.length, 0),
    criticalAlerts: servers.reduce(
      (total, server) => total + server.openAlerts.filter((alert) => alert.severity === "crit").length,
      0,
    ),
    downMbps: bytesPerSecToMbit(sum(live.map((server) => server.metric?.net_rx_bps ?? null)) ?? 0),
    upMbps: bytesPerSecToMbit(sum(live.map((server) => server.metric?.net_tx_bps ?? null)) ?? 0),
    bytes: sum(servers.map((server) => server.bytes)),
    hottestC: max(servers.map((server) => server.metric?.cpu_temp_c)),
    peakCpuPct: max(servers.map((server) => server.metric?.cpu_pct)),
    peakDiskPct: max(servers.map((server) => server.metric?.disk_pct)),
    attention,
  };
}

// Builds the per-server view model from raw rows. Kept here rather than in the
// page so the shape the UI renders is the shape a test can assert on.
export function toFleetServers(args: {
  nodes: Node[];
  metrics: Metric[];
  speedtests: Speedtest[];
  alerts: AlertEvent[];
  bytesByNode?: Record<string, number | null>;
  now?: number;
}): FleetServer[] {
  const newestByNode = <T extends { node_id: string; ts: string }>(rows: T[]) => {
    const out = new Map<string, T>();
    for (const row of rows) {
      const existing = out.get(row.node_id);
      if (!existing || new Date(row.ts).getTime() > new Date(existing.ts).getTime()) out.set(row.node_id, row);
    }
    return out;
  };
  const metric = newestByNode(args.metrics);
  const speed = newestByNode(args.speedtests);
  const now = args.now ?? Date.now();
  return args.nodes.map((node) => ({
    node,
    metric: metric.get(node.id) ?? null,
    speedtest: speed.get(node.id) ?? null,
    openAlerts: args.alerts.filter((alert) => alert.node_id === node.id && !alert.resolved),
    bytes: args.bytesByNode?.[node.id] ?? null,
    freshness: fleetFreshness(node, now),
  }));
}

export function formatBytes(value: number | null): string {
  if (value === null || !Number.isFinite(value)) return "—";
  const units = ["B", "KB", "MB", "GB", "TB", "PB"];
  let scaled = value;
  let unit = 0;
  while (scaled >= 1000 && unit < units.length - 1) {
    scaled /= 1000;
    unit += 1;
  }
  return `${scaled.toFixed(scaled >= 100 || unit === 0 ? 0 : 1)} ${units[unit]}`;
}
