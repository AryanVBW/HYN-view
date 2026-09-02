"use client";

import type { ReactNode } from "react";
import { useAnimatedPct } from "@/lib/use-animated-pct";

// The 30-day delivery counters, as a radial ring instead of the flat
// three-column grid they used to be -- the same instrument language as the
// dashboard's own EssentialRing (components/dashboard/simple-dashboard.tsx),
// so this page reads as more of that established cluster rather than a
// second stat-card style invented for account specifically. Scaled to the
// busiest of the three counts rather than a percentage: these are raw
// counts, not 0-100 readings, so borrowing EssentialRing's own semantics
// unmodified would have been the wrong fit for the data even though the
// *visual* pattern is exactly right. A client component (unlike the rest of
// account/page.tsx) purely because useAnimatedPct needs a ref and an effect
// for its scroll-triggered sweep -- see that hook for why the sweep starts
// on first visibility rather than on page load.
//
// `icon` takes a rendered element, not a component reference: this renders
// from a server component (app/account/page.tsx), and only plain
// serialisable values -- not function/class references like a LucideIcon
// component -- can cross the server-to-client boundary as a prop. The
// caller renders <Icon .../> itself and hands the element down; positioning
// inside the SVG happens here via a <g transform> instead of passing x/y
// straight to the icon, since the caller no longer controls those.
export function StatRing({
  label,
  value,
  scale,
  tone,
  icon,
}: {
  label: string;
  value: number;
  scale: number;
  tone: "ok" | "crit" | "idle";
  icon: ReactNode;
}) {
  const color = tone === "crit" ? "var(--destructive)" : tone === "ok" ? "var(--primary)" : "var(--muted-foreground)";
  const size = 88;
  const r = 36;
  const circumference = 2 * Math.PI * r;
  const target = Math.max(0, Math.min(100, (value / scale) * 100));
  const { value: fill, ref: svgRef } = useAnimatedPct<SVGSVGElement>(target);
  const offset = circumference * (1 - fill / 100);

  return (
    <div
      className={`terminal-panel flex items-center gap-4 rounded-xl p-5 duration-500 animate-in fade-in slide-in-from-bottom-2 ${
        tone === "crit" ? "border-destructive/40" : tone === "ok" ? "border-primary/30" : ""
      }`}
    >
      <svg ref={svgRef} viewBox={`0 0 ${size} ${size}`} className="size-16 shrink-0" role="img" aria-label={`${label}: ${value}`}>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--border)" strokeWidth={7} opacity={0.5} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={color}
          strokeWidth={7}
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={offset}
          transform={`rotate(-90 ${size / 2} ${size / 2})`}
          style={{ filter: value > 0 ? `drop-shadow(0 0 4px ${color})` : undefined }}
        />
        <g transform={`translate(${size / 2 - 9}, ${size / 2 - 9})`} color={color}>
          {icon}
        </g>
      </svg>
      <div className="min-w-0">
        <p className="font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">{label}</p>
        <p className="mt-1 font-sentient text-3xl leading-none" style={{ color }}>
          {value}
        </p>
      </div>
    </div>
  );
}
