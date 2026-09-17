export type Role = "viewer" | "monitor" | "admin" | "super_admin";

export type Profile = {
  id: string;
  email: string | null;
  full_name: string | null;
  role: Role;
  status: "active" | "suspended";
  suspended_reason: string | null;
  created_at: string;
  updated_at: string;
};

export type NodeRow = {
  id: string;
  owner: string;
  name: string;
  hostname: string | null;
  os: string | null;
  agent_version: string | null;
  token_hash: string | null;
  is_demo: number;
  revoked: number;
  status: "active" | "paused" | "suspended";
  paused_until: string | null;
  status_reason: string | null;
  config: string;
  telemetry_mode: "local" | "cloud";
  created_at: string;
  last_seen_at: string | null;
  last_heartbeat_at: string | null;
  last_config_pull_at: string | null;
  last_metric_at: string | null;
  last_telemetry_prune_at: string | null;
};

export type Session = {
  userId: string;
  email: string | null;
  profile: Profile;
  service: boolean;
};

export const NODE_COLUMNS =
  "id, owner, name, hostname, os, agent_version, is_demo, revoked, created_at, last_seen_at, status, paused_until, status_reason, config, last_config_pull_at, last_heartbeat_at, telemetry_mode, last_metric_at";
