"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Loader2, Pause, Play, ShieldOff, Unplug } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { compareVersions, formatRelative, newestVersion } from "@/lib/dashboard-data";
import { fleetFreshness } from "@/lib/admin-data";
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

export function NodeTable({ nodes }: { nodes: AdminNode[] }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const newestAgent = newestVersion(
    nodes.filter((n) => !n.is_demo).map((n) => n.agent_version)
  );

  async function act(
    nodeId: string,
    fn: "hyn_admin_set_node_status" | "hyn_admin_set_node_revoked",
    params: Record<string, unknown>
  ) {
    setBusyId(nodeId);
    setError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc(fn, params);
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
      "60"
    );
    if (raw === null) return;
    const minutes = raw.trim() === "" ? null : Number(raw);
    if (minutes !== null && (!Number.isFinite(minutes) || minutes <= 0)) {
      setError("Pause duration must be a positive number of minutes.");
      return;
    }
    const reason = window.prompt("Reason (recorded in the audit trail):", "maintenance") ?? "";
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
      ""
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
        `Revoke ${node.name}'s credential?\n\nThis is not reversible from here: the machine must be paired again with sudo hyn link. To stop data temporarily, pause it instead.`
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
    <div className="terminal-panel p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="section-kicker">// every machine</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">
            Fleet ({nodes.length})
          </p>
        </div>
        {pending ? <Loader2 className="size-4 animate-spin text-primary" /> : null}
      </div>

      {error ? (
        <p role="alert" className="mt-4 border border-destructive/40 bg-destructive/5 p-3 font-mono text-xs text-destructive">
          {error}
        </p>
      ) : null}

      <div className="mt-6 overflow-x-auto">
        <table className="w-full min-w-[1040px] border-collapse font-mono text-xs">
          <thead>
            <tr className="border-b border-border text-left uppercase text-muted-foreground">
              <th className="py-2 pr-4 font-normal">machine</th>
              <th className="py-2 pr-4 font-normal">client</th>
              <th className="py-2 pr-4 font-normal">state</th>
              <th className="py-2 pr-4 font-normal">cpu</th>
              <th className="py-2 pr-4 font-normal">temp</th>
              <th className="py-2 pr-4 font-normal">mem</th>
              <th className="py-2 pr-4 font-normal">disk</th>
              <th className="py-2 pr-4 font-normal">alerts</th>
              <th className="py-2 pr-4 font-normal">notifs 24h</th>
              <th className="py-2 font-normal">control</th>
            </tr>
          </thead>
          <tbody>
            {nodes.map((node) => {
              const s = staleness(node);
              const busy = busyId === node.id;
              return (
                <tr key={node.id} className="border-b border-border/50 align-top">
                  <td className="py-3 pr-4">
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
                      {node.agent_version ? `hyn ${node.agent_version}` : "version unknown"}
                    </span>
                    {isBehind(node, newestAgent) ? (
                      <span className="block text-[#e8a400]">
                        behind {newestAgent}
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
                      <span className="block text-destructive">account suspended</span>
                    ) : null}
                  </td>
                  <td className="py-3 pr-4 whitespace-nowrap">
                    <span className={s.tone}>{s.label}</span>
                    <span className="block text-muted-foreground">
                      {formatRelative(node.last_seen_at)}
                    </span>
                    {node.paused_until ? (
                      <span className="block text-[#e8a400]">
                        until {new Date(node.paused_until).toLocaleTimeString()}
                      </span>
                    ) : null}
                    {node.status_reason ? (
                      <span className="block text-muted-foreground">{node.status_reason}</span>
                    ) : null}
                  </td>
                  <td className="py-3 pr-4 text-card-foreground/80">{pct(node.last_cpu_pct)}</td>
                  <td className="py-3 pr-4 text-card-foreground/80">
                    {node.last_temp_c === null ? "—" : `${Math.round(Number(node.last_temp_c))}°C`}
                  </td>
                  <td className="py-3 pr-4 text-card-foreground/80">{pct(node.last_mem_pct)}</td>
                  <td className="py-3 pr-4 text-card-foreground/80">{pct(node.last_disk_pct)}</td>
                  <td className="py-3 pr-4">
                    <span className={node.alerts_open > 0 ? "text-destructive" : "text-muted-foreground"}>
                      {node.alerts_open}
                    </span>
                  </td>
                  <td className="py-3 pr-4">
                    <span className="text-card-foreground/80">{node.notifications_24h}</span>
                    {node.notifications_failed_24h > 0 ? (
                      <span className="block text-destructive">
                        {node.notifications_failed_24h} failed
                      </span>
                    ) : null}
                  </td>
                  <td className="py-3">
                    <div className="flex flex-wrap items-center gap-1.5">
                      {busy ? (
                        <Loader2 className="size-4 animate-spin text-primary" />
                      ) : (
                        <>
                          {node.status === "active" ? (
                            <button
                              type="button"
                              onClick={() => pause(node)}
                              title="Pause monitoring"
                              className="flex items-center gap-1 border border-border px-2 py-1 uppercase text-muted-foreground transition-colors hover:border-[#e8a400]/60 hover:text-[#e8a400]"
                            >
                              <Pause className="size-3" /> pause
                            </button>
                          ) : (
                            <button
                              type="button"
                              onClick={() => resume(node)}
                              title="Resume monitoring"
                              className="flex items-center gap-1 border border-primary/50 px-2 py-1 uppercase text-primary transition-colors hover:bg-primary/10"
                            >
                              <Play className="size-3" /> resume
                            </button>
                          )}
                          {node.status !== "suspended" ? (
                            <button
                              type="button"
                              onClick={() => suspend(node)}
                              title="Suspend this machine"
                              className="flex items-center gap-1 border border-border px-2 py-1 uppercase text-muted-foreground transition-colors hover:border-destructive/60 hover:text-destructive"
                            >
                              <ShieldOff className="size-3" /> suspend
                            </button>
                          ) : null}
                          {!node.revoked ? (
                            <button
                              type="button"
                              onClick={() => revoke(node)}
                              title="Revoke the node credential"
                              className="flex items-center gap-1 border border-border px-2 py-1 uppercase text-muted-foreground transition-colors hover:border-destructive/60 hover:text-destructive"
                            >
                              <Unplug className="size-3" /> revoke
                            </button>
                          ) : null}
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

export function ClientTable({ clients, selfId }: { clients: AdminClient[]; selfId: string }) {
  const router = useRouter();
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function call(id: string, fn: string, params: Record<string, unknown>) {
    setBusyId(id);
    setError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc(fn, params);
    setBusyId(null);
    if (error) {
      setError(error.message);
      return;
    }
    router.refresh();
  }

  return (
    <div className="terminal-panel p-6">
      <div>
        <p className="section-kicker">// every client</p>
        <p className="mt-2 font-sentient text-2xl text-card-foreground">
          Accounts ({clients.length})
        </p>
      </div>

      {error ? (
        <p role="alert" className="mt-4 border border-destructive/40 bg-destructive/5 p-3 font-mono text-xs text-destructive">
          {error}
        </p>
      ) : null}

      <div className="mt-6 overflow-x-auto">
        <table className="w-full min-w-[860px] border-collapse font-mono text-xs">
          <thead>
            <tr className="border-b border-border text-left uppercase text-muted-foreground">
              <th className="py-2 pr-4 font-normal">email</th>
              <th className="py-2 pr-4 font-normal">role</th>
              <th className="py-2 pr-4 font-normal">state</th>
              <th className="py-2 pr-4 font-normal">machines</th>
              <th className="py-2 pr-4 font-normal">notifs 30d</th>
              <th className="py-2 pr-4 font-normal">last seen</th>
              <th className="py-2 font-normal">control</th>
            </tr>
          </thead>
          <tbody>
            {clients.map((c) => (
              <tr key={c.id} className="border-b border-border/50 align-top">
                <td className="py-3 pr-4 text-card-foreground/90">
                  <Link
                    href={`/admin?tab=client&client=${c.id}`}
                    className="hover:text-primary"
                  >
                    {c.email ?? c.full_name ?? "Unnamed client"}
                  </Link>
                  {c.id === selfId ? <span className="text-primary"> (you)</span> : null}
                </td>
                <td className="py-3 pr-4">
                  <span className={c.role === "admin" ? "text-primary" : "text-muted-foreground"}>
                    {c.role}
                  </span>
                </td>
                <td className="py-3 pr-4">
                  <span className={c.status === "suspended" ? "text-destructive" : "text-primary"}>
                    {c.status}
                  </span>
                  {c.suspended_reason ? (
                    <span className="block text-muted-foreground">{c.suspended_reason}</span>
                  ) : null}
                </td>
                <td className="py-3 pr-4 text-card-foreground/80">
                  {c.nodes_active}/{c.nodes}
                </td>
                <td className="py-3 pr-4 text-card-foreground/80">
                  {c.notifications_30d}
                  {c.notifications_failed_30d > 0 ? (
                    <span className="block text-destructive">
                      {c.notifications_failed_30d} failed
                    </span>
                  ) : null}
                </td>
                <td className="py-3 pr-4 text-muted-foreground">
                  {formatRelative(c.last_seen_at)}
                </td>
                <td className="py-3">
                  {busyId === c.id ? (
                    <Loader2 className="size-4 animate-spin text-primary" />
                  ) : (
                    <div className="flex flex-wrap items-center gap-1.5">
                      {c.status === "active" ? (
                        <button
                          type="button"
                          disabled={c.id === selfId}
                          onClick={() => {
                            const reason = window.prompt(
                              `Suspend ${c.email}? Their machines stop reporting immediately.\n\nReason (recorded in the audit trail):`,
                              ""
                            );
                            if (reason === null) return;
                            call(c.id, "hyn_admin_set_user_status", {
                              p_user_id: c.id,
                              p_status: "suspended",
                              p_reason: reason,
                            });
                          }}
                          title={c.id === selfId ? "You cannot suspend yourself" : "Suspend this client"}
                          className="border border-border px-2 py-1 uppercase text-muted-foreground transition-colors hover:border-destructive/60 hover:text-destructive disabled:cursor-not-allowed disabled:opacity-40"
                        >
                          suspend
                        </button>
                      ) : (
                        <button
                          type="button"
                          onClick={() =>
                            call(c.id, "hyn_admin_set_user_status", {
                              p_user_id: c.id,
                              p_status: "active",
                              p_reason: null,
                            })
                          }
                          className="border border-primary/50 px-2 py-1 uppercase text-primary transition-colors hover:bg-primary/10"
                        >
                          reinstate
                        </button>
                      )}
                      <button
                        type="button"
                        onClick={() =>
                          call(c.id, "hyn_admin_set_role", {
                            p_user_id: c.id,
                            p_role: c.role === "admin" ? "user" : "admin",
                          })
                        }
                        className="border border-border px-2 py-1 uppercase text-muted-foreground transition-colors hover:border-primary/60 hover:text-primary"
                      >
                        make {c.role === "admin" ? "user" : "admin"}
                      </button>
                    </div>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
