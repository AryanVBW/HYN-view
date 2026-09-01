"use client";

import { useAnimatedPct } from "@/lib/use-animated-pct";

// A thermal dial matching SpeedGauge's visual language (same sweep, same tick
// marks) so the network and temperature sections read as one instrument
// cluster rather than two different widgets bolted together. Scaled 0-100°C
// fixed, not against a peak: a given reading should look identically hot (or
// not) on every machine, which a peak-relative scale could not promise.

const SWEEP_START = 135;
const SWEEP_END = 45 + 360;
const SWEEP_DEGREES = SWEEP_END - SWEEP_START;
const MAX_C = 100;

// Where the safe/moderate/hot bands end, as a fraction of the 0-100°C scale.
// Moderate now starts at 55°C rather than 70°C, per explicit correction --
// 70 read as too high a bar for "worth noticing" on this deployment. 85°C+
// (hot) is unchanged. These are the same thresholds thermalColor already
// judges by -- the zone bands on the dial are that function's boundaries
// made visible, not a second opinion.
const SAFE_END_PCT = 0.55; // 55°C
const MODERATE_END_PCT = 0.85; // 85°C

// A literal green for "safe", not this site's `--primary` token: --primary is
// the brand's amber/gold accent (#a66f00 light, #FFC700 dark -- see
// globals.css), which every other "ok" badge on this dashboard deliberately
// reuses for brand consistency. A thermal dial promising "green means safe"
// is a different kind of claim -- it is describing the reading, not the
// brand -- and rendering that promise in amber is indistinguishable from the
// "moderate" band's own amber, which is the exact bug this constant fixes: a
// 42°C reading, safely in the green two-thirds of the dial, was rendering in
// the same colour family as a 75°C moderate reading. #16a34a (Tailwind's
// green-600) rather than a brighter green: it is the darkest/most-saturated
// of the range that still clears 3:1 contrast (WCAG's minimum for graphical
// UI elements) against this theme's light-mode background, while staying
// well clear of it in dark mode too.
const SAFE_COLOR = "#16a34a";

function polar(cx: number, cy: number, r: number, deg: number) {
  const rad = (deg * Math.PI) / 180;
  return { x: cx + r * Math.cos(rad), y: cy + r * Math.sin(rad) };
}

function arcPath(cx: number, cy: number, r: number, startDeg: number, endDeg: number) {
  const start = polar(cx, cy, r, startDeg);
  const end = polar(cx, cy, r, endDeg);
  const largeArc = endDeg - startDeg > 180 ? 1 : 0;
  return `M ${start.x} ${start.y} A ${r} ${r} 0 ${largeArc} 1 ${end.x} ${end.y}`;
}

// Green below 55 (safe), amber to 85 (moderate -- real heat, not yet a
// problem), red above (hot enough that throttling or instability becomes a
// real possibility on most parts).
function thermalColor(celsius: number): string {
  if (celsius >= 85) return "var(--destructive)";
  if (celsius >= 55) return "#e8a400";
  return SAFE_COLOR;
}

export function ThermalGauge({ celsius }: { celsius: number }) {
  const size = 220;
  const cx = size / 2;
  const cy = size / 2;
  const r = 92;
  const targetPct = Math.max(0, Math.min(1, celsius / MAX_C));
  // Same per-frame interpolation SpeedGauge's needle uses, gated on scrolling
  // into view rather than mount (see use-animated-pct.ts).
  const { value: animatedPct, ref: svgRef } = useAnimatedPct<SVGSVGElement>(targetPct);
  const needleDeg = SWEEP_START + animatedPct * SWEEP_DEGREES;
  const color = thermalColor(celsius);
  const ticks = 10;

  return (
    <svg
      ref={svgRef}
      viewBox={`0 0 ${size} ${size}`}
      className="w-full max-w-[220px]"
      role="img"
      aria-label={`CPU temperature: ${celsius.toFixed(1)}°C`}
    >
      <path d={arcPath(cx, cy, r, SWEEP_START, SWEEP_END)} fill="none" stroke="var(--border)" strokeWidth={10} strokeLinecap="round" opacity={0.5} />
      {/* Three zone bands, safe/moderate/hot, drawn under the track so the
          dial shows what it is judging the reading against before the
          needle even moves -- not just two zones with the safe range left
          implicit as "whatever isn't coloured". */}
      <path d={arcPath(cx, cy, r, SWEEP_START, SWEEP_START + SAFE_END_PCT * SWEEP_DEGREES)} fill="none" stroke={SAFE_COLOR} strokeWidth={3} opacity={0.35} />
      <path d={arcPath(cx, cy, r, SWEEP_START + SAFE_END_PCT * SWEEP_DEGREES, SWEEP_START + MODERATE_END_PCT * SWEEP_DEGREES)} fill="none" stroke="#e8a400" strokeWidth={3} opacity={0.35} />
      <path d={arcPath(cx, cy, r, SWEEP_START + MODERATE_END_PCT * SWEEP_DEGREES, SWEEP_END)} fill="none" stroke="var(--destructive)" strokeWidth={3} opacity={0.35} />
      <path
        d={arcPath(cx, cy, r, SWEEP_START, needleDeg)}
        fill="none"
        stroke={color}
        strokeWidth={10}
        strokeLinecap="round"
        style={{ filter: `drop-shadow(0 0 6px ${color})` }}
      />
      {Array.from({ length: ticks + 1 }, (_, i) => {
        const deg = SWEEP_START + (i / ticks) * SWEEP_DEGREES;
        const outer = polar(cx, cy, r + 8, deg);
        const inner = polar(cx, cy, r + (i % 5 === 0 ? 1 : 4), deg);
        return (
          <line key={i} x1={inner.x} y1={inner.y} x2={outer.x} y2={outer.y} stroke="var(--muted-foreground)" strokeWidth={i % 5 === 0 ? 2 : 1} opacity={0.6} />
        );
      })}
      <line
        x1={cx}
        y1={cy}
        x2={polar(cx, cy, r - 14, needleDeg).x}
        y2={polar(cx, cy, r - 14, needleDeg).y}
        stroke={color}
        strokeWidth={3}
        strokeLinecap="round"
      />
      <circle cx={cx} cy={cy} r={5} fill={color} />
      <text x={cx} y={cy + 34} textAnchor="middle" className="font-sentient" fontSize={26} fill="var(--card-foreground)">
        {celsius.toFixed(1)}°
      </text>
      <text x={cx} y={cy + 50} textAnchor="middle" fontFamily="var(--font-mono)" fontSize={10} fill="var(--muted-foreground)">
        CELSIUS
      </text>
    </svg>
  );
}

export { thermalColor };
