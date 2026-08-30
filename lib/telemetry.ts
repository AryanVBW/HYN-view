// The rest of a pushed payload: filesystems, processes, network detail, kernel
// pressure and per-core clocks.
//
// The agent has always sent all of this (see cloud_payload_v in lib/cloud.sh)
// and hyn_ingest has always stored the whole snapshot in metrics.payload, but
// the dashboard only ever read the promoted columns. That left an operator who
// is not at the terminal unable to see which filesystem is filling, what was
// using the box, or whether the link is dropping frames — which is most of the
// reason the portal exists.
//
// Parsed defensively for the same reasons as lib/highway.ts: a key can be absent
// (older agent), null (sensor unreadable) or a numeric string (PostgREST
// round-trips some numerics as text). A value that cannot be read stays null and
// renders as "—". Never 0: a plotted zero is a claim about the machine.

function num(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

function str(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const s = v.trim();
  return s === "" ? null : s;
}

function obj(v: unknown): Record<string, unknown> | null {
  if (!v || typeof v !== "object" || Array.isArray(v)) return null;
  return v as Record<string, unknown>;
}

function arr(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}

export type Filesystem = {
  mount: string;
  fstype: string | null;
  pct: number | null;
  used: number | null;
  size: number | null;
  avail: number | null;
};

export type TopProcess = {
  pid: number | null;
  name: string;
  cpuPct: number | null;
  rss: number | null;
  threads: number | null;
};

export type ProcessSummary = {
  count: number | null;
  running: number | null;
  blocked: number | null;
  top: TopProcess[];
};

export type NetworkDetail = {
  iface: string | null;
  state: string | null;
  ssid: string | null;
  connection: string | null;
  localIp: string | null;
  gateway: string | null;
  dns: string | null;
  linkMbps: number | null;
  duplex: string | null;
  mtu: number | null;
  driver: string | null;
  rxBps: number | null;
  txBps: number | null;
  rxTotal: number | null;
  txTotal: number | null;
  rxErr: number | null;
  txErr: number | null;
  rxDrop: number | null;
  txDrop: number | null;
  retransPermille: number | null;
  conntrackPct: number | null;
  tcpEstab: number | null;
  tcpTimeWait: number | null;
  listenDrops: number | null;
};

export type Pressure = { cpu: number | null; memory: number | null; io: number | null };

export type CpuClocks = {
  governor: string | null;
  avgMhz: number | null;
  minMhz: number | null;
  maxMhz: number | null;
  cores: number[];
};

// Latency is sent as a map of target -> microseconds, with "gateway" as the
// first hop. Keeping them apart is the whole point of the measurement: it is
// what tells an operator whether a problem is theirs or their provider's.
export type LatencyHop = { target: string; ms: number; firstHop: boolean };

export function readFilesystems(payload: Record<string, unknown> | null): Filesystem[] {
  const disk = obj(payload?.["disk"]);
  if (!disk) return [];
  return arr(disk["mounts"]).flatMap((entry) => {
    const m = obj(entry);
    const mount = str(m?.["mount"]);
    if (!m || !mount) return [];
    return [{
      mount,
      fstype: str(m["fstype"]),
      pct: num(m["pct"]),
      used: num(m["used"]),
      size: num(m["size"]),
      avail: num(m["avail"]),
    }];
  });
}

export function readProcesses(payload: Record<string, unknown> | null): ProcessSummary | null {
  const p = obj(payload?.["processes"]);
  if (!p) return null;
  const top = arr(p["top"]).flatMap((entry) => {
    const t = obj(entry);
    const name = str(t?.["name"]);
    if (!t || !name) return [];
    // The agent sends CPU in tenths of a percent so it can stay integer-only in
    // bash arithmetic. Converting here keeps the wire format alone.
    const tenths = num(t["cpu_tenths"]);
    return [{
      pid: num(t["pid"]),
      name,
      cpuPct: tenths === null ? null : tenths / 10,
      rss: num(t["rss"]),
      threads: num(t["threads"]),
    }];
  });
  return {
    count: num(p["count"]),
    running: num(p["running"]),
    blocked: num(p["blocked"]),
    top,
  };
}

export function readNetworkDetail(payload: Record<string, unknown> | null): NetworkDetail | null {
  const n = obj(payload?.["network"]);
  if (!n) return null;
  return {
    iface: str(n["iface"]),
    state: str(n["state"]),
    ssid: str(n["ssid"]),
    connection: str(n["connection"]),
    localIp: str(n["local_ip"]),
    gateway: str(n["gateway"]),
    dns: str(n["dns"]),
    linkMbps: num(n["link_mbps"]),
    duplex: str(n["duplex"]),
    mtu: num(n["mtu"]),
    driver: str(n["driver"]),
    rxBps: num(n["rx_bps"]),
    txBps: num(n["tx_bps"]),
    rxTotal: num(n["rx_total"]),
    txTotal: num(n["tx_total"]),
    rxErr: num(n["rx_err"]),
    txErr: num(n["tx_err"]),
    rxDrop: num(n["rx_drop"]),
    txDrop: num(n["tx_drop"]),
    retransPermille: num(n["retrans_permille"]),
    conntrackPct: num(n["conntrack_pct"]),
    tcpEstab: num(n["tcp_estab"]),
    tcpTimeWait: num(n["tcp_timewait"]),
    listenDrops: num(n["listen_drops"]),
  };
}

export function readPressure(payload: Record<string, unknown> | null): Pressure | null {
  const p = obj(payload?.["psi"]);
  if (!p) return null;
  const out = { cpu: num(p["cpu"]), memory: num(p["memory"]), io: num(p["io"]) };
  // A kernel built without CONFIG_PSI reports nothing at all. Say so rather than
  // drawing three zeroed bars that look like a machine under no contention.
  if (out.cpu === null && out.memory === null && out.io === null) return null;
  return out;
}

export function readCpuClocks(payload: Record<string, unknown> | null): CpuClocks | null {
  const c = obj(payload?.["cpu"]);
  if (!c) return null;
  const cores = arr(c["cores_mhz"]).flatMap((v) => {
    const n = num(v);
    return n === null || n <= 0 ? [] : [n];
  });
  const out = {
    governor: str(c["governor"]),
    avgMhz: num(c["mhz_avg"]),
    minMhz: num(c["mhz_min"]),
    maxMhz: num(c["mhz_max"]),
    cores,
  };
  if (!out.governor && out.avgMhz === null && cores.length === 0) return null;
  return out;
}

export function readLatencyHops(payload: Record<string, unknown> | null): LatencyHop[] {
  const l = obj(payload?.["latency_us"]);
  if (!l) return [];
  return Object.entries(l).flatMap(([target, raw]) => {
    const us = num(raw);
    // 0 is the agent's "probe did not complete", not a zero-millisecond path.
    if (us === null || us <= 0) return [];
    return [{
      target,
      ms: Math.round(us / 10) / 100,
      firstHop: target === "gateway",
    }];
  }).sort((a, b) => Number(b.firstHop) - Number(a.firstHop) || a.target.localeCompare(b.target));
}

// A filesystem's remaining headroom in days, from this reading alone: how long
// the currently used space took to accumulate is not in one sample, so this is
// deliberately NOT a fill-date projection. The agent's daily report does that
// properly from its own recorded history; inventing a trend from one row here
// would be a worse number wearing the same label.
export function headroomLabel(fs: Filesystem): string | null {
  if (fs.avail === null || fs.size === null || fs.size <= 0) return null;
  const pct = Math.round((fs.avail / fs.size) * 100);
  return `${pct}% free`;
}
