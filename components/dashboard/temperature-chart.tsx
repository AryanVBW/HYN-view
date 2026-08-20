"use client";

import { Area, AreaChart, CartesianGrid, XAxis, YAxis } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart";
import { hasSeriesData, type TempPoint } from "@/lib/dashboard-data";

const chartConfig: ChartConfig = {
  celsius: { label: "CPU temperature", color: "var(--chart-1)" },
};

export function TemperatureChart({ data }: { data: TempPoint[] }) {
  // Most VPS guests expose no thermal sensor. Saying so is more useful than an
  // empty axis that looks like a bug.
  if (!hasSeriesData(data, "celsius")) {
    return (
      <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 flex flex-col p-6 duration-500">
        <p className="section-kicker">// cpu temperature</p>
        <p className="mt-2 font-sentient text-2xl text-card-foreground">No thermal sensor</p>
        <div className="mt-6 flex flex-1 items-center justify-center rounded-sm border border-dashed border-border/60 px-6 py-12">
          <p className="max-w-xs text-center font-mono text-xs leading-6 text-muted-foreground">
            This host does not publish a CPU temperature. That is normal inside a
            virtual machine — the hypervisor does not pass the sensor through.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 flex flex-col p-6 duration-500">
      <div className="flex items-center justify-between">
        <div>
          <p className="section-kicker">// cpu temperature</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">Thermal trace</p>
        </div>
      </div>
      <ChartContainer config={chartConfig} className="mt-6 aspect-auto h-[260px] w-full">
        <AreaChart data={data} margin={{ left: 0, right: 12, top: 8, bottom: 0 }}>
          <defs>
            <linearGradient id="tempFill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--color-celsius)" stopOpacity={0.35} />
              <stop offset="100%" stopColor="var(--color-celsius)" stopOpacity={0} />
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
            width={38}
            tick={{ fill: "var(--muted-foreground)", fontSize: 11 }}
            tickFormatter={(v) => `${v}°`}
          />
          <ChartTooltip content={<ChartTooltipContent indicator="line" labelKey="time" />} />
          <Area
            dataKey="celsius"
            type="monotone"
            stroke="var(--color-celsius)"
            strokeWidth={2}
            fill="url(#tempFill)"
            connectNulls
          />
        </AreaChart>
      </ChartContainer>
    </div>
  );
}
