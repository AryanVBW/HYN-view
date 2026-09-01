"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { LoaderCircle, Mail, RefreshCw } from "lucide-react";
import { MachineCommandModal } from "@/components/dashboard/machine-command-modal";
import { requestAdminNodeUpdates, sendAdminClientReport } from "@/app/admin/actions";
import { compareVersions } from "@/lib/dashboard-data";
import { commandBlockedReason } from "@/lib/node-command";
import { mergePortalConfig } from "@/lib/node-config";
import { createClient } from "@/lib/supabase/client";
import type { AdminClient, AdminNode } from "@/lib/types";

function needsUpdate(node: AdminNode) {
  if (node.revoked || node.is_demo || node.status !== "active") return false;
  if (node.update_available) return true;
  return Boolean(
    node.latest_agent_version &&
    (!node.agent_version || compareVersions(node.agent_version, node.latest_agent_version) < 0)
  );
}

// The dashboard view a client's server opens with, out of everything an admin
// can touch here, gets its own small control rather than living in the bigger
// action bar: it is a UI preference, not an audited operational command, and a
// client who cannot read a terminal should not have to ask for one of those to
// get a screen they can actually use.
function AdminDashboardViewControl({ node }: { node: AdminNode }) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const current = String(node.config?.dashboard_view ?? "dash");

  async function setView(value: string) {
    setPending(true);
    setError(null);
    const merged = mergePortalConfig(node.config ?? {}, { dashboard_view: value });
    const supabase = createClient();
    const { error } = await supabase.rpc("hyn_admin_set_node_config", {
      p_node_id: node.id,
      p_config: merged,
    });
    setPending(false);
    if (error) {
      setError(error.message);
      return;
    }
    router.refresh();
  }

  return (
    <div className="flex flex-col gap-1.5">
      <label className="font-mono text-[0.65rem] uppercase text-muted-foreground" htmlFor="admin-dashboard-view">
        Dashboard view for {node.name}
      </label>
      <select
        id="admin-dashboard-view"
        value={current}
        disabled={pending}
        onChange={(event) => setView(event.target.value)}
        className="border border-input bg-background px-3 py-2 font-mono text-xs text-foreground outline-none focus:border-ring disabled:opacity-50"
      >
        <option value="dash">Advanced (full dashboard)</option>
        <option value="simple">Simple (status, speed, temp only)</option>
      </select>
      <p className="font-mono text-[0.6rem] leading-4 text-muted-foreground">
        Applies to both the terminal and this client&apos;s web dashboard on their next check-in.
      </p>
      {error ? <p role="alert" className="font-mono text-[0.6rem] text-destructive">{error}</p> : null}
    </div>
  );
}

export function AdminClientActions({
  client,
  nodes,
  current,
}: {
  client: AdminClient;
  nodes: AdminNode[];
  current: AdminNode | null;
}) {
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const outdated = nodes.filter(needsUpdate);
  // Why the two per-machine buttons cannot work on the selected machine, if they
  // cannot. The database refuses these states with a stated reason; saying it
  // beside a disabled button spares the administrator the dialog.
  const blocked = current ? commandBlockedReason(current) : null;

  function reportNow() {
    setMessage(null);
    setError(null);
    startTransition(async () => {
      const result = await sendAdminClientReport(client.id);
      if (result.ok) setMessage(result.message);
      else setError(result.error);
    });
  }

  function updateOutdated() {
    if (!window.confirm(
      `Queue a HYN CLI update for ${outdated.length} outdated machine${outdated.length === 1 ? "" : "s"} belonging to ${client.email ?? "this client"}?`,
    )) return;
    setMessage(null);
    setError(null);
    startTransition(async () => {
      const result = await requestAdminNodeUpdates(outdated.map((node) => node.id));
      const summary = `${result.queued.length} queued · ${result.skipped.length} already in progress`;
      if (result.failed.length > 0) {
        setError(`${summary} · ${result.failed.length} failed: ${result.failed.map((item) => item.error).join("; ")}`);
      } else {
        setMessage(summary);
      }
    });
  }

  return (
    <section className="terminal-panel p-6" aria-labelledby="admin-client-actions-title">
      <div className="flex flex-col gap-5 xl:flex-row xl:items-start xl:justify-between">
        <div className="max-w-2xl">
          <p className="section-kicker">// audited client actions</p>
          <h3 id="admin-client-actions-title" className="mt-2 font-sentient text-2xl text-card-foreground">
            Report, synchronize, or update
          </h3>
          <p className="mt-3 font-mono text-xs leading-6 text-muted-foreground">
            The report is generated from every active machine at click time and sent to
            {" "}{client.email ?? "the client email"}. Machine commands are claimed on the
            next heartbeat, with every progress stage recorded in the audit trail.
          </p>
        </div>
        <div className="flex max-w-3xl flex-wrap gap-3">
          <button
            type="button"
            onClick={reportNow}
            disabled={pending || nodes.filter((node) => !node.revoked && !node.is_demo && node.status === "active").length === 0}
            className="inline-flex min-w-44 items-center justify-center gap-2 border border-primary bg-primary/10 px-4 py-2.5 font-mono text-xs uppercase text-primary transition-colors hover:bg-primary/20 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {pending ? <LoaderCircle className="size-4 animate-spin" aria-hidden /> : <Mail className="size-4" aria-hidden />}
            Send report now
          </button>
          {current ? (
            <>
              <MachineCommandModal
                nodeId={current.id}
                nodeName={current.name}
                commandKind="sync"
                triggerLabel="Sync selected"
                scope="admin"
                disabled={Boolean(blocked)}
              />
              <MachineCommandModal
                nodeId={current.id}
                nodeName={current.name}
                commandKind="update"
                triggerLabel={current.update_available && current.latest_agent_version
                  ? `Update to ${current.latest_agent_version}`
                  : "Check & update selected"}
                currentVersion={current.agent_version}
                release={{
                  latest: current.latest_agent_version,
                  available: current.update_available,
                  checkedAt: null,
                }}
                scope="admin"
                disabled={Boolean(blocked)}
              />
            </>
          ) : null}
          <button
            type="button"
            onClick={updateOutdated}
            disabled={pending || outdated.length === 0}
            className="inline-flex min-w-44 items-center justify-center gap-2 border border-[#e8a400]/60 bg-[#e8a400]/5 px-4 py-2.5 font-mono text-xs uppercase text-[#e8a400] transition-colors hover:bg-[#e8a400]/10 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {pending ? <LoaderCircle className="size-4 animate-spin" aria-hidden /> : <RefreshCw className="size-4" aria-hidden />}
            Update outdated ({outdated.length})
          </button>
        </div>
      </div>
      {current ? (
        <div className="mt-6 max-w-sm border-t border-border pt-5">
          <AdminDashboardViewControl node={current} />
        </div>
      ) : null}
      {blocked ? (
        <p role="note" className="mt-5 border border-[#e8a400]/40 bg-[#e8a400]/5 p-3 font-mono text-xs leading-6 text-[#e8a400]">
          {current?.name}: {blocked}
        </p>
      ) : null}
      {message ? (
        <p role="status" className="mt-5 border border-primary/40 bg-primary/5 p-3 font-mono text-xs text-primary">
          {message}
        </p>
      ) : null}
      {error ? (
        <p role="alert" className="mt-5 border border-destructive/40 bg-destructive/5 p-3 font-mono text-xs text-destructive">
          {error}
        </p>
      ) : null}
    </section>
  );
}

export function AdminFleetUpdateButton({ nodes }: { nodes: AdminNode[] }) {
  const [pending, startTransition] = useTransition();
  const [result, setResult] = useState<string | null>(null);
  const outdated = nodes.filter(needsUpdate);
  return (
    <div className="mt-5 flex flex-wrap items-center justify-between gap-3 border-t border-border pt-5">
      <p className="font-mono text-xs text-muted-foreground">
        {outdated.length} machine{outdated.length === 1 ? "" : "s"} reporting an available update.
      </p>
      <button
        type="button"
        disabled={pending || outdated.length === 0}
        onClick={() => {
          if (!window.confirm(
            `Queue a HYN CLI update for ${outdated.length} outdated machine${outdated.length === 1 ? "" : "s"} across the fleet?`,
          )) return;
          startTransition(async () => {
            setResult(null);
            const response = await requestAdminNodeUpdates(outdated.map((node) => node.id));
            setResult(`${response.queued.length} queued · ${response.skipped.length} already active · ${response.failed.length} failed`);
          });
        }}
        className="inline-flex items-center gap-2 border border-[#e8a400]/60 bg-[#e8a400]/5 px-4 py-2.5 font-mono text-xs uppercase text-[#e8a400] hover:bg-[#e8a400]/10 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {pending ? <LoaderCircle className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}
        Update all outdated
      </button>
      {result ? <p role="status" className="w-full font-mono text-xs text-muted-foreground">{result}</p> : null}
    </div>
  );
}
