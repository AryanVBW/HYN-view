"use client";

import Link from "next/link";
import { useState, useTransition } from "react";
import { reviewRelayerRequest } from "@/app/admin/relayer-actions";
import type { RelayerRequest } from "@/lib/relayer";
import "../dashboard/relayer.css";

export type PendingRelayerRequest = RelayerRequest & {
  owner: string;
  ownerName: string;
  active: boolean;
};
export function RelayerRequestQueue({
  requests,
  canWrite = false,
  error,
}: {
  requests: PendingRelayerRequest[];
  canWrite?: boolean;
  error: string | null;
}) {
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  function review(id: string, approve: boolean) {
    setMessage(null);
    startTransition(async () => {
      try {
        const result = await reviewRelayerRequest(id, approve);
        setFailed(!result.ok);
        setMessage(
          result.ok
            ? approve
              ? "Request approved. The relayer is now connected to this account."
              : "Request declined."
            : (result.error ?? "Could not review request."),
        );
      } catch {
        setFailed(true);
        setMessage("Could not save the review. Refresh and try again.");
      }
    });
  }
  return (
    <section
      className="terminal-panel rounded-xl p-6 md:p-7"
      aria-label="Relayer requests"
    >
      <h2 className="font-sentient text-2xl">
        Relayer requests ({requests.length})
      </h2>
      <p className="mt-2 font-mono text-xs leading-6 text-muted-foreground">
        Super admins verify relayer ownership and approve access.
        Approved relayers appear on the requested dashboard.
      </p>
      {error ? (
        <p role="alert" className="mt-3 text-sm text-destructive">
          {error}
        </p>
      ) : null}
      {!error && !requests.length ? (
        <p className="mt-4 font-mono text-xs text-muted-foreground">
          No pending relayer requests.
        </p>
      ) : null}
      <ul className="mt-5 divide-y divide-border">
        {requests.map((r) => (
          <li
            key={r.id}
            className="flex flex-wrap items-center justify-between gap-4 py-4"
          >
            <div>
              <Link
                className="text-primary underline underline-offset-4"
                href={`/admin?tab=client&client=${r.owner}`}
              >
                {r.ownerName}
              </Link>
              <p className="mt-1 text-sm">
                {r.relayer_name} · #{r.relayer_id}
              </p>
              {!r.active ? (
                <p className="text-xs text-destructive">
                  Account suspended. Restore it before approving.
                </p>
              ) : null}
            </div>
            {canWrite ? <div className="flex gap-2">
              <button
                className="relayer-button"
                disabled={pending || !r.active}
                onClick={() => review(r.id, true)}
              >
                Approve relayer
              </button>
              <button
                className="relayer-button"
                disabled={pending}
                onClick={() => review(r.id, false)}
              >
                Decline
              </button>
            </div> : <span className="font-mono text-xs text-muted-foreground">Awaiting Super admin review</span>}
          </li>
        ))}
      </ul>
      {message ? (
        <p className="mt-4 text-sm" role={failed ? "alert" : "status"}>
          {message}
        </p>
      ) : null}
    </section>
  );
}
