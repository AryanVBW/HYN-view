"use client";

import { useEffect, useState } from "react";
import { useTheme } from "next-themes";
import MagicRings from "./magic-rings";

// A quiet, theme-matched instance of MagicRings for the authenticated app
// pages specifically (dashboard, account, admin) -- not mounted sitewide the
// way SiteCursorGrid was, since the landing page and legal pages weren't part
// of this request and already have their own hero-specific backgrounds.
//
// `pointer-events: none` and no mouse-follow/click-burst: those interactions
// exist upstream for a component meant to be the visual centerpiece of a
// section people are actively looking at, not a backdrop sitting behind a
// dense telemetry dashboard someone is trying to read. A ring pattern that
// visibly reacted to every cursor movement over a chart would be competing
// for attention with the data, which is the opposite of what a background on
// these particular pages should do.
//
// Sized to exactly cover the dashboard viewport -- `inset-0 h-full w-full`,
// not the bounded 600x400 box upstream's own demo uses -- per explicit
// correction: a fixed small box read as a floating rectangle sitting on top
// of the page rather than a background blended into it. The shader itself
// normalizes coordinates by min(width, height) to keep rings circular rather
// than stretched into ellipses on a wide screen (see magic-rings.tsx), which
// means the ring radii below are deliberately wider than upstream's own
// defaults (radiusStep 0.1 -> 0.22, ringCount 6 -> 8) so the pattern actually
// reaches both edges on a wide dashboard instead of clustering in the middle
// with empty canvas on either side -- the same scale problem this exact
// component had the first time it was made full-viewport, fixed the same way
// here. Opacity is lower than the bounded-box version for the same reason:
// a wash covering the whole page needs to be gentler than a small centered
// accent to read as *behind* the data rather than competing with it.
//
// `position: fixed` is set via the `magic-rings-fixed` class in globals.css,
// not Tailwind's `fixed` utility, because of a real conflict: this component
// is mounted as the very next sibling after <ParticleField /> on every one of
// these pages (see app/dashboard/page.tsx and its account/admin twins), and
// globals.css's own `.particle-field ~ *` rule forcibly sets `position:
// relative; z-index: 1` on every element after it -- correct for `<main>`,
// which is meant to sit in normal flow, but it silently overrode this
// component's `fixed` positioning and dropped it into normal document flow
// instead. A same-specificity class rule declared later in the stylesheet
// wins the cascade over Tailwind's own utility class for the same property,
// which is exactly what was happening here. `magic-rings-fixed` is declared
// after `.particle-field ~ *` specifically to win that fight back.
const LIGHT_COLOR = "#a66f00"; // --primary, light theme
const LIGHT_COLOR_TWO = "#7a5200"; // --chart-2, light theme
const DARK_COLOR = "#FFC700"; // --primary, dark theme
const DARK_COLOR_TWO = "#e8a400"; // --chart-2, dark theme

export function DashboardMagicRings({ className = "" }: { className?: string }) {
  const { resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const isLight = mounted && resolvedTheme === "light";

  return (
    <div
      aria-hidden
      className={`magic-rings-fixed pointer-events-none inset-0 h-full w-full ${className}`}
    >
      <MagicRings
        color={isLight ? LIGHT_COLOR : DARK_COLOR}
        colorTwo={isLight ? LIGHT_COLOR_TWO : DARK_COLOR_TWO}
        ringCount={8}
        speed={0.4}
        attenuation={9}
        lineThickness={1.4}
        baseRadius={0.3}
        radiusStep={0.22}
        scaleRate={0.08}
        opacity={isLight ? 0.18 : 0.12}
        blur={2}
        noiseAmount={0.03}
        rotation={0}
        ringGap={1.5}
        fadeIn={0.7}
        fadeOut={0.5}
        followMouse={false}
        clickBurst={false}
        alphaMode="luminance"
      />
    </div>
  );
}
