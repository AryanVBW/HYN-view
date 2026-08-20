"use client";

import { useEffect, useState } from "react";
import { useTheme } from "next-themes";
import { cn } from "@/lib/utils";

// A sun that morphs into a moon, not two icons cross-faded -- one <svg> whose
// rays shrink to nothing and whose disc gets eclipsed by a shadow circle,
// scrubbed by the `dark` class rather than swapped. Same reasoning as the logo
// animation in globals.css: opacity/transform only, so a toggle click can
// never reflow the header.
export function ThemeToggle({ className }: { className?: string }) {
  const { resolvedTheme, setTheme } = useTheme();
  // resolvedTheme is undefined until next-themes reads localStorage/system
  // preference on mount; rendering a guess first would flip visibly a moment
  // later. A fixed-size placeholder holds the header's layout without
  // committing to an icon.
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const isDark = resolvedTheme === "dark";

  return (
    <button
      type="button"
      aria-label={mounted ? `Switch to ${isDark ? "light" : "dark"} theme` : "Toggle theme"}
      aria-pressed={mounted ? isDark : undefined}
      onClick={() => setTheme(isDark ? "light" : "dark")}
      className={cn(
        "relative inline-flex size-8 shrink-0 items-center justify-center rounded-full border border-border text-foreground/70 transition-colors duration-300 hover:text-foreground hover:border-foreground/40 cursor-pointer",
        className
      )}
    >
      <svg
        viewBox="0 0 24 24"
        width="16"
        height="16"
        fill="none"
        aria-hidden
        className={cn("transition-transform duration-500", mounted && isDark ? "rotate-[135deg]" : "rotate-0")}
      >
        {/* Rays: present in light mode, scaled to nothing in dark. */}
        <g
          stroke="currentColor"
          strokeWidth="1.6"
          strokeLinecap="round"
          className="origin-center transition-[opacity,scale] duration-300"
          style={{
            opacity: mounted && isDark ? 0 : 1,
            scale: mounted && isDark ? 0.4 : 1,
          }}
        >
          <path d="M12 2.5v2.4M12 19.1v2.4M4.4 4.4l1.7 1.7M17.9 17.9l1.7 1.7M2.5 12h2.4M19.1 12h2.4M4.4 19.6l1.7-1.7M17.9 6.1l1.7-1.7" />
        </g>
        {/* Disc + eclipsing shadow: the shadow slides in from the upper-right
            as the moon phase, covering just enough of the disc to read as a
            crescent -- one shape doing both icons. */}
        <circle cx="12" cy="12" r="5" fill="currentColor" />
        <circle
          cx={mounted && isDark ? 15 : 22}
          cy={mounted && isDark ? 8 : 2}
          r="5.5"
          fill="var(--background)"
          className="transition-all duration-500"
        />
      </svg>
    </button>
  );
}
