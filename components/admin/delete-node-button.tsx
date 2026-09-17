"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2, Trash2 } from "lucide-react";
import { neverLinked } from "@/lib/admin-data";
import { portalRpc } from "@/lib/data-browser";
import type { AdminNode } from "@/lib/types";

// Deleting is the answer for a machine that should not be on the client's
// dashboard at all -- typically one they approved a pairing code for and never
// finished linking. Pause and revoke are the reversible answers for a machine
// that exists, so this one asks for the name to be typed rather than for a
// second click: it takes the telemetry history with it, and it is the only
// administrative action that cannot be undone from the portal.
export function DeleteNodeButton({
  node,
  className = "flex items-center gap-1 rounded-full border border-destructive/40 px-2 py-1 font-mono text-xs uppercase text-destructive transition-colors hover:bg-destructive/10 focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none",
}: {
  node: AdminNode;
  className?: string;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run() {
    const typed = window.prompt(
      `Delete ${node.name} permanently?\n\nThis removes the machine and every reading, alert and delivery recorded for it, from ${node.owner_email ?? "the client"}'s dashboard as well as this one. It cannot be undone, and a machine that is still installed would have to be paired again with sudo hyn link.\n\nType the machine name to confirm:`,
      ""
    );
    if (typed === null) return;
    if (typed.trim() !== node.name) {
      setError(`Nothing was deleted: "${typed.trim()}" does not match ${node.name}.`);
      return;
    }
    const reason = window.prompt(
      "Reason (recorded in the audit trail):",
      neverLinked(node) ? "never linked" : ""
    );
    if (reason === null) return;

    setBusy(true);
    setError(null);
    const { error: failure } = await portalRpc("hyn_admin_delete_node", {
      p_node_id: node.id,
      p_reason: reason,
    });
    setBusy(false);
    if (failure) {
      setError(failure.message);
      return;
    }
    router.refresh();
  }

  return (
    <>
      <button
        type="button"
        onClick={run}
        disabled={busy}
        title="Delete this machine and all of its history"
        className={`${className} disabled:cursor-not-allowed disabled:opacity-50`}
      >
        {busy ? <Loader2 className="size-3 animate-spin" /> : <Trash2 className="size-3" />}
        delete
      </button>
      {error ? (
        <span role="alert" className="block font-mono text-xs text-destructive">
          {error}
        </span>
      ) : null}
    </>
  );
}
