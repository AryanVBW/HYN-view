"use client";

import { useState, useTransition } from "react";
import { Check, Code2, Eye, Loader2, Save } from "lucide-react";
import { saveNotificationTemplate } from "@/app/admin/actions";
import type { NotificationTemplate } from "@/lib/types";

const PREVIEW_CONTENT = `
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="font-family:Arial,sans-serif;background:#ffffff;color:#0f172a;border:1px solid #e2e8f0">
  <tr><td style="height:4px;background:#FFC700"></td></tr>
  <tr><td style="padding:24px">
    <div style="font-size:11px;letter-spacing:.12em;color:#64748b;text-transform:uppercase">HYN-view preview</div>
    <h1 style="font-size:24px;margin:6px 0 16px">Example notification content</h1>
    <p style="font-size:14px;line-height:1.6;margin:0">The generated alert or daily report is inserted here on the monitored server.</p>
  </td></tr>
</table>`;

function previewDocument(template: string): string {
  const rendered = template
    .replaceAll("{{content}}", PREVIEW_CONTENT)
    .replaceAll("{{hostname}}", "edge-node-01")
    .replaceAll("{{version}}", "1.5.0")
    .replaceAll("{{severity}}", "warning")
    .replaceAll("{{subject}}", "[WARNING] edge-node-01: CPU pressure");
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data: cid:"><style>html,body{margin:0;padding:0;background:#eef2f7}</style></head><body>${rendered}</body></html>`;
}

function formatSavedAt(value: string): string {
  return `${new Intl.DateTimeFormat("en-GB", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "UTC",
  }).format(new Date(value))} UTC`;
}

export function EmailTemplateManager({ templates, canWrite = false }: { templates: NotificationTemplate[]; canWrite?: boolean }) {
  const [activeKey, setActiveKey] = useState<NotificationTemplate["template_key"]>(
    templates[0]?.template_key ?? "alert"
  );
  const active = templates.find((template) => template.template_key === activeKey);
  const [drafts, setDrafts] = useState<Record<string, string>>(() =>
    Object.fromEntries(templates.map((template) => [template.template_key, template.html_template]))
  );
  const [view, setView] = useState<"code" | "preview">("code");
  const [message, setMessage] = useState<{ tone: "ok" | "bad"; text: string } | null>(null);
  const [pending, startTransition] = useTransition();
  const draft = drafts[activeKey] ?? active?.html_template ?? "{{content}}";
  const preview = previewDocument(draft);

  function save() {
    setMessage(null);
    startTransition(async () => {
      const result = await saveNotificationTemplate(activeKey, draft);
      setMessage(
        result.ok
          ? { tone: "ok", text: "Template saved. Linked nodes receive it on their next config pull." }
          : { tone: "bad", text: result.error }
      );
    });
  }

  if (templates.length === 0) {
    return (
      <div className="terminal-panel rounded-xl p-8 font-mono text-xs leading-6 text-muted-foreground">
        No templates are installed. Apply the latest Supabase schema to seed the alert and daily report templates.
      </div>
    );
  }

  return (
    <section className="terminal-panel overflow-hidden rounded-xl duration-500 animate-in fade-in slide-in-from-bottom-2">
      <div className="border-b border-border p-6 md:p-7">
        <p className="section-kicker">// email templates</p>
        <h2 className="mt-2 font-sentient text-2xl text-card-foreground">Delivery presentation</h2>
        <p className="mt-2 max-w-3xl font-mono text-xs leading-6 text-muted-foreground">
          Templates wrap incident, daily health, and system-information emails. The shared provider key stays in the portal deployment environment; clients configure only recipients and timing.
        </p>
      </div>

      <div className="grid lg:grid-cols-[260px_1fr]">
        <nav className="border-b border-border bg-muted/20 p-3 lg:border-r lg:border-b-0" aria-label="Email templates">
          {templates.map((template) => (
            <button
              key={template.template_key}
              type="button"
              onClick={() => {
                setActiveKey(template.template_key);
                setMessage(null);
              }}
              className={`mb-2 w-full rounded-md border p-3 text-left transition-colors focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none ${
                template.template_key === activeKey
                  ? "border-primary bg-primary/10"
                  : "border-transparent hover:border-border hover:bg-card"
              }`}
            >
              <span className="block font-mono text-xs uppercase text-card-foreground">{template.name}</span>
              <span className="mt-1 block font-mono text-[0.65rem] leading-5 text-muted-foreground">{template.description}</span>
            </button>
          ))}
        </nav>

        <div className="min-w-0 p-4 md:p-6">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p className="font-mono text-sm text-card-foreground">{active?.name}</p>
              <p className="mt-1 font-mono text-[0.65rem] text-muted-foreground">
                Last saved {active?.updated_at ? formatSavedAt(active.updated_at) : "—"}
                {active?.updated_by_email ? ` by ${active.updated_by_email}` : ""}
              </p>
            </div>
            <div className="flex overflow-hidden rounded-md border border-border">
              <button
                type="button"
                onClick={() => setView("code")}
                className={`flex items-center gap-2 px-3 py-2 font-mono text-xs transition-colors focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none ${view === "code" ? "bg-primary/10 text-primary" : "text-muted-foreground hover:text-foreground"}`}
              >
                <Code2 className="size-3.5" aria-hidden /> HTML
              </button>
              <button
                type="button"
                onClick={() => setView("preview")}
                className={`flex items-center gap-2 px-3 py-2 font-mono text-xs transition-colors focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none ${view === "preview" ? "bg-primary/10 text-primary" : "text-muted-foreground hover:text-foreground"}`}
              >
                <Eye className="size-3.5" aria-hidden /> Preview
              </button>
            </div>
          </div>

          <div className="mt-5">
            {view === "code" ? (
              <textarea readOnly={!canWrite}
                aria-label={`${active?.name ?? activeKey} HTML`}
                value={draft}
                onChange={(event) => {
                  setDrafts((current) => ({ ...current, [activeKey]: event.target.value }));
                  setMessage(null);
                }}
                spellCheck={false}
                className="min-h-[440px] w-full resize-y rounded-md border border-input bg-background p-4 font-mono text-xs leading-6 text-foreground outline-none transition-colors focus:border-primary focus:ring-[3px] focus:ring-ring/50"
              />
            ) : (
              <iframe
                title={`${active?.name ?? activeKey} email preview`}
                srcDoc={preview}
                sandbox=""
                referrerPolicy="no-referrer"
                className="h-[440px] w-full rounded-md border border-border bg-white"
              />
            )}
          </div>

          <div className="mt-4 flex flex-col gap-4 border-t border-border pt-4 md:flex-row md:items-end md:justify-between">
            <div className="font-mono text-[0.65rem] leading-5 text-muted-foreground">
              <p>Required: <code className="text-primary">{"{{content}}"}</code></p>
              <p>Optional: {"{{hostname}} · {{version}} · {{severity}} · {{subject}}"}</p>
            </div>
            {canWrite ? <button
              type="button"
              disabled={pending}
              onClick={save}
              className="flex min-w-40 items-center justify-center gap-2 rounded-md border border-primary bg-primary/10 px-4 py-2.5 font-mono text-xs uppercase text-primary transition-colors hover:bg-primary/20 focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none disabled:cursor-wait disabled:opacity-60"
            >
              {pending ? <Loader2 className="size-4 animate-spin" aria-hidden /> : message?.tone === "ok" ? <Check className="size-4" aria-hidden /> : <Save className="size-4" aria-hidden />}
              {pending ? "Saving" : "Save template"}
            </button> : <p className="font-mono text-xs text-muted-foreground">Only Super admins can edit templates.</p>}
          </div>

          {message ? (
            <p role="status" className={`mt-4 rounded-md border p-3 font-mono text-xs leading-5 ${message.tone === "ok" ? "border-primary/40 bg-primary/5 text-primary" : "border-destructive/40 bg-destructive/5 text-destructive"}`}>
              {message.text}
            </p>
          ) : null}
        </div>
      </div>
    </section>
  );
}
