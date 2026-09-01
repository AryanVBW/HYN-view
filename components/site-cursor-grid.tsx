"use client";

import { useEffect, useState } from "react";
import { useTheme } from "next-themes";
import CursorGrid from "./cursor-grid";

// CursorGrid's `color` prop is parsed into concrete RGB bytes every frame
// (see hexToRgb in cursor-grid.tsx) for the canvas gradient math -- it can't
// take a CSS variable the way a DOM element's `style` could, since the
// browser never resolves custom properties for values baked into a canvas
// draw call. This wrapper is the same "resolve the theme's hex once, in a
// client component, and hand the concrete value down" shape GL and
// ThemeToggle already use for the identical problem (a Three.js `<color>`
// and an SVG fill both have the same constraint).
//
// Mounted once in the root layout so one instance covers every route --
// landing, dashboard, admin -- rather than each page remembering to render
// its own.
const LIGHT_COLOR = "#a66f00"; // --primary, light theme
const DARK_COLOR = "#FFC700"; // --primary, dark theme

export function SiteCursorGrid() {
  const { resolvedTheme } = useTheme();
  // Undefined until next-themes reads the stored preference, same guard
  // ThemeToggle and GL both use -- rendering a guessed colour first would
  // repaint visibly a moment later once the real theme resolves.
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const color = mounted && resolvedTheme === "light" ? LIGHT_COLOR : DARK_COLOR;

  return (
    <CursorGrid
      className="z-40"
      cellSize={64}
      color={color}
      radius={160}
      falloff="smooth"
      holdTime={350}
      fadeDuration={700}
      lineWidth={1}
      maxOpacity={0.55}
      fillOpacity={0.04}
      gridOpacity={0}
      cellRadius={4}
      clickPulse
      pulseSpeed={650}
    />
  );
}
