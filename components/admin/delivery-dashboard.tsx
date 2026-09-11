"use client";

import { useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { saveDailyDigest, saveDeliveryRules, stopDelivery } from "@/app/admin/delivery-actions";
import { attemptTotal, defaultRule, deliveryKinds, effectiveDigest, kindLabel, type DeliveryKind, type DeliverySnapshot, type RuleInput } from "@/lib/delivery-controls";

type Props = { snapshot: DeliverySnapshot; owner: string | null; kind: DeliveryKind; status: string; page: number; canWrite: boolean; enforced: boolean; providerConfigured: boolean; previewHtml: string };
const input = "min-h-10 w-full rounded-md border border-border bg-background px-3 py-2 text-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:opacity-50";
const button = "inline-flex min-h-10 items-center justify-center rounded-md border border-border px-4 py-2 text-sm hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:cursor-not-allowed disabled:opacity-50";
const panel = "terminal-panel min-w-0 rounded-xl border border-border p-5 sm:p-6";
const timestamp = (value: string | null) => value ? new Date(value).toISOString().replace("T", " ").slice(0, 19) + " UTC" : "Not recorded";
const stateLabel = (state: string) => state === "sent" ? "Accepted by provider" : state === "unknown" ? "Needs provider review" : state.charAt(0).toUpperCase() + state.slice(1);

export function DeliveryDashboard({ snapshot, owner, kind, status, page, canWrite, enforced, providerConfigured, previewHtml }: Props) {
  const router = useRouter();
  const [busy, startTransition] = useTransition();
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);
  const [rules, setRules] = useState<RuleInput[]>(() => deliveryKinds.map(({ key }) => {
    const rule = snapshot.rules.find(r => r.owner === owner && r.kind === key) ?? defaultRule(key);
    return { kind: key, enabled: rule.enabled, daily_limit: rule.daily_limit, max_attempts: rule.max_attempts, retry_minutes: rule.retry_minutes };
  }));
  const digest = effectiveDigest(snapshot.digest_settings, owner);
  const explicitDigest = snapshot.digest_settings.find(s => s.owner === owner && s.configured);
  const [inherit, setInherit] = useState(Boolean(owner && !explicitDigest));
  const [enabled, setEnabled] = useState(digest.enabled);
  const [sendAt, setSendAt] = useState(digest.send_at.slice(0, 5));
  const [timezone, setTimezone] = useState(digest.timezone);
  const [confirmAll, setConfirmAll] = useState(false);
  const [stopId, setStopId] = useState<string | null>(null);
  const scopeName = owner ? snapshot.users.find(user => user.id === owner)?.name ?? "Selected user" : "Global defaults";
  const attempts = attemptTotal(snapshot.usage);
  const accepted = snapshot.usage.reduce((sum, row) => sum + row.sent, 0);
  const failed = snapshot.usage.reduce((sum, row) => sum + row.failed, 0);
  const unknown = snapshot.usage.reduce((sum, row) => sum + row.unknown, 0);
  const globalRule = snapshot.rules.find(r => r.owner === null && r.kind === "all");
  const globalAttempts = attemptTotal(snapshot.global_usage);
  const changeFilter = (changes: Record<string, string | null>) => {
    const query = new URLSearchParams();
    const values = { owner, kind, status, page: "1", ...changes };
    Object.entries(values).forEach(([key, value]) => { if (value && value !== "all" && !(key === "page" && value === "1")) query.set(key, value); });
    router.push(`/admin/deliveries${query.size ? `?${query}` : ""}`);
  };
  const save = (operation: () => Promise<{ ok: boolean; error?: string }>, success: string) => {
    setMessage(null);
    startTransition(async () => {
      try {
        const result = await operation();
        setMessage({ ok: result.ok, text: result.ok ? success : result.error ?? "The change was not saved." });
        if (result.ok) { setConfirmAll(false); setStopId(null); router.refresh(); }
      } catch { setMessage({ ok: false, text: "The request failed. Your saved settings have not been confirmed." }); }
    });
  };
  const updateRule = (index: number, patch: Partial<RuleInput>) => setRules(current => current.map((rule, i) => i === index ? { ...rule, ...patch } : rule));

  return <div className="space-y-6">
    {(!enforced || !providerConfigured) && <div role="alert" className="rounded-xl border border-amber-500/40 bg-amber-500/5 p-4 text-sm">
      {!enforced ? "Tracking and caps are not enabled on this deployment. Settings are saved, but legacy sending still applies until HYN_DELIVERY_CONTROLS_ENABLED is enabled." : "The email provider or service credentials are missing. Managed sending fails closed until configuration is complete."}
    </div>}
    {!canWrite && <p className="rounded-lg border border-border p-3 text-sm text-muted-foreground">Read-only admin view. A super admin can change sending policies and schedules.</p>}
    <section className={`${panel} flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between`} aria-label="Delivery scope">
      <div><p className="section-kicker">// scope</p><h2 className="mt-2 font-sentient text-2xl">{scopeName}</h2><p className="mt-1 text-xs text-muted-foreground">Global budgets always apply. User rules may narrow them, never bypass them.</p></div>
      <label className="block w-full text-xs sm:max-w-sm">Manage deliveries for
        <select className={`${input} mt-2`} value={owner ?? ""} onChange={event => changeFilter({ owner: event.target.value || null })}>
          <option value="">Global defaults / all users</option>
          {snapshot.users.map(user => <option key={user.id} value={user.id}>{user.name}{user.email ? ` (${user.email})` : ""}{user.status !== "active" ? " - inactive" : ""}</option>)}
        </select>
      </label>
    </section>
    <section aria-label="Today's sending usage" className="grid grid-cols-2 gap-3 lg:grid-cols-4">
      {[["Attempts reserved", attempts], ["Accepted by provider", accepted], ["Failed attempts", failed], ["Needs review", unknown]].map(([label, value]) => <div key={label} className={panel}><p className="text-xs text-muted-foreground">{label}</p><p className="mt-3 font-sentient text-4xl tabular-nums">{value}</p></div>)}
    </section>
    <p className="text-xs leading-relaxed text-muted-foreground">Daily budgets reset at 00:00 UTC and count every reserved attempt, including retries. Tracking began {timestamp(snapshot.started_at)}. Global email usage: <strong className="text-foreground">{globalAttempts} / {globalRule?.daily_limit ?? "no configured cap"}</strong>. These are your application budgets, not the provider&apos;s plan allowance. Updated {timestamp(snapshot.as_of)}.</p>
    {message && <p role={message.ok ? "status" : "alert"} className={`rounded-lg border p-3 text-sm ${message.ok ? "border-primary/40" : "border-destructive/50"}`}>{message.text}</p>}
    <div className="grid gap-6 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
      <section className={panel}>
        <p className="section-kicker">// email via Resend</p><h2 className="mt-2 font-sentient text-2xl">Sending budgets</h2>
        <p className="mt-2 text-xs leading-relaxed text-muted-foreground">Blank means no additional cap; 0 blocks that type. A pause at any applicable scope blocks sending. The lowest attempt limit and longest retry delay apply. Unknown outcomes are never retried automatically.</p>
        <form className="mt-5" onSubmit={event => { event.preventDefault(); save(() => saveDeliveryRules(owner, rules), "Sending budgets saved."); }}>
          <fieldset disabled={!canWrite || busy} className="space-y-3">
            {rules.map((rule, index) => <details key={rule.kind} open={rule.kind === "all" || rule.kind === "daily"} className="rounded-lg border border-border p-3">
              <summary className="cursor-pointer text-sm font-medium">{kindLabel(rule.kind)} <span className="ml-2 font-mono text-xs text-muted-foreground">{rule.enabled ? rule.daily_limit === null ? "uncapped" : `${rule.daily_limit}/day` : "paused"}</span></summary>
              <p className="mt-3 text-xs text-muted-foreground">{deliveryKinds.find(item => item.key === rule.kind)?.description}</p>
              <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
                <label className="text-xs">Daily attempts<input aria-label={`${kindLabel(rule.kind)} daily attempts`} type="number" min="0" max="100000" step="1" placeholder="No extra cap" className={`${input} mt-1`} value={rule.daily_limit ?? ""} onChange={event => updateRule(index, { daily_limit: event.target.value === "" ? null : Number(event.target.value) })} /></label>
                <label className="text-xs">Max attempts<input aria-label={`${kindLabel(rule.kind)} maximum attempts`} type="number" min="1" max="5" step="1" required className={`${input} mt-1`} value={rule.max_attempts} onChange={event => updateRule(index, { max_attempts: Number(event.target.value) })} /></label>
                <label className="text-xs">Retry delay (min)<input aria-label={`${kindLabel(rule.kind)} retry delay`} type="number" min="1" max="1440" step="1" required className={`${input} mt-1`} value={rule.retry_minutes} onChange={event => updateRule(index, { retry_minutes: Number(event.target.value) })} /></label>
              </div>
              <label className="mt-3 flex min-h-8 items-center gap-2 text-xs"><input type="checkbox" checked={rule.enabled} onChange={event => updateRule(index, { enabled: event.target.checked })} />Allow {kindLabel(rule.kind).toLowerCase()}</label>
              <p className="mt-1 font-mono text-xs text-muted-foreground">{attemptTotal(snapshot.usage, rule.kind)} attempts today in this scope</p>
            </details>)}
            <button className={`${button} w-full bg-primary text-primary-foreground hover:opacity-90`} type="submit">{busy ? "Saving..." : "Save sending budgets"}</button>
          </fieldset>
        </form>
      </section>
      <div className="space-y-6">
        <section className={panel}>
          <p className="section-kicker">// daily summary</p><h2 className="mt-2 font-sentient text-2xl">One user. One daily email.</h2>
          <p className="mt-2 text-sm text-muted-foreground">Combines all currently permitted servers in a single HTML email to the user&apos;s profile address. Shared-server notification opt-outs are respected.</p>
          <p className="mt-3 rounded-md bg-muted/50 p-3 text-xs">Saved state: <strong>{digest.configured ? digest.enabled ? "Enabled" : "Disabled" : "Not configured (combined emails off)"}</strong>{owner && !explicitDigest ? " - inherits global defaults" : ""}. Explicit user overrides are preserved when global defaults change.</p>
          <form className="mt-5" onSubmit={event => { event.preventDefault(); save(() => saveDailyDigest(owner, enabled, sendAt, timezone, inherit, confirmAll), "Daily digest settings saved. No email was sent by this action."); }}>
            <fieldset disabled={!canWrite || busy} className="space-y-4">
              {owner && <label className="flex min-h-8 items-center gap-2 text-sm"><input type="checkbox" checked={inherit} onChange={event => setInherit(event.target.checked)} />Use global digest defaults</label>}
              <fieldset disabled={Boolean(owner && inherit)} className="space-y-4 disabled:opacity-50">
                <label className="flex min-h-8 items-center gap-2 text-sm"><input type="checkbox" checked={enabled} onChange={event => setEnabled(event.target.checked)} />Enable combined daily email</label>
                <div className="grid grid-cols-2 gap-3"><label className="text-xs">Not before<input type="time" required value={sendAt} onChange={event => setSendAt(event.target.value)} className={`${input} mt-1`} /></label>
                  <label className="text-xs">Timezone<input required maxLength={100} placeholder="Asia/Kolkata" value={timezone} onChange={event => setTimezone(event.target.value)} className={`${input} mt-1`} /></label></div>
              </fieldset>
              {!owner && <label className="flex items-start gap-2 rounded-lg border border-amber-500/40 p-3 text-xs leading-relaxed"><input className="mt-1" type="checkbox" checked={confirmAll} onChange={event => setConfirmAll(event.target.checked)} />I confirm this changes the default daily schedule for all active users without an explicit override.</label>}
              <button type="submit" disabled={!owner && !confirmAll} className={`${button} w-full`}>{owner && inherit ? "Restore global digest defaults" : "Save daily schedule"}</button>
            </fieldset>
          </form>
          <p className="mt-4 text-xs leading-relaxed text-muted-foreground">Delivery runs on the next scheduled or telemetry dispatch after this time, not at an exact minute. Configuring this setting replaces legacy per-server daily emails, including when disabled. Unconfigured accounts retain their existing schedule. Saving does not send an immediate email.</p>
        </section>
        <section className={panel}><p className="section-kicker">// in-app & browser</p><h2 className="mt-2 font-sentient text-2xl">A separate channel</h2><p className="mt-3 text-sm text-muted-foreground">Dashboard alerts remain permission-scoped. Browser notifications require the user&apos;s permission. They do not consume these email budgets and do not provide email delivery receipts.</p><p className="mt-3 text-xs text-muted-foreground">Supabase Auth emails and emails sent directly by an external agent/provider are outside this portal ledger. A legacy log marked &quot;web&quot; means web-managed email, not an in-app alert.</p></section>
      </div>
    </div>
    <section className={panel} aria-label="Delivery history">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between"><div><p className="section-kicker">// durable history</p><h2 className="mt-2 font-sentient text-2xl">Deliveries & attempts</h2><p className="mt-2 text-xs text-muted-foreground">Provider acceptance is not confirmed inbox delivery. Stopping retries preserves every attempt.</p></div>
        <div className="grid grid-cols-2 gap-3"><label className="text-xs">Type<select className={`${input} mt-1`} value={kind} onChange={event => changeFilter({ kind: event.target.value })}>{deliveryKinds.map(item => <option key={item.key} value={item.key}>{item.label}</option>)}</select></label><label className="text-xs">Status<select className={`${input} mt-1`} value={status} onChange={event => changeFilter({ status: event.target.value })}>{["all", "pending", "sending", "sent", "failed", "suppressed", "unknown", "cancelled"].map(item => <option key={item} value={item}>{item === "all" ? "All statuses" : stateLabel(item)}</option>)}</select></label></div>
      </div>
      <div className="mt-5 space-y-3">{snapshot.events.length === 0 ? <p className="rounded-lg border border-dashed border-border p-8 text-center text-sm text-muted-foreground">No matching deliveries. Nothing is sent merely by opening this dashboard.</p> : snapshot.events.map(event => <article key={event.id} className="rounded-lg border border-border p-4">
        <div className="flex flex-col gap-2 sm:flex-row sm:justify-between"><div className="min-w-0"><h3 className="break-words text-sm font-medium">{event.subject}</h3><p className="mt-1 break-words text-xs text-muted-foreground">{event.owner_name} / {event.recipient}{event.node_name ? ` / ${event.node_name}` : " / user-level message"}</p></div><span className="shrink-0 self-start rounded border border-border px-2 py-1 font-mono text-xs">{stateLabel(event.status)}</span></div>
        <p className="mt-3 font-mono text-xs text-muted-foreground">{kindLabel(event.kind)} / {event.attempt_count} of {event.attempt_limit} attempts / {timestamp(event.updated_at)}</p>
        {event.reason && <p className="mt-2 break-words text-xs">{event.reason}</p>}{event.next_retry_at && !event.terminal && <p className="mt-1 text-xs text-muted-foreground">Next eligible retry: {timestamp(event.next_retry_at)}</p>}
        <details className="mt-3"><summary className="cursor-pointer text-xs underline underline-offset-4">Attempt history ({event.attempts.length})</summary><ol className="mt-3 space-y-3 border-l border-border pl-4">{event.attempts.map((attempt, index) => <li key={attempt.id} className="text-xs"><p>{index + 1}. {stateLabel(attempt.status)} / {timestamp(attempt.started_at)}</p>{attempt.error && <p className="mt-1 break-words text-muted-foreground">{attempt.error}</p>}{attempt.provider_id && <p className="mt-1 break-all font-mono text-muted-foreground">Provider reference: {attempt.provider_id}</p>}</li>)}</ol>{event.attempts.length === 0 && <p className="mt-2 text-xs text-muted-foreground">Suppressed before contacting the provider.</p>}</details>
        {canWrite && !event.terminal && !["sent", "sending"].includes(event.status) && <div className="mt-3">{stopId === event.id ? <div className="flex flex-wrap items-center gap-2 text-xs"><span>Stop all future attempts for this message?</span><button disabled={busy} className={button} onClick={() => save(() => stopDelivery(event.id), "Future retries stopped. Attempt history was retained.")}>Confirm stop</button><button className={button} onClick={() => setStopId(null)}>Keep retries</button></div> : <button className={button} onClick={() => setStopId(event.id)}>Stop retries</button>}</div>}
      </article>)}</div>
      <div className="mt-5 flex items-center justify-between gap-2"><button className={button} disabled={page <= 1} onClick={() => changeFilter({ page: String(page - 1) })}>Previous</button><p className="text-center text-xs text-muted-foreground">Page {page} / {Math.max(1, Math.ceil(snapshot.total / 25))} / {snapshot.total} messages</p><button className={button} disabled={page * 25 >= snapshot.total || page >= 4001} onClick={() => changeFilter({ page: String(page + 1) })}>Next</button></div>
    </section>
    <div className="grid gap-6 lg:grid-cols-2">
      <section className={panel}><div className="flex items-center justify-between gap-3"><h2 className="font-sentient text-2xl">Email format</h2><Link href="/admin?tab=templates" className="text-xs underline underline-offset-4">Manage templates</Link></div><p className="my-3 text-xs text-muted-foreground">Sample combined HTML digest using the report template. No live data or email is sent.</p><iframe title="Sample combined daily email" sandbox="" srcDoc={previewHtml} className="h-[460px] w-full rounded-lg border border-border bg-white" /></section>
      <section className={panel}><h2 className="font-sentient text-2xl">Legacy / agent log</h2><p className="mt-2 text-xs text-muted-foreground">Latest 50 older or agent-reported entries for this scope. These may overlap managed messages and are not added to budget totals.</p><div className="mt-4 max-h-[470px] space-y-3 overflow-auto">{snapshot.legacy.length === 0 ? <p className="text-sm text-muted-foreground">No legacy entries.</p> : snapshot.legacy.map(entry => <div key={entry.id} className="rounded-lg border border-border p-3 text-xs"><p className="break-words font-medium">{entry.subject ?? entry.kind}</p><p className="mt-1 break-words text-muted-foreground">{entry.owner_name} / {entry.node_name ?? "Server unavailable"}</p><p className="mt-1 font-mono text-muted-foreground">{entry.kind} / {entry.status} / {timestamp(entry.ts)}</p>{entry.error && <p className="mt-2 break-words">{entry.error}</p>}</div>)}</div></section>
    </div>
  </div>;
}
