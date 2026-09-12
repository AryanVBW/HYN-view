"use client";

import { useEffect, useState } from "react";
import { heartbeatState } from "@/lib/heartbeat";
import { MONITORING_EVENT, newerHeartbeatAt } from "@/lib/monitoring-state";

export function HeartbeatIndicator({
  heartbeatAt,
  nodeId,
  quietAfterSeconds = 180,
}: {
  heartbeatAt: string | null;
  nodeId?: string;
  quietAfterSeconds?: number;
}) {
  const [now, setNow] = useState(() => Date.now());
  const [observed, setObserved] = useState<{nodeId: string; at: string | null} | null>(null);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(timer);
  }, []);
  useEffect(() => {
    const receive = (event: Event) => {
      const detail = (event as CustomEvent).detail;
      if (nodeId && detail?.nodeId === nodeId && (detail.heartbeatAt === null || typeof detail.heartbeatAt === "string")) {
        setObserved({nodeId, at: detail.heartbeatAt});
      }
    };
    window.addEventListener(MONITORING_EVENT, receive);
    return () => window.removeEventListener(MONITORING_EVENT, receive);
  }, [nodeId]);

  const liveAt = newerHeartbeatAt(heartbeatAt, nodeId && observed?.nodeId === nodeId ? observed.at : null);
  const state = heartbeatState(liveAt, now, quietAfterSeconds);
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
        ? "New agents send lightweight heartbeats every 24 seconds; older settings may use one minute. The elapsed time updates every second."
        : "This installed agent uses its configured telemetry interval until it receives the heartbeat-capable update."}
    >
      <span className="hyn-heartbeat-pulse size-1.5 rounded-full bg-current" aria-hidden />
      {state.label}
    </span>
  );
}
