"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type { AdminClient } from "@/lib/types";

export type DashboardShare = { viewer_id: string; owner_id: string };
export function DashboardAccess({
  clients,
  shares,
  error,
}: {
  clients: AdminClient[];
  shares: DashboardShare[];
  error?: string | null;
}) {
  const router = useRouter();
  const [viewer, setViewer] = useState("");
  const [owner, setOwner] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const name = (id: string) => {
    const client = clients.find((c) => c.id === id);
    return client?.full_name || client?.email || id;
  };
  function change(viewerId: string, ownerId: string, allow: boolean) {
    startTransition(async () => {
      setMessage(null);
      try {
        const { error: saveError } = await createClient().rpc(
          "hyn_admin_set_dashboard_access",
          {
            p_viewer: viewerId,
            p_owner: ownerId,
            p_allow: allow,
          },
        );
        if (saveError) {
          setMessage(saveError.message);
          return;
        }
        setMessage(
          allow
            ? "Dashboard shared. Access is available immediately."
            : "Dashboard access revoked.",
        );
        router.refresh();
      } catch {
        setMessage("Could not save dashboard access. Try again.");
      }
    });
  }
  const selectClass =
    "w-full rounded-md border border-input bg-background px-3 py-2.5 font-mono text-sm focus-visible:outline-primary";
  return (
    <section
      className="terminal-panel rounded-xl p-6 md:p-7"
      aria-labelledby="sharing-title"
    >
      <p className="section-kicker">// dashboard access</p>
      <h2 id="sharing-title" className="mt-2 font-sentient text-2xl">
        Share a dashboard
      </h2>
      <p className="mt-2 max-w-2xl font-mono text-xs leading-6 text-muted-foreground">
        Viewers and Monitors see only their own dashboard and dashboards shared
        here. Sharing includes machine readings and assigned relayers. Monitors
        can also refresh readings.
      </p>
      {error ? (
        <p role="alert" className="mt-4 text-sm text-destructive">
          {error}
        </p>
      ) : null}
      <form
        className="mt-5 grid items-end gap-4 md:grid-cols-[1fr_1fr_auto]"
        onSubmit={(event) => {
          event.preventDefault();
          change(viewer, owner, true);
        }}
      >
        <label className="space-y-2 font-mono text-xs">
          Give access to
          <select
            className={selectClass}
            required
            value={viewer}
            onChange={(event) => setViewer(event.target.value)}
          >
            <option value="">Choose Viewer or Monitor</option>
            {clients
              .filter(
                (c) =>
                  c.status === "active" &&
                  (c.role === "viewer" || c.role === "monitor"),
              )
              .map((c) => (
                <option key={c.id} value={c.id}>
                  {name(c.id)}
                </option>
              ))}
          </select>
        </label>
        <label className="space-y-2 font-mono text-xs">
          Dashboard owner
          <select
            className={selectClass}
            required
            value={owner}
            onChange={(event) => setOwner(event.target.value)}
          >
            <option value="">Choose a dashboard</option>
            {clients
              .filter((c) => c.id !== viewer && c.status === "active")
              .map((c) => (
                <option key={c.id} value={c.id}>
                  {name(c.id)}
                </option>
              ))}
          </select>
        </label>
        <button
          disabled={
            pending || Boolean(error) || !viewer || !owner || viewer === owner
          }
          className="rounded-md border border-primary bg-primary/10 px-4 py-2.5 font-mono text-sm text-primary disabled:opacity-40"
        >
          Share dashboard
        </button>
      </form>
      <ul className="mt-5 divide-y divide-border">
        {shares.map((share) => (
          <li
            key={`${share.viewer_id}:${share.owner_id}`}
            className="flex flex-wrap items-center justify-between gap-3 py-3 font-mono text-xs"
          >
            <p>
              <span className="text-foreground">{name(share.viewer_id)}</span>
              <span className="text-muted-foreground"> can view </span>
              {name(share.owner_id)}
            </p>
            <button
              type="button"
              disabled={pending}
              onClick={() => change(share.viewer_id, share.owner_id, false)}
              aria-label={`Revoke ${name(share.viewer_id)} access to ${name(share.owner_id)}`}
              className="rounded border border-border px-3 py-1.5 text-muted-foreground hover:border-destructive hover:text-destructive disabled:opacity-40"
            >
              Revoke access
            </button>
          </li>
        ))}
      </ul>
      {!shares.length && !error ? (
        <p className="mt-4 font-mono text-xs text-muted-foreground">
          No dashboards shared yet.
        </p>
      ) : null}
      {message ? (
        <p role="status" className="mt-4 font-mono text-xs">
          {message}
        </p>
      ) : null}
    </section>
  );
}
