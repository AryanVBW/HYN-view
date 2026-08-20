// Row shapes from supabase/schema.sql. Hand-written rather than generated so
// the repo has no dependency on the Supabase CLI being run first; if you do
// generate types later, these are the names to match.

export type Node = {
  id: string;
  owner: string;
  name: string;
  hostname: string | null;
  os: string | null;
  agent_version: string | null;
  is_demo: boolean;
  revoked: boolean;
  created_at: string;
  last_seen_at: string | null;
  status: "active" | "paused" | "suspended";
  paused_until: string | null;
  status_reason: string | null;
  config: Record<string, unknown>;
  last_config_pull_at: string | null;
};

// Every column of `nodes` a browser session is allowed to read. `token_hash` is
// deliberately not granted to `authenticated` (see supabase/schema.sql), so
// `select("*")` fails with a permission error — select this instead. Keep it in
// step with the type above. One literal with `as const`, not a concatenation:
// supabase-js parses the select string at the type level and infers an error
// type for a plain `string`.
export const NODE_COLUMNS =
  "id, owner, name, hostname, os, agent_version, is_demo, revoked, created_at, last_seen_at, status, paused_until, status_reason, config, last_config_pull_at" as const;

export type Metric = {
  id: number;
  node_id: string;
  ts: string;
  cpu_pct: number | null;
  cpu_temp_c: number | null;
  cpu_mhz: number | null;
  cpu_model: string | null;
  cpu_steal: number | null;
  cpu_iowait: number | null;
  cpu_cores: number | null;
  load1: number | null;
  mem_pct: number | null;
  mem_total: number | null;
  mem_used: number | null;
  swap_used: number | null;
  disk_pct: number | null;
  uptime_s: number | null;
  net_iface: string | null;
  net_rx_bps: number | null;
  net_tx_bps: number | null;
  net_retrans_pm: number | null;
  latency_ms: number | null;
  // Added to public.metrics after the first cut of this type (see the
  // `alter table ... add column if not exists` block in supabase/schema.sql).
  net_link_mbps: number | null;
  psi_cpu: number | null;
  psi_mem: number | null;
  psi_io: number | null;
  tcp_estab: number | null;
  conntrack_pct: number | null;
  proc_count: number | null;
  // Every temperature the platform exposes, keyed by sensor label.
  sensors: Record<string, number | null> | null;
  payload: Record<string, unknown> | null;
};

export type Speedtest = {
  id: number;
  node_id: string;
  ts: string;
  down_bps: number | null;
  up_bps: number | null;
  latency_ms: number | null;
  note: string | null;
};

export type AlertEvent = {
  id: number;
  node_id: string;
  ts: string;
  rule: string | null;
  severity: "info" | "warn" | "crit";
  message: string;
  resolved: boolean;
};

export type NodeStatus = "active" | "paused" | "suspended";

export type Profile = {
  id: string;
  email: string | null;
  full_name: string | null;
  role: "user" | "admin";
  status: "active" | "suspended";
  suspended_reason: string | null;
  created_at: string;
  updated_at: string;
};

export type ChannelKind = "resend" | "brevo" | "smtp" | "ntfy" | "telegram" | "webhook";

// Note the absence of `secret`: the column grant in supabase/schema.sql makes it
// unreadable from a browser session, so it is deliberately not in this type.
export type NotificationChannel = {
  id: string;
  owner: string;
  node_id: string | null;
  kind: ChannelKind;
  target: string;
  extra: Record<string, unknown>;
  enabled: boolean;
  created_at: string;
};

// And therefore `select("*")` on notification_channels is denied outright —
// Postgres refuses the whole statement when `*` expands onto a column the role
// cannot read, so this is not "the secret comes back empty", it is "the query
// fails". Select these columns instead.
export const CHANNEL_COLUMNS =
  "id, owner, node_id, kind, target, extra, enabled, created_at" as const;

// What a user picks: an address, an optional phone number, and which admin
// should manage their delivery. The actual channel plumbing lives on that
// admin's own NotificationChannel rows, configured from the admin panel.
export type NotifyPrefs = {
  user_id: string;
  notify_email: string | null;
  notify_phone: string | null;
  admin_id: string | null;
  updated_at: string;
};

export type AdminOption = {
  id: string;
  email: string | null;
  full_name: string | null;
};

export type NotificationLogRow = {
  id: number;
  node_id: string;
  owner: string;
  ts: string;
  kind: string;
  target: string | null;
  severity: "info" | "warn" | "crit";
  subject: string | null;
  status: "sent" | "failed" | "skipped";
  error: string | null;
  category: "alert" | "report" | "test" | "other";
};

// Shapes returned by the admin RPCs. They are json_build_object results rather
// than table rows, which is why they are separate from the table types above.
export type AdminOverview = {
  clients_total: number;
  clients_suspended: number;
  admins: number;
  nodes_total: number;
  nodes_active: number;
  nodes_paused: number;
  nodes_suspended: number;
  nodes_revoked: number;
  nodes_stale: number;
  alerts_open: number;
  notifications_24h: number;
  notifications_failed_24h: number;
  metrics_24h: number;
};

export type AdminNode = {
  id: string;
  name: string;
  hostname: string | null;
  os: string | null;
  agent_version: string | null;
  status: NodeStatus;
  paused_until: string | null;
  status_reason: string | null;
  revoked: boolean;
  is_demo: boolean;
  created_at: string;
  last_seen_at: string | null;
  last_config_pull_at: string | null;
  owner_id: string | null;
  owner_email: string | null;
  owner_status: string | null;
  owner_role: string | null;
  notifications_24h: number;
  notifications_failed_24h: number;
  alerts_open: number;
  last_cpu_pct: number | null;
  last_temp_c: number | null;
  last_mem_pct: number | null;
  last_disk_pct: number | null;
};

export type AdminClient = {
  id: string;
  email: string | null;
  full_name: string | null;
  role: "user" | "admin";
  status: "active" | "suspended";
  suspended_reason: string | null;
  created_at: string;
  nodes: number;
  nodes_active: number;
  notifications_30d: number;
  notifications_failed_30d: number;
  last_seen_at: string | null;
};

export type AdminNotification = {
  id: number;
  ts: string;
  kind: string;
  target: string | null;
  severity: "info" | "warn" | "crit";
  subject: string | null;
  status: "sent" | "failed" | "skipped";
  error: string | null;
  category: string;
  node_name: string | null;
  owner_email: string | null;
};

export type AuditEntry = {
  id: number;
  ts: string;
  actor_email: string | null;
  action: string;
  detail: Record<string, unknown>;
  target_user: string | null;
  target_node: string | null;
  target_node_name: string | null;
  target_user_email: string | null;
};
