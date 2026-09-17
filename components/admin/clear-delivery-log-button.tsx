"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Eraser, Loader2 } from "lucide-react";
import { portalRpc } from "@/lib/data-browser";

// The delivery log is the one table nothing prunes, and this panel is where it is
// read, so clearing it belongs here. The scope defaults to a retention purge
// rather than a wipe: clearing months of resolved failures is routine, and
// deleting this morning's failed sends -- the ones somebody is still working
// through -- is not, so the destructive option is the one you have to choose.
// The overview's attention banner passes `defaultScope="all"`, because there the
// stated problem is the last 24 hours and a 30-day cutoff would leave it on screen.
const SCOPES = [
  { value: "30", label: "older than 30 days" },
  { value: "7", label: "older than 7 days" },
  { value: "all", label: "everything" },
];

export function ClearDeliveryLogButton({ defaultScope = "30" }: { defaultScope?: string }) {
  const router = useRouter();
  const [scope, setScope] = useState(defaultScope);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ tone: "ok" | "bad"; text: string } | null>(null);

  async function run() {
    const label = SCOPES.find((s) => s.value === scope)?.label ?? "";
    const confirmed = window.confirm(
      `Clear delivery records ${label}, for every client?\n\nThis removes them from each client's own delivery list as well as this one, and it cannot be undone. The audit trail keeps who cleared it and how many rows went.`
    );
    if (!confirmed) return;
    const reason = window.prompt("Reason (recorded in the audit trail):", "routine cleanup");
    if (reason === null) return;

    setBusy(true);
    setMessage(null);
    const { data, error } = await portalRpc("hyn_admin_clear_notifications", {
      p_before:
        scope === "all"
          ? null
          : new Date(Date.now() - Number(scope) * 86_400_000).toISOString(),
      p_reason: reason,
    });
    setBusy(false);
    if (error) {
      setMessage({ tone: "bad", text: error.message });
      return;
    }
    const deleted = Number((data as { deleted?: number } | null)?.deleted ?? 0);
    setMessage({
      tone: "ok",
      text: `${deleted} delivery record${deleted === 1 ? "" : "s"} cleared.`,
    });
    router.refresh();
  }

  return (
    <div className="flex flex-col items-start gap-2 sm:items-end">
      <div className="flex flex-wrap items-center gap-2">
        <label className="font-mono text-[0.65rem] uppercase text-muted-foreground" htmlFor="clear-delivery-scope">
          Clear
        </label>
        <select
          id="clear-delivery-scope"
          value={scope}
          disabled={busy}
          onChange={(event) => setScope(event.target.value)}
          className="rounded-md border border-input bg-background px-2 py-1.5 font-mono text-xs text-foreground outline-none transition-colors focus:border-ring focus:ring-[3px] focus:ring-ring/50 disabled:opacity-50"
        >
          {SCOPES.map((s) => (
            <option key={s.value} value={s.value}>
              {s.label}
            </option>
          ))}
        </select>
        <button
          type="button"
          onClick={run}
          disabled={busy}
          title="Delete these delivery records for every client"
          className="flex items-center gap-1 rounded-full border border-destructive/40 px-2.5 py-1.5 font-mono text-xs uppercase text-destructive transition-colors hover:bg-destructive/10 focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-50"
        >
          {busy ? <Loader2 className="size-3 animate-spin" /> : <Eraser className="size-3" />}
          clear log
        </button>
      </div>
      {message ? (
        <p
          role="alert"
          className={`font-mono text-[0.65rem] ${message.tone === "ok" ? "text-primary" : "text-destructive"}`}
        >
          {message.text}
        </p>
      ) : null}
    </div>
  );
}
