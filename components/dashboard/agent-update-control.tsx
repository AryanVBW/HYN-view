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
}: {
  nodeId: string;
  nodeName: string;
  currentVersion: string | null;
  release: AgentRelease;
  automatic: boolean;
  /** Why these controls cannot work right now, from commandBlockedReason. */
  blocked?: string | null;
}) {
  const updateLabel = release.available && release.latest
    ? `Update to hyn ${release.latest}`
    : "Check & update CLI";

  return (
    <section className="terminal-panel p-6" aria-labelledby="machine-controls-title">
      <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
        <div className="max-w-2xl">
          <p className="section-kicker">// synchronized machine controls</p>
          <h2 id="machine-controls-title" className="mt-2 font-sentient text-2xl text-card-foreground">
            Refresh or repair {nodeName}
          </h2>
          <p className="mt-3 font-mono text-xs leading-6 text-muted-foreground">
            Sync now requests a complete temperature, network, speed, process, service,
            hardware and health reading immediately. Update CLI reinstalls the latest
            package, reapplies setup, restarts HYN timers, verifies them, and then sends
            a new full reading.
          </p>
          <p className="mt-2 font-mono text-[0.65rem] leading-5 text-muted-foreground">
            Installed {currentVersion ? `hyn ${currentVersion}` : "version unknown"}
            {release.latest ? ` · npm latest ${release.latest}` : " · the machine checks npm"}.
            Automatic updates are {automatic ? "enabled" : "disabled in Account"}; these are one-time requests.
          </p>
        </div>
        <div className="flex flex-col items-start gap-2">
          <div className="flex flex-wrap gap-3">
            <MachineCommandModal
              nodeId={nodeId}
              nodeName={nodeName}
              commandKind="sync"
              triggerLabel="Sync now"
              disabled={Boolean(blocked)}
            />
            <MachineCommandModal
              nodeId={nodeId}
              nodeName={nodeName}
              commandKind="update"
              triggerLabel={updateLabel}
              currentVersion={currentVersion}
              release={release}
              disabled={Boolean(blocked)}
            />
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
