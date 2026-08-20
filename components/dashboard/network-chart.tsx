"use client";

import { Area, AreaChart, CartesianGrid, XAxis, YAxis } from "recharts";
import {
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart";
import type { NetPoint } from "@/lib/dashboard-data";

const chartConfig: ChartConfig = {
  down: { label: "Down Mbit/s", color: "var(--chart-1)" },
  up: { label: "Up Mbit/s", color: "var(--chart-3)" },
};

// Download and upload deliberately share one Y axis: independent scales would
// make a 10 Mbit/s upload look identical to a 900 Mbit/s download, which is the
// same mistake the terminal UI's graphs are careful to avoid.
export function NetworkChart({ data }: { data: NetPoint[] }) {
  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 flex flex-col p-6 duration-500">
      <div>
        <p className="section-kicker">// network throughput</p>
        <p className="mt-2 font-sentient text-2xl text-card-foreground">Down vs. up</p>
      </div>
      <ChartContainer config={chartConfig} className="mt-6 aspect-auto h-[260px] w-full">
        <AreaChart data={data} margin={{ left: 0, right: 12, top: 8, bottom: 0 }}>
          <defs>
            <linearGradient id="netDownFill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--color-down)" stopOpacity={0.3} />
              <stop offset="100%" stopColor="var(--color-down)" stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid vertical={false} stroke="var(--border)" strokeOpacity={0.4} />
          <XAxis
            dataKey="time"
            tickLine={false}
            axisLine={false}
            minTickGap={48}
            tick={{ fill: "var(--muted-foreground)", fontSize: 11 }}
          />
          <YAxis
            tickLine={false}
            axisLine={false}
            width={44}
            tick={{ fill: "var(--muted-foreground)", fontSize: 11 }}
          />
          <ChartTooltip content={<ChartTooltipContent indicator="dot" labelKey="time" />} />
          <Area
            dataKey="down"
            type="monotone"
            stroke="var(--color-down)"
            strokeWidth={2}
            fill="url(#netDownFill)"
          />
          <Area
            dataKey="up"
            type="monotone"
            stroke="var(--color-up)"
            strokeWidth={2}
            fill="transparent"
          />
          <ChartLegend content={<ChartLegendContent />} />
        </AreaChart>
      </ChartContainer>
    </div>
  );
}
