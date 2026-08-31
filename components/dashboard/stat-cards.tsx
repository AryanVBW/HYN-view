import { Activity, Cpu, Gauge, HardDrive, Thermometer, Timer } from "lucide-react";
import type { Metric } from "@/lib/types";
import { bytesPerSecToMbit, formatDuration } from "@/lib/dashboard-data";

// A value that genuinely has no reading shows an em dash. Rendering 0 for an
// absent sensor is how a dashboard ends up lying about a healthy machine.
function num(value: number | null | undefined, suffix = "", digits = 0): string {
  if (value === null || value === undefined) return "—";
  return `${digits > 0 ? Number(value).toFixed(digits) : Math.round(Number(value))}${suffix}`;
}

export function StatCards({ latest }: { latest: Metric }) {
  const stats = [
    {
      label: "CPU usage",
      value: num(latest.cpu_pct, "%"),
      sub: latest.cpu_cores ? `${latest.cpu_cores} cores` : null,
      icon: Cpu,
    },
    {
      label: "Clock speed",
      value: latest.cpu_mhz === null ? "—" : `${(Number(latest.cpu_mhz) / 1000).toFixed(2)} GHz`,
      sub: latest.cpu_mhz === null ? "not exposed by host" : num(latest.cpu_mhz, " MHz"),
      icon: Gauge,
    },
    {
      label: "CPU temp",
      value: num(latest.cpu_temp_c, "°C", 1),
      sub: latest.cpu_temp_c === null ? "no sensor" : null,
      icon: Thermometer,
    },
    {
      label: "Memory",
      value: num(latest.mem_pct, "%", 1),
      sub: latest.load1 !== null ? `load ${Number(latest.load1).toFixed(2)}` : null,
      icon: Activity,
    },
    {
      label: "Disk",
      value: num(latest.disk_pct, "%", 1),
      sub: "root filesystem",
      icon: HardDrive,
    },
    {
      label: "Uptime",
      value: formatDuration(latest.uptime_s),
      sub: latest.latency_ms !== null ? `${Number(latest.latency_ms).toFixed(1)} ms latency` : null,
      icon: Timer,
    },
  ];

  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
      {stats.map((stat, i) => {
        const Icon = stat.icon;
        return (
          <div
            key={stat.label}
            style={{ animationDelay: `${i * 50}ms` }}
            className="animate-in fade-in slide-in-from-bottom-2 fill-mode-backwards group relative overflow-hidden rounded-xl border border-border bg-card px-5 py-5 duration-500 transition-colors hover:border-primary/40"
          >
            <div
              aria-hidden
              className="pointer-events-none absolute -right-6 -top-6 size-24 rounded-full bg-primary/10 opacity-0 blur-2xl transition-opacity duration-500 group-hover:opacity-100"
            />
            <div className="flex items-center justify-between">
              <p className="font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">
                {stat.label}
              </p>
              <span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/10">
                <Icon className="size-3.5 text-primary" aria-hidden />
              </span>
            </div>
            <p className="mt-3 font-sentient text-2xl text-card-foreground">{stat.value}</p>
            {stat.sub ? (
              <p className="mt-1 font-mono text-[0.65rem] text-muted-foreground">{stat.sub}</p>
            ) : null}
          </div>
        );
      })}
    </div>
  );
}

// Throughput headline, kept next to the cards because it is the number this tool
// exists to put first.
export function ThroughputCard({ latest }: { latest: Metric }) {
  const down = bytesPerSecToMbit(latest.net_rx_bps);
  const up = bytesPerSecToMbit(latest.net_tx_bps);
  const peak = Math.max(down, up, 1);
  const bars = [
    { label: "down", value: down, color: "var(--chart-1)" },
    { label: "up", value: up, color: "var(--chart-3)" },
  ];

  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 relative overflow-hidden rounded-xl p-6 duration-500">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 -z-10 bg-gradient-to-br from-primary/[0.06] via-transparent to-transparent"
      />
      <div className="flex items-baseline justify-between">
        <p className="section-kicker">// live throughput</p>
        <p className="font-mono text-xs text-muted-foreground">{latest.net_iface ?? "—"}</p>
      </div>
      <div className="mt-5 space-y-4">
        {bars.map((bar) => (
          <div key={bar.label}>
            <div className="flex items-baseline justify-between font-mono text-xs">
              <span className="uppercase text-muted-foreground">{bar.label}</span>
              <span className="text-card-foreground">{bar.value} Mbit/s</span>
            </div>
            <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-muted">
              <div
                className="h-full rounded-full shadow-[0_0_6px_var(--tw-shadow-color)] transition-[width] duration-700 ease-out"
                style={{ width: `${(bar.value / peak) * 100}%`, backgroundColor: bar.color, "--tw-shadow-color": bar.color } as React.CSSProperties}
              />
            </div>
          </div>
        ))}
      </div>
      {latest.net_retrans_pm !== null ? (
        <p className="mt-5 font-mono text-[0.65rem] text-muted-foreground">
          TCP retransmits {Number(latest.net_retrans_pm).toFixed(1)}‰ of segments sent
        </p>
      ) : null}
    </div>
  );
}
