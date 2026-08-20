"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";
import type { Node } from "@/lib/types";

// The settings worth exposing in a browser. Deliberately not every config key
// the agent understands: the long tail (theme, graph style, panel order) only
// matters to someone sitting at the terminal, and putting fifty inputs here
// would bury the handful that change behaviour people care about.
const FIELDS: {
  key: string;
  label: string;
  hint: string;
  type: "number" | "text" | "time";
}[] = [
  { key: "alert_mem_pct", label: "Memory alert %", hint: "0 disables this rule", type: "number" },
  { key: "alert_disk_pct", label: "Disk alert %", hint: "per mount point", type: "number" },
  { key: "alert_temp_c", label: "Temperature alert °C", hint: "0 disables", type: "number" },
  { key: "alert_load_per_core", label: "Load alert, % per core", hint: "400 means load 4.0 per core", type: "number" },
  { key: "alert_latency_ms", label: "Latency alert, ms", hint: "first-hop and internet", type: "number" },
  { key: "alert_min_severity", label: "Minimum severity", hint: "crit, warn or info", type: "text" },
  { key: "alert_repeat_hours", label: "Repeat interval, hours", hint: "how often a still-firing alert repeats", type: "number" },
  { key: "report_at", label: "Daily report time", hint: "server local time, HH:MM", type: "time" },
  { key: "notify_max_per_day", label: "Daily notification cap", hint: "backstop against a flapping rule", type: "number" },
  { key: "cloud_push_min", label: "Push interval, minutes", hint: "how often this server reports in", type: "number" },
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
      <div className="terminal-panel p-6">
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
    const merged: Record<string, string> = {
      ...((node.config ?? {}) as Record<string, string>),
    };
    // An emptied field means "stop overriding this", not "set it to empty" --
    // otherwise clearing a box would push a blank value to the agent and the
    // built-in default would become unreachable.
    for (const [k, v] of Object.entries(draft)) {
      if (v.trim() === "") delete merged[k];
      else merged[k] = v.trim();
    }
    const supabase = createClient();
    const { error } = await supabase.from("nodes").update({ config: merged }).eq("id", node.id);
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
    <div className="terminal-panel p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="section-kicker">// server settings</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">
            Thresholds and schedule
          </p>
          <p className="mt-2 max-w-xl font-mono text-xs leading-6 text-muted-foreground">
            Saved here and pulled by the server on its next check-in. A value left
            blank uses the built-in default. A setting written directly on the box
            still wins, so a local override is never silently reverted.
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
            className="border border-input bg-background px-3 py-2 font-mono text-sm text-foreground outline-none focus:border-ring"
          >
            {real.map((n) => (
              <option key={n.id} value={n.id}>
                {n.name}
              </option>
            ))}
          </select>
        ) : null}
      </div>

      <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {FIELDS.map((f) => (
          <label key={f.key} className="block">
            <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">
              {f.label}
            </span>
            <input
              type={f.type === "number" ? "number" : "text"}
              value={current(f.key)}
              placeholder="default"
              onChange={(event) => {
                setDraft({ ...draft, [f.key]: event.target.value });
                setSaved(false);
              }}
              className="w-full border border-input bg-background px-3 py-2 font-mono text-sm text-foreground outline-none focus:border-ring placeholder:text-muted-foreground/50"
            />
            <span className="mt-1 block font-mono text-[0.6rem] leading-4 text-muted-foreground">
              {f.hint}
            </span>
          </label>
        ))}
      </div>

      {error ? (
        <p role="alert" className="mt-4 font-mono text-xs text-destructive">
          {error}
        </p>
      ) : null}
      {saved ? (
        <p role="status" className="mt-4 font-mono text-xs text-primary">
          Saved. {node?.name} will apply this on its next check-in
          {node?.last_config_pull_at
            ? ` (last pulled ${new Date(node.last_config_pull_at).toLocaleString()})`
            : " — it has not pulled config yet; run `hyn config pull` to apply now"}
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
        {busy ? <Loader2 className="size-4 animate-spin" /> : null}
        Save settings
      </Button>
    </div>
  );
}
