"use client";

import { Cell, Pie, PieChart } from "recharts";
import { ChartContainer, type ChartConfig } from "@/components/ui/chart";
import type { Metric } from "@/lib/types";
import { formatBytes, formatDuration } from "@/lib/dashboard-data";

const chartConfig: ChartConfig = {
  used: { label: "Used", color: "var(--chart-1)" },
  free: { label: "Free", color: "var(--border)" },
};

function Gauge({
  label,
  pct,
  caption,
}: {
  label: string;
  pct: number | null;
  caption: string;
}) {
  const value = pct === null ? 0 : Math.min(100, Math.max(0, Number(pct)));
  const unknown = pct === null;
  // Colour by severity so the gauge is readable at a glance without reading the
  // number: the whole point of preferring a graphic here.
  const colour =
    unknown ? "var(--border)" : value >= 90 ? "var(--destructive)" : value >= 75 ? "#e8a400" : "var(--chart-1)";

  return (
    <div className="flex flex-col items-center">
      <div className="relative rounded-full transition-transform duration-300 hover:scale-[1.03]">
        <ChartContainer config={chartConfig} className="aspect-square h-[124px] w-[124px]">
          <PieChart>
            <Pie
              data={[
                { name: "used", value: unknown ? 0 : value },
                { name: "free", value: unknown ? 100 : 100 - value },
              ]}
              dataKey="value"
              nameKey="name"
              innerRadius={42}
              outerRadius={58}
              startAngle={90}
              endAngle={-270}
              stroke="none"
              isAnimationActive
            >
              <Cell fill={colour} />
              <Cell fill="var(--muted)" />
            </Pie>
          </PieChart>
        </ChartContainer>
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
          <span className="font-sentient text-xl text-card-foreground">
            {unknown ? "—" : `${value.toFixed(0)}%`}
          </span>
        </div>
      </div>
      <p className="mt-2 font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">
        {label}
      </p>
      <p className="font-mono text-[0.65rem] text-muted-foreground">{caption}</p>
    </div>
  );
}

export function HealthPanel({ latest }: { latest: Metric }) {
  const memCaption =
    latest.mem_used !== null && latest.mem_total !== null
      ? `${formatBytes(latest.mem_used)} / ${formatBytes(latest.mem_total)}`
      : "unknown";

  const loadPerCore =
    latest.load1 !== null && latest.cpu_cores
      ? `${((Number(latest.load1) / latest.cpu_cores) * 100).toFixed(0)}% per core`
      : "unknown";

  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 rounded-xl p-6 duration-500">
      <p className="section-kicker">// resource pressure</p>
      <p className="mt-2 font-sentient text-2xl text-card-foreground">Where the node stands</p>

      <div className="mt-6 grid grid-cols-2 gap-4 rounded-lg border border-border/60 bg-foreground/[0.02] p-4 sm:grid-cols-4">
        <Gauge label="CPU" pct={latest.cpu_pct} caption={loadPerCore} />
        <Gauge label="Memory" pct={latest.mem_pct} caption={memCaption} />
        <Gauge label="Disk" pct={latest.disk_pct} caption="root fs" />
        <Gauge
          label="Steal"
          pct={latest.cpu_steal}
          caption={latest.cpu_steal !== null && Number(latest.cpu_steal) > 5 ? "host oversold" : "healthy"}
        />
      </div>

      <dl className="mt-6 grid grid-cols-2 gap-3 border-t border-border/60 pt-4 sm:grid-cols-4">
        {[
          { k: "Uptime", v: formatDuration(latest.uptime_s) },
          {
            k: "iowait",
            v: latest.cpu_iowait === null ? "—" : `${Number(latest.cpu_iowait).toFixed(1)}%`,
          },
          {
            k: "Latency",
            v: latest.latency_ms === null ? "—" : `${Number(latest.latency_ms).toFixed(1)} ms`,
          },
          { k: "Swap", v: formatBytes(latest.swap_used) },
        ].map((row) => (
          <div key={row.k}>
            <dt className="font-mono text-[0.6rem] uppercase text-muted-foreground">{row.k}</dt>
            <dd className="mt-1 font-mono text-sm text-card-foreground">{row.v}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}
