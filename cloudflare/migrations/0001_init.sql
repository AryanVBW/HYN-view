-- HYN application data. Auth identities stay in Supabase; every row here is
-- keyed by that user UUID. SQLite types: TEXT timestamps are UTC ISO-8601.

PRAGMA foreign_keys = ON;

CREATE TABLE profiles (
  id TEXT PRIMARY KEY,
  email TEXT,
  full_name TEXT,
  role TEXT NOT NULL DEFAULT 'monitor'
    CHECK (role IN ('viewer', 'monitor', 'admin', 'super_admin')),
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'suspended')),
  suspended_reason TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX profiles_role_idx ON profiles (role);
CREATE INDEX profiles_email_idx ON profiles (email);

CREATE TABLE admin_allowlist (
  email TEXT PRIMARY KEY
);

CREATE TABLE nodes (
  id TEXT PRIMARY KEY,
  owner TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  hostname TEXT,
  os TEXT,
  agent_version TEXT,
  token_hash TEXT UNIQUE,
  is_demo INTEGER NOT NULL DEFAULT 0,
  revoked INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'paused', 'suspended')),
  paused_until TEXT,
  status_reason TEXT,
  config TEXT NOT NULL DEFAULT '{}',
  telemetry_mode TEXT NOT NULL DEFAULT 'cloud'
    CHECK (telemetry_mode IN ('local', 'cloud')),
  created_at TEXT NOT NULL,
  last_seen_at TEXT,
  last_heartbeat_at TEXT,
  last_config_pull_at TEXT,
  last_metric_at TEXT,
  last_telemetry_prune_at TEXT
);
CREATE INDEX nodes_owner_idx ON nodes (owner);

CREATE TABLE metrics (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  ts TEXT NOT NULL,
  cpu_pct REAL,
  cpu_temp_c REAL,
  cpu_mhz REAL,
  cpu_model TEXT,
  cpu_steal REAL,
  cpu_iowait REAL,
  cpu_cores INTEGER,
  load1 REAL,
  mem_pct REAL,
  mem_total INTEGER,
  mem_used INTEGER,
  swap_used INTEGER,
  disk_pct REAL,
  uptime_s INTEGER,
  net_iface TEXT,
  net_rx_bps INTEGER,
  net_tx_bps INTEGER,
  net_retrans_pm REAL,
  latency_ms REAL,
  net_link_mbps REAL,
  psi_cpu REAL,
  psi_mem REAL,
  psi_io REAL,
  tcp_estab INTEGER,
  conntrack_pct REAL,
  proc_count INTEGER,
  sensors TEXT,
  payload TEXT,
  UNIQUE (node_id, ts)
);
CREATE INDEX metrics_node_ts_idx ON metrics (node_id, ts DESC);

CREATE TABLE speedtests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  ts TEXT NOT NULL,
  down_bps INTEGER,
  up_bps INTEGER,
  latency_ms REAL,
  note TEXT,
  UNIQUE (node_id, ts)
);
CREATE INDEX speedtests_node_ts_idx ON speedtests (node_id, ts DESC);

CREATE TABLE alert_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  ts TEXT NOT NULL,
  rule TEXT,
  severity TEXT NOT NULL CHECK (severity IN ('info', 'warn', 'crit')),
  message TEXT NOT NULL,
  resolved INTEGER NOT NULL DEFAULT 0,
  event_fingerprint TEXT
);
CREATE UNIQUE INDEX alert_events_fingerprint_idx
  ON alert_events (node_id, event_fingerprint)
  WHERE event_fingerprint IS NOT NULL;
CREATE INDEX alert_events_node_ts_idx ON alert_events (node_id, ts DESC);

CREATE TABLE device_codes (
  id TEXT PRIMARY KEY,
  user_code_hash TEXT NOT NULL,
  device_code_hash TEXT NOT NULL UNIQUE,
  hostname TEXT,
  os TEXT,
  agent_version TEXT,
  approved_by TEXT REFERENCES profiles(id) ON DELETE CASCADE,
  node_id TEXT REFERENCES nodes(id) ON DELETE SET NULL,
  node_token_hash TEXT,
  token_claimed INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE INDEX device_codes_expiry_idx ON device_codes (expires_at);
CREATE INDEX device_codes_user_hash_idx ON device_codes (user_code_hash);

CREATE TABLE node_commands (
  id TEXT PRIMARY KEY,
  node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  requested_by TEXT REFERENCES profiles(id) ON DELETE SET NULL,
  command TEXT NOT NULL CHECK (command IN ('update', 'sync')),
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'expired')),
  stage TEXT NOT NULL DEFAULT 'queued',
  message TEXT NOT NULL DEFAULT 'Waiting for the machine to check in',
  target_version TEXT,
  result_version TEXT,
  requested_at TEXT NOT NULL,
  started_at TEXT,
  finished_at TEXT,
  updated_at TEXT NOT NULL,
  lease_expires_at TEXT
);
CREATE INDEX node_commands_node_requested_idx ON node_commands (node_id, requested_at DESC);

CREATE TABLE dashboard_access (
  viewer_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  owner_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  granted_by TEXT,
  created_at TEXT NOT NULL,
  PRIMARY KEY (viewer_id, owner_id),
  CHECK (viewer_id <> owner_id)
);

CREATE TABLE server_access (
  viewer_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  allowed INTEGER NOT NULL,
  notifications_allowed INTEGER NOT NULL DEFAULT 1,
  granted_by TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (viewer_id, node_id)
);
CREATE TABLE server_access_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL,
  actor TEXT,
  viewer_id TEXT,
  node_id TEXT,
  allowed INTEGER NOT NULL
);

CREATE TABLE bandwidth_counters (
  node_id TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
  iface TEXT NOT NULL,
  boot_id TEXT NOT NULL,
  rx TEXT NOT NULL,
  tx TEXT NOT NULL,
  sampled_at TEXT NOT NULL
);
CREATE TABLE bandwidth_daily (
  node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  day TEXT NOT NULL,
  ingress_bytes TEXT NOT NULL DEFAULT '0',
  egress_bytes TEXT NOT NULL DEFAULT '0',
  samples INTEGER NOT NULL DEFAULT 0,
  incomplete INTEGER NOT NULL DEFAULT 0,
  estimated INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (node_id, day)
);

CREATE TABLE notification_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  node_id TEXT REFERENCES nodes(id) ON DELETE CASCADE,
  owner TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  ts TEXT NOT NULL,
  kind TEXT NOT NULL,
  target TEXT,
  severity TEXT NOT NULL DEFAULT 'info',
  subject TEXT,
  status TEXT NOT NULL,
  error TEXT,
  category TEXT NOT NULL DEFAULT 'other'
);
CREATE INDEX notification_log_owner_ts_idx ON notification_log (owner, ts DESC);

CREATE TABLE notification_templates (
  template_key TEXT PRIMARY KEY,
  html_template TEXT NOT NULL DEFAULT ''
);
INSERT INTO notification_templates (template_key, html_template) VALUES
  ('alert', ''),
  ('report', ''),
  ('system', '');

CREATE TABLE email_preferences (
  node_id TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
  recipient TEXT,
  timezone TEXT,
  incident_enabled INTEGER NOT NULL DEFAULT 0,
  daily_enabled INTEGER NOT NULL DEFAULT 0,
  system_enabled INTEGER NOT NULL DEFAULT 1,
  send_at TEXT,
  last_alert_id INTEGER
);

CREATE TABLE web_notification_jobs (
  id TEXT PRIMARY KEY,
  node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  event TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  created_at TEXT NOT NULL
);

CREATE TABLE transient_snapshots (
  node_id TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
  payload TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE TABLE relayer_assignments (
  id TEXT PRIMARY KEY,
  owner TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  relayer_id INTEGER NOT NULL,
  relayer_name TEXT,
  created_at TEXT NOT NULL
);
CREATE TABLE relayer_requests (
  id TEXT PRIMARY KEY,
  owner TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  relayer_id INTEGER NOT NULL,
  relayer_name TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL
);
CREATE TABLE node_relayer_links (
  node_id TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
  assignment_id TEXT NOT NULL REFERENCES relayer_assignments(id) ON DELETE CASCADE
);

CREATE TABLE admin_audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL,
  actor TEXT,
  actor_email TEXT,
  action TEXT NOT NULL,
  target_user TEXT,
  target_node TEXT,
  detail TEXT
);
