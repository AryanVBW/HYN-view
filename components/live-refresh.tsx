"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { startRecurringRefresh } from "@/lib/live-refresh";
import { MONITORING_EVENT, MONITORING_POLL_MS, monitoringFullRefreshDue } from "@/lib/monitoring-state";

export function LiveRefresh({nodeId, revision}: {nodeId?: string; revision?: string} = {}) {
  const router = useRouter();
  useEffect(() => {
    let busy = false;
    let stopped = false;
    let currentRevision = revision;
    let lastFullRefresh = Date.now();
    let controller: AbortController | undefined;
    const refresh = () => {
      lastFullRefresh = Date.now();
      router.refresh();
    };
    const poll = async () => {
      if (busy || document.visibilityState !== "visible" || !navigator.onLine) return;
      // A timestamp cutoff or transient-cache expiry does not change node
      // revision. Re-read every five minutes even without new metrics.
      if (!nodeId || monitoringFullRefreshDue(lastFullRefresh, Date.now())) { refresh(); return; }
      busy = true;
      controller = new AbortController();
      const timeout = setTimeout(() => controller?.abort(), 10_000);
      try {
        const response = await fetch(`/api/dashboard/freshness?node=${encodeURIComponent(nodeId)}`, {
          cache: "no-store", signal: controller.signal,
        });
        if (stopped) return;
        if ([401, 403, 404].includes(response.status)) { refresh(); return; }
        if (!response.ok) return;
        const data = await response.json();
        if (stopped || data.nodeId !== nodeId || typeof data.revision !== "string") return;
        window.dispatchEvent(new CustomEvent(MONITORING_EVENT, {detail: data}));
        if (currentRevision !== data.revision) {
          currentRevision = data.revision;
          refresh();
        }
      } catch { /* Keep last observed data; its age continues to advance. */ }
      finally { clearTimeout(timeout); busy = false; }
    };
    const stop = startRecurringRefresh(() => { void poll(); }, undefined, undefined, nodeId ? MONITORING_POLL_MS : 60_000);
    const resume = () => { void poll(); };
    document.addEventListener("visibilitychange", resume);
    window.addEventListener("online", resume);
    return () => {
      stopped = true;
      stop();
      controller?.abort();
      document.removeEventListener("visibilitychange", resume);
      window.removeEventListener("online", resume);
    };
  }, [router, nodeId, revision]);
  return null;
}
