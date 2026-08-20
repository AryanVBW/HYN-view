"use client";

import { useEffect, useId, useState } from "react";
import {
  Area,
  AreaChart,
  CartesianGrid,
  Cell,
  Pie,
  PieChart,
  XAxis,
  YAxis,
} from "recharts";
import {
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart";
import type { AdminTrendPoint } from "@/lib/types";

export type AdminStat = {
  label: string;
  value: number;
  note: string;
  tone?: "bad" | "warn";
};

export type FleetStatusSlice = {
  key: "reporting" | "quiet" | "paused" | "suspended" | "revoked";
  label: string;
  value: number;
  color: string;
};

const trendConfig: ChartConfig = {
  cpu: { label: "Fleet CPU %", color: "var(--chart-1)" },
  down: { label: "Down Mbit/s", color: "var(--chart-1)" },
  up: { label: "Up Mbit/s", color: "var(--chart-3)" },
};

const statusConfig: ChartConfig = {
  reporting: { label: "Reporting", color: "var(--chart-1)" },
  quiet: { label: "Gone quiet", color: "var(--chart-5)" },
  paused: { label: "Paused", color: "var(--chart-2)" },
  suspended: { label: "Suspended", color: "var(--destructive)" },
  revoked: { label: "Revoked", color: "var(--chart-4)" },
};

function AnimatedNumber({ value }: { value: number }) {
  const [display, setDisplay] = useState(0);

  useEffect(() => {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const started = performance.now();
    const duration = reduced ? 1 : 650;
    let frame = 0;

    const draw = (now: number) => {
      const progress = Math.min(1, (now - started) / duration);
      const eased = 1 - Math.pow(1 - progress, 3);
      setDisplay(Math.round(value * eased));
      if (progress < 1) frame = requestAnimationFrame(draw);
    };
    frame = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(frame);
  }, [value]);

  return <>{display.toLocaleString()}</>;
}

export function AnimatedAdminStats({ stats }: { stats: AdminStat[] }) {
  return (
    <div className="grid gap-px overflow-hidden border border-border bg-border sm:grid-cols-2 lg:grid-cols-4">
      {stats.map((stat, index) => (
        <article
          key={stat.label}
          className="admin-stat-card bg-card px-5 py-5"
          style={{ animationDelay: `${index * 55}ms` }}
        >
          <p className="font-mono text-[0.62rem] uppercase tracking-[0.12em] text-muted-foreground">
            {stat.label}
          </p>
          <p
            className={`mt-3 font-sentient text-3xl tabular-nums ${
              stat.tone === "bad"
                ? "text-destructive"
                : stat.tone === "warn"
                  ? "text-[#e8a400]"
                  : "text-card-foreground"
            }`}
          >
            <AnimatedNumber value={stat.value} />
          </p>
          <p className="mt-2 font-mono text-[0.65rem] leading-5 text-muted-foreground">
            {stat.note}
          </p>
        </article>
      ))}
    </div>
  );
}

export function FleetOverviewCharts({
  trend,
  statuses,
}: {
  trend: AdminTrendPoint[];
  statuses: FleetStatusSlice[];
}) {
  const cpuGradient = `fleet-cpu-${useId().replace(/:/g, "")}`;
  const netGradient = `fleet-net-${useId().replace(/:/g, "")}`;
  const visibleStatuses = statuses.filter((status) => status.value > 0);

  if (trend.length === 0 && visibleStatuses.length === 0) {
    return (
      <div className="terminal-panel p-6 font-mono text-xs leading-6 text-muted-foreground">
        Fleet charts appear after the first machines report telemetry.
      </div>
    );
  }

  return (
    <section className="grid gap-6 xl:grid-cols-[1.2fr_1.2fr_0.8fr]" aria-label="Fleet telemetry overview">
      <article className="terminal-panel flex min-h-[340px] flex-col p-6">
        <p className="section-kicker">// fleet signal · 24h</p>
        <h2 className="mt-2 font-sentient text-2xl text-card-foreground">CPU pressure</h2>
        <p className="mt-2 font-mono text-xs leading-5 text-muted-foreground">
          Average utilization across every received sample.
        </p>
        {trend.length > 0 ? (
          <ChartContainer config={trendConfig} className="mt-5 aspect-auto h-[220px] w-full">
            <AreaChart data={trend} margin={{ left: 0, right: 12, top: 8 }}>
              <defs>
                <linearGradient id={cpuGradient} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="var(--color-cpu)" stopOpacity={0.4} />
                  <stop offset="100%" stopColor="var(--color-cpu)" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid vertical={false} stroke="var(--border)" strokeOpacity={0.45} />
              <XAxis dataKey="time" tickLine={false} axisLine={false} minTickGap={42} />
              <YAxis domain={[0, 100]} width={36} tickLine={false} axisLine={false} tickFormatter={(v) => `${v}%`} />
              <ChartTooltip content={<ChartTooltipContent indicator="line" labelKey="time" />} />
              <Area dataKey="cpu" type="monotone" stroke="var(--color-cpu)" strokeWidth={2} fill={`url(#${cpuGradient})`} connectNulls />
            </AreaChart>
          </ChartContainer>
        ) : (
          <ChartEmpty />
        )}
      </article>

      <article className="terminal-panel flex min-h-[340px] flex-col p-6">
        <p className="section-kicker">// observed traffic · 24h</p>
        <h2 className="mt-2 font-sentient text-2xl text-card-foreground">Network flow</h2>
        <p className="mt-2 font-mono text-xs leading-5 text-muted-foreground">
          Mean ingress and egress rates in each thirty-minute window.
        </p>
        {trend.length > 0 ? (
          <ChartContainer config={trendConfig} className="mt-5 aspect-auto h-[220px] w-full">
            <AreaChart data={trend} margin={{ left: 0, right: 12, top: 8 }}>
              <defs>
                <linearGradient id={netGradient} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="var(--color-down)" stopOpacity={0.35} />
                  <stop offset="100%" stopColor="var(--color-down)" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid vertical={false} stroke="var(--border)" strokeOpacity={0.45} />
              <XAxis dataKey="time" tickLine={false} axisLine={false} minTickGap={42} />
              <YAxis width={40} tickLine={false} axisLine={false} />
              <ChartTooltip content={<ChartTooltipContent indicator="dot" labelKey="time" />} />
              <Area dataKey="down" type="monotone" stroke="var(--color-down)" strokeWidth={2} fill={`url(#${netGradient})`} />
              <Area dataKey="up" type="monotone" stroke="var(--color-up)" strokeWidth={2} fill="transparent" />
              <ChartLegend content={<ChartLegendContent />} />
            </AreaChart>
          </ChartContainer>
        ) : (
          <ChartEmpty />
        )}
      </article>

      <article className="terminal-panel flex min-h-[340px] flex-col p-6">
        <p className="section-kicker">// node state</p>
        <h2 className="mt-2 font-sentient text-2xl text-card-foreground">Fleet posture</h2>
        {visibleStatuses.length > 0 ? (
          <ChartContainer config={statusConfig} className="mt-4 aspect-auto h-[250px] w-full" aria-label="Node status distribution">
            <PieChart>
              <ChartTooltip content={<ChartTooltipContent nameKey="key" hideLabel />} />
              <Pie data={visibleStatuses} dataKey="value" nameKey="key" innerRadius={52} outerRadius={82} paddingAngle={3} strokeWidth={0}>
                {visibleStatuses.map((status) => (
                  <Cell key={status.key} fill={status.color} />
                ))}
              </Pie>
              <ChartLegend content={<ChartLegendContent nameKey="key" />} />
            </PieChart>
          </ChartContainer>
        ) : (
          <ChartEmpty />
        )}
      </article>
    </section>
  );
}

function ChartEmpty() {
  return (
    <div className="mt-6 grid flex-1 place-items-center border border-dashed border-border font-mono text-xs text-muted-foreground">
      Waiting for telemetry
    </div>
  );
}
