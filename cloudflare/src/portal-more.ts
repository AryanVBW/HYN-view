import {
  audit,
  canMonitor,
  canViewNode,
  isAdmin,
  isSuper,
  publicNode,
  requireActive,
  requireViewNode,
} from "./access.ts";
import { hoursAgoIso, nowIso, uuid } from "./crypto.ts";
import { asBool, count } from "./db.ts";
import { RpcError } from "./http.ts";
import type { NodeRow, Session } from "./types.ts";
import { NODE_COLUMNS } from "./types.ts";

const COMMAND_COLUMNS =
  "id, node_id, command, status, stage, message, target_version, result_version, requested_at, started_at, finished_at, updated_at";

function asId(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim().slice(0, 64) : null;
}

function asIds(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => asId(item)).filter((id): id is string => Boolean(id)))];
}

function requireAdmin(session: Session) {
  const profile = requireActive(session);
  if (!isAdmin(profile.role) && !session.service) throw new RpcError("administrator role required", 403);
  return profile;
}

function requireSuper(session: Session) {
  const profile = requireActive(session);
  if (!isSuper(profile.role) && !session.service) throw new RpcError("super administrator role required", 403);
  return profile;
}

async function visibleNodeIds(db: D1Database, session: Session): Promise<string[]> {
  const rows = await db.prepare("SELECT id FROM nodes WHERE revoked = 0 AND is_demo = 0").all<{ id: string }>();
  const ids: string[] = [];
  for (const row of rows.results) {
    if (await canViewNode(db, session, row.id)) ids.push(row.id);
  }
  return ids;
}

function dayRow(row: Record<string, unknown>) {
  return {
    day: String(row.day),
    ingress_bytes: String(row.ingress_bytes ?? "0"),
    egress_bytes: String(row.egress_bytes ?? "0"),
    samples: Number(row.samples ?? 0),
    incomplete: asBool(row.incomplete),
    estimated: asBool(row.estimated),
  };
}

export async function bandwidthReport(
  db: D1Database,
  nodeIds: string[],
  days: number,
  extras: Record<string, unknown> = {},
) {
  if (!nodeIds.length) {
    return {
      iface: null,
      sampled_at: null,
      since: null,
      ingress_bytes: "0",
      egress_bytes: "0",
      days: [],
      ...extras,
    };
  }
  const placeholders = nodeIds.map(() => "?").join(",");
  const start = new Date(Date.now() - (days - 1) * 86400_000).toISOString().slice(0, 10);
  const totals = await db.prepare(
    `SELECT MIN(day) AS since,
            CAST(SUM(CAST(ingress_bytes AS INTEGER)) AS TEXT) AS ingress_bytes,
            CAST(SUM(CAST(egress_bytes AS INTEGER)) AS TEXT) AS egress_bytes
     FROM bandwidth_daily WHERE node_id IN (${placeholders})`,
  ).bind(...nodeIds).first<{ since: string | null; ingress_bytes: string | null; egress_bytes: string | null }>();
  const window = await db.prepare(
    `SELECT day,
            CAST(SUM(CAST(ingress_bytes AS INTEGER)) AS TEXT) AS ingress_bytes,
            CAST(SUM(CAST(egress_bytes AS INTEGER)) AS TEXT) AS egress_bytes,
            SUM(samples) AS samples,
            MAX(incomplete) AS incomplete,
            MAX(estimated) AS estimated
     FROM bandwidth_daily WHERE node_id IN (${placeholders}) AND day >= ?
     GROUP BY day ORDER BY day DESC`,
  ).bind(...nodeIds, start).all<Record<string, unknown>>();
  const counter = nodeIds.length === 1
    ? await db.prepare("SELECT iface, sampled_at FROM bandwidth_counters WHERE node_id = ?")
      .bind(nodeIds[0]).first<{ iface: string; sampled_at: string }>()
    : null;
  return {
    iface: counter?.iface ?? null,
    sampled_at: counter?.sampled_at ?? null,
    since: totals?.since ?? null,
    ingress_bytes: totals?.ingress_bytes ?? "0",
    egress_bytes: totals?.egress_bytes ?? "0",
    days: window.results.map(dayRow),
    ...extras,
  };
}

async function adminOverview(db: D1Database) {
  const staleCutoff = new Date(Date.now() - 3 * 60_000).toISOString();
  const dayAgo = hoursAgoIso(24);
  const weekAgo = hoursAgoIso(24 * 7);
  return {
    clients_total: await count(db, "SELECT COUNT(*) AS n FROM profiles"),
    clients_suspended: await count(db, "SELECT COUNT(*) AS n FROM profiles WHERE status = 'suspended'"),
    admins: await count(db, "SELECT COUNT(*) AS n FROM profiles WHERE role IN ('admin', 'super_admin')"),
    nodes_total: await count(db, "SELECT COUNT(*) AS n FROM nodes WHERE is_demo = 0"),
    nodes_active: await count(db, "SELECT COUNT(*) AS n FROM nodes WHERE status = 'active' AND revoked = 0 AND is_demo = 0"),
    nodes_paused: await count(db, "SELECT COUNT(*) AS n FROM nodes WHERE status = 'paused' AND is_demo = 0"),
    nodes_suspended: await count(db, "SELECT COUNT(*) AS n FROM nodes WHERE status = 'suspended' AND is_demo = 0"),
    nodes_revoked: await count(db, "SELECT COUNT(*) AS n FROM nodes WHERE revoked = 1"),
    nodes_stale: await count(
      db,
      `SELECT COUNT(*) AS n FROM nodes
       WHERE is_demo = 0 AND revoked = 0 AND status = 'active'
         AND (last_heartbeat_at IS NULL OR last_heartbeat_at < ?)`,
      staleCutoff,
    ),
    alerts_open: await count(db, "SELECT COUNT(*) AS n FROM alert_events WHERE resolved = 0 AND ts > ?", weekAgo),
    notifications_24h: await count(db, "SELECT COUNT(*) AS n FROM notification_log WHERE ts > ?", dayAgo),
    notifications_failed_24h: await count(
      db,
      "SELECT COUNT(*) AS n FROM notification_log WHERE ts > ? AND status = 'failed'",
      dayAgo,
    ),
    metrics_24h: await count(db, "SELECT COUNT(*) AS n FROM metrics WHERE ts > ?", dayAgo),
  };
}

async function adminNodes(db: D1Database) {
  const dayAgo = hoursAgoIso(24);
  const weekAgo = hoursAgoIso(24 * 7);
  const rows = await db.prepare(
    `SELECT n.*, p.id AS owner_id, p.email AS owner_email, p.status AS owner_status, p.role AS owner_role
     FROM nodes n LEFT JOIN profiles p ON p.id = n.owner
     ORDER BY n.last_heartbeat_at DESC`,
  ).all<NodeRow & { owner_id: string | null; owner_email: string | null; owner_status: string | null; owner_role: string | null }>();
  const out = [];
  for (const row of rows.results) {
    const metric = await db.prepare(
      "SELECT cpu_pct, cpu_temp_c, mem_pct, disk_pct, payload FROM metrics WHERE node_id = ? ORDER BY ts DESC LIMIT 1",
    ).bind(row.id).first<{
      cpu_pct: number | null; cpu_temp_c: number | null; mem_pct: number | null; disk_pct: number | null; payload: string | null;
    }>();
    let payload: Record<string, unknown> | null = null;
    try { payload = metric?.payload ? JSON.parse(metric.payload) as Record<string, unknown> : null; } catch { payload = null; }
    const update = payload && typeof payload.agent_update === "object" && payload.agent_update
      ? payload.agent_update as Record<string, unknown>
      : null;
    out.push({
      ...publicNode(row),
      owner_id: row.owner_id,
      owner_email: row.owner_email,
      owner_status: row.owner_status,
      owner_role: row.owner_role,
      ever_connected: Boolean(row.token_hash || row.last_heartbeat_at || row.last_seen_at),
      notifications_24h: await count(db, "SELECT COUNT(*) AS n FROM notification_log WHERE node_id = ? AND ts > ?", row.id, dayAgo),
      notifications_failed_24h: await count(
        db,
        "SELECT COUNT(*) AS n FROM notification_log WHERE node_id = ? AND ts > ? AND status = 'failed'",
        row.id,
        dayAgo,
      ),
      alerts_open: await count(
        db,
        "SELECT COUNT(*) AS n FROM alert_events WHERE node_id = ? AND resolved = 0 AND ts > ?",
        row.id,
        weekAgo,
      ),
      last_cpu_pct: metric?.cpu_pct ?? null,
      last_temp_c: metric?.cpu_temp_c ?? null,
      last_mem_pct: metric?.mem_pct ?? null,
      last_disk_pct: metric?.disk_pct ?? null,
      latest_agent_version: typeof update?.latest === "string" ? update.latest : null,
      update_available: update?.available === true || update?.available === "true" || update?.available === "1",
    });
  }
  return out;
}

async function adminClients(db: D1Database) {
  const monthAgo = hoursAgoIso(24 * 30);
  const profiles = await db.prepare("SELECT * FROM profiles ORDER BY created_at DESC").all<{
    id: string; email: string | null; full_name: string | null; role: string; status: string;
    suspended_reason: string | null; created_at: string;
  }>();
  const out = [];
  for (const p of profiles.results) {
    out.push({
      ...p,
      nodes: await count(db, "SELECT COUNT(*) AS n FROM nodes WHERE owner = ? AND is_demo = 0", p.id),
      nodes_active: await count(
        db,
        "SELECT COUNT(*) AS n FROM nodes WHERE owner = ? AND is_demo = 0 AND revoked = 0 AND status = 'active'",
        p.id,
      ),
      nodes_unlinked: await count(
        db,
        `SELECT COUNT(*) AS n FROM nodes WHERE owner = ? AND is_demo = 0
           AND token_hash IS NULL AND last_heartbeat_at IS NULL AND last_seen_at IS NULL`,
        p.id,
      ),
      notifications_30d: await count(db, "SELECT COUNT(*) AS n FROM notification_log WHERE owner = ? AND ts > ?", p.id, monthAgo),
      notifications_failed_30d: await count(
        db,
        "SELECT COUNT(*) AS n FROM notification_log WHERE owner = ? AND ts > ? AND status = 'failed'",
        p.id,
        monthAgo,
      ),
      last_seen_at: (await db.prepare("SELECT MAX(last_seen_at) AS ts FROM nodes WHERE owner = ?").bind(p.id)
        .first<{ ts: string | null }>())?.ts ?? null,
    });
  }
  return out;
}

async function fleetMetricHistory(db: D1Database) {
  const cutoff = hoursAgoIso(24);
  const rows = await db.prepare(
    `SELECT ts, cpu_pct, net_rx_bps, net_tx_bps FROM metrics m
     JOIN nodes n ON n.id = m.node_id
     WHERE n.is_demo = 0 AND m.ts >= ? ORDER BY m.ts DESC LIMIT 8000`,
  ).bind(cutoff).all<{ ts: string; cpu_pct: number | null; net_rx_bps: number | null; net_tx_bps: number | null }>();
  const buckets = new Map<number, { ts: string; cpu: number[]; rx: number[]; tx: number[] }>();
  for (const row of rows.results) {
    const bucket = Math.floor(Date.parse(row.ts) / 1_800_000);
    const key = bucket * 1_800_000;
    let acc = buckets.get(key);
    if (!acc) {
      acc = { ts: new Date(key).toISOString(), cpu: [], rx: [], tx: [] };
      buckets.set(key, acc);
    }
    if (row.cpu_pct != null) acc.cpu.push(row.cpu_pct);
    if (row.net_rx_bps != null) acc.rx.push(row.net_rx_bps);
    if (row.net_tx_bps != null) acc.tx.push(row.net_tx_bps);
  }
  return [...buckets.values()]
    .sort((a, b) => a.ts.localeCompare(b.ts))
    .slice(-49)
    .map((b) => ({
      ts: b.ts,
      cpu_pct: b.cpu.length ? b.cpu.reduce((s, n) => s + n, 0) / b.cpu.length : null,
      net_rx_bps: b.rx.length ? b.rx.reduce((s, n) => s + n, 0) / b.rx.length : null,
      net_tx_bps: b.tx.length ? b.tx.reduce((s, n) => s + n, 0) / b.tx.length : null,
    }));
}

async function claimDispatch(db: D1Database, key: string, nodeId: string | null, kind: string, owner: string | null = null) {
  const now = nowIso();
  const result = await db.prepare(
    `INSERT OR IGNORE INTO cloud_email_dispatches (idempotency_key, node_id, owner, kind, created_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).bind(key, nodeId, owner, kind, now).run();
  return (result.meta.changes ?? 0) > 0;
}

function parseJson(value: unknown): unknown {
  if (typeof value !== "string" || !value) return value ?? null;
  try { return JSON.parse(value); } catch { return null; }
}

async function insertNotificationLog(
  db: D1Database,
  body: Record<string, unknown>,
) {
  const owner = asId(body.p_owner);
  if (!owner) throw new RpcError("owner required");
  await db.prepare(
    `INSERT INTO notification_log (node_id, owner, ts, kind, target, severity, subject, status, error, category)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    asId(body.p_node_id),
    owner,
    nowIso(),
    typeof body.p_kind === "string" ? body.p_kind.slice(0, 40) : "resend-cloud",
    typeof body.p_target === "string" ? body.p_target.slice(0, 320) : null,
    typeof body.p_severity === "string" ? body.p_severity.slice(0, 16) : "info",
    typeof body.p_subject === "string" ? body.p_subject.slice(0, 240) : null,
    body.p_status === "sent" ? "sent" : "failed",
    typeof body.p_error === "string" ? body.p_error.slice(0, 500) : null,
    typeof body.p_category === "string" ? body.p_category.slice(0, 40) : "other",
  ).run();
}

export async function handlePortalMore(
  db: D1Database,
  session: Session,
  name: string,
  body: Record<string, unknown>,
): Promise<unknown> {
  switch (name) {
    case "hyn_admin_overview":
      requireAdmin(session);
      return adminOverview(db);
    case "hyn_admin_nodes":
      requireAdmin(session);
      return adminNodes(db);
    case "hyn_admin_clients":
      requireAdmin(session);
      return adminClients(db);
    case "hyn_admin_notifications": {
      requireAdmin(session);
      const limit = Math.min(1000, Math.max(1, Number(body.p_limit) || 100));
      const rows = await db.prepare(
        `SELECT l.id, l.ts, l.kind, l.target, l.severity, l.subject, l.status, l.error, l.category,
                n.name AS node_name, p.email AS owner_email
         FROM notification_log l
         LEFT JOIN nodes n ON n.id = l.node_id
         LEFT JOIN profiles p ON p.id = l.owner
         ORDER BY l.ts DESC LIMIT ?`,
      ).bind(limit).all();
      return rows.results;
    }
    case "hyn_admin_audit": {
      requireSuper(session);
      const limit = Math.min(200, Math.max(1, Number(body.p_limit) || 100));
      const rows = await db.prepare(
        `SELECT a.id, a.ts, a.actor_email, a.action, a.detail, a.target_user, a.target_node,
                n.name AS target_node_name, p.email AS target_user_email
         FROM admin_audit a
         LEFT JOIN nodes n ON n.id = a.target_node
         LEFT JOIN profiles p ON p.id = a.target_user
         ORDER BY a.ts DESC LIMIT ?`,
      ).bind(limit).all();
      return rows.results.map((row) => ({
        ...row,
        detail: typeof row.detail === "string" ? JSON.parse(String(row.detail)) : row.detail,
      }));
    }
    case "hyn_fleet_metric_history":
      requireAdmin(session);
      return fleetMetricHistory(db);
    case "hyn_admin_set_node_status": {
      requireAdmin(session);
      const nodeId = asId(body.p_node_id);
      const status = typeof body.p_status === "string" ? body.p_status : "";
      if (!nodeId || !["active", "paused", "suspended"].includes(status)) throw new RpcError("unknown status");
      const minutes = Number(body.p_minutes);
      const until = status === "paused" && Number.isFinite(minutes) && minutes > 0
        ? new Date(Date.now() + minutes * 60_000).toISOString()
        : null;
      const reason = status === "active" ? null : (typeof body.p_reason === "string" ? body.p_reason.slice(0, 300) : null);
      const updated = await db.prepare(
        "UPDATE nodes SET status = ?, paused_until = ?, status_reason = ? WHERE id = ?",
      ).bind(status, until, reason, nodeId).run();
      if ((updated.meta.changes ?? 0) === 0) throw new RpcError("no such node");
      await audit(db, session, `node.status.${status}`, null, nodeId, { minutes: body.p_minutes ?? null, reason, until });
      return { status: "ok", node_status: status, paused_until: until };
    }
    case "hyn_admin_set_node_revoked": {
      requireAdmin(session);
      const nodeId = asId(body.p_node_id);
      if (!nodeId) throw new RpcError("no such node");
      const revoked = Boolean(body.p_revoked);
      const reason = typeof body.p_reason === "string" ? body.p_reason.slice(0, 300) : null;
      const updated = await db.prepare(
        "UPDATE nodes SET revoked = ?, status_reason = CASE WHEN ? = 1 THEN ? ELSE status_reason END WHERE id = ?",
      ).bind(revoked ? 1 : 0, revoked ? 1 : 0, reason, nodeId).run();
      if ((updated.meta.changes ?? 0) === 0) throw new RpcError("no such node");
      await audit(db, session, revoked ? "node.revoke" : "node.unrevoke", null, nodeId, { reason });
      return { status: "ok", revoked };
    }
    case "hyn_admin_set_user_status": {
      requireAdmin(session);
      const userId = asId(body.p_user_id);
      const status = typeof body.p_status === "string" ? body.p_status : "";
      if (!userId || !["active", "suspended"].includes(status)) throw new RpcError("unknown status");
      const reason = typeof body.p_reason === "string" ? body.p_reason.slice(0, 300) : null;
      await db.prepare("UPDATE profiles SET status = ?, suspended_reason = ?, updated_at = ? WHERE id = ?")
        .bind(status, status === "suspended" ? reason : null, nowIso(), userId).run();
      await audit(db, session, `client.status.${status}`, userId, null, { reason });
      return { status: "ok" };
    }
    case "hyn_admin_set_user_servers": {
      requireAdmin(session);
      const viewer = asId(body.p_viewer);
      if (!viewer) throw new RpcError("Choose an active Viewer or Monitor");
      const target = await db.prepare("SELECT role, status FROM profiles WHERE id = ?")
        .bind(viewer).first<{ role: string; status: string }>();
      if (!target || target.status !== "active" || (target.role !== "viewer" && target.role !== "monitor")) {
        throw new RpcError("Choose an active Viewer or Monitor");
      }
      const requested = asIds(body.p_nodes);
      const valid: string[] = [];
      for (const id of requested) {
        const node = await db.prepare(
          `SELECT n.id, n.owner FROM nodes n JOIN profiles p ON p.id = n.owner
           WHERE n.id = ? AND n.revoked = 0 AND n.is_demo = 0 AND p.status = 'active'`,
        ).bind(id).first<{ id: string; owner: string }>();
        if (!node) throw new RpcError("One or more selected servers are unavailable. Refresh and try again");
        if (node.owner !== viewer) valid.push(node.id);
      }
      await db.prepare("DELETE FROM dashboard_access WHERE viewer_id = ?").bind(viewer).run();
      if (valid.length) {
        const keep = valid.map(() => "?").join(",");
        await db.prepare(`DELETE FROM server_access WHERE viewer_id = ? AND node_id NOT IN (${keep})`)
          .bind(viewer, ...valid).run();
      } else {
        await db.prepare("DELETE FROM server_access WHERE viewer_id = ?").bind(viewer).run();
      }
      const now = nowIso();
      for (const id of valid) {
        await db.prepare(
          `INSERT INTO server_access (viewer_id, node_id, allowed, notifications_allowed, granted_by, updated_at)
           VALUES (?, ?, 1, 1, ?, ?)
           ON CONFLICT (viewer_id, node_id) DO UPDATE SET allowed = 1, granted_by = excluded.granted_by, updated_at = excluded.updated_at`,
        ).bind(viewer, id, session.userId, now).run();
      }
      await audit(db, session, "user.servers.assign", viewer, null, { node_ids: valid });
      return { node_ids: valid };
    }
    case "hyn_admin_share_server": {
      requireAdmin(session);
      const nodeId = asId(body.p_node);
      const viewers = asIds(body.p_viewers);
      if (!nodeId || !viewers.length) throw new RpcError("choose 1 to 100 users and a notification permission");
      const notify = body.p_notify !== false;
      const allow = body.p_allow !== false;
      const now = nowIso();
      for (const viewer of viewers) {
        await db.prepare(
          `INSERT INTO server_access (viewer_id, node_id, allowed, notifications_allowed, granted_by, updated_at)
           VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT (viewer_id, node_id) DO UPDATE SET
             allowed = excluded.allowed, notifications_allowed = excluded.notifications_allowed,
             granted_by = excluded.granted_by, updated_at = excluded.updated_at`,
        ).bind(viewer, nodeId, allow ? 1 : 0, notify ? 1 : 0, session.userId, now).run();
        await db.prepare(
          "INSERT INTO server_access_events (ts, actor, viewer_id, node_id, allowed) VALUES (?, ?, ?, ?, ?)",
        ).bind(now, session.userId, viewer, nodeId, allow ? 1 : 0).run();
      }
      return { updated: viewers.length };
    }
    case "hyn_admin_set_dashboard_access": {
      requireAdmin(session);
      const viewer = asId(body.p_viewer);
      const owner = asId(body.p_owner);
      if (!viewer || !owner) throw new RpcError("viewer and owner required");
      if (viewer === owner) throw new RpcError("accounts already have access to their own dashboard");
      if (body.p_allow) {
        await db.prepare(
          `INSERT OR IGNORE INTO dashboard_access (viewer_id, owner_id, granted_by, created_at)
           VALUES (?, ?, ?, ?)`,
        ).bind(viewer, owner, session.userId, nowIso()).run();
      } else {
        await db.prepare("DELETE FROM dashboard_access WHERE viewer_id = ? AND owner_id = ?")
          .bind(viewer, owner).run();
      }
      await audit(db, session, "dashboard.access", viewer, null, { owner, allowed: Boolean(body.p_allow) });
      return { status: "ok" };
    }
    case "hyn_admin_clear_notifications": {
      requireAdmin(session);
      const before = typeof body.p_before === "string" ? body.p_before : null;
      const deleted = before
        ? await db.prepare("DELETE FROM notification_log WHERE ts < ?").bind(before).run()
        : await db.prepare("DELETE FROM notification_log").run();
      const n = deleted.meta.changes ?? 0;
      await audit(db, session, "notification_log.clear", null, null, { reason: body.p_reason ?? null, deleted: n, before });
      return { status: "ok", deleted: n };
    }
    case "hyn_admin_request_node_command": {
      requireSuper(session);
      const nodeId = asId(body.p_node_id);
      const command = typeof body.p_command === "string" ? body.p_command : "";
      if (!nodeId || (command !== "update" && command !== "sync")) throw new RpcError("invalid command");
      await requireViewNode(db, session, nodeId);
      const existing = await db.prepare(
        `SELECT ${COMMAND_COLUMNS} FROM node_commands
         WHERE node_id = ? AND command = ? AND status IN ('queued', 'running')
         ORDER BY requested_at DESC LIMIT 1`,
      ).bind(nodeId, command).first<Record<string, unknown>>();
      if (existing) return { ...existing, action: existing.command, created: false };
      const id = uuid();
      const now = nowIso();
      const message = command === "sync"
        ? "Waiting for the machine to synchronize"
        : "Waiting for the machine to check in";
      await db.prepare(
        `INSERT INTO node_commands (id, node_id, requested_by, command, status, stage, message, requested_at, updated_at)
         VALUES (?, ?, ?, ?, 'queued', 'queued', ?, ?, ?)`,
      ).bind(id, nodeId, session.userId, command, message, now, now).run();
      return { id, node_id: nodeId, action: command, command, status: "queued", stage: "queued", message, created: true, requested_at: now, updated_at: now };
    }
    case "hyn_latest_node_command": {
      const nodeId = asId(body.p_node_id);
      const command = typeof body.p_command === "string" ? body.p_command : "";
      if (!nodeId || (command !== "update" && command !== "sync")) throw new RpcError("invalid command");
      await requireViewNode(db, session, nodeId);
      return db.prepare(
        `SELECT ${COMMAND_COLUMNS} FROM node_commands
         WHERE node_id = ? AND command = ? ORDER BY requested_at DESC LIMIT 1`,
      ).bind(nodeId, command).first();
    }
    case "hyn_node_relayer": {
      const nodeId = asId(body.p_node);
      if (!nodeId) throw new RpcError("Server unavailable", 403);
      if (!await canViewNode(db, session, nodeId)) throw new RpcError("Server unavailable", 403);
      const rows = await db.prepare(
        `SELECT a.id, a.owner, a.relayer_id, a.relayer_name, a.created_at
         FROM node_relayer_links l
         JOIN relayer_assignments a ON a.id = l.assignment_id
         WHERE l.node_id = ?`,
      ).bind(nodeId).all();
      return rows.results;
    }
    case "hyn_list_relayer_assignments": {
      requireActive(session);
      const owner = asId(body.p_owner);
      const all = body.p_all === true;
      if (all) requireAdmin(session);
      else if (owner && owner !== session.userId) {
        const share = await db.prepare(
          "SELECT 1 AS ok FROM dashboard_access WHERE viewer_id = ? AND owner_id = ?",
        ).bind(session.userId, owner).first();
        if (!share && !isAdmin(session.profile.role)) throw new RpcError("You cannot view another account's relayers.", 403);
      }
      const scope = all ? null : (owner ?? session.userId);
      const rows = scope
        ? await db.prepare(
          "SELECT id, owner, relayer_id, relayer_name, created_at FROM relayer_assignments WHERE owner = ? ORDER BY created_at",
        ).bind(scope).all()
        : await db.prepare(
          "SELECT id, owner, relayer_id, relayer_name, created_at FROM relayer_assignments ORDER BY created_at",
        ).all();
      return rows.results;
    }
    case "hyn_list_relayer_requests": {
      const owner = asId(body.p_owner) ?? session.userId;
      const status = typeof body.p_status === "string" ? body.p_status : null;
      if (owner !== session.userId) requireAdmin(session);
      const sql = status
        ? "SELECT id, owner, relayer_id, relayer_name, status, created_at FROM relayer_requests WHERE owner = ? AND status = ? ORDER BY created_at"
        : "SELECT id, owner, relayer_id, relayer_name, status, created_at FROM relayer_requests WHERE owner = ? ORDER BY created_at";
      const rows = status
        ? await db.prepare(sql).bind(owner, status).all()
        : await db.prepare(sql).bind(owner).all();
      return rows.results;
    }
    case "hyn_list_pending_relayer_requests": {
      requireAdmin(session);
      return (await db.prepare(
        `SELECT id, owner, relayer_id, relayer_name, status, created_at
         FROM relayer_requests WHERE status = 'pending' ORDER BY created_at LIMIT 200`,
      ).all()).results;
    }
    case "hyn_list_node_relayer_links": {
      requireActive(session);
      const owner = asId(body.p_owner);
      if (owner) {
        return (await db.prepare(
          `SELECT l.node_id, l.assignment_id FROM node_relayer_links l
           JOIN relayer_assignments a ON a.id = l.assignment_id
           WHERE a.owner = ?`,
        ).bind(owner).all()).results;
      }
      if (!isAdmin(session.profile.role) && !session.service) throw new RpcError("administrator role required", 403);
      return (await db.prepare("SELECT node_id, assignment_id FROM node_relayer_links").all()).results;
    }
    case "hyn_request_relayer": {
      const profile = requireActive(session);
      if (!canMonitor(profile.role)) throw new RpcError("A Monitor or Super admin role is required to request relayers.", 403);
      const relayerId = Number(body.p_relayer_id);
      const relayerName = typeof body.p_relayer_name === "string" ? body.p_relayer_name.trim().slice(0, 160) : "";
      if (!Number.isInteger(relayerId) || relayerId <= 0 || !relayerName) {
        throw new RpcError("A positive relayer ID and name are required");
      }
      const taken = await db.prepare("SELECT owner FROM relayer_assignments WHERE relayer_id = ?")
        .bind(relayerId).first<{ owner: string }>();
      if (taken) throw new RpcError("This relayer is already assigned. Ask an administrator to check its assignment");
      const pending = await db.prepare(
        "SELECT id FROM relayer_requests WHERE owner = ? AND relayer_id = ? AND status = 'pending'",
      ).bind(session.userId, relayerId).first<{ id: string }>();
      if (pending) return pending.id;
      const pendingCount = await count(
        db,
        "SELECT COUNT(*) AS n FROM relayer_requests WHERE owner = ? AND status = 'pending'",
        session.userId,
      );
      if (pendingCount >= 10) throw new RpcError("You already have 10 pending requests. Cancel one or wait for a review");
      const id = uuid();
      await db.prepare(
        `INSERT INTO relayer_requests (id, owner, relayer_id, relayer_name, status, created_at)
         VALUES (?, ?, ?, ?, 'pending', ?)
         ON CONFLICT (owner, relayer_id) DO UPDATE SET relayer_name = excluded.relayer_name, status = 'pending', created_at = excluded.created_at`,
      ).bind(id, session.userId, relayerId, relayerName, nowIso()).run();
      const row = await db.prepare(
        "SELECT id FROM relayer_requests WHERE owner = ? AND relayer_id = ?",
      ).bind(session.userId, relayerId).first<{ id: string }>();
      return row?.id ?? id;
    }
    case "hyn_cancel_relayer_request": {
      requireActive(session);
      const id = asId(body.p_request_id);
      if (!id) throw new RpcError("Pending request not found");
      const updated = await db.prepare(
        "UPDATE relayer_requests SET status = 'cancelled' WHERE id = ? AND owner = ? AND status = 'pending'",
      ).bind(id, session.userId).run();
      if ((updated.meta.changes ?? 0) === 0) throw new RpcError("Pending request not found");
      return { status: "ok" };
    }
    case "hyn_admin_assign_relayer": {
      requireSuper(session);
      const owner = asId(body.p_owner);
      const relayerId = Number(body.p_relayer_id);
      const relayerName = typeof body.p_relayer_name === "string" ? body.p_relayer_name.trim().slice(0, 160) : "";
      if (!owner || !Number.isInteger(relayerId) || relayerId <= 0 || !relayerName) {
        throw new RpcError("A user, positive relayer ID and name are required");
      }
      const profile = await db.prepare("SELECT status FROM profiles WHERE id = ?").bind(owner).first<{ status: string }>();
      if (!profile || profile.status !== "active") throw new RpcError("Select an active portal account");
      const existing = await db.prepare("SELECT id, owner FROM relayer_assignments WHERE relayer_id = ?")
        .bind(relayerId).first<{ id: string; owner: string }>();
      if (existing && existing.owner !== owner) throw new RpcError("This relayer is already assigned to another account");
      const id = existing?.id ?? uuid();
      if (existing) {
        await db.prepare("UPDATE relayer_assignments SET relayer_name = ? WHERE id = ?").bind(relayerName, id).run();
      } else {
        await db.prepare(
          "INSERT INTO relayer_assignments (id, owner, relayer_id, relayer_name, created_at) VALUES (?, ?, ?, ?, ?)",
        ).bind(id, owner, relayerId, relayerName, nowIso()).run();
      }
      await db.prepare(
        "UPDATE relayer_requests SET status = 'approved' WHERE owner = ? AND relayer_id = ? AND status = 'pending'",
      ).bind(owner, relayerId).run();
      await audit(db, session, "relayer.assign", owner, null, { relayer_id: relayerId, relayer_name: relayerName });
      return id;
    }
    case "hyn_admin_remove_relayer": {
      requireSuper(session);
      const id = asId(body.p_assignment_id);
      if (!id) throw new RpcError("Assignment no longer exists");
      const row = await db.prepare("SELECT * FROM relayer_assignments WHERE id = ?")
        .bind(id).first<{ owner: string; relayer_id: number; relayer_name: string }>();
      if (!row) throw new RpcError("Assignment no longer exists");
      await db.prepare("DELETE FROM relayer_assignments WHERE id = ?").bind(id).run();
      await audit(db, session, "relayer.remove", row.owner, null, { relayer_id: row.relayer_id, relayer_name: row.relayer_name });
      return { status: "ok" };
    }
    case "hyn_admin_set_node_relayer": {
      requireSuper(session);
      const nodeId = asId(body.p_node_id);
      if (!nodeId) throw new RpcError("Select a valid server and relayer assignment.");
      const assignmentId = asId(body.p_assignment_id);
      if (!assignmentId) {
        await db.prepare("DELETE FROM node_relayer_links WHERE node_id = ?").bind(nodeId).run();
        await audit(db, session, "node.relayer.unlink", null, nodeId, {});
        return { status: "ok" };
      }
      const assignment = await db.prepare("SELECT id, owner FROM relayer_assignments WHERE id = ?")
        .bind(assignmentId).first<{ id: string; owner: string }>();
      if (!assignment) throw new RpcError("Assignment no longer exists");
      await db.prepare(
        `INSERT INTO node_relayer_links (node_id, assignment_id) VALUES (?, ?)
         ON CONFLICT (node_id) DO UPDATE SET assignment_id = excluded.assignment_id`,
      ).bind(nodeId, assignmentId).run();
      await audit(db, session, "node.relayer.link", assignment.owner, nodeId, { assignment_id: assignmentId });
      return { status: "ok" };
    }
    case "hyn_admin_review_relayer_request": {
      requireSuper(session);
      const id = asId(body.p_request_id);
      if (!id || typeof body.p_approve !== "boolean") throw new RpcError("Choose approve or reject");
      const request = await db.prepare(
        "SELECT * FROM relayer_requests WHERE id = ? AND status = 'pending'",
      ).bind(id).first<{ owner: string; relayer_id: number; relayer_name: string }>();
      if (!request) throw new RpcError("This request is no longer pending");
      if (body.p_approve) {
        return handlePortalMore(db, session, "hyn_admin_assign_relayer", {
          p_owner: request.owner,
          p_relayer_id: request.relayer_id,
          p_relayer_name: typeof body.p_relayer_name === "string" && body.p_relayer_name.trim()
            ? body.p_relayer_name
            : request.relayer_name,
        });
      }
      await db.prepare("UPDATE relayer_requests SET status = 'rejected' WHERE id = ?").bind(id).run();
      await audit(db, session, "relayer.request.rejected", request.owner, null, { relayer_id: request.relayer_id });
      return { status: "ok" };
    }
    case "hyn_list_server_access":
      requireAdmin(session);
      return (await db.prepare(
        "SELECT viewer_id, node_id, allowed, notifications_allowed FROM server_access ORDER BY updated_at DESC",
      ).all()).results.map((row) => ({ ...row, allowed: asBool(row.allowed), notifications_allowed: asBool(row.notifications_allowed) }));
    case "hyn_list_access_events":
      requireAdmin(session);
      return (await db.prepare(
        "SELECT id, ts, actor, viewer_id, node_id, allowed FROM server_access_events ORDER BY ts DESC LIMIT 50",
      ).all()).results.map((row) => ({ ...row, allowed: asBool(row.allowed) }));
    case "hyn_list_dashboard_access":
      requireAdmin(session);
      return (await db.prepare(
        "SELECT viewer_id, owner_id FROM dashboard_access ORDER BY created_at DESC",
      ).all()).results;
    case "hyn_account_workspace": {
      const profile = requireActive(session);
      const nodes = (await db.prepare(
        `SELECT ${NODE_COLUMNS} FROM nodes WHERE revoked = 0 ORDER BY created_at`,
      ).all<NodeRow>()).results;
      const visible = [];
      for (const row of nodes) {
        if (await canViewNode(db, session, row.id)) visible.push(publicNode(row));
      }
      const since = hoursAgoIso(24 * 30);
      const log = (await db.prepare(
        `SELECT l.* FROM notification_log l JOIN nodes n ON n.id = l.node_id
         WHERE n.revoked = 0 ORDER BY l.ts DESC LIMIT 50`,
      ).all<Record<string, unknown> & { node_id: string }>()).results;
      const visibleLog = [];
      for (const row of log) {
        if (await canViewNode(db, session, row.node_id)) visibleLog.push(row);
      }
      const prefs = (await db.prepare("SELECT * FROM email_preferences ORDER BY node_id").all()).results
        .map((row) => ({
          ...row,
          incident_enabled: asBool(row.incident_enabled),
          daily_enabled: asBool(row.daily_enabled),
          system_enabled: asBool(row.system_enabled),
        }));
      return {
        profile,
        nodes: visible,
        log: visibleLog,
        emailPreferences: prefs,
        counts: {
          total: await count(db, "SELECT COUNT(*) AS n FROM notification_log WHERE owner = ? AND ts > ?", session.userId, since),
          sent: await count(db, "SELECT COUNT(*) AS n FROM notification_log WHERE owner = ? AND ts > ? AND status = 'sent'", session.userId, since),
          failed: await count(db, "SELECT COUNT(*) AS n FROM notification_log WHERE owner = ? AND ts > ? AND status = 'failed'", session.userId, since),
        },
      };
    }
    case "hyn_upsert_email_preferences": {
      requireActive(session);
      const nodeId = asId(body.p_node_id);
      if (!nodeId) throw new RpcError("node required");
      const node = await requireViewNode(db, session, nodeId);
      if (!isSuper(session.profile.role) && node.owner !== session.userId) {
        throw new RpcError("server access required", 403);
      }
      const recipient = typeof body.p_recipient === "string" ? body.p_recipient.slice(0, 200) : session.email;
      const timezone = typeof body.p_timezone === "string" ? body.p_timezone.slice(0, 100) : "UTC";
      await db.prepare(
        `INSERT INTO email_preferences (
           node_id, recipient, timezone, incident_enabled, daily_enabled, system_enabled,
           daily_at, system_at, send_at, updated_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (node_id) DO UPDATE SET
           recipient = excluded.recipient, timezone = excluded.timezone,
           incident_enabled = excluded.incident_enabled, daily_enabled = excluded.daily_enabled,
           system_enabled = excluded.system_enabled, daily_at = excluded.daily_at,
           system_at = excluded.system_at, send_at = excluded.send_at, updated_at = excluded.updated_at`,
      ).bind(
        nodeId, recipient, timezone,
        body.p_incident_enabled ? 1 : 0, body.p_daily_enabled ? 1 : 0, body.p_system_enabled ? 1 : 0,
        typeof body.p_daily_at === "string" ? body.p_daily_at : "08:00",
        typeof body.p_system_at === "string" ? body.p_system_at : "09:00",
        typeof body.p_daily_at === "string" ? body.p_daily_at : "08:00",
        nowIso(),
      ).run();
      return { status: "ok" };
    }
    case "hyn_transient_get": {
      const nodeId = asId(body.p_node);
      if (!nodeId) throw new RpcError("node required");
      await requireViewNode(db, session, nodeId);
      const row = await db.prepare(
        "SELECT payload, expires_at FROM transient_snapshots WHERE node_id = ? AND expires_at > ?",
      ).bind(nodeId, nowIso()).first<{ payload: string; expires_at: string }>();
      if (!row) return null;
      try { return JSON.parse(row.payload); } catch { return null; }
    }
    case "hyn_claim_device_linked_email": {
      requireActive(session);
      const nodeId = asId(body.p_node_id);
      if (!nodeId) throw new RpcError("node not found");
      const node = await db.prepare(
        "SELECT * FROM nodes WHERE id = ? AND owner = ? AND revoked = 0 AND is_demo = 0",
      ).bind(nodeId, session.userId).first<NodeRow>();
      if (!node) throw new RpcError("node not found");
      const pref = await db.prepare("SELECT recipient FROM email_preferences WHERE node_id = ?")
        .bind(nodeId).first<{ recipient: string | null }>();
      const recipient = pref?.recipient || session.email;
      if (!recipient) return { status: "skip", reason: "email preference missing" };
      const claimed = await claimDispatch(db, `device-linked:${nodeId}`, nodeId, "system");
      if (!claimed) return { status: "skip", reason: "already sent" };
      if (!pref?.recipient) {
        await db.prepare(
          `INSERT OR IGNORE INTO email_preferences (node_id, recipient, timezone, incident_enabled, daily_enabled, system_enabled, daily_at, system_at, send_at, updated_at)
           VALUES (?, ?, 'UTC', 0, 1, 1, '08:00', '09:00', '08:00', ?)`,
        ).bind(nodeId, recipient, nowIso()).run();
      }
      return {
        status: "send",
        node_id: node.id,
        node_name: node.name,
        hostname: node.hostname,
        os: node.os,
        agent_version: node.agent_version,
        recipient,
        linked_at: node.created_at,
      };
    }
    case "hyn_complete_device_linked_email": {
      const nodeId = asId(body.p_node_id);
      if (!nodeId) throw new RpcError("node not found");
      await db.prepare(
        "UPDATE cloud_email_dispatches SET provider_id = ? WHERE idempotency_key = ?",
      ).bind(typeof body.p_provider_id === "string" ? body.p_provider_id.slice(0, 200) : null, `device-linked:${nodeId}`).run();
      return { status: "ok" };
    }
    case "hyn_release_device_linked_email": {
      const nodeId = asId(body.p_node_id);
      if (!nodeId) throw new RpcError("node not found");
      await db.prepare("DELETE FROM cloud_email_dispatches WHERE idempotency_key = ?")
        .bind(`device-linked:${nodeId}`).run();
      return { status: "ok" };
    }
    case "hyn_claim_web_notification": {
      if (!session.service) throw new RpcError("service credentials required", 403);
      const requested = asId(body.p_job_id);
      const job = requested
        ? await db.prepare("SELECT * FROM web_notification_jobs WHERE id = ? AND status = 'queued'")
          .bind(requested).first<{ id: string; node_id: string; event: string }>()
        : await db.prepare("SELECT * FROM web_notification_jobs WHERE status = 'queued' ORDER BY created_at LIMIT 1")
          .first<{ id: string; node_id: string; event: string }>();
      if (!job) return { status: "idle" };
      await db.prepare("UPDATE web_notification_jobs SET status = 'running' WHERE id = ?").bind(job.id).run();
      const node = await db.prepare("SELECT * FROM nodes WHERE id = ?").bind(job.node_id).first<NodeRow>();
      const pref = await db.prepare("SELECT recipient FROM email_preferences WHERE node_id = ?")
        .bind(job.node_id).first<{ recipient: string | null }>();
      const owner = node ? await db.prepare("SELECT email FROM profiles WHERE id = ?").bind(node.owner).first<{ email: string | null }>() : null;
      let event: Record<string, unknown> = {};
      try { event = JSON.parse(job.event) as Record<string, unknown>; } catch { event = {}; }
      return {
        status: "send",
        id: job.id,
        node_id: job.node_id,
        node_name: node?.name ?? "linked machine",
        hostname: node?.hostname ?? null,
        recipient: pref?.recipient || owner?.email || event.recipient,
        fingerprint: event.fingerprint ?? job.id,
        category: event.category ?? "alert",
        severity: event.severity ?? "info",
        subject: event.subject ?? "HYN-view notification",
        text_body: event.text_body ?? event.message ?? "No details supplied",
        html_body: event.html_body ?? null,
      };
    }
    case "hyn_defer_web_delivery": {
      if (!session.service) throw new RpcError("service credentials required", 403);
      const id = asId(body.p_job);
      if (!id) throw new RpcError("job required");
      await db.prepare("UPDATE web_notification_jobs SET status = 'queued' WHERE id = ?").bind(id).run();
      return { status: "ok" };
    }
    case "hyn_complete_web_notification": {
      if (!session.service) throw new RpcError("service credentials required", 403);
      const id = asId(body.p_job_id);
      if (!id) throw new RpcError("job required");
      const job = await db.prepare("SELECT node_id FROM web_notification_jobs WHERE id = ?")
        .bind(id).first<{ node_id: string }>();
      await db.prepare("UPDATE web_notification_jobs SET status = ? WHERE id = ?")
        .bind(body.p_status === "sent" ? "sent" : "failed", id).run();
      if (job) {
        const node = await db.prepare("SELECT owner FROM nodes WHERE id = ?").bind(job.node_id).first<{ owner: string }>();
        if (node) {
          await db.prepare(
            `INSERT INTO notification_log (node_id, owner, ts, kind, target, severity, subject, status, error, category)
             VALUES (?, ?, ?, 'web', ?, 'info', 'web notification', ?, ?, 'other')`,
          ).bind(
            job.node_id, node.owner, nowIso(),
            typeof body.p_target === "string" ? body.p_target : null,
            body.p_status === "sent" ? "sent" : "failed",
            typeof body.p_error === "string" ? body.p_error : null,
          ).run();
        }
      }
      return { status: "ok" };
    }
    case "hyn_command_lookup": {
      if (!session.service && !isAdmin(session.profile.role)) throw new RpcError("administrator role required", 403);
      const id = asId(body.p_id);
      if (!id) return null;
      return db.prepare(`SELECT ${COMMAND_COLUMNS} FROM node_commands WHERE id = ?`).bind(id).first();
    }
    case "hyn_prune_telemetry": {
      if (!session.service && !isSuper(session.profile.role)) throw new RpcError("service credentials required", 403);
      const batch = Math.min(5000, Math.max(1, Number(body.p_batch) || 5000));
      const cutoff = hoursAgoIso(48);
      const metrics = await db.prepare("DELETE FROM metrics WHERE id IN (SELECT id FROM metrics WHERE ts < ? LIMIT ?)").bind(cutoff, batch).run();
      const speed = await db.prepare("DELETE FROM speedtests WHERE id IN (SELECT id FROM speedtests WHERE ts < ? LIMIT ?)").bind(cutoff, batch).run();
      const alerts = await db.prepare("DELETE FROM alert_events WHERE id IN (SELECT id FROM alert_events WHERE ts < ? LIMIT ?)").bind(cutoff, batch).run();
      const deleted = (metrics.meta.changes ?? 0) + (speed.meta.changes ?? 0) + (alerts.meta.changes ?? 0);
      return { deleted, has_more: deleted >= batch };
    }
    case "hyn_admin_delivery_dashboard": {
      requireSuper(session);
      const offset = Math.max(0, Number(body.p_offset) || 0);
      const owner = asId(body.p_owner);
      const kind = typeof body.p_kind === "string" && body.p_kind !== "all" ? body.p_kind : null;
      const status = typeof body.p_status === "string" && body.p_status !== "all" ? body.p_status : null;
      let where = " WHERE 1=1";
      const binds: unknown[] = [];
      if (owner) { where += " AND l.owner = ?"; binds.push(owner); }
      if (kind) { where += " AND l.kind = ?"; binds.push(kind); }
      if (status) { where += " AND l.status = ?"; binds.push(status); }
      const total = await count(db, `SELECT COUNT(*) AS n FROM notification_log l${where}`, ...binds);
      const rows = await db.prepare(
        `SELECT l.*, p.email AS owner_email, p.full_name AS owner_name, n.name AS node_name
         FROM notification_log l
         LEFT JOIN profiles p ON p.id = l.owner
         LEFT JOIN nodes n ON n.id = l.node_id
         ${where} ORDER BY l.ts DESC LIMIT 25 OFFSET ?`,
      ).bind(...binds, offset).all<Record<string, unknown>>();
      const users = (await db.prepare(
        "SELECT id, COALESCE(full_name, email, id) AS name, email, status FROM profiles ORDER BY email",
      ).all()).results;
      const now = nowIso();
      return {
        as_of: now,
        day_start: `${now.slice(0, 10)}T00:00:00.000Z`,
        started_at: now,
        rules: [],
        digest_settings: [],
        users,
        usage: [],
        global_usage: [],
        events: [],
        total,
        legacy: rows.results.map((row) => ({
          id: row.id,
          ts: row.ts,
          owner_name: row.owner_name || row.owner_email || row.owner,
          node_name: row.node_name ?? null,
          kind: row.kind,
          status: row.status,
          subject: row.subject ?? null,
          error: row.error ?? null,
        })),
      };
    }
    case "hyn_admin_set_delivery_rules":
    case "hyn_admin_set_digest":
    case "hyn_admin_stop_delivery":
      requireSuper(session);
      return { status: "ok" };
    case "hyn_claim_admin_report": {
      requireSuper(session);
      const clientId = asId(body.p_target_user);
      if (!clientId) throw new RpcError("A valid client is required.");
      const id = uuid();
      await claimDispatch(db, `admin-report:${id}`, null, "admin_report", clientId);
      return { id };
    }
    case "hyn_complete_admin_report": {
      requireSuper(session);
      const reportId = asId(body.p_report_id);
      if (!reportId) throw new RpcError("report required");
      const status = typeof body.p_status === "string" ? body.p_status.slice(0, 32) : "failed";
      await db.prepare(
        "UPDATE cloud_email_dispatches SET status = ?, provider_id = ? WHERE idempotency_key = ?",
      ).bind(
        status,
        typeof body.p_provider_id === "string" ? body.p_provider_id.slice(0, 200) : null,
        `admin-report:${reportId}`,
      ).run();
      return { status: "ok" };
    }
    case "hyn_admin_client_report": {
      requireSuper(session);
      const clientId = asId(body.p_target_user);
      if (!clientId) throw new RpcError("A valid client is required.");
      const profile = await db.prepare(
        "SELECT id, email, full_name, status FROM profiles WHERE id = ?",
      ).bind(clientId).first<{ id: string; email: string | null; full_name: string | null; status: string }>();
      if (!profile || profile.status !== "active" || !profile.email) {
        throw new RpcError("The selected active client does not have an email address.");
      }
      const nodes = (await db.prepare(
        `SELECT id, name, hostname, os, agent_version, last_seen_at, last_heartbeat_at
         FROM nodes WHERE owner = ? AND revoked = 0 AND is_demo = 0 AND status = 'active' ORDER BY name`,
      ).bind(clientId).all<{
        id: string; name: string; hostname: string | null; os: string | null;
        agent_version: string | null; last_seen_at: string | null; last_heartbeat_at: string | null;
      }>()).results;
      if (!nodes.length) throw new RpcError("The selected client has no active linked machines.");
      const machines = [];
      for (const node of nodes) {
        const metric = await db.prepare(
          `SELECT cpu_pct, cpu_temp_c, cpu_model, cpu_cores, mem_pct, mem_total, mem_used, disk_pct,
                  net_iface, net_rx_bps, net_tx_bps, net_link_mbps, sensors, payload
           FROM metrics WHERE node_id = ? ORDER BY ts DESC LIMIT 1`,
        ).bind(node.id).first<Record<string, unknown>>();
        const speedtest = await db.prepare(
          "SELECT down_bps, up_bps, latency_ms FROM speedtests WHERE node_id = ? ORDER BY ts DESC LIMIT 1",
        ).bind(node.id).first();
        const alerts = (await db.prepare(
          "SELECT severity, message FROM alert_events WHERE node_id = ? AND resolved = 0 ORDER BY ts DESC LIMIT 50",
        ).bind(node.id).all()).results;
        machines.push({
          id: node.id,
          name: node.name,
          hostname: node.hostname,
          os: node.os,
          agentVersion: node.agent_version,
          lastHeartbeatAt: node.last_heartbeat_at,
          lastSeenAt: node.last_seen_at,
          alerts,
          metric: metric
            ? { ...metric, sensors: parseJson(metric.sensors), payload: parseJson(metric.payload) }
            : null,
          speedtest,
        });
      }
      const template = await db.prepare(
        "SELECT html_template FROM notification_templates WHERE template_key = 'report'",
      ).first<{ html_template: string }>();
      return { profile, machines, template: template?.html_template ?? null };
    }
    case "hyn_log_notification": {
      if (!session.service && !isSuper(session.profile.role)) throw new RpcError("service credentials required", 403);
      await insertNotificationLog(db, body);
      return { status: "ok" };
    }
    case "hyn_expire_node_command": {
      if (!session.service && !isSuper(session.profile.role)) throw new RpcError("service credentials required", 403);
      const id = asId(body.p_id);
      if (!id) throw new RpcError("command required");
      const now = nowIso();
      const result = await db.prepare(
        `UPDATE node_commands SET status = 'expired', stage = 'expired',
           message = 'The machine did not finish within 24 hours. Run sudo hyn doctor, then try the update again.',
           finished_at = ?, updated_at = ?, lease_expires_at = NULL
         WHERE id = ? AND status IN ('queued', 'running')`,
      ).bind(now, now, id).run();
      return { id, status: (result.meta.changes ?? 0) > 0 ? "expired" : "already-terminal" };
    }
    case "hyn_claim_command_email": {
      if (!session.service && !isAdmin(session.profile.role)) throw new RpcError("administrator role required", 403);
      const id = asId(body.p_id);
      if (!id) return { status: "pending" };
      const command = await db.prepare(
        `SELECT ${COMMAND_COLUMNS} FROM node_commands WHERE id = ? AND status IN ('succeeded', 'failed', 'expired')`,
      ).bind(id).first<Record<string, unknown> & { node_id: string; status: string }>();
      if (!command) return { status: "pending" };
      const claimed = await claimDispatch(db, `command:${command.id}:${command.status}`, command.node_id, "system");
      if (!claimed) return { status: "already-sent" };
      const node = await db.prepare(
        "SELECT id, owner, name, hostname, agent_version FROM nodes WHERE id = ?",
      ).bind(command.node_id).first<{
        id: string; owner: string; name: string; hostname: string | null; agent_version: string | null;
      }>();
      const preference = node
        ? await db.prepare("SELECT recipient, system_enabled FROM email_preferences WHERE node_id = ?")
          .bind(node.id).first<{ recipient: string | null; system_enabled: number }>()
        : null;
      if (!node || !preference?.recipient || !asBool(preference.system_enabled)) {
        await db.prepare("DELETE FROM cloud_email_dispatches WHERE idempotency_key = ?")
          .bind(`command:${command.id}:${command.status}`).run();
        return { status: "disabled" };
      }
      const template = await db.prepare(
        "SELECT html_template FROM notification_templates WHERE template_key = 'system'",
      ).first<{ html_template: string }>();
      return {
        status: "send",
        command,
        node,
        preference: { recipient: preference.recipient, system_enabled: true },
        template: template?.html_template ?? null,
      };
    }
    case "hyn_complete_command_email": {
      if (!session.service && !isAdmin(session.profile.role)) throw new RpcError("administrator role required", 403);
      const key = typeof body.p_key === "string" ? body.p_key.slice(0, 200) : null;
      if (!key) throw new RpcError("dispatch key required");
      if (body.p_release === true) {
        await db.prepare("DELETE FROM cloud_email_dispatches WHERE idempotency_key = ?").bind(key).run();
        return { status: "ok" };
      }
      await db.prepare("UPDATE cloud_email_dispatches SET provider_id = ?, status = 'sent' WHERE idempotency_key = ?")
        .bind(typeof body.p_provider_id === "string" ? body.p_provider_id.slice(0, 200) : null, key).run();
      return { status: "ok" };
    }
    case "hyn_heartbeat_watchdog_tick": {
      if (!session.service) throw new RpcError("service credentials required", 403);
      const nodeId = asId(body.p_node);
      if (!nodeId) throw new RpcError("node required");
      const node = await db.prepare(
        "SELECT id, owner, name, hostname, last_heartbeat_at, status, revoked, is_demo FROM nodes WHERE id = ?",
      ).bind(nodeId).first<{
        id: string; owner: string; name: string; hostname: string | null; last_heartbeat_at: string | null;
        status: string; revoked: number; is_demo: number;
      }>();
      const now = nowIso();
      if (!node || node.revoked || node.is_demo || node.status !== "active") {
        await db.prepare("UPDATE node_watchdogs SET state = 'stopped', updated_at = ? WHERE node_id = ?")
          .bind(now, nodeId).run();
        return { stop: true };
      }
      const heartbeatMs = node.last_heartbeat_at ? Date.parse(node.last_heartbeat_at) : Number.NaN;
      const ageSeconds = Number.isFinite(heartbeatMs)
        ? Math.max(0, Math.floor((Date.now() - heartbeatMs) / 1_000))
        : null;
      const state = ageSeconds !== null && ageSeconds < 180 ? "online" : "offline";
      const watchdog = await db.prepare(
        "SELECT last_alert_state FROM node_watchdogs WHERE node_id = ?",
      ).bind(nodeId).first<{ last_alert_state: string | null }>();
      const prior = watchdog?.last_alert_state ?? "unknown";
      const notify = state !== prior && (state === "offline" || prior === "offline");
      await db.prepare(
        `INSERT INTO node_watchdogs (node_id, state, last_alert_state, updated_at)
         VALUES (?, 'running', ?, ?)
         ON CONFLICT (node_id) DO UPDATE SET state = 'running', last_alert_state = excluded.last_alert_state, updated_at = excluded.updated_at`,
      ).bind(nodeId, state, now).run();
      const preference = notify
        ? await db.prepare("SELECT recipient, incident_enabled FROM email_preferences WHERE node_id = ?")
          .bind(nodeId).first<{ recipient: string | null; incident_enabled: number }>()
        : null;
      const template = notify
        ? await db.prepare("SELECT html_template FROM notification_templates WHERE template_key = 'alert'")
          .first<{ html_template: string }>()
        : null;
      return {
        stop: false,
        state,
        notify,
        nodeId: node.id,
        nodeName: node.name,
        hostname: node.hostname,
        owner: node.owner,
        heartbeatAt: node.last_heartbeat_at,
        ageSeconds,
        recipient: preference?.recipient ?? null,
        incident_enabled: preference ? asBool(preference.incident_enabled) : false,
        template: template?.html_template ?? null,
      };
    }
    default:
      throw new RpcError(`unknown rpc ${name}`, 404);
  }
}

export { visibleNodeIds };
