"use client";

import { useId } from "react";
import type { LucideIcon } from "lucide-react";
import { useAnimatedPct } from "@/lib/use-animated-pct";

// A circular speedometer, the way a car or a bike draws one: a sweep arc, tick
// marks, a needle, the number in the middle. Built as one SVG rather than a
// chart library, because this is a dial reading a single instantaneous value
// against a fixed maximum -- recharts and its <ChartContainer> exist for time
// series, and forcing a one-point "chart" through that machinery would be more
// code for a worse result than plain geometry.
//
// The sweep is 270° (start at 135°, end at 45°, going clockwise through 90°
// at the bottom) -- BMW/Ducati-style, not the full circle some regard as
// harder to read at a glance because the needle can start pointing anywhere.
//
// The scale's top end (full sweep) is always the fastest this link has ever
// measured -- not an arbitrary round number -- so "the needle is nearly at the
// end" means the same thing on every machine: this is close to its personal
// best, not close to a number a designer picked.

const SWEEP_START = 135; // degrees, 0 = 3 o'clock, clockwise
const SWEEP_END = 45 + 360; // one full lap past start, i.e. 270° of travel
const SWEEP_DEGREES = SWEEP_END - SWEEP_START;

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

export function SpeedGauge({
  label,
  icon: Icon,
  valueMbps,
  valueLabel = "MBPS",
  peakMbps,
  markerMbps,
  markerLabel,
  live = false,
  color,
}: {
  label: string;
  icon: LucideIcon;
  valueMbps: number;
  /** What the big centre number is measuring -- "MBPS NOW" for a live rate,
   *  "MBPS TODAY" or "MBPS EVER" for a recorded test result. Defaults to the
   *  plain unit so a caller that doesn't pass one still reads correctly. */
  valueLabel?: string;
  /** The dial's full-scale reading: the fastest this link has ever measured
   *  (either direction), so the needle's position at full sweep always means
   *  "as fast as this connection has ever gone". */
  peakMbps: number;
  /** A second reading to flag on the same arc -- e.g. today's best on the
   *  all-time dial, or the live rate on the today's-best dial -- so two
   *  numbers compare on one instrument instead of needing a second gauge.
   *  Omit when there's nothing to compare against. */
  markerMbps?: number | null;
  /** Short caption under the flag's own reading, shown in the corner nearest
   *  the marker. Defaults to no caption (just the flag). */
  markerLabel?: string;
  /** Whether this is an actively-refreshing rate -- gates the needle-tip pulse,
   *  which exists specifically to say "this number is live", so it must not
   *  render for a recorded speed-test result being replayed on the same dial. */
  live?: boolean;
  color: string;
}) {
  const size = 240;
  const cx = size / 2;
  const cy = size / 2;
  // Pulled in from the dial's outer edge (was 96) to leave room for the scale
  // numbers at r+19 without their glyphs clipping the SVG viewBox -- verified
  // against every angle on the sweep, not just the tick positions, since the
  // tightest point (the very top of the arc) is where a numeral's height is
  // most likely to run past the edge. r=80 (rather than the smaller r=88 a
  // slimmer label needed) buys the margin a bold 13px numeral needs to read
  // like a printed speedometer scale instead of a thin data-label.
  const r = 80;
  // A gauge with nothing recorded yet still needs a scale to draw against; 100
  // Mbps is a reasonable floor for "no speed test yet" rather than a
  // divide-by-zero needle pinned at max.
  const max = peakMbps > 0 ? peakMbps : 100;
  const targetPct = Math.max(0, Math.min(1, valueMbps / max));
  const markerPct =
    markerMbps && markerMbps > 0 ? Math.max(0, Math.min(1, markerMbps / max)) : null;

  // Sweep-in from zero the first time this dial scrolls into view -- see
  // useAnimatedPct for the actual duration, the visibility gating, and why it
  // animates itself frame-by-frame instead of via a CSS transition. A needle
  // that visibly travels reads as "live instrument", a needle that teleports
  // reads as a static icon. Skipped entirely under reduced motion: the final
  // position renders immediately instead of animating toward it.
  const { value: animatedPct, ref: svgRef } = useAnimatedPct<SVGSVGElement>(targetPct);

  const needleDeg = SWEEP_START + animatedPct * SWEEP_DEGREES;
  // 20 tick marks, numbering every other one (11 numbers: 0 through max) --
  // doubled from the original 10/3 so the face reads as a dense, printed
  // instrument scale instead of three widely-spaced data points, the way a
  // real bike cluster numbers nearly every gradation. Verified the labels at
  // this spacing sit ~46px apart centre-to-centre at this radius, well clear
  // of even a 3-character numeral's width, so more numbers never means
  // crowded numbers.
  const ticks = 20;
  // React's own SSR-safe unique id, sanitised for use as an SVG element id:
  // useId() returns a string wrapped in colons (":r0:") to stay collision-safe
  // against CSS selectors, but SVG ids must be valid XML 1.0 names and a
  // colon there is a namespace separator, not a literal character -- an
  // unsanitised useId() value silently fails to resolve the <filter>
  // reference. Replacing the colons keeps the uniqueness guarantee (React
  // still generated a distinct value) while making it a legal SVG id.
  const glowId = `glow-${useId().replace(/:/g, "")}`;

  return (
    <div className="flex flex-col items-center">
      <svg
        ref={svgRef}
        viewBox={`0 0 ${size} ${size}`}
        className="w-full max-w-[240px]"
        role="img"
        aria-label={`${label}: ${valueMbps.toFixed(1)} of ${max.toFixed(0)} Mbps, peak ${peakMbps.toFixed(0)} Mbps`}
      >
        <defs>
          <filter id={glowId} x="-50%" y="-50%" width="200%" height="200%">
            <feGaussianBlur stdDeviation="4" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        {/* Track: the full sweep, dimmed */}
        <path
          d={arcPath(cx, cy, r, SWEEP_START, SWEEP_END)}
          fill="none"
          stroke="var(--border)"
          strokeWidth={10}
          strokeLinecap="round"
          opacity={0.5}
        />

        {/* Fill: how far the needle has travelled, in the gauge's own colour.
            `d` is not a CSS-transitionable property in any browser, so this
            is redrawn every animation frame from `useAnimatedPct`'s own
            interpolated value instead -- no CSS `transition` on `d`, which
            would have been silently ignored and left the arc jumping
            straight to its final shape (see the hook's own comment). */}
        <path
          d={arcPath(cx, cy, r, SWEEP_START, needleDeg)}
          fill="none"
          stroke={color}
          strokeWidth={10}
          strokeLinecap="round"
          filter={`url(#${glowId})`}
        />

        {/* Tick marks around the sweep, supercar-dial style, with every other
            tick numbered -- 11 numbers spanning 0 through max instead of the
            original 3 (0/mid/max), so the face reads as a dense, printed
            instrument scale the way a real bike cluster numbers nearly every
            gradation, with the odd ticks left as plain marks for texture
            between the numbers. Bold, bright, sized to actually read at a
            glance, with the same glow filter the needle arc uses so the
            numerals feel lit rather than pasted on. */}
        {Array.from({ length: ticks + 1 }, (_, i) => {
          const deg = SWEEP_START + (i / ticks) * SWEEP_DEGREES;
          const isMajor = i % 2 === 0;
          const outer = polar(cx, cy, r + 8, deg);
          const inner = polar(cx, cy, r + (isMajor ? 1 : 4), deg);
          const labelPos = polar(cx, cy, r + 19, deg);
          const labelValue = Math.round((i / ticks) * max);
          return (
            <g key={i}>
              <line
                x1={inner.x}
                y1={inner.y}
                x2={outer.x}
                y2={outer.y}
                stroke="var(--muted-foreground)"
                strokeWidth={isMajor ? 2 : 1}
                opacity={0.6}
              />
              {isMajor ? (
                <text
                  x={labelPos.x}
                  y={labelPos.y}
                  textAnchor="middle"
                  dominantBaseline="middle"
                  fontFamily="var(--font-mono)"
                  fontSize={11}
                  fontWeight={700}
                  letterSpacing={-0.3}
                  fill="var(--card-foreground)"
                  filter={`url(#${glowId})`}
                >
                  {labelValue >= 1000 ? `${(labelValue / 1000).toFixed(1)}k` : labelValue}
                </text>
              ) : null}
            </g>
          );
        })}

        {/* Marker flag: a short radial tick in the accent colour at the angle
            the comparison value sits on this same scale -- e.g. today's best
            drawn on the all-time dial -- so two numbers compare on one
            instrument instead of needing a second gauge. */}
        {markerPct !== null ? (
          <g>
            <line
              x1={polar(cx, cy, r - 9, SWEEP_START + markerPct * SWEEP_DEGREES).x}
              y1={polar(cx, cy, r - 9, SWEEP_START + markerPct * SWEEP_DEGREES).y}
              x2={polar(cx, cy, r + 11, SWEEP_START + markerPct * SWEEP_DEGREES).x}
              y2={polar(cx, cy, r + 11, SWEEP_START + markerPct * SWEEP_DEGREES).y}
              stroke="#e8a400"
              strokeWidth={2.5}
              strokeLinecap="round"
            />
            <circle
              cx={polar(cx, cy, r + 15, SWEEP_START + markerPct * SWEEP_DEGREES).x}
              cy={polar(cx, cy, r + 15, SWEEP_START + markerPct * SWEEP_DEGREES).y}
              r={2}
              fill="#e8a400"
            />
          </g>
        ) : null}

        {/* Needle, with a live pulse ring at the tip while data is actually
            moving -- the ring is what says "this is a live reading", not a
            frozen dial pointing at yesterday's number. `x2`/`y2` on a <line>
            are not reliably CSS-transitionable across browsers (see
            useAnimatedPct's comment) -- the needle is redrawn from the
            hook's per-frame interpolated angle instead of a CSS
            `transition`, which is what made it appear to snap rather than
            sweep. */}
        <line
          x1={cx}
          y1={cy}
          x2={polar(cx, cy, r - 14, needleDeg).x}
          y2={polar(cx, cy, r - 14, needleDeg).y}
          stroke={color}
          strokeWidth={3}
          strokeLinecap="round"
        />
        {live ? (
          <circle
            cx={polar(cx, cy, r - 14, needleDeg).x}
            cy={polar(cx, cy, r - 14, needleDeg).y}
            r={5}
            fill="none"
            stroke={color}
            strokeWidth={1.5}
            opacity={0.8}
            className="gauge-live-pulse"
            style={{ transformOrigin: `${polar(cx, cy, r - 14, needleDeg).x}px ${polar(cx, cy, r - 14, needleDeg).y}px` }}
          />
        ) : null}
        <circle cx={cx} cy={cy} r={5} fill={color} />

        {/* Readout, centred low in the dial like a digital speedo insert.
            The marker's own value sits underneath in the same accent colour
            as its flag, so what the flag stands for is readable without
            leaving the dial -- omitted when there's no marker to caption. */}
        <text x={cx} y={cy + 30} textAnchor="middle" className="font-sentient" fontSize={28} fill="var(--card-foreground)">
          {valueMbps.toFixed(valueMbps < 10 ? 1 : 0)}
        </text>
        <text x={cx} y={cy + 47} textAnchor="middle" fontFamily="var(--font-mono)" fontSize={10} fill="var(--muted-foreground)">
          {valueLabel}
        </text>
        {markerMbps && markerLabel ? (
          <text x={cx} y={cy + 64} textAnchor="middle" fontFamily="var(--font-mono)" fontSize={9.5} fill="#e8a400" opacity={0.9}>
            {markerLabel} {markerMbps.toFixed(0)}
          </text>
        ) : null}
      </svg>

      <span
        className="-mt-2 flex items-center gap-1.5 rounded-full border px-3 py-1"
        style={{ borderColor: `color-mix(in oklab, ${color} 45%, transparent)`, backgroundColor: `color-mix(in oklab, ${color} 10%, transparent)`, color }}
      >
        <Icon className="size-3.5" aria-hidden />
        <span className="font-mono text-[0.65rem] uppercase tracking-wide">{label}</span>
      </span>
    </div>
  );
}
