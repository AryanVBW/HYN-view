"use client";

import { portalRoles, roleLabels, normalizeRole } from "@/lib/permissions";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Loader2, Pause, Play, ShieldOff, Unplug } from "lucide-react";
import { DeleteNodeButton } from "@/components/admin/delete-node-button";
import { portalRpc } from "@/lib/data-browser";
import {
  compareVersions,
  formatRelative,
  newestVersion,
} from "@/lib/dashboard-data";
import { fleetFreshness, neverLinked } from "@/lib/admin-data";
import type { AdminClient, AdminNode } from "@/lib/types";

function pct(v: number | null, suffix = "%") {
  if (v === null || v === undefined) return "—";
  return `${Math.round(Number(v))}${suffix}`;
}

// "Behind" means behind the newest agent reporting into this fleet. A demo node
// carries a fake version, so it is excluded from the yardstick by the caller.
function isBehind(node: AdminNode, newest: string | null): boolean {
  if (node.is_demo || newest === null) return false;
  if (!node.agent_version) return false;
  return compareVersions(node.agent_version, newest) < 0;
}

// A node is "stale" when it stopped checking in. The server cannot know the
// machine is down -- only that it went quiet -- and saying "no data for 22m" is
// honest where a red "OFFLINE" badge would be a guess.
function staleness(node: AdminNode): { label: string; tone: string } {
  return fleetFreshness(node);
}

export function NodeTable({
  nodes,
  canWrite = false,
}: {
  nodes: AdminNode[];
  canWrite?: boolean;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [onlyUnlinked, setOnlyUnlinked] = useState(false);
  const unlinkedCount = nodes.filter(neverLinked).length;
  const rows = onlyUnlinked ? nodes.filter(neverLinked) : nodes;
  const newestAgent = newestVersion(
    nodes.filter((n) => !n.is_demo).map((n) => n.agent_version),
  );

  async function act(
    nodeId: string,
    fn: "hyn_admin_set_node_status" | "hyn_admin_set_node_revoked",
    params: Record<string, unknown>,
  ) {
    setBusyId(nodeId);
    setError(null);
    const { error } = await portalRpc(fn, params);
    setBusyId(null);
    if (error) {
      setError(error.message);
      return;
    }
    startTransition(() => router.refresh());
  }

  function pause(node: AdminNode) {
    const raw = window.prompt(
      `Pause ${node.name} for how many minutes?\n\nLeave blank for an indefinite pause. A timed pause resumes by itself, which is safer: monitoring you forgot to switch back on is worse than none.`,
      "60",
    );
    if (raw === null) return;
    const minutes = raw.trim() === "" ? null : Number(raw);
    if (minutes !== null && (!Number.isFinite(minutes) || minutes <= 0)) {
      setError("Pause duration must be a positive number of minutes.");
      return;
    }
    const reason =
      window.prompt("Reason (recorded in the audit trail):", "maintenance") ??
      "";
    act(node.id, "hyn_admin_set_node_status", {
      p_node_id: node.id,
      p_status: "paused",
      p_minutes: minutes,
      p_reason: reason,
    });
  }

  function suspend(node: AdminNode) {
    const reason = window.prompt(
      `Suspend ${node.name}? It stops accepting data until an administrator reinstates it.\n\nReason (recorded in the audit trail):`,
      "",
    );
    if (reason === null) return;
    act(node.id, "hyn_admin_set_node_status", {
      p_node_id: node.id,
      p_status: "suspended",
      p_minutes: null,
      p_reason: reason,
    });
  }

  function resume(node: AdminNode) {
    act(node.id, "hyn_admin_set_node_status", {
      p_node_id: node.id,
      p_status: "active",
      p_minutes: null,
      p_reason: null,
    });
  }

  function revoke(node: AdminNode) {
    if (
      !window.confirm(
        `Revoke ${node.name}'s credential?\n\nThis is not reversible from here: the machine must be paired again with sudo hyn link. To stop data temporarily, pause it instead.`,
      )
    )
      return;
    act(node.id, "hyn_admin_set_node_revoked", {
      p_node_id: node.id,
      p_revoked: true,
      p_reason: "revoked by administrator",
    });
  }

  return (
    <div className="terminal-panel rounded-xl p-6 duration-500 animate-in fade-in slide-in-from-bottom-2 md:p-7">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="section-kicker">// every machine</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">
            Fleet ({rows.length}
            {onlyUnlinked ? ` of ${nodes.length}` : ""})
          </p>
          {unlinkedCount > 0 ? (
            <button
              type="button"
              onClick={() => setOnlyUnlinked((v) => !v)}
              aria-pressed={onlyUnlinked}
              className={`mt-3 rounded-full border px-2.5 py-1 font-mono text-xs uppercase transition-colors ${
                onlyUnlinked
                  ? "border-[color:var(--chart-2)] bg-[color:var(--chart-2)]/10 text-[color:var(--chart-2)]"
                  : "border-border text-muted-foreground hover:border-[color:var(--chart-2)]/60 hover:text-[color:var(--chart-2)]"
              }`}
            >
              {onlyUnlinked
                ? "show all machines"
                : `never linked (${unlinkedCount})`}
            </button>
          ) : null}
        </div>
        {pending ? (
          <Loader2 className="size-4 animate-spin text-primary" />
        ) : null}
      </div>

      {error ? (
        <p
          role="alert"
          className="mt-4 rounded-md border border-destructive/40 bg-destructive/5 p-3 font-mono text-xs text-destructive"
        >
          {error}
        </p>
      ) : null}

      <div className="mt-6 overflow-x-auto rounded-lg border border-border/60">
        <table className="w-full min-w-[1040px] border-collapse font-mono text-xs">
          <thead>
            <tr className="border-b border-border bg-card/60 text-left uppercase text-muted-foreground">
              <th className="py-3 pr-4 pl-4 font-normal">machine</th>
              <th className="py-3 pr-4 font-normal">client</th>
              <th className="py-3 pr-4 font-normal">state</th>
              <th className="py-3 pr-4 font-normal">cpu</th>
              <th className="py-3 pr-4 font-normal">temp</th>
              <th className="py-3 pr-4 font-normal">mem</th>
              <th className="py-3 pr-4 font-normal">disk</th>
              <th className="py-3 pr-4 font-normal">alerts</th>
              <th className="py-3 pr-4 font-normal">notifs 24h</th>
              <th className="py-3 pr-4 font-normal">control</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((node) => {
              const s = staleness(node);
              const busy = busyId === node.id;
              return (
                <tr
                  key={node.id}
                  className="border-b border-border/40 align-top transition-colors hover:bg-card/40"
                >
                  <td className="py-3 pr-4 pl-4">
                    <Link
                      href={`/admin?tab=client&client=${node.owner_id ?? ""}&node=${node.id}`}
                      className="text-card-foreground hover:text-primary"
                    >
                      {node.name}
                    </Link>
                    <span className="block text-muted-foreground">
                      {node.hostname ?? "—"}
                      {node.is_demo ? " · demo" : ""}
                    </span>
                    <span className="block text-muted-foreground">
                      {node.agent_version
                        ? `hyn ${node.agent_version}`
                        : "version unknown"}
                    </span>
                    {isBehind(node, newestAgent) ? (
                      <span className="block text-[color:var(--chart-2)]">
                        behind {newestAgent}
                      </span>
                    ) : null}
                    {neverLinked(node) ? (
                      <span className="block text-[color:var(--chart-2)]">
                        never linked · approved{" "}
                        {formatRelative(node.created_at)}
                      </span>
                    ) : null}
                  </td>
                  <td className="py-3 pr-4">
                    {node.owner_id ? (
                      <Link
                        href={`/admin?tab=client&client=${node.owner_id}&node=${node.id}`}
                        className="text-card-foreground/80 hover:text-primary"
                      >
                        {node.owner_email ?? "Unnamed client"}
                      </Link>
                    ) : (
                      <span className="text-card-foreground/80">—</span>
                    )}
                    {node.owner_status === "suspended" ? (
                      <span className="block text-destructive">
                        account suspended
                      </span>
                    ) : null}
                  </td>
                  <td className="py-3 pr-4 whitespace-nowrap">
                    <span className={s.tone}>{s.label}</span>
                    <span className="block text-muted-foreground">
                      {formatRelative(node.last_seen_at)}
                    </span>
                    {node.paused_until ? (
                      <span className="block text-[color:var(--chart-2)]">
                        until {new Date(node.paused_until).toLocaleTimeString()}
                      </span>
                    ) : null}
                    {node.status_reason ? (
                      <span className="block text-muted-foreground">
                        {node.status_reason}
                      </span>
                    ) : null}
                  </td>
                  <td className="py-3 pr-4 text-card-foreground/80">
                    {pct(node.last_cpu_pct)}
                  </td>
                  <td className="py-3 pr-4 text-card-foreground/80">
                    {node.last_temp_c === null
                      ? "—"
                      : `${Math.round(Number(node.last_temp_c))}°C`}
                  </td>
                  <td className="py-3 pr-4 text-card-foreground/80">
                    {pct(node.last_mem_pct)}
                  </td>
                  <td className="py-3 pr-4 text-card-foreground/80">
                    {pct(node.last_disk_pct)}
                  </td>
                  <td className="py-3 pr-4">
                    <span
                      className={
                        node.alerts_open > 0
                          ? "text-destructive"
                          : "text-muted-foreground"
                      }
                    >
                      {node.alerts_open}
                    </span>
                  </td>
                  <td className="py-3 pr-4">
                    <span className="text-card-foreground/80">
                      {node.notifications_24h}
                    </span>
                    {node.notifications_failed_24h > 0 ? (
                      <span className="block text-destructive">
                        {node.notifications_failed_24h} failed
                      </span>
                    ) : null}
                  </td>
                  <td className="py-3 pr-4">
                    <div className="flex flex-wrap items-center gap-1.5">
                      {!canWrite ? (
                        <span className="text-muted-foreground">View only</span>
                      ) : busy ? (
                        <Loader2 className="size-4 animate-spin text-primary" />
                      ) : (
                        <>
                          {node.status === "active" ? (
                            <button
                              type="button"
                              onClick={() => pause(node)}
                              title="Pause monitoring"
                              className="flex items-center gap-1 rounded-full border border-border px-2 py-1 uppercase text-muted-foreground transition-colors hover:border-[color:var(--chart-2)]/60 hover:text-[color:var(--chart-2)]"
                            >
                              <Pause className="size-3" /> pause
                            </button>
                          ) : (
                            <button
                              type="button"
                              onClick={() => resume(node)}
                              title="Resume monitoring"
                              className="flex items-center gap-1 rounded-full border border-primary/50 px-2 py-1 uppercase text-primary transition-colors hover:bg-primary/10"
                            >
                              <Play className="size-3" /> resume
                            </button>
                          )}
                          {node.status !== "suspended" ? (
                            <button
                              type="button"
                              onClick={() => suspend(node)}
                              title="Suspend this machine"
                              className="flex items-center gap-1 rounded-full border border-border px-2 py-1 uppercase text-muted-foreground transition-colors hover:border-destructive/60 hover:text-destructive"
                            >
                              <ShieldOff className="size-3" /> suspend
                            </button>
                          ) : null}
                          {!node.revoked ? (
                            <button
                              type="button"
                              onClick={() => revoke(node)}
                              title="Revoke the node credential"
                              className="flex items-center gap-1 rounded-full border border-border px-2 py-1 uppercase text-muted-foreground transition-colors hover:border-destructive/60 hover:text-destructive"
                            >
                              <Unplug className="size-3" /> revoke
                            </button>
                          ) : null}
                          <DeleteNodeButton node={node} />
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export function ClientTable({
  clients,
  selfId,
  canWrite = false,
}: {
  clients: AdminClient[];
  selfId: string;
  canWrite?: boolean;
}) {
  const router = useRouter();
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [roleFilter, setRoleFilter] = useState("");
  const rows = clients.filter(
    (client) =>
      (!roleFilter || client.role === roleFilter) &&
      `${client.email ?? ""} ${client.full_name ?? ""}`
        .toLowerCase()
        .includes(query.toLowerCase()),
  );
  async function call(id: string, fn: string, params: Record<string, unknown>) {
    setBusyId(id);
    setError(null);
    try {
      const { error: saveError } = await portalRpc(fn, params);
      if (saveError) setError(saveError.message);
      else router.refresh();
    } catch {
      setError("Could not save the account change. Try again.");
    } finally {
      setBusyId(null);
    }
  }
  return (
    <section
      className="terminal-panel rounded-xl p-6 md:p-7"
      aria-labelledby="accounts-title"
    >
      <p className="section-kicker">// people and permissions</p>
      <h2 id="accounts-title" className="mt-2 font-sentient text-2xl">
        Accounts ({clients.length})
      </h2>
      <p className="mt-2 font-mono text-xs leading-6 text-muted-foreground">
        {canWrite
          ? "Manage account roles, dashboard access, and account status."
          : "Browse every account or promote a Viewer or Monitor to Admin."}
      </p>
      <div className="mt-5 grid gap-3 sm:grid-cols-4">
        {portalRoles.map((role) => (
          <button
            key={role}
            type="button"
            aria-pressed={roleFilter === role}
            onClick={() => setRoleFilter(roleFilter === role ? "" : role)}
            className={`rounded-lg border p-4 text-left transition-colors ${roleFilter === role ? "border-primary bg-primary/10" : "border-border hover:border-primary/60"}`}
          >
            <span className="block font-mono text-xs text-muted-foreground">
              {roleLabels[role]}
            </span>
            <span className="mt-2 block font-sentient text-3xl">
              {clients.filter((c) => c.role === role).length}
            </span>
          </button>
        ))}
      </div>
      <label className="mt-5 block font-mono text-xs text-muted-foreground">
        Search accounts
        <input
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search name or email"
          className="mt-2 w-full rounded-md border border-input bg-background px-3 py-2.5 text-sm text-foreground focus-visible:outline-primary"
        />
      </label>
      {error ? (
        <p role="alert" className="mt-4 text-sm text-destructive">
          {error}
        </p>
      ) : null}
      <div className="mt-5 overflow-x-auto rounded-lg border border-border">
        <table className="w-full min-w-[720px] text-left font-mono text-xs">
          <thead className="border-b border-border bg-card/60 text-muted-foreground">
            <tr>
              {[
                "Account",
                "Role",
                "Status",
                "Machines",
                "Last seen",
                "Access",
              ].map((label) => (
                <th key={label} className="p-3 font-normal">
                  {label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((c) => (
              <tr
                key={c.id}
                className="border-b border-border/40 align-top hover:bg-card/40"
              >
                <td className="p-3">
                  <Link
                    href={`/admin?tab=client&client=${c.id}`}
                    className="text-foreground hover:text-primary"
                  >
                    {c.full_name || c.email || "Unnamed account"}
                  </Link>
                  {c.id === selfId ? " (you)" : null}
                  {c.full_name ? (
                    <p className="mt-1 text-muted-foreground">{c.email}</p>
                  ) : null}
                </td>
                <td className="p-3 text-primary">
                  {roleLabels[normalizeRole(c.role)]}
                </td>
                <td
                  className={`p-3 ${c.status === "suspended" ? "text-destructive" : "text-muted-foreground"}`}
                >
                  {c.status}
                  {c.suspended_reason ? (
                    <p className="mt-1">{c.suspended_reason}</p>
                  ) : null}
                </td>
                <td className="p-3">
                  {c.nodes_active}/{c.nodes} active
                  {c.nodes_unlinked ? (
                    <p className="mt-1 text-muted-foreground">
                      {c.nodes_unlinked} never linked
                    </p>
                  ) : null}
                </td>
                <td className="p-3 text-muted-foreground">
                  {formatRelative(c.last_seen_at)}
                </td>
                <td className="p-3">
                  <div className="flex flex-wrap gap-2">
                    {canWrite ? (
                      <>
                        <select
                          aria-label={`Role for ${c.email || c.full_name || c.id}`}
                          value={c.role}
                          disabled={busyId !== null || c.id === selfId}
                          onChange={(event) =>
                            call(c.id, "hyn_admin_set_role", {
                              p_user_id: c.id,
                              p_role: event.target.value,
                            })
                          }
                          className="rounded border border-input bg-background p-2 disabled:opacity-40"
                        >
                          {portalRoles.map((role) => (
                            <option key={role} value={role}>
                              {roleLabels[role]}
                            </option>
                          ))}
                        </select>
                        <button
                          disabled={busyId !== null || c.id === selfId}
                          onClick={() => {
                            const reason =
                              c.status === "active"
                                ? window.prompt(
                                    `Suspend ${c.email || c.full_name}? Their machines will stop reporting. Reason:`,
                                    "",
                                  )
                                : null;
                            if (c.status === "active" && reason === null)
                              return;
                            call(c.id, "hyn_admin_set_user_status", {
                              p_user_id: c.id,
                              p_status:
                                c.status === "active" ? "suspended" : "active",
                              p_reason: reason,
                            });
                          }}
                          className="rounded border border-border px-2 py-1 text-muted-foreground hover:text-destructive disabled:opacity-40"
                        >
                          {c.status === "active" ? "Suspend" : "Reinstate"}
                        </button>
                      </>
                    ) : c.role === "viewer" || c.role === "monitor" ? (
                      <button
                        disabled={busyId !== null}
                        onClick={() =>
                          call(c.id, "hyn_admin_set_role", {
                            p_user_id: c.id,
                            p_role: "admin",
                          })
                        }
                        className="rounded border border-primary/40 px-3 py-2 text-primary disabled:opacity-40"
                      >
                        Make Admin
                      </button>
                    ) : (
                      <span className="text-muted-foreground">View only</span>
                    )}
                    {busyId === c.id ? (
                      <Loader2
                        className="size-4 animate-spin text-primary"
                        aria-label="Saving"
                      />
                    ) : null}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!rows.length ? (
          <p className="p-6 font-mono text-sm text-muted-foreground">
            No accounts match this search.
          </p>
        ) : null}
      </div>
    </section>
  );
}
