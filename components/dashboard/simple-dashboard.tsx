"use client";

import { useRouter } from "next/navigation";
import { useId, useState } from "react";
import {
  ArrowUpRight,
  ChevronDown,
  Clock,
  Cpu,
  Gauge as GaugeIcon,
  HardDrive,
  LayoutGrid,
  MemoryStick,
  Thermometer,
  Trophy,
  type LucideIcon,
} from "lucide-react";
import { readHighway, servicesVerdict } from "@/lib/highway";
import {
  bytesPerSecToMbit,
  formatBytes,
  formatDuration,
  formatRelative,
  nearestSampleIndex,
  readSensors,
  toTempSeries,
} from "@/lib/dashboard-data";
import { readCpuClocks } from "@/lib/telemetry";
import { useAnimatedPct } from "@/lib/use-animated-pct";
import { writeViewMode } from "@/components/dashboard-view-toggle";
import { SpeedGauge } from "@/components/dashboard/speed-gauge";
import { ThermalGauge, thermalColor } from "@/components/dashboard/thermal-gauge";
import { RelayerDashboard } from "@/components/dashboard/relayer-dashboard";
import { ReadingAge } from "@/components/dashboard/reading-age";
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

// One verdict for "is the thing this box exists for running", built only from
// whether the Highway process/units are actually down -- not from the advanced
// health verdict, which also weighs the mesh tunnel and journal warnings a
// viewer of this page was never going to be shown anyway. A crash-looping or
// journal-noisy node still reads as "Running" here: those are real things to
// look at, and the small button below says so, but they are not "the node is
// down", and showing crit-red for them taught people to be alarmed by a
// service that is, in fact, up.
function mainServiceVerdict(hw: ReturnType<typeof readHighway>): {
  label: string;
  tone: "ok" | "crit" | "idle";
  detail: string;
} {
  if (!hw || !hw.tracked) {
    return { label: "Not tracked", tone: "idle", detail: "This machine is not reporting a Highway node." };
  }
  if (!hw.present) {
    return { label: "Not installed", tone: "idle", detail: "No Highway node on this machine." };
  }
  // "Down" is reserved for the one case that actually means it: the process
  // is not running and no unit is active either. Everything short of that —
  // including a legacy summary-only agent with no unit rows at all — reads as
  // running, because it is.
  const hasProcess = hw.pid !== null;
  const hasActiveUnit = (hw.unitsActive ?? 0) > 0 || hw.units.some((u) => u.state === "active");
  const down = !hasProcess && !hasActiveUnit && hw.units.length > 0;
  if (down) {
    return { label: "Not running", tone: "crit", detail: "The Highway process and its services are stopped." };
  }
  return { label: "Running", tone: "ok", detail: "The Highway node is up and doing its job." };
}

const TONE_CLASS: Record<string, string> = {
  ok: "border-primary/50 bg-primary/10 text-primary",
  warn: "border-[#e8a400]/50 bg-[#e8a400]/10 text-[#e8a400]",
  crit: "border-destructive/50 bg-destructive/10 text-destructive",
  idle: "border-border bg-muted/20 text-muted-foreground",
};

// Solid-fill twin of TONE_CLASS for the one badge per page that should read as
// a verdict rather than a label -- the node status pill. A tinted-border chip
// reads as informational; a filled one reads as a decision, which is the
// distinction this dashboard's first section exists to make at a glance.
const TONE_SOLID: Record<string, string> = {
  ok: "border-primary bg-primary text-primary-foreground",
  warn: "border-[#e8a400] bg-[#e8a400] text-[#0a0a0a]",
  crit: "border-destructive bg-destructive text-white",
  idle: "border-border bg-muted text-muted-foreground",
};

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

// The known top speed of this connection, per the ISP plan -- not derived
// from anything the agent measures. A speedometer's scale is fixed to the
// vehicle's actual top speed, not to "the fastest I've personally driven it";
// using the recorded peak as the dial's ceiling meant a link that had never
// been pushed to its real limit showed a needle sitting near full sweep on an
// ordinary reading, which is backwards. Change this if your plan changes.
const CONNECTION_PLAN_MBPS = 300;

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

// The verdict pill's status dot. "Running" gets a heartbeat -- an expanding
// ring that pulses outward and fades, the same visual grammar a phone's
// call-in-progress or screen-recording dot uses for "this is live, right
// now", conveying the one fact this whole card exists to state. Anything
// short of that tone (crit, idle) gets a plain static dot: pulsing on "not
// running" or "not tracked" would be motion asserting the opposite of what
// the label says, which is a worse failure than looking static.
function RunningDot({ tone }: { tone: "ok" | "crit" | "idle" }) {
  if (tone !== "ok") {
    return <span aria-hidden className="size-2.5 rounded-full bg-current opacity-80" />;
  }
  return (
    <span aria-hidden className="relative flex size-2.5 items-center justify-center">
      <span className="node-heartbeat-ring absolute inset-0 rounded-full bg-current" />
      <span className="relative size-2.5 rounded-full bg-current" />
    </span>
  );
}

// A percentage essential, drawn as a small radial ring rather than a plain
// number -- the same instrument language the network and temperature dials
// already use, so this section reads as more of the same cluster instead of
// a plainer afterthought underneath it. The ring fills in on mount (see
// useAnimatedPct) instead of appearing pre-drawn, which is the one animation
// this card needs: it conveys "this is a live reading", not decoration for
// its own sake.
function EssentialRing({
  label,
  icon: Icon,
  pct,
  tone,
  detail,
}: {
  label: string;
  icon: LucideIcon;
  /** 0-100, or null when the machine reports no reading for this metric. */
  pct: number | null;
  tone: "ok" | "warn" | "crit" | "idle";
  detail?: string;
}) {
  const color =
    tone === "crit" ? "var(--destructive)" : tone === "warn" ? "#e8a400" : tone === "ok" ? "var(--primary)" : "var(--muted-foreground)";
  const size = 72;
  const r = 30;
  const circumference = 2 * Math.PI * r;
  const target = pct === null ? 0 : Math.max(0, Math.min(100, pct));
  const { value: fill, ref: svgRef } = useAnimatedPct<SVGSVGElement>(target);

  const offset = circumference * (1 - fill / 100);

  return (
    <div className={`rounded-lg border px-4 py-3.5 ${tone !== "idle" ? TONE_CLASS[tone] : "border-border bg-card/60"}`}>
      <div className="flex items-center gap-3">
        <svg ref={svgRef} viewBox={`0 0 ${size} ${size}`} className="size-14 shrink-0" role="img" aria-label={`${label}: ${pct === null ? "no reading" : `${Math.round(pct)}%`}`}>
          <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--border)" strokeWidth={6} opacity={0.5} />
          {pct !== null ? (
            <circle
              cx={size / 2}
              cy={size / 2}
              r={r}
              fill="none"
              stroke={color}
              strokeWidth={6}
              strokeLinecap="round"
              strokeDasharray={circumference}
              strokeDashoffset={offset}
              transform={`rotate(-90 ${size / 2} ${size / 2})`}
            />
          ) : null}
          <Icon
            x={size / 2 - 8}
            y={size / 2 - 8}
            width={16}
            height={16}
            color={pct === null ? "var(--muted-foreground)" : color}
          />
        </svg>
        <div className="min-w-0">
          <p className="font-mono text-[0.65rem] uppercase tracking-wide opacity-70">{label}</p>
          <p className="mt-0.5 font-sentient text-xl leading-none text-card-foreground">
            {pct === null ? "—" : Math.round(pct)}
            {pct === null ? null : <span className="ml-1 text-sm font-normal opacity-70">%</span>}
          </p>
          {detail ? <p className="mt-1 truncate font-mono text-[0.6rem] opacity-70" title={detail}>{detail}</p> : null}
        </div>
      </div>
    </div>
  );
}

// The small button: collapsed, it says nothing alarming even when there is a
// failure to report, because "1 failed" next to a green "Running" pill is
// information, not a verdict -- the verdict already happened above. Expanding
// it shows the exact breakdown the user asked for (failed / inactive / not
// needed) and a one-click way to the Advanced dashboard, which is where that
// detail actually lives.
function ServiceDetailButton({ services }: { services: ReturnType<typeof servicesVerdict> }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);

  if (services.tone === "idle") return null;

  const goAdvanced = () => {
    writeViewMode("dash");
    router.push("/dashboard");
  };

  return (
    <div className="mt-4">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        className="flex items-center gap-2 rounded-full border border-border px-3.5 py-1.5 font-mono text-[0.7rem] uppercase tracking-wide text-muted-foreground transition-colors hover:border-primary/50 hover:text-foreground"
      >
        Service detail
        <ChevronDown className={`size-3.5 transition-transform ${open ? "rotate-180" : ""}`} aria-hidden />
      </button>

      {open ? (
        <div className="mt-3 flex flex-wrap items-center gap-2 rounded-lg border border-border bg-card/60 px-4 py-3">
          <span className="font-mono text-xs text-muted-foreground">
            {services.failedCount} failed · {services.inactiveCount} inactive, not needed
          </span>
          <button
            type="button"
            onClick={goAdvanced}
            className="ml-auto flex items-center gap-1.5 rounded-full bg-primary px-3 py-1.5 font-mono text-[0.65rem] uppercase text-primary-foreground transition-opacity hover:opacity-90"
          >
            <LayoutGrid className="size-3" aria-hidden />
            Open advanced dashboard
          </button>
        </div>
      ) : null}
    </div>
  );
}

// Only the fields this view actually reads, so it accepts both the
// client-facing Node and the admin's AdminNode without either owing the other
// a shape neither fully has.
type SimpleNode = { name: string; last_seen_at: string | null; config?: Record<string, unknown> | null };

export function SimpleDashboard({
  node,
  latest,
  speedtests,
  metrics,
  relayerNodeId,
}: {
  node: SimpleNode;
  latest: Metric;
  speedtests: Speedtest[];
  /** Last 24h of readings, oldest-first, for the temperature history strip.
   *  Optional so a caller that has not fetched history yet still renders. */
  metrics?: Metric[];
  /** Only the explicit admin link for this server is shown. */
  relayerNodeId?: string;
}) {
  const hw = readHighway(latest.payload);
  const verdict = mainServiceVerdict(hw);
  const services = servicesVerdict(hw);
  const high = todayHigh(speedtests);
  const peak = peakEver(speedtests);
  // The recorded peak is authoritative whenever one exists -- the link's
  // negotiated speed (e.g. a 10 Gbps NIC, 10000 Mbps) is a theoretical
  // ceiling real throughput never reaches, so using it as anything but a
  // last-resort floor put the gauge's needle a fraction of the way round on
  // every real reading. Only fall back to it when there is truly nothing
  // recorded yet, so a fresh install still gets a real ceiling instead of the
  // gauge's generic 100 Mbps floor.
  const peakMbit =
    peak > 0
      ? bytesPerSecToMbit(peak)
      : bytesPerSecToMbit(latest.net_link_mbps ? (latest.net_link_mbps * 1_000_000) / 8 : 0);
  const temp = latest.cpu_temp_c;
  const sensors = readSensors(latest.payload);
  const clock = readCpuClocks(latest.payload);
  const tempHistory = metrics && metrics.length > 1 ? toTempSeries(metrics) : [];
  const mTone = pctTone(latest.mem_pct);
  const dTone = pctTone(latest.disk_pct);
  const loadPerCore =
    latest.load1 !== null && latest.cpu_cores ? (Number(latest.load1) / latest.cpu_cores) * 100 : null;
  const pTone = pctTone(loadPerCore);

  return (
    <div className="space-y-6">
      {/* 1. Is it running -- the one question that outranks every other number
          on this page, answered once, calmly. Failed/inactive counts are
          available on demand behind the small button, not thrown at the
          reader alongside the verdict. */}
      <SectionCard kicker="// highway node" accent>
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="min-w-0 flex-1">
            <div className={`flex w-fit items-center gap-3 rounded-full border px-5 py-3 ${TONE_SOLID[verdict.tone]}`}>
              <RunningDot tone={verdict.tone} />
              <span className="font-sentient text-xl">{verdict.label}</span>
            </div>
            <p className="mt-3 max-w-lg font-mono text-sm leading-6 text-muted-foreground">{verdict.detail}</p>
            {relayerNodeId ? (
              <RelayerDashboard key={relayerNodeId} nodeId={relayerNodeId} compact />
            ) : null}
            {services.tone !== "idle" ? (
              <span className="mt-3 inline-flex rounded-full border border-border px-3 py-1.5 font-mono text-xs text-muted-foreground">
                {services.activeCount} service{services.activeCount === 1 ? "" : "s"} up
              </span>
            ) : null}
          </div>
          {/* The animated server-rack illustration, right-aligned, only while
              the node is actually running -- it depicts an active operation
              (a drone circling live server units), so showing it next to
              "Not running" or "Not tracked" would visually assert the
              opposite of the verdict beside it, the same reason RunningDot's
              own heartbeat is gated on `ok`. The node's own name sits at its
              bottom-left corner, small and dim, so the animation reads as
              "this specific machine is doing work" rather than generic
              decoration with no attachment to what's actually running. */}
          {verdict.tone === "ok" ? (
            <div className="relative hidden shrink-0 sm:block">
              <img
                src="/server.svg"
                alt=""
                aria-hidden
                className="h-auto w-48 select-none md:w-56"
              />
              <span className="absolute bottom-1 left-1 rounded-full border border-border/60 bg-background/80 px-2 py-0.5 font-mono text-[0.6rem] text-muted-foreground backdrop-blur-sm">
                {node.name}
              </span>
            </div>
          ) : null}
        </div>
        <ServiceDetailButton services={services} />
      </SectionCard>

      {/* 2. How fast this link tested today, and how fast it can go at its
          best -- drawn as a pair of speedometers scaled to this connection's
          actual plan speed, so the dial's own top end means something fixed
          (what this link is rated for) rather than drifting with whatever
          the best test happened to record. The live receive/send rate used
          to sit here too; dropped in favour of just these two recorded
          results, which is what "how fast is this connection" actually means
          to someone who runs a speed test to find out. */}
      <SectionCard kicker="// network">
        <div className="grid gap-6 sm:grid-cols-2">
          <div className="flex justify-center">
            <SpeedGauge
              label="Fastest today"
              icon={ArrowUpRight}
              valueMbps={high ? bytesPerSecToMbit(high.bps) : 0}
              valueLabel="MBPS TODAY"
              peakMbps={CONNECTION_PLAN_MBPS}
              markerMbps={peakMbit > 0 ? peakMbit : null}
              markerLabel="EVER"
              color="var(--chart-1)"
            />
            <p className="sr-only">{high ? formatRelative(high.ts) : "No test run yet today"}</p>
          </div>
          <div className="flex justify-center">
            <SpeedGauge
              label="Highest speed possible"
              icon={Trophy}
              valueMbps={peakMbit}
              valueLabel="MBPS EVER"
              peakMbps={CONNECTION_PLAN_MBPS}
              color="var(--chart-3)"
            />
          </div>
        </div>
        <p className="mt-2 text-center font-mono text-[0.65rem] text-muted-foreground">
          {high
            ? `today's best was ${formatRelative(high.ts)}`
            : "no speed test run yet today"}
          {peak > 0 ? ` · best ever recorded, either direction` : " · no speed test recorded yet"}
        </p>
      </SectionCard>

      {/* 3. Is it too hot -- a thermal dial in the same instrument style as the
          network gauges, next to every sensor the platform actually exposes
          and the clock speed that is usually the other half of "why is it
          hot". History is the last 24h at a glance, not a number that could
          be a one-off spike or a sustained climb. */}
      <SectionCard kicker="// temperature">
        {temp === null || temp === undefined ? (
          <p className="font-mono text-sm text-muted-foreground">No temperature sensor on this machine.</p>
        ) : (
          <div className="grid gap-6 lg:grid-cols-[auto_1fr]">
            <div className="flex justify-center">
              <ThermalGauge celsius={temp} />
            </div>
            <div className="space-y-5">
              {sensors.length > 0 ? (
                <div>
                  <p className="font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">
                    Every sensor on this machine
                  </p>
                  <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-3">
                    {sensors.map((s) => (
                      <div key={s.label} className="flex items-center gap-2 rounded-md border border-border/60 px-3 py-2">
                        <Thermometer className="size-3.5 shrink-0" style={{ color: thermalColor(s.celsius) }} aria-hidden />
                        <span className="truncate font-mono text-xs text-card-foreground" title={s.label}>
                          {s.label}
                        </span>
                        <span className="ml-auto font-mono text-xs" style={{ color: thermalColor(s.celsius) }}>
                          {s.celsius.toFixed(0)}°
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              ) : null}

              {clock && (clock.avgMhz || clock.cores.length > 0) ? (
                <div>
                  <p className="flex items-center gap-1.5 font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">
                    <GaugeIcon className="size-3" aria-hidden /> Clock speed
                    {clock.governor ? <span className="ml-1 opacity-70">· {clock.governor} governor</span> : null}
                  </p>
                  <div className="mt-2 flex flex-wrap gap-4 font-mono text-xs text-card-foreground">
                    {clock.minMhz ? <span>min {(clock.minMhz / 1000).toFixed(2)} GHz</span> : null}
                    {clock.avgMhz ? <span className="text-primary">avg {(clock.avgMhz / 1000).toFixed(2)} GHz</span> : null}
                    {clock.maxMhz ? <span>max {(clock.maxMhz / 1000).toFixed(2)} GHz</span> : null}
                  </div>
                  {clock.cores.length > 0 ? (
                    <div className="mt-2 flex flex-wrap gap-1.5">
                      {clock.cores.map((mhz, i) => (
                        <span
                          key={i}
                          className="flex items-center gap-1 rounded border border-border/60 px-2 py-1 font-mono text-[0.65rem] text-muted-foreground"
                          title={`core ${i}`}
                        >
                          <Cpu className="size-2.5" aria-hidden />
                          {(mhz / 1000).toFixed(1)}
                        </span>
                      ))}
                    </div>
                  ) : null}
                </div>
              ) : null}

              {tempHistory.length > 1 ? (
                <TempHistoryCard points={tempHistory} />
              ) : null}
            </div>
          </div>
        )}
      </SectionCard>

      {/* 4. Anything else worth a glance -- load, memory, disk as radial
          instruments matching the gauges above, uptime as plain text since it
          isn't a percentage. A reader who wants more than this reaches for
          Advanced. */}
      <SectionCard kicker="// essentials">
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <EssentialRing label="Load, per core" icon={Cpu} pct={loadPerCore} tone={pTone} />
          <EssentialRing
            label="Memory"
            icon={MemoryStick}
            pct={latest.mem_pct}
            tone={mTone}
            detail={
              latest.mem_used !== null && latest.mem_total !== null
                ? `${formatBytes(latest.mem_used)} / ${formatBytes(latest.mem_total)}`
                : undefined
            }
          />
          <EssentialRing label="Disk" icon={HardDrive} pct={latest.disk_pct} tone={dTone} />
          <div className="flex items-center gap-3 rounded-lg border border-border bg-card/60 px-4 py-3.5">
            <span className="flex size-14 shrink-0 items-center justify-center rounded-full border border-border/60">
              <Clock className="size-5 text-muted-foreground" aria-hidden />
            </span>
            <div>
              <p className="font-mono text-[0.65rem] uppercase tracking-wide opacity-70">Uptime</p>
              <p className="mt-0.5 font-sentient text-xl leading-none text-card-foreground">
                {formatDuration(latest.uptime_s)}
              </p>
            </div>
          </div>
        </div>
        <p className="mt-4 font-mono text-xs text-muted-foreground">
          {node.name} · latest reading <ReadingAge sampleAt={latest.ts} intervalMinutes={node.config?.cloud_push_min} />
        </p>
      </SectionCard>
    </div>
  );
}

// The 24-hour history strip: a filled area trace rather than a bare
// polyline, in the same gradient-under-a-line language the advanced
// dashboard's own TemperatureChart uses (see temperature-chart.tsx's
// `tempFill` gradient) -- one visual vocabulary for "temperature over time"
// across both dashboards, not a second, plainer chart invented for this one.
// Coloured by the *current* reading's zone (thermalColor) rather than a fixed
// hue, so a history strip under a red gauge reads as urgent at a glance and a
// history strip under a green one reads calm, matching the needle above it
// instead of contradicting it in a different colour.
//
// It answers "climbing, flat, or falling" at a glance and, on hover, "what was
// it at 14:32" -- the question people actually ask of a trace once they can see
// a bump in it. recharts' <ChartContainer>/axis apparatus is still skipped: a
// crosshair and one readout is the whole interaction, and it costs less than the
// machinery would. Hover snaps to the nearest real sample, so a gap where the
// machine sent nothing reads as the reading either side of it rather than as an
// invented value.
function TempHistoryCard({ points }: { points: { time: string; celsius: number | null }[] }) {
  // Must run before the early return below -- hooks cannot be called
  // conditionally, and an early `return null` for "not enough points yet"
  // would otherwise skip this call on some renders and not others.
  const glowId = `temphist-${useId().replace(/:/g, "")}`;
  const readoutId = `${glowId}-readout`;
  const [hoverIndex, setHoverIndex] = useState<number | null>(null);
  const values = points.map((p) => p.celsius).filter((c): c is number => c !== null);
  if (values.length < 2) return null;

  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = Math.max(max - min, 2);
  const w = 400;
  const h = 96;
  const padTop = 14;
  const padBottom = 20;
  const plotH = h - padTop - padBottom;
  const step = w / (points.length - 1);

  const color = thermalColor(values[values.length - 1]);

  // Sample index is kept alongside the plotted coordinates so a hover can name
  // the time of the reading it landed on, not just its value.
  const plotted = points.flatMap((p, i) =>
    p.celsius === null
      ? []
      : [{ i, x: i * step, y: padTop + plotH - ((p.celsius - min) / span) * plotH, celsius: p.celsius }]
  );
  const lineStr = plotted.map((p) => `${p.x},${p.y}`).join(" ");
  const areaStr = `${plotted[0].x},${padTop + plotH} ${lineStr} ${plotted[plotted.length - 1].x},${padTop + plotH}`;
  const last = plotted[plotted.length - 1];
  const hovered = hoverIndex === null ? null : plotted[Math.min(hoverIndex, plotted.length - 1)];

  // Pointer, not mouse: the same handler serves a trackpad and a finger dragged
  // along the strip, which is the only way to read one on a phone.
  function track(clientX: number, element: HTMLElement) {
    const rect = element.getBoundingClientRect();
    if (rect.width === 0) return;
    const at = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width)) * w;
    setHoverIndex(nearestSampleIndex(plotted.map((p) => p.x), at));
  }

  function moveHover(by: number) {
    setHoverIndex((current) => {
      const from = current ?? plotted.length - 1;
      return Math.min(plotted.length - 1, Math.max(0, from + by));
    });
  }

  return (
    <div className="rounded-lg border border-border/60 bg-card/40 p-3">
      <div className="flex items-baseline justify-between">
        <p className="font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">Last 24 hours</p>
        <p className="font-mono text-[0.65rem]" style={{ color }}>
          now {values[values.length - 1].toFixed(0)}°
        </p>
      </div>
      <div
        className="relative mt-2 cursor-crosshair rounded-sm outline-none focus-visible:ring-1 focus-visible:ring-ring"
        tabIndex={0}
        aria-describedby={readoutId}
        onPointerMove={(event) => track(event.clientX, event.currentTarget)}
        onPointerLeave={() => setHoverIndex(null)}
        onBlur={() => setHoverIndex(null)}
        onKeyDown={(event) => {
          if (event.key === "ArrowLeft") moveHover(-1);
          else if (event.key === "ArrowRight") moveHover(1);
          else if (event.key === "Home") setHoverIndex(0);
          else if (event.key === "End") setHoverIndex(plotted.length - 1);
          else if (event.key === "Escape") setHoverIndex(null);
          else return;
          event.preventDefault();
        }}
      >
        <svg
          viewBox={`0 0 ${w} ${h}`}
          className="h-24 w-full"
          preserveAspectRatio="none"
          role="img"
          aria-label={`Temperature over the last 24 hours, ${min.toFixed(0)} to ${max.toFixed(0)} degrees, currently ${values[values.length - 1].toFixed(0)} degrees. Hover or use the arrow keys to read one sample.`}
        >
          <defs>
            <linearGradient id={glowId} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={color} stopOpacity={0.4} />
              <stop offset="100%" stopColor={color} stopOpacity={0} />
            </linearGradient>
          </defs>
          {/* Two faint horizontal gridlines (33%/66% of the range) for scale
              reference -- enough to judge "how much did it move" without the
              full axis apparatus a labelled grid would need. */}
          <line x1={0} y1={padTop + plotH / 3} x2={w} y2={padTop + plotH / 3} stroke="var(--border)" strokeWidth={1} opacity={0.3} />
          <line x1={0} y1={padTop + (plotH * 2) / 3} x2={w} y2={padTop + (plotH * 2) / 3} stroke="var(--border)" strokeWidth={1} opacity={0.3} />
          <polygon points={areaStr} fill={`url(#${glowId})`} />
          <polyline points={lineStr} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
          {/* Current-value marker: a glowing dot at the most recent reading, the
              same "this is live" language the speed gauges' needle-tip pulse
              and the node-status heartbeat use elsewhere on this page. */}
          <circle cx={last.x} cy={last.y} r={7} fill={color} opacity={0.25} />
          <circle cx={last.x} cy={last.y} r={3} fill={color} />
          {hovered ? (
            <>
              {/* The crosshair is drawn in the hovered sample's own zone colour,
                  so a hover into a hot stretch of an otherwise green trace says
                  so rather than repeating the strip's current-reading hue. */}
              <line
                x1={hovered.x}
                y1={padTop - 6}
                x2={hovered.x}
                y2={padTop + plotH}
                stroke={thermalColor(hovered.celsius)}
                strokeWidth={1}
                strokeDasharray="3 3"
                opacity={0.8}
              />
              <circle cx={hovered.x} cy={hovered.y} r={4} fill="var(--card)" stroke={thermalColor(hovered.celsius)} strokeWidth={2} />
            </>
          ) : null}
          <text x={0} y={h - 4} fontFamily="var(--font-mono)" fontSize={9} fill="var(--muted-foreground)">
            24h ago
          </text>
          <text x={w} y={h - 4} textAnchor="end" fontFamily="var(--font-mono)" fontSize={9} fill="var(--muted-foreground)">
            now
          </text>
        </svg>
        {hovered ? (
          <div
            className="pointer-events-none absolute top-0 -translate-x-1/2 whitespace-nowrap rounded-sm border border-border bg-card px-2 py-1 font-mono text-[0.65rem] shadow-sm"
            // Clamped away from both edges so the readout never hangs outside
            // the card at the ends of the trace, where people hover most.
            style={{ left: `${Math.min(88, Math.max(12, (hovered.x / w) * 100))}%` }}
          >
            <span className="text-muted-foreground">{points[hovered.i].time}</span>{" "}
            <span style={{ color: thermalColor(hovered.celsius) }}>{hovered.celsius.toFixed(1)}°C</span>
          </div>
        ) : null}
      </div>
      <p id={readoutId} role="status" className="sr-only">
        {hovered ? `${points[hovered.i].time}, ${hovered.celsius.toFixed(1)} degrees` : ""}
      </p>
      <div className="mt-1 flex justify-between font-mono text-[0.6rem] text-muted-foreground">
        <span>low {min.toFixed(0)}°</span>
        <span>high {max.toFixed(0)}°</span>
      </div>
    </div>
  );
}
