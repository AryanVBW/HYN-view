import { readHighway, servicesVerdict } from "@/lib/highway";
import { bytesPerSecToMbit, formatBytes, formatDuration, formatRelative } from "@/lib/dashboard-data";
import type { Metric, Speedtest } from "@/lib/types";

// The simple dashboard: everything the advanced view shows, minus everything a
// non-technical viewer does not need to make sense of it. Answered once, in
// the order someone actually asks: is it running, how much data is moving right
// now, how fast can this link go, is it too hot, is there anything else worth a
// glance. No charts, no jargon, no panel that repeats a number another panel
// already gave.
//
// This is the web equivalent of the terminal's `0` view (lib/panels.sh
// render_simple) — same four sections, same "today's high" definition — so an
// administrator switching a client between the terminal and the browser is
// describing the same machine both times, not two different products.

function nodeVerdict(latest: Metric): { label: string; tone: "ok" | "warn" | "crit" | "idle"; detail: string } {
  const hw = readHighway(latest.payload);
  if (!hw || !hw.present) {
    return { label: "Not tracked", tone: "idle", detail: "This machine is not reporting a Highway node." };
  }
  if (hw.health === "ok") return { label: "Running", tone: "ok", detail: "The node and its services are healthy." };
  if (hw.health === "warn") return { label: "Needs attention", tone: "warn", detail: "One or more services are degraded." };
  if (hw.health === "crit") return { label: "Not running", tone: "crit", detail: "The node is down or a service has failed." };
  return { label: "Unknown", tone: "idle", detail: "No recent status from this machine." };
}

const TONE_CLASS: Record<string, string> = {
  ok: "border-primary/50 bg-primary/10 text-primary",
  warn: "border-[#e8a400]/50 bg-[#e8a400]/10 text-[#e8a400]",
  crit: "border-destructive/50 bg-destructive/10 text-destructive",
  idle: "border-border bg-muted/20 text-muted-foreground",
};

// Solid-fill twin of TONE_CLASS for the one badge per page that should read as
// a verdict rather than a label -- the node status pill and the services
// verdict. A tinted-border chip reads as informational; a filled one reads as
// a decision, which is the distinction this dashboard's first two sections
// exist to make at a glance.
const TONE_SOLID: Record<string, string> = {
  ok: "border-primary bg-primary text-primary-foreground",
  warn: "border-[#e8a400] bg-[#e8a400] text-[#0a0a0a]",
  crit: "border-destructive bg-destructive text-white",
  idle: "border-border bg-muted text-muted-foreground",
};

function tempTone(celsius: number | null): "ok" | "warn" | "crit" | "idle" {
  if (celsius === null || celsius === undefined) return "idle";
  if (celsius >= 85) return "crit";
  if (celsius >= 70) return "warn";
  return "ok";
}

function pctTone(pct: number | null): "ok" | "warn" | "crit" | "idle" {
  if (pct === null || pct === undefined) return "idle";
  if (pct >= 93) return "crit";
  if (pct >= 80) return "warn";
  return "ok";
}

// Best download recorded since local midnight, mirroring the agent's
// st_today_high_v: pick the winner among today's rows only, not the all-time
// best and not simply the latest.
function todayHigh(speedtests: Speedtest[]): { bps: number; ts: string } | null {
  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);
  const cutoff = startOfToday.getTime();
  let best: { bps: number; ts: string } | null = null;
  for (const row of speedtests) {
    if (row.down_bps === null || row.down_bps <= 0) continue;
    const t = new Date(row.ts).getTime();
    if (Number.isNaN(t) || t < cutoff) continue;
    if (!best || row.down_bps > best.bps) best = { bps: row.down_bps, ts: row.ts };
  }
  return best;
}

// The fastest thing this link has ever measured, upload or download, across
// every recorded test -- "how fast can this connection go" rather than "how
// fast was it a moment ago". today's-high already answers the recent-trend
// question elsewhere on this page, so this one is deliberately all-time.
function peakEver(speedtests: Speedtest[]): number {
  let best = 0;
  for (const row of speedtests) {
    if (row.down_bps !== null && row.down_bps > best) best = row.down_bps;
    if (row.up_bps !== null && row.up_bps > best) best = row.up_bps;
  }
  return best;
}

function SectionCard({
  kicker,
  title,
  children,
  accent = false,
}: {
  kicker: string;
  title?: React.ReactNode;
  children: React.ReactNode;
  accent?: boolean;
}) {
  return (
    <div
      className={`terminal-panel animate-in fade-in slide-in-from-bottom-2 rounded-xl p-6 duration-500 md:p-7 ${
        accent ? "relative overflow-hidden" : ""
      }`}
    >
      {accent ? (
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 -z-10 bg-gradient-to-br from-primary/[0.07] via-transparent to-transparent"
        />
      ) : null}
      <p className="section-kicker">{kicker}</p>
      {title ? <div className="mt-2 font-sentient text-2xl text-card-foreground">{title}</div> : null}
      <div className={title ? "mt-5" : "mt-1"}>{children}</div>
    </div>
  );
}

function EssentialCard({
  label,
  value,
  unit,
  tone,
}: {
  label: string;
  value: string;
  unit?: string;
  tone?: "ok" | "warn" | "crit" | "idle";
}) {
  return (
    <div className={`rounded-lg border px-4 py-3.5 ${tone ? TONE_CLASS[tone] : "border-border bg-card/60"}`}>
      <p className="font-mono text-[0.65rem] uppercase tracking-wide opacity-70">{label}</p>
      <p className="mt-1.5 font-sentient text-xl leading-none text-card-foreground">
        {value}
        {unit ? <span className="ml-1 text-sm font-normal opacity-70">{unit}</span> : null}
      </p>
    </div>
  );
}

// Only the fields this view actually reads, so it accepts both the
// client-facing Node and the admin's AdminNode without either owing the other
// a shape neither fully has.
type SimpleNode = { name: string; last_seen_at: string | null };

export function SimpleDashboard({
  node,
  latest,
  speedtests,
}: {
  node: SimpleNode;
  latest: Metric;
  speedtests: Speedtest[];
}) {
  const verdict = nodeVerdict(latest);
  const hw = readHighway(latest.payload);
  const services = servicesVerdict(hw);
  const down = bytesPerSecToMbit(latest.net_rx_bps);
  const up = bytesPerSecToMbit(latest.net_tx_bps);
  const high = todayHigh(speedtests);
  const peak = peakEver(speedtests);
  const temp = latest.cpu_temp_c;
  const tTone = tempTone(temp);
  const mTone = pctTone(latest.mem_pct);
  const dTone = pctTone(latest.disk_pct);
  const loadPerCore =
    latest.load1 !== null && latest.cpu_cores ? (Number(latest.load1) / latest.cpu_cores) * 100 : null;
  const pTone = pctTone(loadPerCore);

  return (
    <div className="space-y-6">
      {/* 1. Is it running, and are its services okay -- the two questions that
          outrank every other number on this page, so they sit first, biggest,
          and side by side: one glance answers both without further reading. */}
      <div className="grid gap-6 md:grid-cols-2">
        <SectionCard kicker="// node status" accent>
          <div className={`flex w-fit items-center gap-3 rounded-full border px-5 py-3 ${TONE_SOLID[verdict.tone]}`}>
            <span aria-hidden className="size-2.5 rounded-full bg-current opacity-80" />
            <span className="font-sentient text-xl">{verdict.label}</span>
          </div>
          <p className="mt-3 max-w-lg font-mono text-sm leading-6 text-muted-foreground">{verdict.detail}</p>
        </SectionCard>

        <SectionCard kicker="// highway services">
          <div className={`flex w-fit items-center gap-3 rounded-full border px-5 py-3 ${TONE_SOLID[services.tone]}`}>
            <span aria-hidden className="size-2.5 rounded-full bg-current opacity-80" />
            <span className="font-sentient text-xl">{services.label}</span>
          </div>
          <p className="mt-3 font-mono text-xs leading-6 text-muted-foreground">
            {services.tone === "idle"
              ? "No Highway node to track on this machine."
              : `${services.activeCount} running` +
                (services.inactiveCount > 0 ? ` · ${services.inactiveCount} not needed, inactive` : "") +
                (services.failedCount > 0 ? ` · ${services.failedCount} failed` : "")}
          </p>
        </SectionCard>
      </div>

      {/* 2. How much is moving right now, framed as data received / data sent
          -- the plain-language version of "throughput" -- next to the fastest
          test recorded today and the fastest this link has ever measured. */}
      <SectionCard kicker="// network">
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
          <div className="rounded-lg border border-border bg-gradient-to-br from-primary/10 to-transparent px-4 py-4">
            <p className="font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">Data received</p>
            <p className="mt-1.5 font-sentient text-3xl text-card-foreground">
              {down} <span className="text-sm font-normal text-muted-foreground">Mbps</span>
            </p>
            <p className="mt-1 font-mono text-[0.65rem] text-muted-foreground">right now, downloading</p>
          </div>
          <div className="rounded-lg border border-border bg-gradient-to-br from-[color-mix(in_oklab,var(--chart-3)_18%,transparent)] to-transparent px-4 py-4">
            <p className="font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">Data sent</p>
            <p className="mt-1.5 font-sentient text-3xl text-card-foreground">
              {up} <span className="text-sm font-normal text-muted-foreground">Mbps</span>
            </p>
            <p className="mt-1 font-mono text-[0.65rem] text-muted-foreground">right now, uploading</p>
          </div>
          <div className="rounded-lg border border-border px-4 py-4">
            <p className="font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">Fastest today</p>
            {high ? (
              <>
                <p className="mt-1.5 font-sentient text-3xl text-card-foreground">
                  {bytesPerSecToMbit(high.bps)} <span className="text-sm font-normal text-muted-foreground">Mbps</span>
                </p>
                <p className="mt-1 font-mono text-[0.65rem] text-muted-foreground">{formatRelative(high.ts)}</p>
              </>
            ) : (
              <p className="mt-3 font-mono text-xs text-muted-foreground">No speed test run yet today</p>
            )}
          </div>
          <div className="rounded-lg border border-border px-4 py-4">
            <p className="font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">
              Highest speed possible
            </p>
            {peak > 0 ? (
              <>
                <p className="mt-1.5 font-sentient text-3xl text-card-foreground">
                  {bytesPerSecToMbit(peak)} <span className="text-sm font-normal text-muted-foreground">Mbps</span>
                </p>
                <p className="mt-1 font-mono text-[0.65rem] text-muted-foreground">best ever recorded, either direction</p>
              </>
            ) : (
              <p className="mt-3 font-mono text-xs text-muted-foreground">No speed test recorded yet</p>
            )}
          </div>
        </div>
      </SectionCard>

      {/* 3. Is it too hot -- one figure, coloured against a fixed threshold
          rather than anything relative, so 70°C means the same thing here as
          it does on any other machine. */}
      <SectionCard kicker="// temperature">
        {temp === null || temp === undefined ? (
          <p className="font-mono text-sm text-muted-foreground">No temperature sensor on this machine.</p>
        ) : (
          <div className="flex items-center gap-4">
            <span className={`rounded-full border px-4 py-2 font-sentient text-2xl ${TONE_CLASS[tTone]}`}>
              {Math.round(temp)}°C
            </span>
            <span className="font-mono text-sm text-muted-foreground">
              {tTone === "crit" ? "Hotter than expected" : tTone === "warn" ? "Running warm" : "Normal range"}
            </span>
          </div>
        )}
      </SectionCard>

      {/* 4. Anything else worth a glance -- pressure, memory, disk, uptime, one
          card each. A reader who wants more than this reaches for Advanced. */}
      <SectionCard kicker="// essentials">
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <EssentialCard
            label="Load, per core"
            value={loadPerCore === null ? "—" : Math.round(loadPerCore).toString()}
            unit={loadPerCore === null ? undefined : "%"}
            tone={pTone}
          />
          <EssentialCard
            label="Memory"
            value={latest.mem_pct === null ? "—" : Math.round(latest.mem_pct).toString()}
            unit={latest.mem_pct === null ? undefined : "%"}
            tone={mTone}
          />
          <EssentialCard
            label="Disk"
            value={latest.disk_pct === null ? "—" : Math.round(latest.disk_pct).toString()}
            unit={latest.disk_pct === null ? undefined : "%"}
            tone={dTone}
          />
          <EssentialCard label="Uptime" value={formatDuration(latest.uptime_s)} />
        </div>
        {latest.mem_used !== null && latest.mem_total !== null ? (
          <p className="mt-4 font-mono text-xs text-muted-foreground">
            {formatBytes(latest.mem_used)} of {formatBytes(latest.mem_total)} memory in use
          </p>
        ) : null}
        <p className="mt-2 font-mono text-xs text-muted-foreground">
          {node.name} · last update {formatRelative(node.last_seen_at)}
        </p>
      </SectionCard>
    </div>
  );
}
