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
