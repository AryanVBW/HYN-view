import { nowIso } from "./crypto.ts";
import { isD1WriteLimit, RpcError } from "./http.ts";
import type { NodeRow, Profile, Role, Session } from "./types.ts";

export function bool(value: number | null | undefined): boolean {
  return value === 1;
}

export function parseConfig(raw: string | null | undefined): Record<string, unknown> {
  if (!raw) return {};
  try {
    const value = JSON.parse(raw) as unknown;
    return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

export function publicNode(row: NodeRow) {
  return {
    id: row.id,
    owner: row.owner,
    name: row.name,
    hostname: row.hostname,
    os: row.os,
    agent_version: row.agent_version,
    is_demo: bool(row.is_demo),
    revoked: bool(row.revoked),
    created_at: row.created_at,
    last_seen_at: row.last_seen_at,
    status: row.status,
    paused_until: row.paused_until,
    status_reason: row.status_reason,
    config: parseConfig(row.config),
    last_config_pull_at: row.last_config_pull_at,
    last_heartbeat_at: row.last_heartbeat_at,
    telemetry_mode: row.telemetry_mode,
    last_metric_at: row.last_metric_at,
  };
}

export function isAdmin(role: Role): boolean {
  return role === "admin" || role === "super_admin";
}

export function isSuper(role: Role): boolean {
  return role === "super_admin";
}

export function canMonitor(role: Role): boolean {
  return role === "monitor" || role === "super_admin";
}

export function canLink(role: Role): boolean {
  return role === "monitor" || role === "admin" || role === "super_admin";
}

export async function loadProfile(db: D1Database, id: string): Promise<Profile | null> {
  return db.prepare("SELECT * FROM profiles WHERE id = ?").bind(id).first<Profile>();
}

export async function ensureProfile(
  db: D1Database,
  userId: string,
  email: string | null,
  bootstrapEmail: string | null,
): Promise<Profile> {
  const existing = await loadProfile(db, userId);
  const now = nowIso();
  if (existing) {
    const sameEmail = !email || !existing.email
      || existing.email.toLowerCase() === email.toLowerCase();
    if (sameEmail) return existing;
    try {
      await db.prepare("UPDATE profiles SET email = ?, updated_at = ? WHERE id = ?")
        .bind(email, now, userId).run();
      return { ...existing, email, updated_at: now };
    } catch (error) {
      if (isD1WriteLimit(error)) return existing;
      throw error;
    }
  }
  const allow = email
    ? await db.prepare("SELECT email FROM admin_allowlist WHERE lower(email) = lower(?)")
      .bind(email).first()
    : null;
  const count = await db.prepare("SELECT COUNT(*) AS n FROM profiles").first<{ n: number }>();
  const bootstrap = bootstrapEmail && email
    && email.toLowerCase() === bootstrapEmail.toLowerCase();
  const role: Role = allow || bootstrap || (count?.n ?? 0) === 0 ? "super_admin" : "monitor";
  try {
    await db.prepare(
      `INSERT INTO profiles (id, email, full_name, role, status, created_at, updated_at)
       VALUES (?, ?, NULL, ?, 'active', ?, ?)`,
    ).bind(userId, email, role, now, now).run();
  } catch (error) {
    if (isD1WriteLimit(error)) {
      throw new RpcError("this account cannot be created until the live database write limit resets at midnight UTC, or Workers Paid is enabled", 503);
    }
    throw error;
  }
  return {
    id: userId,
    email,
    full_name: null,
    role,
    status: "active",
    suspended_reason: null,
    created_at: now,
    updated_at: now,
  };
}

export function requireActive(session: Session): Profile {
  if (session.profile.status !== "active") {
    throw new RpcError("this account is suspended, so it cannot send commands to its machines", 403);
  }
  return session.profile;
}

export async function canViewDashboard(db: D1Database, session: Session, ownerId: string): Promise<boolean> {
  if (session.profile.status !== "active" && !session.service) return false;
  if (isAdmin(session.profile.role) || session.service) return true;
  if (session.userId === ownerId) {
    const owner = await loadProfile(db, ownerId);
    return owner?.status === "active";
  }
  const share = await db.prepare(
    "SELECT 1 AS ok FROM dashboard_access WHERE viewer_id = ? AND owner_id = ?",
  ).bind(session.userId, ownerId).first();
  if (!share) return false;
  const owner = await loadProfile(db, ownerId);
  return owner?.status === "active";
}

export async function canViewNode(db: D1Database, session: Session, nodeId: string): Promise<boolean> {
  if (session.profile.status !== "active" && !session.service) return false;
  const node = await db.prepare("SELECT * FROM nodes WHERE id = ? AND revoked = 0").bind(nodeId).first<NodeRow>();
  if (!node) return false;
  if (isAdmin(session.profile.role) || session.service) return true;
  const grant = await db.prepare(
    "SELECT allowed FROM server_access WHERE viewer_id = ? AND node_id = ?",
  ).bind(session.userId, nodeId).first<{ allowed: number }>();
  if (grant) return grant.allowed === 1;
  return canViewDashboard(db, session, node.owner);
}

export async function requireViewNode(db: D1Database, session: Session, nodeId: string): Promise<NodeRow> {
  const node = await db.prepare("SELECT * FROM nodes WHERE id = ?").bind(nodeId).first<NodeRow>();
  if (!node || node.revoked) throw new RpcError("server unavailable", 404);
  if (!await canViewNode(db, session, nodeId)) throw new RpcError("server access required", 403);
  return node;
}

export async function nodeByToken(db: D1Database, tokenHash: string): Promise<NodeRow | null> {
  return db.prepare("SELECT * FROM nodes WHERE token_hash = ?").bind(tokenHash).first<NodeRow>();
}

export async function activateIfPauseElapsed(db: D1Database, node: NodeRow): Promise<NodeRow> {
  if (node.status !== "paused" || !node.paused_until) return node;
  if (Date.parse(node.paused_until) > Date.now()) return node;
  await db.prepare(
    "UPDATE nodes SET status = 'active', paused_until = NULL, status_reason = NULL WHERE id = ?",
  ).bind(node.id).run();
  return { ...node, status: "active", paused_until: null, status_reason: null };
}

export async function requireLiveNode(db: D1Database, tokenHash: string): Promise<NodeRow> {
  const found = await nodeByToken(db, tokenHash);
  if (!found) throw new RpcError("invalid node token", 401);
  if (found.revoked) throw new RpcError("node revoked", 401);
  const node = await activateIfPauseElapsed(db, found);
  const owner = await loadProfile(db, node.owner);
  if (owner?.status !== "active") throw new RpcError("account suspended", 403);
  if (node.status === "paused") {
    throw new RpcError(`node paused${node.paused_until ? ` until ${node.paused_until}` : ""}`, 403);
  }
  if (node.status === "suspended") {
    throw new RpcError(`node suspended: ${node.status_reason ?? "contact your administrator"}`, 403);
  }
  return node;
}

export async function audit(
  db: D1Database,
  session: Session,
  action: string,
  targetUser: string | null,
  targetNode: string | null,
  detail: Record<string, unknown>,
): Promise<void> {
  await db.prepare(
    `INSERT INTO admin_audit (ts, actor, actor_email, action, target_user, target_node, detail)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).bind(nowIso(), session.userId, session.email, action, targetUser, targetNode, JSON.stringify(detail)).run();
}
