"use client";

import { Area, AreaChart, CartesianGrid, Line, XAxis, YAxis } from "recharts";
import {
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart";
import { hasSeriesData, type CpuPoint } from "@/lib/dashboard-data";

const chartConfig: ChartConfig = {
  usage: { label: "Utilization %", color: "var(--chart-1)" },
  mhz: { label: "Clock MHz", color: "var(--chart-3)" },
};

export function CpuUsageChart({ data }: { data: CpuPoint[] }) {
  const hasClock = hasSeriesData(data, "mhz");

  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 flex flex-col p-6 duration-500">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="section-kicker">// processor</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">
            Utilization {hasClock ? "& clock speed" : ""}
          </p>
        </div>
        {!hasClock ? (
          <span className="rounded-full border border-border px-3 py-1 font-mono text-[0.65rem] uppercase text-muted-foreground">
            clock not exposed
          </span>
        ) : null}
      </div>

      <ChartContainer config={chartConfig} className="mt-6 aspect-auto h-[260px] w-full">
        <AreaChart data={data} margin={{ left: 0, right: 12, top: 8, bottom: 0 }}>
          <defs>
            <linearGradient id="cpuUsageFill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--color-usage)" stopOpacity={0.35} />
              <stop offset="100%" stopColor="var(--color-usage)" stopOpacity={0} />
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
            yAxisId="usage"
            tickLine={false}
            axisLine={false}
            width={38}
            domain={[0, 100]}
            tick={{ fill: "var(--muted-foreground)", fontSize: 11 }}
            tickFormatter={(v) => `${v}%`}
          />
          {hasClock ? (
            <YAxis
              yAxisId="clock"
              orientation="right"
              tickLine={false}
              axisLine={false}
              width={46}
              tick={{ fill: "var(--muted-foreground)", fontSize: 11 }}
              tickFormatter={(v) => `${(Number(v) / 1000).toFixed(1)}G`}
            />
          ) : null}
          <ChartTooltip content={<ChartTooltipContent indicator="line" labelKey="time" />} />
          <Area
            yAxisId="usage"
            dataKey="usage"
            type="monotone"
            stroke="var(--color-usage)"
            strokeWidth={2}
            fill="url(#cpuUsageFill)"
            connectNulls
          />
          {hasClock ? (
            <Line
              yAxisId="clock"
              dataKey="mhz"
              type="monotone"
              stroke="var(--color-mhz)"
              strokeWidth={2}
              strokeDasharray="4 4"
              dot={false}
              connectNulls
            />
          ) : null}
          <ChartLegend content={<ChartLegendContent />} />
        </AreaChart>
      </ChartContainer>
    </div>
  );
}
