"use client";

import { useEffect, useState } from "react";
import { readingAge } from "@/lib/monitoring-state";

export function ReadingAge({ sampleAt, intervalMinutes = 1 }: {
  sampleAt: string | null;
  intervalMinutes?: unknown;
}) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(timer);
  }, []);
  const age = readingAge(sampleAt, now, intervalMinutes);
  return (
    <span
      className={age.stale ? "text-[#e8a400]" : undefined}
      title={age.sampledAt ? `Reading captured ${age.sampledAt}. Heartbeats are tracked separately.` : "No valid reading timestamp was reported."}
      aria-live="off"
      suppressHydrationWarning
    >
      {age.label}{age.stale ? " · readings delayed" : ""}
    </span>
  );
}
