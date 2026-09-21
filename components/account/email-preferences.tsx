"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { BellRing, Check, Clock3, Cpu, Loader2, Mail } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { portalRpc } from "@/lib/data-browser";
import type { EmailPreference, Node } from "@/lib/types";

type EditablePreference = Pick<
  EmailPreference,
  | "recipient"
  | "timezone"
  | "incident_enabled"
  | "daily_enabled"
  | "daily_at"
  | "system_enabled"
  | "system_at"
>;

// Incident mail is off unless the account turns it on, matching the
// email_preferences column default (supabase migration 20260902050000). These
// defaults are what the form shows for a node with no saved row yet, so a `true`
// here would put the switch on for somebody who has never chosen it -- the same
// mistake the column default made, one layer up.
function defaults(email: string): EditablePreference {
  let timezone = "UTC";
  try { timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC"; } catch {}
  return {
    recipient: email,
    timezone,
    incident_enabled: false,
    daily_enabled: false,
    daily_at: "08:00",
    system_enabled: false,
    system_at: "09:00",
  };
}

export function EmailPreferences({
  nodes,
  preferences,
  accountEmail,
}: {
  nodes: Node[];
  preferences: EmailPreference[];
  accountEmail: string;
}) {
  const router = useRouter();
  const real = nodes.filter((node) => !node.is_demo);
  const [selected, setSelected] = useState(real[0]?.id ?? "");
  const savedPreference = preferences.find((preference) => preference.node_id === selected);
  const initial = useMemo(
    () => ({ ...defaults(accountEmail), ...(savedPreference ?? {}) }),
    [accountEmail, savedPreference]
  );
  const [draft, setDraft] = useState<EditablePreference>(initial);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);

  function selectNode(nodeId: string) {
    setSelected(nodeId);
    const preference = preferences.find((item) => item.node_id === nodeId);
    setDraft({ ...defaults(accountEmail), ...(preference ?? {}) });
    setMessage(null);
  }

  function update<K extends keyof EditablePreference>(key: K, value: EditablePreference[K]) {
    setDraft((current) => ({ ...current, [key]: value }));
    setMessage(null);
  }

  async function save() {
    if (!selected) return;
    setBusy(true);
    setMessage(null);
    try {
      new Intl.DateTimeFormat("en", { timeZone: draft.timezone }).format();
    } catch {
      setBusy(false);
      setMessage({ ok: false, text: "Use an IANA timezone such as Asia/Kolkata, Europe/London, or UTC." });
      return;
    }
    const { error } = await portalRpc("hyn_upsert_email_preferences", {
      p_node_id: selected,
      p_recipient: draft.recipient,
      p_timezone: draft.timezone,
      p_incident_enabled: draft.incident_enabled,
      p_daily_enabled: draft.daily_enabled,
      p_daily_at: draft.daily_at,
      p_system_enabled: draft.system_enabled,
      p_system_at: draft.system_at,
    });
    setBusy(false);
    if (error) {
      setMessage({ ok: false, text: error.message });
      return;
    }
    setMessage({ ok: true, text: "Email schedule saved. No server-side provider setup is required." });
    router.refresh();
  }

  if (real.length === 0) return null;

  const streams = [
    // The note names outage detection because this switch gates it too
    // (workflows/heartbeat-watchdog.ts reads the same incident_enabled), and it is
    // off until asked for -- so somebody who wants to hear that a machine went
    // quiet has to find that out here, not during the outage.
    { key: "incident_enabled" as const, icon: BellRing, title: "Incident alerts", note: "New, ongoing, and resolved problems, and a machine going quiet. Off unless you turn it on", time: null },
    { key: "daily_enabled" as const, icon: Clock3, title: "Daily health", note: "Performance and network summary", time: "daily_at" as const },
    { key: "system_enabled" as const, icon: Cpu, title: "System information", note: "Hardware, software, and service inventory", time: "system_at" as const },
  ];

  return (
    <section className="terminal-panel overflow-hidden rounded-xl duration-500 animate-in fade-in slide-in-from-bottom-2">
      <div className="border-b border-border p-6 md:p-7">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="section-kicker">// email automation</p>
            <h2 className="mt-2 font-sentient text-2xl text-card-foreground">Three signals, one managed delivery rail</h2>
            <p className="mt-2 max-w-2xl font-mono text-xs leading-6 text-muted-foreground">
              HYN sends through the portal&apos;s shared email service. Choose what arrives and when; there are no API keys, SMTP passwords, or templates to configure on your server.
            </p>
          </div>
          {real.length > 1 ? (
            <select
              value={selected}
              onChange={(event) => selectNode(event.target.value)}
              className="rounded-md border border-input bg-background px-3 py-2 font-mono text-sm text-foreground outline-none transition-colors focus:border-ring focus:ring-[3px] focus:ring-ring/50"
            >
              {real.map((node) => <option key={node.id} value={node.id}>{node.name}</option>)}
            </select>
          ) : null}
        </div>
      </div>

      {real.find((node) => node.id === selected)?.telemetry_mode === "local" ? (
        <p className="border-b border-border px-6 py-4 font-mono text-xs leading-6 text-muted-foreground">
          This machine keeps its history locally. Cloud history digests are paused.
          Sending reports from the CLI requires enabling cloud_notifications on the machine.
        </p>
      ) : null}
      <div className="grid gap-px bg-border lg:grid-cols-3">
        {streams.map((stream) => {
          const active = draft[stream.key];
          return (
            <div
              key={stream.key}
              className={`relative bg-card p-5 transition-colors ${active ? "shadow-[inset_0_1px_0_var(--primary)]" : ""}`}
            >
              <div className="flex items-start justify-between gap-3">
                <span
                  className={`flex size-9 items-center justify-center rounded-md border transition-colors ${
                    active ? "border-primary/40 bg-primary/10 text-primary" : "border-border bg-muted text-muted-foreground"
                  }`}
                >
                  <stream.icon className="size-4" aria-hidden />
                </span>
                <Switch checked={active} onCheckedChange={(checked) => update(stream.key, checked)} aria-label={`${stream.title} notifications`} />
              </div>
              <h3 className="mt-4 font-mono text-sm text-card-foreground">{stream.title}</h3>
              <p className="mt-1 min-h-10 font-mono text-[0.65rem] leading-5 text-muted-foreground">{stream.note}</p>
              {stream.time ? (
                <label className="mt-4 block">
                  <span className="mb-1 block font-mono text-[0.6rem] uppercase text-muted-foreground">Send at</span>
                  <input
                    type="time"
                    value={draft[stream.time]}
                    disabled={!active}
                    onChange={(event) => update(stream.time!, event.target.value)}
                    className="w-full rounded-md border border-input bg-background px-3 py-2 font-mono text-sm text-foreground outline-none transition-colors focus:border-ring focus:ring-[3px] focus:ring-ring/50 disabled:opacity-40"
                  />
                </label>
              ) : (
                <p className="mt-6 flex items-center gap-1.5 font-mono text-[0.65rem] uppercase text-primary">
                  <span className="relative flex size-1.5">
                    <span className="node-heartbeat-ring absolute inline-flex size-full rounded-full bg-primary" />
                    <span className="relative inline-flex size-1.5 rounded-full bg-primary" />
                  </span>
                  Immediate
                </p>
              )}
            </div>
          );
        })}
      </div>

      <div className="grid gap-4 border-t border-border p-6 md:grid-cols-2 md:p-7">
        <label>
          <span className="mb-1.5 flex items-center gap-2 font-mono text-[0.65rem] uppercase text-muted-foreground"><Mail className="size-3.5" /> Recipient</span>
          <input
            type="email"
            required
            value={draft.recipient}
            onChange={(event) => update("recipient", event.target.value)}
            className="w-full rounded-md border border-input bg-background px-3 py-2 font-mono text-sm text-foreground outline-none transition-colors focus:border-ring focus:ring-[3px] focus:ring-ring/50"
          />
        </label>
        <label>
          <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">Timezone</span>
          <input
            type="text"
            value={draft.timezone}
            onChange={(event) => update("timezone", event.target.value)}
            placeholder="Asia/Kolkata"
            className="w-full rounded-md border border-input bg-background px-3 py-2 font-mono text-sm text-foreground outline-none transition-colors focus:border-ring focus:ring-[3px] focus:ring-ring/50"
          />
        </label>
        <div className="md:col-span-2 flex flex-wrap items-center justify-between gap-4 border-t border-border pt-4">
          {message ? <p role="status" className={`font-mono text-xs ${message.ok ? "text-primary" : "text-destructive"}`}>{message.ok ? <Check className="mr-1 inline size-3.5" /> : null}{message.text}</p> : <span />}
          <Button type="button" size="sm" onClick={save} disabled={busy || !draft.recipient} className="gap-2">
            {busy ? <Loader2 className="size-4 animate-spin" /> : null} Save email schedule
          </Button>
        </div>
      </div>
    </section>
  );
}
