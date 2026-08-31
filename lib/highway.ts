// The Highway (hw-os) slice of a pushed metric payload.
//
// The agent stores its whole snapshot in metrics.payload as jsonb, so this is
// read out of an untyped bag rather than a column. Everything here is therefore
// parsed defensively: a field can be absent (older agent), null (the sensor or
// property could not be read) or a string where a number is expected (PostgREST
// round-trips numerics as strings in some shapes). A value that cannot be read
// stays null and renders as "—", never as 0 — a fabricated zero about a live
// node is worse than an admitted gap.
//
// Field names mirror lib/cloud.sh's `highway` object. Keep the two in step.

export type HighwayUnit = {
  name: string;
  state: string | null;
  sub: string | null;
  restarts: number | null;
  memory: number | null;
  activeFor: number | null;
};

export type HighwayHealth = "ok" | "warn" | "crit" | "absent" | "unknown";

export type HighwayState = {
  tracked: boolean;
  present: boolean;
  health: HighwayHealth;
  healthWhy: string | null;
  version: string | null;
  versionSrc: string | null;
  latest: string | null;
  updateAvailable: boolean;
  binPath: string | null;
  binSize: number | null;
  binMtime: number | null;
  unitsTotal: number | null;
  unitsActive: number | null;
  unitsFailed: number | null;
  units: HighwayUnit[];
  pid: number | null;
  cpuPct: number | null;
  rss: number | null;
  threads: number | null;
  fds: number | null;
  procUptime: number | null;
  meshIface: string | null;
  meshRxBps: number | null;
  meshTxBps: number | null;
  meshRxTotal: number | null;
  meshTxTotal: number | null;
  meshDrops: number | null;
  qdisc: string | null;
  qdiscDrops: number | null;
  congestion: string | null;
  nftTables: number | null;
  journalErr: number | null;
  journalWarn: number | null;
  journalTail: string[];
  // True when the payload carries only the six keys the pre-1.5 agent sent, so
  // the panel can say "upgrade the agent" instead of "this node has no
  // services" — which would be a claim about the server, not about the agent.
  legacyAgent: boolean;
};

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

function bool(v: unknown): boolean {
  return v === true || v === 1 || v === "1" || v === "true";
}

function health(v: unknown): HighwayHealth {
  switch (str(v)) {
    case "ok":
      return "ok";
    case "warn":
      return "warn";
    case "crit":
      return "crit";
    case "absent":
      return "absent";
    default:
      return "unknown";
  }
}

export function readHighway(payload: Record<string, unknown> | null): HighwayState | null {
  if (!payload || typeof payload !== "object") return null;
  const raw = payload["highway"];
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const h = raw as Record<string, unknown>;

  const units: HighwayUnit[] = Array.isArray(h["units"])
    ? (h["units"] as unknown[])
        .filter((u): u is Record<string, unknown> => !!u && typeof u === "object")
        .map((u) => ({
          name: str(u["name"]) ?? "unnamed unit",
          state: str(u["state"]),
          sub: str(u["sub"]),
          restarts: num(u["restarts"]),
          memory: num(u["memory"]),
          activeFor: num(u["active_s"]),
        }))
    : [];

  const cpuTenths = num(h["cpu_tenths"]);

  return {
    // An agent that predates the `tracked` flag was, by definition, tracking:
    // it would not have sent a highway object otherwise.
    tracked: "tracked" in h ? bool(h["tracked"]) : true,
    present: bool(h["present"]),
    health: health(h["health"]),
    healthWhy: str(h["health_why"]),
    version: str(h["version"]),
    versionSrc: str(h["version_src"]),
    latest: str(h["latest"]),
    updateAvailable: bool(h["update_available"]),
    binPath: str(h["bin_path"]),
    binSize: num(h["bin_size"]),
    binMtime: num(h["bin_mtime"]),
    unitsTotal: num(h["units_total"]) ?? (units.length > 0 ? units.length : null),
    unitsActive: num(h["units_active"]),
    unitsFailed: num(h["units_failed"]),
    units,
    pid: num(h["pid"]),
    cpuPct: cpuTenths === null ? null : Math.round(cpuTenths) / 10,
    rss: num(h["rss"]),
    threads: num(h["threads"]),
    fds: num(h["fds"]),
    procUptime: num(h["proc_uptime_s"]),
    meshIface: str(h["mesh_iface"]),
    meshRxBps: num(h["mesh_rx_bps"]),
    meshTxBps: num(h["mesh_tx_bps"]),
    meshRxTotal: num(h["mesh_rx_total"]),
    meshTxTotal: num(h["mesh_tx_total"]),
    meshDrops: num(h["mesh_drops"]),
    qdisc: str(h["qdisc"]),
    qdiscDrops: num(h["qdisc_drops"]),
    congestion: str(h["congestion"]),
    nftTables: num(h["nft_tables"]),
    journalErr: num(h["journal_err_1h"]),
    journalWarn: num(h["journal_warn_1h"]),
    journalTail: Array.isArray(h["journal_tail"])
      ? (h["journal_tail"] as unknown[]).map(str).filter((s): s is string => s !== null)
      : [],
    legacyAgent: !("units" in h),
  };
}

// A unit's state as one of the four things the UI colours by. systemd has more
// states than this (reloading, deactivating, activating); they group with
// "transitional" because the operator's question is only ever "is it up".
export type UnitTone = "ok" | "warn" | "crit" | "idle";

export function unitTone(unit: HighwayUnit): UnitTone {
  if (unit.state === "failed") return "crit";
  if (unit.state === "active") {
    // A unit that is up but has restarted repeatedly is the crash-loop case: it
    // reads as healthy in a single sample and is the thing worth surfacing.
    return unit.restarts !== null && unit.restarts >= 3 ? "warn" : "ok";
  }
  if (unit.state === "inactive") return "idle";
  return "warn";
}

// One verdict for "are the services okay", built from hw.units the same way
// unitTone colours each row, rather than re-deriving health from hw.health /
// hw.unitsFailed. hw.health already answers a slightly different question (it
// also weighs the mesh tunnel, the journal and the process itself), and the
// simple dashboard's promise is specifically about *services*: a node whose
// journal has a stray warning but every unit is active should not show red
// here even if the advanced health verdict is "warn".
//
// An inactive unit (one deliberately not started -- most nodes ship several
// optional services) is muted, not red: only a unit systemd reports as
// "failed" counts against the verdict. A crash-looping unit (unitTone "warn")
// is active but unhealthy, which is exactly the case the amber tone exists for.
export type ServicesVerdict = {
  tone: "ok" | "warn" | "crit" | "idle";
  label: string;
  activeCount: number;
  failedCount: number;
  inactiveCount: number;
};

export function servicesVerdict(hw: HighwayState | null): ServicesVerdict {
  if (!hw || !hw.present || !hw.tracked) {
    return { tone: "idle", label: "Not applicable", activeCount: 0, failedCount: 0, inactiveCount: 0 };
  }
  if (hw.units.length === 0) {
    // present + tracked but no unit rows: hw.pid tells us whether the process
    // itself is at least running, which is the best a summary-only or
    // unit-less reading can say.
    return hw.pid !== null
      ? { tone: "warn", label: "Running, unit detail unavailable", activeCount: 0, failedCount: 0, inactiveCount: 0 }
      : { tone: "crit", label: "Not running", activeCount: 0, failedCount: 0, inactiveCount: 0 };
  }

  let failed = 0;
  let active = 0;
  let looping = 0;
  let inactive = 0;
  for (const unit of hw.units) {
    const tone = unitTone(unit);
    if (tone === "crit") failed++;
    else if (tone === "warn") looping++;
    else if (tone === "idle") inactive++;
    else active++;
  }

  if (failed > 0) {
    return {
      tone: "crit",
      label: `${failed} service${failed === 1 ? "" : "s"} failed`,
      activeCount: active,
      failedCount: failed,
      inactiveCount: inactive,
    };
  }
  if (looping > 0) {
    return {
      tone: "warn",
      label: `${looping} service${looping === 1 ? "" : "s"} restarting repeatedly`,
      activeCount: active,
      failedCount: 0,
      inactiveCount: inactive,
    };
  }
  return {
    tone: "ok",
    label: active > 0 ? "All running services are okay" : "No services active",
    activeCount: active,
    failedCount: 0,
    inactiveCount: inactive,
  };
}
