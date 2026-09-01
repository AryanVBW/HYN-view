"use client";

import { useId, useState } from "react";
import { Area, AreaChart, CartesianGrid, XAxis, YAxis } from "recharts";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart";
import { hasSeriesData, type TempPoint } from "@/lib/dashboard-data";
import { thermalColor } from "@/components/dashboard/thermal-gauge";

const chartConfig: ChartConfig = {
  celsius: { label: "CPU temperature", color: "var(--chart-1)" },
};

// One gradient stop per data point plus one extra pair of stops at every
// safe/moderate/hot boundary (55° and 85°) actually crossed between two
// consecutive samples, so the line and its fill change colour at the true
// crossing time rather than only at whichever sample happened to land nearest
// it. A segment can cross *both* boundaries at once (e.g. a sparse series
// jumping from 40° straight to 90°) -- checking each threshold independently,
// rather than picking "the" one threshold for a segment, is what handles that
// without silently skipping the middle (yellow) zone. Two stops at the same
// offset (the outgoing colour's last instant, the incoming colour's first) is
// what makes each transition a clean edge instead of a blended blur.
function zoneGradientStops(data: TempPoint[]): { offset: number; color: string }[] {
  const points = data
    .map((d, i) => (d.celsius === null ? null : { x: i, celsius: d.celsius }))
    .filter((p): p is { x: number; celsius: number } => p !== null);
  if (points.length === 0) return [{ offset: 0, color: "var(--muted-foreground)" }];
  if (points.length === 1) {
    const c = thermalColor(points[0].celsius);
    return [{ offset: 0, color: c }, { offset: 1, color: c }];
  }

  const lastX = points[points.length - 1].x;
  const stops: { offset: number; color: string }[] = [];
  stops.push({ offset: points[0].x / lastX, color: thermalColor(points[0].celsius) });

  for (let i = 1; i < points.length; i++) {
    const prev = points[i - 1];
    const curr = points[i];
    const lo = Math.min(prev.celsius, curr.celsius);
    const hi = Math.max(prev.celsius, curr.celsius);
    // Both thresholds are checked independently and in the direction the
    // reading is actually moving, so a segment that crosses both (rising
    // through green -> yellow -> red, or the reverse) gets both edges in the
    // right order rather than only the first one found.
    const crossings = [55, 85].filter((t) => t > lo && t < hi);
    if (curr.celsius < prev.celsius) crossings.reverse();

    let cursorColor = thermalColor(prev.celsius);
    for (const threshold of crossings) {
      const t = (threshold - prev.celsius) / (curr.celsius - prev.celsius);
      const crossX = prev.x + t * (curr.x - prev.x);
      const crossOffset = Math.max(0, Math.min(1, crossX / lastX));
      // The colour on the far side of this one threshold, holding the other
      // coordinate fixed at `threshold` itself so thermalColor reports
      // exactly the zone the reading is entering, not a value that has
      // already run past the next threshold too.
      const enteringColor = thermalColor(curr.celsius < prev.celsius ? threshold - 0.001 : threshold);
      stops.push({ offset: crossOffset, color: cursorColor });
      stops.push({ offset: crossOffset, color: enteringColor });
      cursorColor = enteringColor;
    }
    stops.push({ offset: curr.x / lastX, color: thermalColor(curr.celsius) });
  }
  return stops;
}

export function TemperatureChart({ data }: { data: TempPoint[] }) {
  const gradientId = `tempFill-${useId().replace(/:/g, "")}`;
  const [hoverColor, setHoverColor] = useState<string | null>(null);
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

  const stops = zoneGradientStops(data);

  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 flex flex-col p-6 duration-500">
      <div className="flex items-center justify-between">
        <div>
          <p className="section-kicker">// cpu temperature</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">Thermal trace</p>
        </div>
      </div>
      <ChartContainer config={chartConfig} className="mt-6 aspect-auto h-[260px] w-full">
        <AreaChart
          data={data}
          margin={{ left: 0, right: 12, top: 8, bottom: 0 }}
          onMouseMove={(state) => {
            const index = typeof state?.activeTooltipIndex === "number" ? state.activeTooltipIndex : null;
            const point = index !== null ? data[index] : undefined;
            setHoverColor(point && point.celsius !== null ? thermalColor(point.celsius) : null);
          }}
          onMouseLeave={() => setHoverColor(null)}
        >
          <defs>
            {/* Horizontal (x1→x2), not vertical: the colour has to change
                along time, not along temperature magnitude on the y-axis --
                a vertical gradient would tint the top of the fill differently
                from the bottom of the same, single-coloured moment. */}
            <linearGradient id={gradientId} x1="0" y1="0" x2="1" y2="0">
              {stops.map((s, i) => (
                <stop key={i} offset={s.offset} stopColor={s.color} />
              ))}
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
          <ChartTooltip
            content={
              <ChartTooltipContent
                indicator="line"
                labelKey="time"
                color={hoverColor ?? undefined}
                formatter={(value) => (
                  <div className="flex w-full items-center justify-between gap-2">
                    <span className="text-muted-foreground">CPU temperature</span>
                    <span
                      className="font-mono font-medium tabular-nums"
                      style={{ color: typeof value === "number" ? thermalColor(value) : undefined }}
                    >
                      {typeof value === "number" ? `${value.toFixed(1)}°` : String(value)}
                    </span>
                  </div>
                )}
              />
            }
          />
          <Area
            dataKey="celsius"
            type="monotone"
            stroke={`url(#${gradientId})`}
            strokeWidth={2}
            fill={`url(#${gradientId})`}
            fillOpacity={0.25}
            connectNulls
          />
        </AreaChart>
      </ChartContainer>
    </div>
  );
}
