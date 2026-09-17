import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { insertSql } from "../src/sql-literal.ts";

type Cfg = {
  NEXT_PUBLIC_SUPABASE_URL?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
};

const database = process.argv.includes("--staging") ? "hynview" : "hyn-view-production";
const envFlag = database === "hynview" ? ["--env", "staging"] : [];

const raw = await new Response(process.stdin).text();
const cfg = JSON.parse(raw) as Cfg;
const base = (cfg.NEXT_PUBLIC_SUPABASE_URL ?? "").replace(/\/$/, "");
const key = cfg.SUPABASE_SERVICE_ROLE_KEY ?? "";
if (!base || !key) throw new Error("missing supabase configuration on stdin");

const PAGE = 1000;

async function fetchTable(table: string, query = "select=*"): Promise<Record<string, unknown>[]> {
  const rows: Record<string, unknown>[] = [];
  for (let from = 0; ; from += PAGE) {
    const to = from + PAGE - 1;
    const res = await fetch(`${base}/rest/v1/${table}?${query}`, {
      headers: {
        apikey: key,
        authorization: `Bearer ${key}`,
        range: `${from}-${to}`,
        prefer: "count=exact",
      },
    });
    if (!res.ok) throw new Error(`${table} HTTP ${res.status}`);
    const page = await res.json() as Record<string, unknown>[];
    rows.push(...page);
    if (page.length < PAGE) return rows;
  }
}

function exec(sql: string): void {
  const dir = mkdtempSync(join(tmpdir(), "hyn-d1-"));
  const file = join(dir, "batch.sql");
  writeFileSync(file, sql.endsWith(";") ? sql : `${sql};`);
  try {
    const result = spawnSync(
      "npx",
      ["wrangler", "d1", "execute", database, "--remote", ...envFlag, "--file", file],
      { encoding: "utf8" },
    );
    if (result.status !== 0) {
      const err = `${result.stdout}\n${result.stderr}`.slice(0, 800);
      throw new Error(`d1 execute failed: ${err}`);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function importRows(table: string, columns: string[], rows: Record<string, unknown>[], maxChars = 350_000): void {
  let buffer: string[] = [];
  let size = 0;
  const flush = () => {
    if (!buffer.length) return;
    exec(buffer.join(";\n"));
    buffer = [];
    size = 0;
  };
  for (const row of rows) {
    const stmt = insertSql(table, columns, row);
    if (size + stmt.length > maxChars) flush();
    buffer.push(stmt);
    size += stmt.length + 2;
  }
  flush();
  console.log(`${table} ${rows.length}`);
}

function jsonCol(value: unknown): unknown {
  if (value === null || value === undefined) return null;
  if (typeof value === "object") return value;
  if (typeof value === "string") {
    try { return JSON.parse(value); } catch { return null; }
  }
  return null;
}

async function importTable(label: string, run: () => Promise<void>): Promise<void> {
  try {
    await run();
  } catch (error) {
    console.error(`${label} failed: ${error instanceof Error ? error.message.slice(0, 240) : "error"}`);
  }
}

const profiles = await fetchTable("profiles");
importRows("profiles", ["id", "email", "full_name", "role", "status", "suspended_reason", "created_at", "updated_at"], profiles);

const allow = await fetchTable("admin_allowlist");
importRows("admin_allowlist", ["email"], allow);

const nodes = await fetchTable("nodes");
importRows("nodes", [
  "id", "owner", "name", "hostname", "os", "agent_version", "token_hash",
  "is_demo", "revoked", "created_at", "last_seen_at", "status", "paused_until",
  "status_reason", "config", "last_config_pull_at", "last_heartbeat_at",
  "telemetry_mode", "last_metric_at", "last_telemetry_prune_at",
], nodes);

const grants = await fetchTable("server_access");
importRows("server_access", ["viewer_id", "node_id", "allowed", "notifications_allowed", "granted_by", "updated_at"], grants);

await importTable("relayer_assignments", async () => {
  const assignments = (await fetchTable("relayer_assignments")).map((row) => ({
    ...row,
    relayer_name: String(row.relayer_name ?? `Relay ${row.relayer_id}`).slice(0, 160) || `Relay ${row.relayer_id}`,
    assignment_role: row.assignment_role === "view" ? "view" : "primary",
  }));
  importRows("relayer_assignments", ["id", "owner", "relayer_id", "relayer_name", "created_at", "assignment_role"], assignments);
});

await importTable("node_relayer_links", async () => {
  const links = (await fetchTable("node_relayer_links")).filter((row) => row.node_id && row.owner && row.assignment_id && row.assignment_role !== "view")
    .map((row) => ({
      ...row,
      assignment_role: "primary",
    }));
  importRows("node_relayer_links", ["node_id", "owner", "assignment_id", "assignment_role"], links);
});

await importTable("relayer_requests", async () => {
  const requests = (await fetchTable("relayer_requests")).map((row) => ({
    ...row,
    relayer_name: String(row.relayer_name ?? `Relay ${row.relayer_id}`).slice(0, 160) || `Relay ${row.relayer_id}`,
  }));
  importRows("relayer_requests", ["id", "owner", "relayer_id", "relayer_name", "status", "created_at", "reviewed_at", "reviewed_by"], requests);
});

await importTable("email_preferences", async () => {
  const prefs = (await fetchTable("email_preferences")).filter((row) => {
    const recipient = String(row.recipient ?? "");
    return recipient.includes("@") && !recipient.includes(" ") && recipient.length <= 320;
  }).map((row) => ({
    ...row,
    timezone: row.timezone || "UTC",
    daily_at: row.daily_at || "08:00:00",
    system_at: row.system_at || "09:00:00",
    last_alert_id: row.last_alert_id ?? 0,
  }));
  importRows("email_preferences", [
    "node_id", "recipient", "timezone", "incident_enabled", "daily_enabled",
    "system_enabled", "daily_at", "system_at", "last_daily_local_date",
    "last_system_local_date", "last_alert_id", "updated_at",
  ], prefs);
});

await importTable("notification_templates", async () => {
  const templates = (await fetchTable("notification_templates")).map((row) => {
    let html = String(row.html_template ?? "");
    if (!html.includes("{{content}}")) html = `${html}{{content}}`;
    return {
      template_key: row.template_key,
      name: row.name || row.template_key,
      description: row.description || row.template_key,
      html_template: html.slice(0, 100000),
      updated_at: row.updated_at,
      updated_by: row.updated_by,
    };
  });
  importRows("notification_templates", ["template_key", "name", "description", "html_template", "updated_at", "updated_by"], templates);
});

await importTable("metrics", async () => {
  const metrics = (await fetchTable("metrics")).map((row) => ({
    ...row,
    payload: jsonCol(row.payload),
    sensors: jsonCol(row.sensors),
  }));
  importRows("metrics", [
    "id", "node_id", "ts", "cpu_pct", "cpu_temp_c", "cpu_mhz", "cpu_model",
    "cpu_steal", "cpu_iowait", "cpu_cores", "load1", "mem_pct", "mem_total",
    "mem_used", "swap_used", "disk_pct", "uptime_s", "net_iface", "net_rx_bps",
    "net_tx_bps", "net_retrans_pm", "latency_ms", "net_link_mbps", "psi_cpu",
    "psi_mem", "psi_io", "tcp_estab", "conntrack_pct", "proc_count", "sensors",
    "payload",
  ], metrics);
});

await importTable("speedtests", async () => {
  importRows("speedtests", ["id", "node_id", "ts", "down_bps", "up_bps", "latency_ms", "note"], await fetchTable("speedtests"));
});

await importTable("alert_events", async () => {
  importRows("alert_events", ["id", "node_id", "ts", "rule", "severity", "message", "resolved", "event_fingerprint"], await fetchTable("alert_events"));
});

console.log("import complete");
