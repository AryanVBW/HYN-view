import {
  audit,
  canLink,
  canMonitor,
  canViewDashboard,
  canViewNode,
  isAdmin,
  isSuper,
  publicNode,
  requireActive,
  requireViewNode,
} from "./access.ts";
import { asString, hoursAgoIso, nowIso, sha256Hex, userCodeHash, uuid } from "./crypto.ts";
import { RpcError } from "./http.ts";
import { bandwidthReport, handlePortalMore, visibleNodeIds } from "./portal-more.ts";
import type { NodeRow, Session } from "./types.ts";
import { NODE_COLUMNS } from "./types.ts";

const TELEMETRY_HOURS = 48;

async function lookupCode(db: D1Database, pepper: string, raw: string) {
  const hash = await userCodeHash(raw, pepper);
  return db.prepare(
    "SELECT * FROM device_codes WHERE user_code_hash = ? ORDER BY created_at DESC LIMIT 1",
  ).bind(hash).first<{
    id: string; hostname: string | null; os: string | null; agent_version: string | null;
    created_at: string; expires_at: string; node_id: string | null;
  }>();
}

export async function handlePortalRpc(
  db: D1Database,
  session: Session,
  name: string,
  body: Record<string, unknown>,
  pepper: string,
): Promise<unknown> {
  const profile = session.service ? session.profile : requireActive(session);

  switch (name) {
    case "hyn_is_active":
      return profile.status === "active";
    case "hyn_is_admin":
      return isAdmin(profile.role);
    case "hyn_is_super_admin":
      return isSuper(profile.role);
    case "hyn_can_monitor":
      return canMonitor(profile.role);
    case "hyn_can_link":
      return canLink(profile.role);
    case "hyn_can_view_dashboard": {
      const owner = asString(body.p_owner, 64);
      if (!owner) throw new RpcError("owner required");
      return canViewDashboard(db, session, owner);
    }
    case "hyn_can_view_node": {
      const node = asString(body.p_node, 64);
      if (!node) throw new RpcError("node required");
      return canViewNode(db, session, node);
    }
    case "hyn_dashboard_accounts": {
      const rows = await db.prepare("SELECT id, full_name FROM profiles").all<{ id: string; full_name: string | null }>();
      const accounts = [];
      for (const row of rows.results) {
        const dashboard = await canViewDashboard(db, session, row.id);
        const sharedNode = await db.prepare(
          `SELECT n.id FROM nodes n WHERE n.owner = ? AND n.revoked = 0 LIMIT 20`,
        ).bind(row.id).all<{ id: string }>();
        let nodeOk = false;
        for (const n of sharedNode.results) {
          if (await canViewNode(db, session, n.id)) { nodeOk = true; break; }
        }
        if (!dashboard && !nodeOk) continue;
        accounts.push({
          id: row.id,
          name: row.id === session.userId
            ? "My dashboard"
            : (row.full_name || `Shared dashboard ${row.id.slice(0, 8)}`),
          own: row.id === session.userId,
          relayers: dashboard,
        });
      }
      accounts.sort((a, b) => Number(b.own) - Number(a.own) || a.name.localeCompare(b.name));
      return accounts;
    }
    case "hyn_device_lookup": {
      if (!canLink(profile.role)) throw new RpcError("an active Monitor, Admin or Super admin account is required to link a server", 403);
      const code = asString(body.p_user_code, 20);
      if (!code) return { status: "not_found" };
      const row = await lookupCode(db, pepper, code);
      if (!row) return { status: "not_found" };
      if (row.expires_at <= nowIso()) return { status: "expired" };
      if (row.node_id) return { status: "already_approved" };
      return {
        status: "pending",
        hostname: row.hostname,
        os: row.os,
        agent_version: row.agent_version,
        requested_at: row.created_at,
      };
    }
    case "hyn_device_approve": {
      if (!canLink(profile.role)) {
        throw new RpcError("an active Monitor, Admin or Super admin account is required to link a server", 403);
      }
      const code = asString(body.p_user_code, 20);
      if (!code) return { status: "not_found" };
      const row = await lookupCode(db, pepper, code);
      if (!row) return { status: "not_found" };
      if (row.expires_at <= nowIso()) return { status: "expired" };
      if (row.node_id) return { status: "already_approved" };
      const nodeId = uuid();
      const name = asString(body.p_node_name, 80) || row.hostname || "node";
      const now = nowIso();
      await db.batch([
        db.prepare(
          `INSERT INTO nodes (id, owner, name, hostname, os, agent_version, is_demo, revoked, status, config, telemetry_mode, created_at)
           VALUES (?, ?, ?, ?, ?, ?, 0, 0, 'active', '{}', 'cloud', ?)`,
        ).bind(nodeId, session.userId, name, row.hostname, row.os, row.agent_version, now),
        db.prepare(
          "UPDATE device_codes SET approved_by = ?, node_id = ? WHERE id = ?",
        ).bind(session.userId, nodeId, row.id),
      ]);
      return { status: "approved", node_id: nodeId, node_name: name };
    }
    case "hyn_metric_history": {
      const nodeId = asString(body.p_node, 64);
      if (!nodeId) throw new RpcError("node required");
      await requireViewNode(db, session, nodeId);
      const cutoff = hoursAgoIso(TELEMETRY_HOURS);
      const rows = await db.prepare(
        `SELECT id, node_id, ts, cpu_pct, cpu_temp_c, cpu_mhz, cpu_model, cpu_steal, cpu_iowait, cpu_cores,
                load1, mem_pct, mem_total, mem_used, swap_used, disk_pct, uptime_s,
                net_iface, net_rx_bps, net_tx_bps, net_retrans_pm, latency_ms,
                net_link_mbps, psi_cpu, psi_mem, psi_io, tcp_estab, conntrack_pct, proc_count
         FROM metrics WHERE node_id = ? AND ts >= ? AND ts <= ?
         ORDER BY ts DESC LIMIT 2880`,
      ).bind(nodeId, cutoff, new Date(Date.now() + 5 * 60_000).toISOString()).all<Record<string, unknown>>();
      const buckets = new Map<number, Record<string, unknown>>();
      for (const row of rows.results) {
        const bucket = Math.floor(Date.parse(String(row.ts)) / 300_000);
        if (!buckets.has(bucket)) buckets.set(bucket, { ...row, payload: null, sensors: null });
        if (buckets.size >= 600) break;
      }
      return [...buckets.values()].reverse();
    }
    case "hyn_demo_seed": {
      await db.prepare("DELETE FROM nodes WHERE owner = ? AND is_demo = 1").bind(session.userId).run();
      const nodeId = uuid();
      const now = Date.now();
      const stmts = [
        db.prepare(
          `INSERT INTO nodes (id, owner, name, hostname, os, agent_version, is_demo, revoked, status, config, telemetry_mode, created_at, last_seen_at, last_heartbeat_at, last_metric_at)
           VALUES (?, ?, 'demo-node', 'demo-node', 'Ubuntu 24.04 LTS (demo)', '0.0.0-demo', 1, 0, 'active', '{}', 'cloud', ?, ?, ?, ?)`,
        ).bind(nodeId, session.userId, nowIso(), nowIso(), nowIso(), nowIso()),
      ];
      for (let i = 0; i <= 287; i++) {
        const ts = new Date(now - i * 5 * 60_000).toISOString();
        const cpu = 18 + 22 * Math.abs(Math.sin(i / 26)) + Math.random() * 9;
        stmts.push(db.prepare(
          `INSERT INTO metrics (node_id, ts, cpu_pct, cpu_temp_c, cpu_mhz, cpu_cores, load1, mem_pct, mem_total, mem_used, swap_used, disk_pct, uptime_s, net_iface, net_rx_bps, net_tx_bps, payload)
           VALUES (?, ?, ?, ?, ?, 8, ?, ?, 33285996544, 17301504000, 0, ?, ?, 'eth0', ?, ?, ?)`,
        ).bind(
          nodeId, ts, Math.round(cpu * 10) / 10, Math.round((41 + cpu * 0.32) * 10) / 10,
          Math.round(2400 + cpu * 14), Math.round((cpu / 100) * 8 * 0.7 * 100) / 100,
          Math.round(52 + 9 * Math.sin(i / 41)), Math.round(58 + (i / 288) * 3),
          1_900_800 - i * 300, Math.floor(620_000_000 + Math.random() * 260_000_000),
          Math.floor(180_000_000 + Math.random() * 90_000_000),
          JSON.stringify({ demo: true }),
        ));
      }
      await db.batch(stmts);
      return { status: "ok", node_id: nodeId };
    }
    case "hyn_demo_clear": {
      await db.prepare("DELETE FROM nodes WHERE owner = ? AND is_demo = 1").bind(session.userId).run();
      return { status: "ok" };
    }
    case "hyn_request_node_command": {
      if (!canMonitor(profile.role)) throw new RpcError("monitor or super administrator role required", 403);
      const nodeId = asString(body.p_node_id, 64);
      const command = asString(body.p_command, 20);
      if (!nodeId || !command) throw new RpcError("invalid command");
      if (command !== "update" && command !== "sync") throw new RpcError("invalid command");
      if (command === "update" && !isSuper(profile.role)) throw new RpcError("super administrator role required", 403);
      await requireViewNode(db, session, nodeId);
      const existing = await db.prepare(
        "SELECT * FROM node_commands WHERE node_id = ? AND command = ? AND status IN ('queued', 'running') ORDER BY requested_at DESC LIMIT 1",
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
      return { id, node_id: nodeId, action: command, status: "queued", stage: "queued", message, created: true, requested_at: now, updated_at: now };
    }
    case "hyn_update_node_config":
    case "hyn_admin_set_node_config": {
      const nodeId = asString(body.p_node_id, 64);
      if (!nodeId) throw new RpcError("node required");
      const node = await requireViewNode(db, session, nodeId);
      if (!isSuper(profile.role) && node.owner !== session.userId) {
        throw new RpcError("super administrator role required", 403);
      }
      const config = body.p_config && typeof body.p_config === "object" ? body.p_config : {};
      await db.prepare("UPDATE nodes SET config = ? WHERE id = ?").bind(JSON.stringify(config), nodeId).run();
      return { status: "ok" };
    }
    case "hyn_bandwidth_report": {
      const nodeId = asString(body.p_node, 64);
      const days = Math.min(366, Math.max(1, Number(body.p_days) || 30));
      if (!nodeId) throw new RpcError("node required");
      await requireViewNode(db, session, nodeId);
      return bandwidthReport(db, [nodeId], days);
    }
    case "hyn_fleet_bandwidth_report": {
      const days = Math.min(366, Math.max(1, Number(body.p_days) || 30));
      const ids = await visibleNodeIds(db, session);
      const reporting = ids.length
        ? await db.prepare(
          `SELECT COUNT(*) AS n FROM bandwidth_counters WHERE node_id IN (${ids.map(() => "?").join(",")})`,
        ).bind(...ids).first<{ n: number }>()
        : { n: 0 };
      const staleCutoff = new Date(Date.now() - 3 * 60_000).toISOString();
      const stale = ids.length
        ? await db.prepare(
          `SELECT COUNT(*) AS n FROM bandwidth_counters WHERE node_id IN (${ids.map(() => "?").join(",")}) AND sampled_at < ?`,
        ).bind(...ids, staleCutoff).first<{ n: number }>()
        : { n: 0 };
      return bandwidthReport(db, ids, days, {
        node_count: ids.length,
        reporting_count: reporting?.n ?? 0,
        stale_count: stale?.n ?? 0,
      });
    }
    case "hyn_server_notifications": {
      const limit = Math.min(200, Math.max(1, Number(body.p_limit) || 50));
      const rows = await db.prepare(
        `SELECT l.* FROM notification_log l
         JOIN nodes n ON n.id = l.node_id
         WHERE n.revoked = 0
         ORDER BY l.ts DESC LIMIT ?`,
      ).bind(limit).all<Record<string, unknown> & { node_id: string }>();
      const visible = [];
      for (const row of rows.results) {
        if (await canViewNode(db, session, row.node_id)) visible.push(row);
      }
      return visible;
    }
    case "hyn_admin_delete_node": {
      if (!isSuper(profile.role)) throw new RpcError("super administrator role required", 403);
      const nodeId = asString(body.p_node_id, 64);
      if (!nodeId) throw new RpcError("no such node");
      const node = await db.prepare("SELECT * FROM nodes WHERE id = ?").bind(nodeId).first<NodeRow>();
      if (!node) throw new RpcError("no such node");
      await audit(db, session, "node.delete", node.owner, nodeId, { name: node.name, reason: body.p_reason ?? null });
      await db.prepare("DELETE FROM device_codes WHERE node_id = ?").bind(nodeId).run();
      await db.prepare("DELETE FROM nodes WHERE id = ?").bind(nodeId).run();
      return { status: "ok", deleted: nodeId, name: node.name };
    }
    case "hyn_admin_promote_by_email": {
      if (!isSuper(profile.role)) throw new RpcError("super administrator role required", 403);
      const email = asString(body.p_email, 200);
      if (!email) throw new RpcError("email required");
      const target = await db.prepare("SELECT * FROM profiles WHERE lower(email) = lower(?)")
        .bind(email).first<{ id: string }>();
      if (!target) return { status: "not_found" };
      await db.prepare("UPDATE profiles SET role = 'super_admin', updated_at = ? WHERE id = ?")
        .bind(nowIso(), target.id).run();
      await audit(db, session, "role.promote", target.id, null, { email });
      return { status: "ok", id: target.id };
    }
    case "hyn_admin_set_role": {
      if (!isSuper(profile.role)) throw new RpcError("super administrator role required", 403);
      const userId = asString(body.p_user_id, 64);
      const role = asString(body.p_role, 20);
      if (!userId || !role || !["viewer", "monitor", "admin", "super_admin"].includes(role)) {
        throw new RpcError("invalid role");
      }
      await db.prepare("UPDATE profiles SET role = ?, updated_at = ? WHERE id = ?")
        .bind(role, nowIso(), userId).run();
      return { status: "ok" };
    }
    case "hyn_admin_templates":
      return (await db.prepare("SELECT * FROM notification_templates").all()).results;
    case "hyn_admin_save_template": {
      if (!isSuper(profile.role)) throw new RpcError("super administrator role required", 403);
      const key = asString(body.p_template_key, 40);
      const html = typeof body.p_html_template === "string" ? body.p_html_template : "";
      if (!key) throw new RpcError("template required");
      await db.prepare(
        `INSERT INTO notification_templates (template_key, html_template) VALUES (?, ?)
         ON CONFLICT (template_key) DO UPDATE SET html_template = excluded.html_template`,
      ).bind(key, html).run();
      return { status: "ok" };
    }
    case "hyn_claim_env_admin": {
      const email = asString(body.p_caller_email, 200);
      if (!email || email.toLowerCase() !== (session.email ?? "").toLowerCase()) {
        throw new RpcError("email mismatch", 403);
      }
      const allow = await db.prepare("SELECT email FROM admin_allowlist WHERE lower(email) = lower(?)")
        .bind(email).first();
      if (!allow) throw new RpcError("not on the administrator allowlist", 403);
      await db.prepare("UPDATE profiles SET role = 'super_admin', updated_at = ? WHERE id = ?")
        .bind(nowIso(), session.userId).run();
      return { status: "ok" };
    }
    case "hyn_list_nodes": {
      const rows = await db.prepare(
        `SELECT ${NODE_COLUMNS} FROM nodes WHERE revoked = 0 ORDER BY is_demo ASC, created_at ASC`,
      ).all<NodeRow>();
      const visible = [];
      for (const row of rows.results) {
        if (await canViewNode(db, session, row.id)) visible.push(publicNode(row));
      }
      return visible;
    }
    case "hyn_node_freshness": {
      const nodeId = asString(body.p_node, 64);
      if (!nodeId) throw new RpcError("Invalid server");
      const node = await requireViewNode(db, session, nodeId);
      return publicNode(node);
    }
    case "hyn_latest_metric": {
      const nodeId = asString(body.p_node, 64);
      if (!nodeId) throw new RpcError("node required");
      await requireViewNode(db, session, nodeId);
      const cutoff = hoursAgoIso(TELEMETRY_HOURS);
      const row = await db.prepare(
        "SELECT * FROM metrics WHERE node_id = ? AND ts >= ? ORDER BY ts DESC LIMIT 1",
      ).bind(nodeId, cutoff).first<Record<string, unknown>>();
      return row ? hydrateMetric(row) : null;
    }
    case "hyn_list_speedtests": {
      const nodeId = asString(body.p_node, 64);
      if (!nodeId) throw new RpcError("node required");
      await requireViewNode(db, session, nodeId);
      const cutoff = hoursAgoIso(TELEMETRY_HOURS);
      const rows = await db.prepare(
        "SELECT * FROM speedtests WHERE node_id = ? AND ts >= ? ORDER BY ts DESC LIMIT 14",
      ).bind(nodeId, cutoff).all();
      return rows.results;
    }
    case "hyn_list_alerts": {
      const nodeId = asString(body.p_node, 64);
      if (!nodeId) throw new RpcError("node required");
      await requireViewNode(db, session, nodeId);
      const cutoff = hoursAgoIso(TELEMETRY_HOURS);
      const rows = await db.prepare(
        "SELECT * FROM alert_events WHERE node_id = ? AND ts >= ? ORDER BY ts DESC LIMIT 8",
      ).bind(nodeId, cutoff).all();
      return rows.results.map((row) => ({ ...row, resolved: row.resolved === 1 }));
    }
    case "hyn_profile":
      return profile;
    default:
      return handlePortalMore(db, session, name, body);
  }
}

function hydrateMetric(row: Record<string, unknown>) {
  return {
    ...row,
    sensors: typeof row.sensors === "string" ? JSON.parse(row.sensors) : row.sensors,
    payload: typeof row.payload === "string" ? JSON.parse(row.payload) : row.payload,
  };
}
