"use client";

import { useState } from "react";
import Link from "next/link";
import { CheckCircle2, Loader2, Server } from "lucide-react";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";

type Pending = {
  hostname: string | null;
  os: string | null;
  agent_version: string | null;
  requested_at: string | null;
};

type Approved = { node_id: string; node_name: string };

// Codes are shown as XXXX-XXXX. Accept whatever the user types (spaces, lower
// case, a missing dash) and normalise, because retyping a code off another
// screen is exactly where fussy input validation costs people time.
function normalise(raw: string) {
  const bare = raw.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 8);
  return bare.length > 4 ? `${bare.slice(0, 4)}-${bare.slice(4)}` : bare;
}

const STATUS_COPY: Record<string, string> = {
  not_found: "No pending request matches that code. Check it and try again.",
  expired: "That code has expired. Run `sudo hyn link` again on the server.",
  already_approved: "That code was already approved.",
};

export function LinkForm({ nodeCount }: { nodeCount: number }) {
  const [code, setCode] = useState("");
  const [pending, setPending] = useState<Pending | null>(null);
  const [approved, setApproved] = useState<Approved | null>(null);
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [emailNotice, setEmailNotice] = useState<string | null>(null);

  const ready = code.replace(/[^A-Z0-9]/g, "").length === 8;

  async function lookup(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setBusy(true);
    const supabase = createClient();
    const { data, error } = await supabase.rpc("hyn_device_lookup", {
      p_user_code: code,
    });
    setBusy(false);
    if (error) {
      setError(error.message);
      return;
    }
    const status = (data as { status?: string })?.status;
    if (status !== "pending") {
      setError(STATUS_COPY[status ?? ""] ?? `Unexpected status: ${status}`);
      return;
    }
    const row = data as Pending & { status: string };
    setPending(row);
    setName(row.hostname ?? "");
  }

  async function approve() {
    setError(null);
    setBusy(true);
    const supabase = createClient();
    const { data, error } = await supabase.rpc("hyn_device_approve", {
      p_user_code: code,
      p_node_name: name,
    });
    setBusy(false);
    if (error) {
      setError(error.message);
      return;
    }
    const row = data as { status?: string; node_id?: string; node_name?: string };
    if (row?.status !== "approved") {
      setError(STATUS_COPY[row?.status ?? ""] ?? `Unexpected status: ${row?.status}`);
      return;
    }
    setApproved({ node_id: row.node_id!, node_name: row.node_name! });
    const emailResponse = await fetch("/api/email/device-linked", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ nodeId: row.node_id }),
      signal: AbortSignal.timeout(10_000),
    }).catch(() => null);
    if (!emailResponse?.ok) {
      setEmailNotice("The machine is linked, but the confirmation email could not be delivered yet. The first telemetry email will retry on check-in.");
    }
  }

  if (approved) {
    return (
      <div className="mt-8 space-y-6 text-center">
        <CheckCircle2 className="mx-auto size-10 text-primary" />
        <div>
          <p className="font-sentient text-2xl text-card-foreground">
            {approved.node_name} is linked
          </p>
          <p className="mt-2 font-mono text-xs leading-6 text-muted-foreground">
            This device is now in your dashboard. No assignment is needed.
            Readings will appear when the server finishes linking and checks in.
          </p>
          {emailNotice ? <p className="mt-3 font-mono text-xs leading-6 text-[#e8a400]">{emailNotice}</p> : null}
        </div>
        <Link href={`/dashboard?node=${encodeURIComponent(approved.node_id)}`} className="contents">
          <Button size="sm" className="w-full">
            Open dashboard
          </Button>
        </Link>
      </div>
    );
  }

  if (pending) {
    return (
      <div className="mt-8 space-y-6">
        <div className="border border-border bg-input/20 p-4">
          <div className="flex items-center gap-3">
            <Server className="size-5 shrink-0 text-primary" aria-hidden />
            <div className="min-w-0">
              <p className="truncate font-mono text-sm text-card-foreground">
                {pending.hostname || "unknown host"}
              </p>
              <p className="truncate font-mono text-xs text-muted-foreground">
                {pending.os || "unknown OS"}
                {pending.agent_version ? ` · hyn ${pending.agent_version}` : ""}
              </p>
            </div>
          </div>
        </div>

        <p className="font-mono text-xs leading-6 text-muted-foreground">
          Only approve this if it matches the machine you just ran{" "}
          <code>sudo hyn link</code> on. Approving grants it permission to send
          telemetry to your account.
        </p>

        <label className="block">
          <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">
            Name this node
          </span>
          <input
            type="text"
            value={name}
            onChange={(event) => setName(event.target.value)}
            placeholder="web-01"
            className="w-full border border-input bg-input/20 px-3 py-2.5 font-mono text-sm text-foreground outline-none focus:border-ring placeholder:text-muted-foreground/60"
          />
        </label>

        {error ? (
          <p role="alert" className="font-mono text-xs text-destructive">
            {error}
          </p>
        ) : null}

        <div className="flex gap-3">
          <Button
            type="button"
            size="sm"
            onClick={approve}
            disabled={busy}
            className="flex-1 gap-2"
          >
            {busy ? <Loader2 className="size-4 animate-spin" /> : null}
            Approve
          </Button>
          <Button
            type="button"
            size="sm"
            onClick={() => {
              setPending(null);
              setError(null);
            }}
            className="flex-1 !border-border !text-foreground"
          >
            Cancel
          </Button>
        </div>
      </div>
    );
  }

  return (
    <form onSubmit={lookup} className="mt-8 space-y-6">
      <label className="block">
        <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">
          Pairing code
        </span>
        <input
          type="text"
          inputMode="text"
          autoFocus
          autoCapitalize="characters"
          autoComplete="off"
          spellCheck={false}
          value={code}
          onChange={(event) => setCode(normalise(event.target.value))}
          placeholder="XXXX-XXXX"
          aria-describedby="code-help"
          className="w-full border border-input bg-input/20 px-3 py-3 text-center font-mono text-2xl tracking-[0.3em] text-foreground outline-none focus:border-ring placeholder:tracking-[0.2em] placeholder:text-muted-foreground/40"
        />
      </label>

      <p id="code-help" className="font-mono text-xs leading-6 text-muted-foreground">
        Run <code className="text-primary">sudo hyn link</code> on the Ubuntu server and
        type the code it prints. It expires after 15 minutes.
      </p>

      {error ? (
        <p role="alert" className="font-mono text-xs text-destructive">
          {error}
        </p>
      ) : null}

      <Button type="submit" size="sm" disabled={!ready || busy} className="w-full gap-2">
        {busy ? <Loader2 className="size-4 animate-spin" /> : null}
        Continue
      </Button>

      {nodeCount > 0 ? (
        <p className="text-center font-mono text-xs text-muted-foreground">
          You already have {nodeCount} linked {nodeCount === 1 ? "node" : "nodes"} ·{" "}
          <Link href="/dashboard" className="text-primary underline underline-offset-4">
            dashboard
          </Link>
        </p>
      ) : null}
    </form>
  );
}
