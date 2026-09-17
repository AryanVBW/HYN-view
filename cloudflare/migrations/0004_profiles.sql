-- Existing production D1 already applied 0001_operational.sql (nodes, metrics,
-- pairing, email, relayers). This Worker also needs Auth-keyed profiles.

CREATE TABLE IF NOT EXISTS profiles (
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
CREATE INDEX IF NOT EXISTS profiles_role_idx ON profiles (role);
CREATE INDEX IF NOT EXISTS profiles_email_idx ON profiles (email);

CREATE TABLE IF NOT EXISTS admin_allowlist (
  email TEXT PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS transient_snapshots (
  node_id TEXT PRIMARY KEY,
  payload TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
