"use client";

import { useEffect, useState } from "react";
import { heartbeatState } from "@/lib/heartbeat";

export function HeartbeatIndicator({
  heartbeatAt,
  quietAfterSeconds = 180,
}: {
  heartbeatAt: string | null;
  quietAfterSeconds?: number;
}) {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(timer);
  }, []);

  const state = heartbeatState(heartbeatAt, now, quietAfterSeconds);
  const tone = state.key === "quiet"
    ? "border-destructive/50 bg-destructive/10 text-destructive"
    : state.key === "delayed"
      ? "border-[#e8a400]/50 bg-[#e8a400]/10 text-[#e8a400]"
      : state.key === "unknown"
        ? "border-border bg-muted/20 text-muted-foreground"
        : "border-primary/40 bg-primary/5 text-primary";

  return (
    <span
      className={`flex w-fit items-center gap-2 rounded-full border px-3 py-1.5 font-mono text-xs uppercase ${tone}`}
      role="status"
      aria-live="off"
      title={quietAfterSeconds === 180
        ? "The machine sends one durable heartbeat each minute; this elapsed time updates locally."
        : "This installed agent uses its configured telemetry interval until it receives the heartbeat-capable update."}
    >
      <span className="hyn-heartbeat-pulse size-1.5 rounded-full bg-current" aria-hidden />
      {state.label}
    </span>
  );
}
