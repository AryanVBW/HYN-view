"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { AlertTriangle, Check, Circle, LoaderCircle, RefreshCw } from "lucide-react";
import {
  normalizeNodeUpdate,
  UPDATE_STEPS,
  updateIsActive,
  updateStageIndex,
  type AgentRelease,
  type NodeUpdateCommand,
} from "@/lib/node-update";

async function fetchNodeUpdateStatus(nodeId: string) {
  const response = await fetch(`/api/nodes/update?nodeId=${encodeURIComponent(nodeId)}`, {
    cache: "no-store",
  });
  const payload = await response.json().catch(() => ({})) as {
    command?: unknown;
    message?: string;
  };
  if (!response.ok) throw new Error(payload.message ?? "Could not read update status");
  return normalizeNodeUpdate(payload.command);
}

export function AgentUpdateControl({
  nodeId,
  nodeName,
  currentVersion,
  release,
  automatic,
}: {
  nodeId: string;
  nodeName: string;
  currentVersion: string | null;
  release: AgentRelease;
  automatic: boolean;
}) {
  const router = useRouter();
  const [command, setCommand] = useState<NodeUpdateCommand | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchNodeUpdateStatus(nodeId)
      .then((next) => {
        if (!cancelled) setCommand(next);
      })
      .catch((reason: unknown) => {
        if (!cancelled) setError(reason instanceof Error ? reason.message : "Could not read update status");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
    });
    return () => { cancelled = true; };
  }, [nodeId]);

  useEffect(() => {
    if (!updateIsActive(command)) return;
    const timer = window.setInterval(() => {
      fetchNodeUpdateStatus(nodeId)
        .then((next) => {
          setCommand(next);
          if (next?.status === "succeeded") router.refresh();
        })
        .catch((reason: unknown) => {
          setError(reason instanceof Error ? reason.message : "Could not refresh update progress");
        });
    }, 2_000);
    return () => window.clearInterval(timer);
  }, [command, nodeId, router]);

  async function requestUpdate() {
    setSubmitting(true);
    setError(null);
    try {
      const response = await fetch("/api/nodes/update", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ nodeId }),
      });
      const payload = await response.json().catch(() => ({})) as {
        command?: unknown;
        message?: string;
      };
      if (!response.ok) throw new Error(payload.message ?? "The update could not be queued");
      const next = normalizeNodeUpdate(payload.command);
      if (!next) throw new Error("The update service returned an invalid status");
      setCommand(next);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "The update could not be queued");
    } finally {
      setSubmitting(false);
    }
  }

  const active = updateIsActive(command);
  const stageIndex = command ? updateStageIndex(command.stage) : -1;
  const completed = command?.status === "succeeded";
  const failed = command?.status === "failed" || command?.status === "expired";
  const buttonLabel = release.available && release.latest
    ? `Update to hyn ${release.latest}`
    : "Check & update CLI";

  return (
    <section className="terminal-panel p-6" aria-labelledby="agent-update-title">
      <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
        <div className="max-w-2xl">
          <p className="section-kicker">// managed CLI update</p>
          <h2 id="agent-update-title" className="mt-2 font-sentient text-2xl text-card-foreground">
            Keep {nodeName} synchronized
          </h2>
          <p className="mt-3 font-mono text-xs leading-6 text-muted-foreground">
            Installed {currentVersion ? `hyn ${currentVersion}` : "version unknown"}
            {release.latest ? ` · npm latest ${release.latest}` : " · the machine will check npm"}.
            The machine checks for portal commands every minute. An update installs the package,
            refreshes configuration, restarts HYN timers, verifies them, and immediately sends fresh telemetry.
          </p>
          <p className="mt-2 font-mono text-[0.65rem] leading-5 text-muted-foreground">
            Automatic updates are {automatic ? "enabled" : "disabled in Account"}. This button is an explicit
            one-time request and does not change that preference.
          </p>
        </div>
        <button
          type="button"
          onClick={requestUpdate}
          disabled={loading || submitting || active}
          className="inline-flex min-w-48 items-center justify-center gap-2 border border-primary bg-primary/10 px-4 py-2.5 font-mono text-xs uppercase text-primary transition-colors hover:bg-primary/20 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {submitting || active ? <LoaderCircle className="size-4 animate-spin" aria-hidden /> : <RefreshCw className="size-4" aria-hidden />}
          {active ? "Update in progress" : submitting ? "Queuing update" : buttonLabel}
        </button>
      </div>

      {command ? (
        <div className="mt-6 border-t border-border pt-5" aria-live="polite">
          <ol className="grid gap-3 sm:grid-cols-3 lg:grid-cols-6" aria-label="CLI update progress">
            {UPDATE_STEPS.map((step, index) => {
              const done = completed || (stageIndex >= 0 && index < stageIndex);
              const current = !completed && !failed && index === stageIndex;
              return (
                <li key={step.key} className="flex items-center gap-2 font-mono text-[0.65rem] uppercase">
                  {done ? (
                    <Check className="size-4 shrink-0 text-primary" aria-hidden />
                  ) : current ? (
                    <LoaderCircle className="size-4 shrink-0 animate-spin text-[#e8a400]" aria-hidden />
                  ) : (
                    <Circle className="size-4 shrink-0 text-muted-foreground/50" aria-hidden />
                  )}
                  <span className={done ? "text-primary" : current ? "text-[#e8a400]" : "text-muted-foreground"}>
                    {step.label}
                  </span>
                </li>
              );
            })}
          </ol>
          <div className={`mt-4 flex items-start gap-2 border p-3 font-mono text-xs leading-6 ${
            failed
              ? "border-destructive/40 bg-destructive/5 text-destructive"
              : completed
                ? "border-primary/40 bg-primary/5 text-primary"
                : "border-[#e8a400]/40 bg-[#e8a400]/5 text-[#e8a400]"
          }`}>
            {failed ? <AlertTriangle className="mt-1 size-4 shrink-0" aria-hidden /> : null}
            <span>
              {command.message}
              {completed && command.result_version ? ` The machine now reports hyn ${command.result_version}.` : ""}
            </span>
          </div>
        </div>
      ) : null}

      {error ? (
        <p className="mt-4 border border-destructive/40 bg-destructive/5 p-3 font-mono text-xs leading-6 text-destructive" role="alert">
          {error}
        </p>
      ) : null}
    </section>
  );
}
