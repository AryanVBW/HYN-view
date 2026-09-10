import type { Metric } from "./types";

export const SNAPSHOT_TTL_MS = 5 * 60_000;
export const SNAPSHOT_MAX_BYTES = 256 * 1024;
const CACHE_MAX_BYTES = 8 * 1024 * 1024;
type Entry = { expires: number; bytes: number; payload: Record<string, unknown>; timer?: ReturnType<typeof setTimeout> };

// Shared by Next route and page bundles within ONE Node process. This cache is
// deliberately expendable: Heroku restarts/sleep/scale discard it. No disk, no
// Supabase Storage and no fallback to a durable telemetry table.
const runtime = globalThis as typeof globalThis & { hynSnapshots?: Map<string, Entry> };
const entries = runtime.hynSnapshots ??= new Map<string, Entry>();

function prune(now: number) {
  for (const [key, entry] of entries) if (entry.expires <= now) {
    clearTimeout(entry.timer);
    entries.delete(key);
  }
}

export function storeTransientSnapshot(nodeId: string, payload: Record<string, unknown>, now = Date.now()) {
  const bytes = Buffer.byteLength(JSON.stringify(payload), "utf8");
  if (bytes > SNAPSHOT_MAX_BYTES) throw new Error("snapshot exceeds 256 KiB");
  prune(now);
  clearTimeout(entries.get(nodeId)?.timer);
  entries.delete(nodeId);
  let total = [...entries.values()].reduce((sum, entry) => sum + entry.bytes, 0);
  for (const [key, entry] of entries) {
    if (total + bytes <= CACHE_MAX_BYTES) break;
    entries.delete(key);
    clearTimeout(entry.timer);
    total -= entry.bytes;
  }
  const entry: Entry = { expires: now + SNAPSHOT_TTL_MS, bytes, payload };
  entries.set(nodeId, entry);
  // Expiry releases memory even if nobody ever reads the snapshot again.
  const timer = setTimeout(() => {
    if (entries.get(nodeId) === entry) entries.delete(nodeId);
  }, SNAPSHOT_TTL_MS);
  timer.unref();
  entry.timer = timer;
}

type PresenceRpc = (name: string, args: Record<string, unknown>) => PromiseLike<{
  data: { node_id?: unknown; node_status?: unknown } | null;
  error: { message: string } | null;
}>;

export async function acceptTransientSnapshot(
  body: Record<string, unknown>, rpc: PresenceRpc, save = storeTransientSnapshot,
) {
  const payload = body.p_payload;
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return { status: 400, message: "snapshot must be an object" };
  if (Buffer.byteLength(JSON.stringify(payload), "utf8") > SNAPSHOT_MAX_BYTES) return { status: 413, message: "snapshot exceeds 256 KiB" };
  if (typeof body.p_node_token !== "string") return { status: 401, message: "invalid node token" };
  const reading = payload as Record<string, unknown>;
  // This narrow object is the entire database boundary: never spread body or
  // reading here. In particular it has no p_payload, logs, processes or metrics.
  const { data: accepted, error } = await rpc("hyn_local_heartbeat", {
    p_node_token: body.p_node_token,
    p_agent_version: typeof reading.agent_version === "string" ? reading.agent_version : null,
  });
  if (error) return { status: 401, message: error.message };
  if (accepted?.node_status !== "active") return { status: 403, message: `node ${accepted?.node_status ?? "unavailable"}` };
  if (typeof accepted.node_id !== "string") return { status: 502, message: "invalid node authorization response" };
  save(accepted.node_id, reading);
  return { status: 200, node_id: accepted.node_id, storage: "transient", expires_in: 300 };
}

// Call only AFTER checking current ownership/admin permissions and node status.
export function readTransientSnapshot(nodeId: string, now = Date.now()) {
  prune(now);
  return entries.get(nodeId)?.payload ?? null;
}

export function snapshotMetric(nodeId: string, p: Record<string, unknown>): Metric {
  const obj = (key: string): Record<string, unknown> =>
    p[key] && typeof p[key] === "object" && !Array.isArray(p[key]) ? p[key] as Record<string, unknown> : {};
  const num = (v: unknown) => typeof v === "number" && Number.isFinite(v) ? v : null;
  const str = (v: unknown) => typeof v === "string" ? v : null;
  const cpu = obj("cpu"), mem = obj("memory"), net = obj("network"), psi = obj("psi");
  return {
    id: 0, node_id: nodeId, ts: str(p.ts) ?? new Date().toISOString(),
    cpu_pct: num(cpu.pct), cpu_temp_c: num(cpu.temp_c), cpu_mhz: num(cpu.mhz),
    cpu_model: str(cpu.model), cpu_steal: num(cpu.steal), cpu_iowait: num(cpu.iowait), cpu_cores: num(cpu.cores),
    load1: num(Array.isArray(p.load) ? p.load[0] : null), mem_pct: num(mem.pct),
    mem_total: num(mem.total), mem_used: num(mem.used), swap_used: num(mem.swap_used),
    disk_pct: num(obj("disk").pct), uptime_s: num(p.uptime_s), net_iface: str(net.iface),
    net_rx_bps: num(net.rx_bps), net_tx_bps: num(net.tx_bps), net_retrans_pm: num(net.retrans_permille),
    latency_ms: num(p.latency_ms), net_link_mbps: num(net.link_mbps), psi_cpu: num(psi.cpu),
    psi_mem: num(psi.memory), psi_io: num(psi.io), tcp_estab: num(net.tcp_estab),
    conntrack_pct: num(net.conntrack_pct), proc_count: num(obj("processes").count),
    sensors: Object.fromEntries(Object.entries(obj("sensors")).map(([k, v]) => [k, num(v)])), payload: p,
  };
}
