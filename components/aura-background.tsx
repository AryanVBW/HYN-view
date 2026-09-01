"use client";

import { useTheme } from "next-themes";
import { useEffect, useState } from "react";

// Third-party embed markup is copy-pasted verbatim on purpose (the project id,
// script src and version pin are Unicorn Studio's, not ours to restate by
// hand) -- everything React-specific around it (the theme gate, the
// once-only script load) is what actually needed writing.
const PROJECT_ID = "HzcaAbRLaALMhHJp8gLY";
const SCRIPT_SRC =
  "https://cdn.jsdelivr.net/gh/hiunicornstudio/unicornstudio.js@v1.4.29/dist/unicornStudio.umd.js";

declare global {
  interface Window {
    UnicornStudio?: { isInitialized: boolean; init: () => void };
  }
}

// Loads and initialises the Unicorn Studio runtime at most once per page,
// mirroring the embed snippet's own `if(!window.UnicornStudio)` guard --
// every mounted <AuraBackground> shares one script tag and one init() call
// rather than racing to inject the same <script> twice (this component can
// legitimately mount on both the hero and the dashboard in the same
// session).
function loadUnicornStudio() {
  if (window.UnicornStudio) {
    if (!window.UnicornStudio.isInitialized) {
      window.UnicornStudio.init();
      window.UnicornStudio.isInitialized = true;
    }
    return;
  }
  window.UnicornStudio = { isInitialized: false, init: () => {} };
  const script = document.createElement("script");
  script.src = SCRIPT_SRC;
  script.onload = () => {
    if (!window.UnicornStudio!.isInitialized) {
      window.UnicornStudio!.init();
      window.UnicornStudio!.isInitialized = true;
    }
  };
  (document.head || document.body).appendChild(script);
}

/**
 * The "aura" gradient background from Unicorn Studio. Light-theme only: it was
 * designed against a warm off-white page (see the light `--background` in
 * globals.css) and reads as a wash of grey noise on the near-black dark theme,
 * the same problem `.particle-field`'s dark-mode opacity comment already
 * describes for the other full-bleed background on this site. Rather than
 * fight that with more theme-specific CSS, it simply doesn't render outside
 * light mode.
 *
 * `resolvedTheme` is undefined until next-themes reads the stored preference
 * on mount (see ThemeToggle for the same guard), so this stays unmounted for
 * that first tick instead of guessing -- a guess that mounted the embed and
 * then had to tear it back down would run Unicorn Studio's own init/observer
 * cycle for nothing on every dark-mode load.
 */
export function AuraBackground({ className = "" }: { className?: string }) {
  const { resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const showAura = mounted && resolvedTheme === "light";

  useEffect(() => {
    if (showAura) loadUnicornStudio();
  }, [showAura]);

  if (!showAura) return null;

  // `fixed inset-0`, matching how GL's #webgl and ParticleField are both
  // anchored to the viewport rather than to whatever ancestor happens to be
  // `relative` -- and *no* explicit z-index. Both call sites rely on plain
  // DOM order (mount this after the canvas it should cover, before the
  // content that should stay on top) rather than a z-index arms race against
  // two other full-bleed layers this component doesn't own.
  return (
    <div className={`aura-background-component pointer-events-none fixed inset-0 h-full w-full ${className}`}>
      <div data-us-project={PROJECT_ID} className="absolute left-0 top-0 h-full w-full" />
    </div>
  );
}
