"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import * as Dialog from "@radix-ui/react-dialog";
import { AlertTriangle, Check, Circle, LoaderCircle, RefreshCw, X } from "lucide-react";
import {
  type AgentRelease,
  type CommandKind,
  type NodeCommand,
  commandIsActive,
  commandRecovery,
  commandStageIndex,
  commandSteps,
  normalizeNodeCommand,
} from "@/lib/node-command";

type Scope = "owner" | "admin";

export function MachineCommandModal({
  nodeId,
  nodeName,
  commandKind,
  triggerLabel,
  currentVersion,
  release,
  scope = "owner",
  disabled = false,
}: {
  nodeId: string;
  nodeName: string;
  commandKind: CommandKind;
  triggerLabel: string;
  currentVersion?: string | null;
  release?: AgentRelease;
  scope?: Scope;
  disabled?: boolean;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [command, setCommand] = useState<NodeCommand | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const endpoint = scope === "admin"
    ? "/api/admin/nodes/command"
    : `/api/nodes/${commandKind}`;
  const statusUrl = scope === "admin"
    ? `${endpoint}?nodeId=${encodeURIComponent(nodeId)}&command=${commandKind}`
    : `${endpoint}?nodeId=${encodeURIComponent(nodeId)}`;
  const active = commandIsActive(command);

  async function readStatus() {
    const response = await fetch(statusUrl, { cache: "no-store" });
    const payload = await response.json().catch(() => ({})) as { command?: unknown; message?: string };
    if (!response.ok) throw new Error(payload.message ?? "Could not read command status");
    const next = payload.command ? normalizeNodeCommand(payload.command) : null;
    setCommand(next);
    if (next?.status === "succeeded") router.refresh();
    return next;
  }

  useEffect(() => {
    if (!open || !active) return;
    const timer = window.setInterval(() => {
      readStatus().catch((reason: unknown) => {
        setError(reason instanceof Error ? reason.message : "Could not refresh command progress");
      });
    }, command?.status === "queued" ? 15_000 : 5_000);
    return () => window.clearInterval(timer);
  }, [active, open, statusUrl, command?.status]); // eslint-disable-line react-hooks/exhaustive-deps

  async function requestCommand() {
    setOpen(true);
    setSubmitting(true);
    setError(null);
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ nodeId, command: commandKind }),
      });
      const payload = await response.json().catch(() => ({})) as { command?: unknown; message?: string };
      if (!response.ok) throw new Error(payload.message ?? `The ${commandKind} could not be queued`);
      const next = normalizeNodeCommand(payload.command);
      if (!next || next.command !== commandKind) throw new Error("The command service returned an invalid status");
      setCommand(next);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : `The ${commandKind} could not be queued`);
    } finally {
      setSubmitting(false);
    }
  }

  const completed = command?.status === "succeeded";
  const failed = command?.status === "failed" || command?.status === "expired";
  const stageIndex = command ? commandStageIndex(command.command, command.stage) : -1;
  const steps = commandSteps(commandKind);
  const title = commandKind === "sync" ? "Synchronize current system" : "Update and repair HYN CLI";

  return (
    <Dialog.Root
      open={open}
      onOpenChange={(next) => {
        if (next || !active) setOpen(next);
      }}
    >
      <button
        type="button"
        onClick={requestCommand}
        disabled={disabled || submitting || active}
        className="inline-flex min-w-44 items-center justify-center gap-2 border border-primary bg-primary/10 px-4 py-2.5 font-mono text-xs uppercase text-primary transition-colors hover:bg-primary/20 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {submitting || active ? <LoaderCircle className="size-4 animate-spin" aria-hidden /> : <RefreshCw className="size-4" aria-hidden />}
        {submitting ? "Queuing" : active ? "In progress" : triggerLabel}
      </button>

      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm" />
        <Dialog.Content
          className="fixed top-1/2 left-1/2 z-50 max-h-[90vh] w-[min(94vw,46rem)] -translate-x-1/2 -translate-y-1/2 overflow-y-auto border border-primary/30 bg-background p-6 shadow-2xl outline-none md:p-8"
          onEscapeKeyDown={(event) => { if (active) event.preventDefault(); }}
          onPointerDownOutside={(event) => { if (active) event.preventDefault(); }}
          aria-describedby="machine-command-description"
        >
          <div className="flex items-start justify-between gap-6">
            <div>
              <p className="section-kicker">// live machine command</p>
              <Dialog.Title className="mt-2 font-sentient text-2xl text-card-foreground">
                {title}
              </Dialog.Title>
              <Dialog.Description id="machine-command-description" className="mt-3 font-mono text-xs leading-6 text-muted-foreground">
                {nodeName}
                {commandKind === "update"
                  ? ` · installed ${currentVersion ?? "unknown"}${release?.latest ? ` · available ${release.latest}` : ""}`
                  : " · requesting every current metric regardless of the recurring interval"}
              </Dialog.Description>
            </div>
            {!active ? (
              <Dialog.Close className="p-1 text-muted-foreground transition-colors hover:text-foreground" aria-label="Close command progress">
                <X className="size-5" />
              </Dialog.Close>
            ) : null}
          </div>

          <ol className="mt-8 grid gap-3 sm:grid-cols-2" aria-label={`${commandKind} progress`}>
            {steps.map((step, index) => {
              const done = completed || (stageIndex >= 0 && index < stageIndex);
              const current = !completed && !failed && index === stageIndex;
              return (
                <li key={step.key} className="flex items-center gap-3 border border-border p-3 font-mono text-[0.7rem] uppercase">
                  {done ? <Check className="size-4 text-primary" aria-hidden />
                    : current ? <LoaderCircle className="size-4 animate-spin text-[#e8a400]" aria-hidden />
                      : <Circle className="size-4 text-muted-foreground/50" aria-hidden />}
                  <span className={done ? "text-primary" : current ? "text-[#e8a400]" : "text-muted-foreground"}>
                    {step.label}
                  </span>
                </li>
              );
            })}
          </ol>

          <div
            className={`mt-5 border p-4 font-mono text-xs leading-6 ${
              failed ? "border-destructive/40 bg-destructive/5 text-destructive"
                : completed ? "border-primary/40 bg-primary/5 text-primary"
                  : "border-[#e8a400]/40 bg-[#e8a400]/5 text-[#e8a400]"
            }`}
            aria-live="polite"
          >
            <div className="flex items-start gap-2">
              {failed ? <AlertTriangle className="mt-1 size-4 shrink-0" aria-hidden /> : null}
              <span>{error ?? command?.message ?? (submitting ? "Sending the request…" : "Waiting for command status…")}</span>
            </div>
            {command?.updated_at ? (
              <p className="mt-2 text-[0.65rem] text-muted-foreground">
                Last progress {new Date(command.updated_at).toLocaleString()}
              </p>
            ) : null}
          </div>

          {(failed || error) ? (() => {
            // The failure text decides the advice. An administrative refusal is
            // fixed in the portal, not by ssh-ing into a machine that is working.
            const recovery = commandRecovery(error ?? command?.message);
            return (
              <div className="mt-5 border border-destructive/30 bg-destructive/5 p-4">
                <p className="font-mono text-xs font-semibold uppercase text-destructive">
                  {recovery.where === "portal" ? "How to clear this" : "Recovery on the server"}
                </p>
                <p className="mt-2 font-mono text-xs leading-6 text-card-foreground">{recovery.hint}</p>
                {recovery.commands.length > 0 ? (
                  <pre className="mt-3 overflow-x-auto font-mono text-xs leading-6 text-card-foreground">
                    {recovery.commands.join("\n")}
                  </pre>
                ) : null}
              </div>
            );
          })() : null}

          <div className="mt-6 flex flex-wrap justify-end gap-3">
            {active ? (
              <button
                type="button"
                onClick={() => setOpen(false)}
                className="border border-border px-4 py-2 font-mono text-xs uppercase text-muted-foreground hover:text-foreground"
              >
                Continue in background
              </button>
            ) : (
              <Dialog.Close className="border border-primary bg-primary/10 px-4 py-2 font-mono text-xs uppercase text-primary hover:bg-primary/20">
                Close
              </Dialog.Close>
            )}
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
