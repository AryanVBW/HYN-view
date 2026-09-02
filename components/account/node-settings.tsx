"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2, Save } from "lucide-react";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";
import type { Node } from "@/lib/types";
import { mergePortalConfig } from "@/lib/node-config";

// The settings worth exposing in a browser. Deliberately not every config key
// the agent understands: the long tail (theme, graph style, panel order) only
// matters to someone sitting at the terminal, and putting fifty inputs here
// would bury the handful that change behaviour people care about.
//
// `group` is presentational only -- it decides which sub-heading a field
// renders under, nothing else. The three groups (thresholds / schedule /
// update & display) are the natural clusters already implied by the field
// order below; grouping them visually is the smallest fix for "twelve
// identical boxes in a row" that doesn't touch what any field does.
const GROUPS = ["Alert thresholds", "Alerting schedule", "Update & display"] as const;
type Group = (typeof GROUPS)[number];

const FIELDS: {
  key: string;
  label: string;
  hint: string;
  type: "number" | "text" | "time" | "select";
  group: Group;
  choices?: { value: string; label: string }[];
}[] = [
  { key: "alert_mem_pct", label: "Memory alert %", hint: "0 disables this rule", type: "number", group: "Alert thresholds" },
  { key: "alert_disk_pct", label: "Disk alert %", hint: "per mount point", type: "number", group: "Alert thresholds" },
  { key: "alert_temp_c", label: "Temperature alert °C", hint: "0 disables", type: "number", group: "Alert thresholds" },
  { key: "alert_load_per_core", label: "Load alert, % per core", hint: "400 means load 4.0 per core", type: "number", group: "Alert thresholds" },
  { key: "alert_latency_ms", label: "Latency alert, ms", hint: "first-hop and internet", type: "number", group: "Alert thresholds" },
  {
    key: "alert_min_severity", label: "Minimum severity", hint: "minimum alert level sent", type: "select", group: "Alerting schedule",
    choices: [
      { value: "crit", label: "Critical only" },
      { value: "warn", label: "Warnings and critical" },
      { value: "info", label: "All events" },
    ],
  },
  { key: "alert_repeat_hours", label: "Repeat interval, hours", hint: "how often a still-firing alert repeats", type: "number", group: "Alerting schedule" },
  { key: "report_at", label: "Daily report time", hint: "server local time, HH:MM", type: "time", group: "Alerting schedule" },
  { key: "notify_max_per_day", label: "Daily notification cap", hint: "backstop against a flapping rule", type: "number", group: "Alerting schedule" },
  { key: "cloud_push_min", label: "Telemetry interval, minutes", hint: "10 recommended; settings still sync every minute", type: "number", group: "Alerting schedule" },
  {
    key: "auto_update",
    label: "CLI updates",
    hint: "applies on the next server check-in",
    type: "select",
    group: "Update & display",
    choices: [
      { value: "check", label: "Notify before installing" },
      { value: "install", label: "Install automatically" },
      { value: "off", label: "Manual only" },
    ],
  },
  {
    key: "dashboard_view",
    label: "Terminal dashboard view",
    hint: "what opens on the server's own screen with no key pressed",
    type: "select",
    group: "Update & display",
    choices: [
      { value: "dash", label: "Advanced (full dashboard)" },
      { value: "simple", label: "Simple (status, speed, temp only)" },
    ],
  },
];

export function NodeSettings({ nodes }: { nodes: Node[] }) {
  const router = useRouter();
  const real = nodes.filter((n) => !n.is_demo);
  const [selected, setSelected] = useState(real[0]?.id ?? "");
  const node = real.find((n) => n.id === selected);
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  if (real.length === 0) {
    return (
      <div className="terminal-panel rounded-xl p-6 duration-500 animate-in fade-in slide-in-from-bottom-2 md:p-7">
        <p className="section-kicker">// server settings</p>
        <p className="mt-2 font-sentient text-2xl text-card-foreground">No servers linked</p>
        <p className="mt-3 font-mono text-xs leading-6 text-muted-foreground">
          Link a server and its settings become editable here instead of in
          /etc/hyn-view/config.
        </p>
      </div>
    );
  }

  const current = (key: string) => {
    if (key in draft) return draft[key];
    const config = (node?.config ?? {}) as Record<string, unknown>;
    const v = config[key];
    return v === undefined || v === null ? "" : String(v);
  };

  async function save() {
    if (!node) return;
    setBusy(true);
    setError(null);
    setSaved(false);
    const merged = mergePortalConfig(node.config ?? {}, draft);
    const supabase = createClient();
    const { error } = await supabase.rpc("hyn_update_node_config", {
      p_node_id: node.id,
      p_config: merged,
    });
    setBusy(false);
    if (error) {
      setError(error.message);
      return;
    }
    setDraft({});
    setSaved(true);
    router.refresh();
  }

  return (
    <div className="terminal-panel rounded-xl p-6 duration-500 animate-in fade-in slide-in-from-bottom-2 md:p-7">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="section-kicker">// server settings</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">
            Thresholds and schedule
          </p>
          <p className="mt-2 max-w-xl font-mono text-xs leading-6 text-muted-foreground">
            Saved here and pulled by the server on its next check-in. A value left
            blank uses the built-in default. These managed thresholds and schedules
            take precedence on linked servers; local-only settings and credentials
            remain on the machine.
          </p>
        </div>
        {real.length > 1 ? (
          <select
            value={selected}
            onChange={(event) => {
              setSelected(event.target.value);
              setDraft({});
              setSaved(false);
            }}
            className="rounded-md border border-input bg-background px-3 py-2 font-mono text-sm text-foreground outline-none transition-colors focus:border-ring focus:ring-[3px] focus:ring-ring/50"
          >
            {real.map((n) => (
              <option key={n.id} value={n.id}>
                {n.name}
              </option>
            ))}
          </select>
        ) : null}
      </div>

      {GROUPS.map((group, groupIndex) => (
        <div key={group} className={groupIndex > 0 ? "mt-8 border-t border-border pt-6" : "mt-6"}>
          <p className="font-mono text-[0.7rem] uppercase tracking-wide text-primary">{group}</p>
          <div className="mt-3 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {FIELDS.filter((f) => f.group === group).map((f) => (
              <label key={f.key} className="block">
                <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">
                  {f.label}
                </span>
                {f.type === "select" ? (
                  <select
                    value={current(f.key)}
                    onChange={(event) => {
                      setDraft({ ...draft, [f.key]: event.target.value });
                      setSaved(false);
                    }}
                    className="w-full rounded-md border border-input bg-background px-3 py-2 font-mono text-sm text-foreground outline-none transition-colors focus:border-ring focus:ring-[3px] focus:ring-ring/50"
                  >
                    <option value="">Built-in default</option>
                    {f.choices?.map((choice) => (
                      <option key={choice.value} value={choice.value}>{choice.label}</option>
                    ))}
                  </select>
                ) : (
                  <input
                    type={f.type === "number" ? "number" : f.type === "time" ? "time" : "text"}
                    value={current(f.key)}
                    placeholder="default"
                    min={f.key === "cloud_push_min" ? 1 : f.type === "number" ? 0 : undefined}
                    max={f.key === "cloud_push_min" ? 1440 : undefined}
                    onChange={(event) => {
                      setDraft({ ...draft, [f.key]: event.target.value });
                      setSaved(false);
                    }}
                    className="w-full rounded-md border border-input bg-background px-3 py-2 font-mono text-sm text-foreground outline-none transition-colors focus:border-ring focus:ring-[3px] focus:ring-ring/50 placeholder:text-muted-foreground/50"
                  />
                )}
                <span className="mt-1 block font-mono text-[0.6rem] leading-4 text-muted-foreground">
                  {f.hint}
                </span>
              </label>
            ))}
          </div>
        </div>
      ))}

      {error ? (
        <p role="alert" className="mt-6 rounded-md border border-destructive/40 bg-destructive/5 px-3 py-2 font-mono text-xs text-destructive">
          {error}
        </p>
      ) : null}
      {saved ? (
        <p role="status" className="mt-6 rounded-md border border-primary/30 bg-primary/5 px-3 py-2 font-mono text-xs text-primary">
          Saved. {node?.name} will apply this on its next check-in
          {node?.last_config_pull_at
            ? ` (last pulled ${new Date(node.last_config_pull_at).toLocaleString()})`
            : " — it has not pulled config yet; use Sync now on the dashboard or run `sudo hyn cloud pull`"}
          .
        </p>
      ) : null}

      <Button
        type="button"
        size="sm"
        onClick={save}
        disabled={busy || Object.keys(draft).length === 0}
        className="mt-6 gap-2"
      >
        {busy ? <Loader2 className="size-4 animate-spin" /> : <Save className="size-4" aria-hidden />}
        Save settings
      </Button>
    </div>
  );
}
