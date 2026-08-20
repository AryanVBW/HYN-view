"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2, Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";
import type { ChannelKind, Node, NotificationChannel } from "@/lib/types";

// What each channel's "target" actually means, and whether it needs a credential.
// Getting this wrong is the most common way a notification setup silently fails,
// so the form says it rather than leaving the user to guess.
const KINDS: Record<
  ChannelKind,
  { label: string; targetLabel: string; targetHint: string; secretLabel?: string; secretHint?: string }
> = {
  resend: {
    label: "Email via Resend",
    targetLabel: "Send to",
    targetHint: "you@example.com — without a verified domain, Resend only delivers to your own account address",
    secretLabel: "API key",
    secretHint: "re_… from resend.com/api-keys",
  },
  brevo: {
    label: "Email via Brevo",
    targetLabel: "Send to",
    targetHint: "you@example.com — needs a verified sender",
    secretLabel: "API key",
    secretHint: "xkeysib-…",
  },
  smtp: {
    label: "Email via SMTP",
    targetLabel: "Send to",
    targetHint: "you@example.com — set smtp_host and smtp_port in node settings",
    secretLabel: "Password",
    secretHint: "an app password, not your account password",
  },
  ntfy: {
    label: "Push via ntfy",
    targetLabel: "Topic",
    targetHint: "the topic name is the only access control, so make it long and unguessable",
  },
  telegram: {
    label: "Push via Telegram",
    targetLabel: "Chat ID",
    targetHint: "numeric chat id from @BotFather",
    secretLabel: "Bot token",
    secretHint: "123456:ABC-…",
  },
  webhook: {
    label: "Slack or Discord webhook",
    targetLabel: "Webhook URL",
    targetHint: "the full incoming-webhook URL — treat it as a secret, the path is the credential",
  },
};

export function ChannelManager({
  channels,
  nodes,
  ownerId,
}: {
  channels: NotificationChannel[];
  nodes: Node[];
  ownerId: string;
}) {
  const router = useRouter();
  const [adding, setAdding] = useState(false);
  const [kind, setKind] = useState<ChannelKind>("resend");
  const [target, setTarget] = useState("");
  const [secret, setSecret] = useState("");
  const [nodeId, setNodeId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const spec = KINDS[kind];

  async function add(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!target.trim()) return;
    setBusy(true);
    setError(null);
    const supabase = createClient();
    const { error } = await supabase.from("notification_channels").insert({
      owner: ownerId,
      node_id: nodeId || null,
      kind,
      target: target.trim(),
      secret: secret.trim() || null,
    });
    setBusy(false);
    if (error) {
      setError(error.message);
      return;
    }
    setTarget("");
    setSecret("");
    setAdding(false);
    router.refresh();
  }

  async function toggle(channel: NotificationChannel) {
    const supabase = createClient();
    const { error } = await supabase
      .from("notification_channels")
      .update({ enabled: !channel.enabled })
      .eq("id", channel.id);
    if (error) setError(error.message);
    router.refresh();
  }

  async function remove(id: string) {
    const supabase = createClient();
    const { error } = await supabase.from("notification_channels").delete().eq("id", id);
    if (error) setError(error.message);
    router.refresh();
  }

  return (
    <div className="terminal-panel p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="section-kicker">// where alerts go</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">
            Notification channels
          </p>
          <p className="mt-2 max-w-xl font-mono text-xs leading-6 text-muted-foreground">
            Configured here, pulled by each server on its next check-in. Nothing
            needs editing on the machine itself.
          </p>
        </div>
        <Button type="button" size="sm" onClick={() => setAdding(!adding)} className="gap-2">
          <Plus className="size-4" />
          Add channel
        </Button>
      </div>

      {adding ? (
        <form onSubmit={add} className="mt-6 space-y-4 border border-border bg-input/10 p-4">
          <label className="block">
            <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">
              Channel
            </span>
            <select
              value={kind}
              onChange={(event) => setKind(event.target.value as ChannelKind)}
              className="w-full border border-input bg-background px-3 py-2.5 font-mono text-sm text-foreground outline-none focus:border-ring"
            >
              {(Object.keys(KINDS) as ChannelKind[]).map((k) => (
                <option key={k} value={k}>
                  {KINDS[k].label}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">
              {spec.targetLabel}
            </span>
            <input
              value={target}
              onChange={(event) => setTarget(event.target.value)}
              required
              className="w-full border border-input bg-background px-3 py-2.5 font-mono text-sm text-foreground outline-none focus:border-ring"
            />
            <span className="mt-1 block font-mono text-[0.65rem] leading-5 text-muted-foreground">
              {spec.targetHint}
            </span>
          </label>

          {spec.secretLabel ? (
            <label className="block">
              <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">
                {spec.secretLabel}
              </span>
              <input
                type="password"
                value={secret}
                onChange={(event) => setSecret(event.target.value)}
                autoComplete="off"
                className="w-full border border-input bg-background px-3 py-2.5 font-mono text-sm text-foreground outline-none focus:border-ring"
              />
              <span className="mt-1 block font-mono text-[0.65rem] leading-5 text-muted-foreground">
                {spec.secretHint} · stored write-only: it can be replaced but never read back here
              </span>
            </label>
          ) : null}

          <label className="block">
            <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">
              Applies to
            </span>
            <select
              value={nodeId}
              onChange={(event) => setNodeId(event.target.value)}
              className="w-full border border-input bg-background px-3 py-2.5 font-mono text-sm text-foreground outline-none focus:border-ring"
            >
              <option value="">every server</option>
              {nodes.map((n) => (
                <option key={n.id} value={n.id}>
                  {n.name}
                </option>
              ))}
            </select>
          </label>

          {error ? (
            <p role="alert" className="font-mono text-xs text-destructive">
              {error}
            </p>
          ) : null}

          <Button type="submit" size="sm" disabled={busy} className="w-full gap-2">
            {busy ? <Loader2 className="size-4 animate-spin" /> : null}
            Save channel
          </Button>
        </form>
      ) : null}

      {channels.length === 0 ? (
        <div className="mt-6 flex items-center justify-center rounded-sm border border-dashed border-border/60 px-6 py-10">
          <p className="max-w-md text-center font-mono text-xs leading-6 text-muted-foreground">
            No channels configured, so nothing is sent. Alerts are still evaluated
            on each server and shown here — they just do not reach you.
          </p>
        </div>
      ) : (
        <ul className="mt-6 divide-y divide-border/60">
          {channels.map((c) => (
            <li key={c.id} className="flex flex-wrap items-center gap-4 py-4">
              <div className="min-w-0 flex-1">
                <p className="font-mono text-sm text-card-foreground">
                  {KINDS[c.kind]?.label ?? c.kind}
                </p>
                <p className="truncate font-mono text-xs text-muted-foreground">
                  {c.target} ·{" "}
                  {c.node_id
                    ? nodes.find((n) => n.id === c.node_id)?.name ?? "one server"
                    : "every server"}
                </p>
              </div>
              <button
                type="button"
                onClick={() => toggle(c)}
                className={`border px-2 py-1 font-mono text-[0.65rem] uppercase transition-colors ${
                  c.enabled
                    ? "border-primary/50 text-primary"
                    : "border-border text-muted-foreground"
                }`}
              >
                {c.enabled ? "enabled" : "disabled"}
              </button>
              <button
                type="button"
                onClick={() => remove(c.id)}
                aria-label={`Remove ${c.kind} channel`}
                className="text-muted-foreground transition-colors hover:text-destructive"
              >
                <Trash2 className="size-4" />
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
