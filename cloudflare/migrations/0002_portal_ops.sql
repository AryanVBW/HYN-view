-- Extra columns and tables used by account, admin, relayer and email RPCs.
-- Auth identities stay in Supabase.

ALTER TABLE email_preferences ADD COLUMN daily_at TEXT;
ALTER TABLE email_preferences ADD COLUMN system_at TEXT;
ALTER TABLE email_preferences ADD COLUMN last_daily_local_date TEXT;
ALTER TABLE email_preferences ADD COLUMN last_system_local_date TEXT;
ALTER TABLE email_preferences ADD COLUMN updated_at TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS relayer_assignments_relayer_id_idx
  ON relayer_assignments (relayer_id);
CREATE UNIQUE INDEX IF NOT EXISTS relayer_requests_owner_relayer_idx
  ON relayer_requests (owner, relayer_id);

CREATE TABLE IF NOT EXISTS cloud_email_dispatches (
  idempotency_key TEXT PRIMARY KEY,
  node_id TEXT,
  owner TEXT,
  kind TEXT,
  status TEXT,
  provider_id TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS node_watchdogs (
  node_id TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
  state TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS delivery_digest_settings (
  scope TEXT NOT NULL,
  owner TEXT,
  configured INTEGER NOT NULL DEFAULT 1,
  enabled INTEGER NOT NULL DEFAULT 1,
  send_at TEXT,
  timezone TEXT,
  PRIMARY KEY (scope, owner)
);
