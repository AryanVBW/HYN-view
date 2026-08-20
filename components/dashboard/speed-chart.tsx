"use client";

import { Bar, BarChart, CartesianGrid, XAxis, YAxis } from "recharts";
import {
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart";
import type { SpeedPoint } from "@/lib/dashboard-data";

const chartConfig: ChartConfig = {
  download: { label: "Download Mbit/s", color: "var(--chart-1)" },
  upload: { label: "Upload Mbit/s", color: "var(--chart-3)" },
};

export function SpeedChart({ data }: { data: SpeedPoint[] }) {
  if (data.length === 0) {
    return (
      <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 flex flex-col p-6 duration-500">
        <p className="section-kicker">// throughput tests</p>
        <p className="mt-2 font-sentient text-2xl text-card-foreground">No speed tests yet</p>
        <div className="mt-6 flex flex-1 items-center justify-center rounded-sm border border-dashed border-border/60 px-6 py-12">
          <p className="max-w-xs text-center font-mono text-xs leading-6 text-muted-foreground">
            Scheduled tests run four times a day once the timers are installed.
            Run one now with <code className="text-primary">hyn speedtest</code>.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 flex flex-col p-6 duration-500">
      <div>
        <p className="section-kicker">// throughput tests</p>
        <p className="mt-2 font-sentient text-2xl text-card-foreground">Measured speed</p>
      </div>
      <ChartContainer config={chartConfig} className="mt-6 aspect-auto h-[240px] w-full">
        <BarChart data={data} margin={{ left: 0, right: 12, top: 8, bottom: 0 }}>
          <CartesianGrid vertical={false} stroke="var(--border)" strokeOpacity={0.4} />
          <XAxis
            dataKey="time"
            tickLine={false}
            axisLine={false}
            minTickGap={24}
            tick={{ fill: "var(--muted-foreground)", fontSize: 11 }}
          />
          <YAxis
            tickLine={false}
            axisLine={false}
            width={44}
            tick={{ fill: "var(--muted-foreground)", fontSize: 11 }}
          />
          <ChartTooltip content={<ChartTooltipContent indicator="dot" labelKey="time" />} />
          <Bar dataKey="download" fill="var(--color-download)" radius={[2, 2, 0, 0]} />
          <Bar dataKey="upload" fill="var(--color-upload)" radius={[2, 2, 0, 0]} />
          <ChartLegend content={<ChartLegendContent />} />
        </BarChart>
      </ChartContainer>
    </div>
  );
}
