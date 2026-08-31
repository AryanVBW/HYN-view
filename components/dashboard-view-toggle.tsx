"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { LayoutGrid, Sparkles } from "lucide-react";
import { cn } from "@/lib/utils";

export type DashboardViewMode = "simple" | "dash";

const COOKIE_NAME = "hyn_view_mode";
// A year is "effectively permanent" for a UI preference without living forever
// in the cookie jar -- the same reasoning next-themes uses for its own storage.
const COOKIE_MAX_AGE = 60 * 60 * 24 * 365;

// Client-side override for which dashboard renders, independent of the
// server-managed `node.config.dashboard_view` an administrator or the account
// page sets. That setting is what the *agent* and the portal's defaults agree
// on; this is a personal "how do I want to look at it right now" switch, so it
// lives in a cookie (for the server component to read on the next render) and
// mirrors into localStorage (so a client-side read never has to wait on a
// round trip). Cookie wins when both exist, matching how dashboard/page.tsx
// resolves the effective mode.
export function readViewModeCookie(): DashboardViewMode | null {
  if (typeof document === "undefined") return null;
  const match = document.cookie.match(new RegExp(`(?:^|; )${COOKIE_NAME}=(simple|dash)`));
  return (match?.[1] as DashboardViewMode) ?? null;
}

function writeViewMode(mode: DashboardViewMode) {
  document.cookie = `${COOKIE_NAME}=${mode}; path=/; max-age=${COOKIE_MAX_AGE}; SameSite=Lax`;
  try {
    window.localStorage.setItem(COOKIE_NAME, mode);
  } catch {
    // Storage can throw in private-browsing/quota-exceeded contexts; the
    // cookie already carries the preference, so a failed mirror is not fatal.
  }
}

// Segmented pill matching ThemeToggle's border/hover language (same height,
// same border-foreground/40 hover, same 300ms colour transition) so the two
// controls read as one family sitting side by side in the header. Mounted
// globally (the header is rendered once, in the root layout, for every route)
// but only meaningful on the dashboard, so it renders nothing anywhere else —
// the same "hide the whole thing rather than show a button that does nothing
// here" call the header already makes for the sign-in link.
export function DashboardViewToggle({ className }: { className?: string }) {
  const router = useRouter();
  const pathname = usePathname();
  // Undefined until mount, so the initial render never guesses a mode the
  // cookie disagrees with -- same reason ThemeToggle waits for `mounted`
  // before it commits to an icon. This hook, like theme-toggle.tsx, is
  // exempted from react-hooks/set-state-in-effect in eslint.config.mjs: the
  // rule's own docs sanction reading a ref via useLayoutEffect, and reading
  // document.cookie/localStorage on mount is the same "hydrate from a
  // browser API the server could not see" shape, just without a ref to hang
  // it on.
  const [mode, setMode] = useState<DashboardViewMode | undefined>(undefined);
  const [pending, setPending] = useState<DashboardViewMode | null>(null);

  useEffect(() => {
    const stored = readViewModeCookie() ?? (window.localStorage.getItem(COOKIE_NAME) as DashboardViewMode | null);
    // No cookie yet means the user has never touched this control, so the pill
    // guesses the system-wide default ("dash") rather than reading the
    // per-node DB setting the header has no access to. dashboard/page.tsx
    // still renders from that DB setting regardless -- this only affects
    // which pill looks pressed before the first click, and self-corrects the
    // moment either option is chosen.
    setMode(stored === "simple" || stored === "dash" ? stored : "dash");
  }, []);

  if (!pathname?.startsWith("/dashboard")) return null;
  // Nothing to render until the real value is known -- see the ThemeToggle
  // comment above for why a placeholder guess is worse than a brief absence.
  if (mode === undefined) return null;

  const active = pending ?? mode;

  const select = (next: DashboardViewMode) => {
    if (next === active) return;
    setPending(next);
    setMode(next);
    writeViewMode(next);
    router.refresh();
  };

  const options: { value: DashboardViewMode; label: string; icon: typeof Sparkles }[] = [
    { value: "simple", label: "Simple", icon: Sparkles },
    { value: "dash", label: "Advanced", icon: LayoutGrid },
  ];

  return (
    <div
      role="radiogroup"
      aria-label="Dashboard detail level"
      className={cn(
        "inline-flex items-center gap-0.5 rounded-full border border-border p-0.5 font-mono text-xs uppercase",
        className
      )}
    >
      {options.map(({ value, label, icon: Icon }) => {
        const isActive = active === value;
        return (
          <button
            key={value}
            type="button"
            role="radio"
            aria-checked={isActive}
            onClick={() => select(value)}
            className={cn(
              "flex items-center gap-1.5 rounded-full px-3 py-1.5 transition-colors duration-300 cursor-pointer",
              isActive
                ? "bg-primary text-primary-foreground"
                : "text-foreground/60 hover:text-foreground"
            )}
          >
            <Icon className="size-3.5" aria-hidden />
            {label}
          </button>
        );
      })}
    </div>
  );
}
