"use client";

import { MachineCommandModal } from "@/components/dashboard/machine-command-modal";
import type { AgentRelease } from "@/lib/node-command";

export function AgentUpdateControl({
  nodeId,
  nodeName,
  currentVersion,
  release,
  automatic,
  blocked = null,
  canSync = false,
  canWrite = false,
  compact = false,
}: {
  nodeId: string;
  nodeName: string;
  currentVersion: string | null;
  release: AgentRelease;
  automatic: boolean;
  /** Why these controls cannot work right now, from commandBlockedReason. */
  blocked?: string | null;
  canSync?: boolean;
  canWrite?: boolean;
  compact?: boolean;
}) {
  if (!canSync && !canWrite) return null;
  if (compact) return canSync ? (
    <div className="flex flex-wrap items-center gap-3 border-t border-border pt-5">
      <MachineCommandModal nodeId={nodeId} nodeName={nodeName} commandKind="sync" triggerLabel="Refresh reading" disabled={Boolean(blocked)} />
      <p className="text-xs text-muted-foreground">{blocked ?? "A new reading appears after your server checks in."}</p>
    </div>
  ) : null;
  const updateLabel = release.available && release.latest
    ? `Update to hyn ${release.latest}`
    : "Check & update CLI";

  return (
    <section className="terminal-panel p-6" aria-labelledby="machine-controls-title">
      <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
        <div className="max-w-2xl">
          <p className="section-kicker">// synchronized machine controls</p>
          <h2 id="machine-controls-title" className="mt-2 font-sentient text-2xl text-card-foreground">
            Refresh {nodeName}
          </h2>
          <p className="mt-3 font-mono text-xs leading-6 text-muted-foreground">
            Sync now requests a complete temperature, network, speed, process, service,
            hardware and health reading on the next check-in (normally within five minutes).
            Cloud monitoring retains readings for 48 hours, with a longer backup on the server.
            {canWrite ? "Update CLI reinstalls the latest package, reapplies setup, restarts HYN timers, verifies them, and sends a new reading." : "A Super admin manages CLI updates and server settings."}
          </p>
          <p className="mt-2 font-mono text-[0.65rem] leading-5 text-muted-foreground">
            Installed {currentVersion ? `hyn ${currentVersion}` : "version unknown"}
            {release.latest ? ` · npm latest ${release.latest}` : " · the machine checks npm"}.
            Automatic updates are {automatic ? "enabled" : "disabled in server settings"}.
            Portal requests run unattended; you can close this page after queuing an update.
          </p>
        </div>
        <div className="flex flex-col items-start gap-2">
          <div className="flex flex-wrap gap-3">
            {canSync ? <MachineCommandModal
              nodeId={nodeId}
              nodeName={nodeName}
              commandKind="sync"
              triggerLabel="Sync now"
              disabled={Boolean(blocked)}
            /> : null}
            {canWrite ? <MachineCommandModal
              nodeId={nodeId}
              nodeName={nodeName}
              commandKind="update"
              triggerLabel={updateLabel}
              currentVersion={currentVersion}
              release={release}
              disabled={Boolean(blocked)}
            /> : null}
          </div>
          {blocked ? (
            <p role="note" className="max-w-sm font-mono text-[0.65rem] leading-5 text-[#e8a400]">
              {blocked}
            </p>
          ) : null}
        </div>
      </div>
    </section>
  );
}
