import { activateIfPauseElapsed, loadProfile, nodeByToken, parseConfig, requireLiveNode } from "./access.ts";
import { recordBandwidth } from "./bandwidth.ts";
import {
  asFiniteNumber,
  asRecord,
  asString,
  hoursAgoIso,
  jsonBytes,
  nestNum,
  nestStr,
  nowIso,
  parseIso,
  path,
  randomHex,
  sha256Hex,
  userCode,
  userCodeHash,
  utf8Bytes,
  uuid,
} from "./crypto.ts";
import { RpcError } from "./http.ts";
import type { NodeRow } from "./types.ts";

const INGEST_MAX = 65_536;
const STORED_MAX = 16_384;
const SNAPSHOT_MAX = 256 * 1024;
const TELEMETRY_HOURS = 48;

function token(body: Record<string, unknown>): string {
  const value = asString(body.p_node_token, 200);
  if (!value) throw new RpcError("invalid node token", 401);
  return value;
}

async function pruneTelemetry(db: D1Database, batch = 5000): Promise<number> {
  const cutoff = hoursAgoIso(TELEMETRY_HOURS);
  const result = await db.batch([
    db.prepare("DELETE FROM metrics WHERE id IN (SELECT id FROM metrics WHERE ts < ? LIMIT ?)").bind(cutoff, batch),
    db.prepare("DELETE FROM speedtests WHERE id IN (SELECT id FROM speedtests WHERE ts < ? LIMIT ?)").bind(cutoff, batch),
    db.prepare("DELETE FROM alert_events WHERE id IN (SELECT id FROM alert_events WHERE ts < ? LIMIT ?)").bind(cutoff, batch),
    db.prepare("DELETE FROM transient_snapshots WHERE expires_at < ?").bind(nowIso()),
    db.prepare("DELETE FROM device_codes WHERE expires_at < ? AND token_claimed = 1").bind(nowIso()),
  ]);
  return result.reduce((sum, row) => sum + (row.meta.changes ?? 0), 0);
}

async function maybePrune(db: D1Database, node: NodeRow): Promise<void> {
  const due = !node.last_telemetry_prune_at
    || Date.parse(node.last_telemetry_prune_at) < Date.now() - 5 * 60_000;
  if (!due) return;
  await pruneTelemetry(db, 100);
  await db.prepare("UPDATE nodes SET last_telemetry_prune_at = ? WHERE id = ?").bind(nowIso(), node.id).run();
}

async function heartbeat(db: D1Database, body: Record<string, unknown>, local = false) {
  const hash = await sha256Hex(token(body));
  const found = await nodeByToken(db, hash);
  if (!found) throw new RpcError("invalid node token", 401);
  if (found.revoked) throw new RpcError("node revoked", 401);
  const node = await activateIfPauseElapsed(db, found);
  const version = asString(body.p_agent_version, 50);
  const at = nowIso();
  await db.prepare(
    `UPDATE nodes SET last_heartbeat_at = ?, agent_version = COALESCE(?, agent_version),
     telemetry_mode = CASE WHEN ? = 1 THEN 'local' ELSE telemetry_mode END
     WHERE id = ?`,
  ).bind(at, version, local ? 1 : 0, node.id).run();
  if (local) {
    const owner = await loadProfile(db, node.owner);
    if (owner?.status !== "active") throw new RpcError("account suspended", 403);
  }
  return { status: "ok", node_id: node.id, node_status: node.status, heartbeat_at: at };
}

function dropPath(payload: Record<string, unknown>, dotted: string): void {
  const keys = dotted.split(".");
  let cur: unknown = payload;
  for (let i = 0; i < keys.length - 1; i++) {
    const rec = asRecord(cur);
    if (!rec) return;
    cur = rec[keys[i]!];
  }
  const rec = asRecord(cur);
  if (rec) delete rec[keys[keys.length - 1]!];
}

function trimPayload(payload: Record<string, unknown>): Record<string, unknown> {
  const copy = structuredClone(payload);
  if (jsonBytes(copy) > STORED_MAX) copy.monitoring_truncated = true;
  for (const dotted of [
    "highway.units", "disk.mounts", "processes.top", "cpu.cores_mhz",
    "power.rails", "sensors", "latency_us", "alerts",
  ]) {
    if (jsonBytes(copy) <= STORED_MAX) break;
    dropPath(copy, dotted);
  }
  if (jsonBytes(copy) > STORED_MAX) throw new RpcError("stored monitoring payload exceeds 16 KiB");
  return copy;
}

async function ingest(db: D1Database, body: Record<string, unknown>) {
  const node = await requireLiveNode(db, await sha256Hex(token(body)));
  const raw = body.p_payload;
  const payload = asRecord(raw);
  if (!payload) throw new RpcError("monitoring payload must be an object");
  if (jsonBytes(payload) > INGEST_MAX) throw new RpcError("monitoring payload exceeds 64 KiB");
  const cutoff = hoursAgoIso(TELEMETRY_HOURS);
  const future = new Date(Date.now() + 5 * 60_000).toISOString();
  const ts = parseIso(payload.ts, nowIso());
  if (!ts || ts > future) throw new RpcError("monitoring timestamp is in the future or invalid");
  if (ts < cutoff) {
    return { status: "ok", node_id: node.id, discarded: "expired", alerts_written: 0 };
  }
  const stored = trimPayload(payload);
  const inserted = await db.prepare(
    `INSERT OR IGNORE INTO metrics (
      node_id, ts, cpu_pct, cpu_temp_c, cpu_mhz, cpu_model, cpu_steal, cpu_iowait, cpu_cores,
      load1, mem_pct, mem_total, mem_used, swap_used, disk_pct, uptime_s,
      net_iface, net_rx_bps, net_tx_bps, net_retrans_pm, latency_ms,
      net_link_mbps, psi_cpu, psi_mem, psi_io, tcp_estab, conntrack_pct, proc_count,
      sensors, payload
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
  ).bind(
    node.id, ts,
    nestNum(stored, ["cpu", "pct"]), nestNum(stored, ["cpu", "temp_c"]), nestNum(stored, ["cpu", "mhz"]),
    nestStr(stored, ["cpu", "model"], 120), nestNum(stored, ["cpu", "steal"]), nestNum(stored, ["cpu", "iowait"]),
    nestNum(stored, ["cpu", "cores"]),
    asFiniteNumber(path(stored, ["load", "0"]) ?? (Array.isArray(stored.load) ? stored.load[0] : null)),
    nestNum(stored, ["memory", "pct"]), nestNum(stored, ["memory", "total"]), nestNum(stored, ["memory", "used"]),
    nestNum(stored, ["memory", "swap_used"]), nestNum(stored, ["disk", "pct"]), nestNum(stored, ["uptime_s"]),
    nestStr(stored, ["network", "iface"], 64), nestNum(stored, ["network", "rx_bps"]), nestNum(stored, ["network", "tx_bps"]),
    nestNum(stored, ["network", "retrans_permille"]), nestNum(stored, ["latency_ms"]),
    nestNum(stored, ["network", "link_mbps"]), nestNum(stored, ["psi", "cpu"]), nestNum(stored, ["psi", "memory"]),
    nestNum(stored, ["psi", "io"]), nestNum(stored, ["network", "tcp_estab"]), nestNum(stored, ["network", "conntrack_pct"]),
    nestNum(stored, ["processes", "count"]),
    stored.sensors ? JSON.stringify(stored.sensors) : null,
    JSON.stringify(stored),
  ).run();
  if ((inserted.meta.changes ?? 0) === 0) {
    return { status: "ok", node_id: node.id, duplicate: true, alerts_written: 0 };
  }
  const speed = asRecord(stored.speedtest);
  const speedTs = speed ? Number(speed.ts) : 0;
  if (speed && speedTs > 0) {
    const speedIso = new Date(speedTs * (speedTs < 1e12 ? 1000 : 1)).toISOString();
    if (speedIso >= cutoff && speedIso <= future) {
      await db.prepare(
        `INSERT OR IGNORE INTO speedtests (node_id, ts, down_bps, up_bps, latency_ms, note)
         VALUES (?, ?, ?, ?, ?, ?)`,
      ).bind(
        node.id, speedIso, asFiniteNumber(speed.down_bps), asFiniteNumber(speed.up_bps),
        Math.round((asFiniteNumber(speed.latency_us) ?? 0) / 10) / 100,
        asString(speed.note, 200),
      ).run();
    }
  }
  const alerts = Array.isArray(payload.alerts) ? payload.alerts : [];
  let alertsWritten = 0;
  for (const item of alerts) {
    const alert = asRecord(item);
    if (!alert) continue;
    const eventTs = parseIso(alert.ts, ts);
    if (!eventTs || eventTs < cutoff || eventTs > future) continue;
    const severity = alert.severity === "warn" || alert.severity === "crit" ? alert.severity : "info";
    const message = (asString(alert.message, 500) ?? "alert");
    const resolved = alert.resolved === true || alert.resolved === "true" ? 1 : 0;
    const fingerprint = await sha256Hex(JSON.stringify([
      Math.floor(Date.parse(eventTs) / 1000), alert.rule, severity, message, Boolean(resolved),
    ]));
    const wrote = await db.prepare(
      `INSERT OR IGNORE INTO alert_events (node_id, ts, rule, severity, message, resolved, event_fingerprint)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    ).bind(node.id, eventTs, asString(alert.rule, 80), severity, message, resolved, fingerprint).run();
    alertsWritten += wrote.meta.changes ?? 0;
  }
  const host = asString(payload.host, 200);
  const version = asString(payload.agent_version, 50);
  await db.prepare(
    `UPDATE nodes SET
       last_seen_at = CASE WHEN last_seen_at IS NULL OR last_seen_at < ? THEN ? ELSE last_seen_at END,
       last_metric_at = CASE WHEN last_metric_at IS NULL OR last_metric_at < ? THEN ? ELSE last_metric_at END,
       agent_version = COALESCE(?, agent_version),
       hostname = COALESCE(?, hostname),
       telemetry_mode = 'cloud'
     WHERE id = ?`,
  ).bind(ts, ts < nowIso() ? ts : nowIso(), ts, ts, version, host, node.id).run();
  await maybePrune(db, node);
  return { status: "ok", node_id: node.id, alerts_written: alertsWritten };
}

async function templates(db: D1Database): Promise<{ alert: string; report: string }> {
  const rows = await db.prepare("SELECT template_key, html_template FROM notification_templates").all<{
    template_key: string; html_template: string;
  }>();
  const map = Object.fromEntries(rows.results.map((r) => [r.template_key, r.html_template]));
  const b64 = (html: string) => btoa(unescape(encodeURIComponent(html)));
  return { alert: b64(map.alert ?? ""), report: b64(map.report ?? "") };
}

async function fetchConfig(db: D1Database, body: Record<string, unknown>, local = false) {
  const beat = await heartbeat(db, body, local);
  const node = await nodeByToken(db, await sha256Hex(token(body)));
  if (!node) throw new RpcError("invalid node token", 401);
  await db.prepare("UPDATE nodes SET last_config_pull_at = ? WHERE id = ?").bind(nowIso(), node.id).run();
  if (local) {
    return {
      node_id: node.id,
      node_status: node.status,
      status_reason: node.status_reason,
      config: parseConfig(node.config),
    };
  }
  const html = await templates(db);
  return {
    status: "ok",
    node_id: node.id,
    node_name: node.name,
    node_status: node.status,
    paused_until: node.paused_until,
    status_reason: node.status_reason,
    config: parseConfig(node.config),
    heartbeat_at: beat.heartbeat_at,
    watchdog: { created: false, state: "stopped" },
    alert_template_b64: html.alert,
    report_template_b64: html.report,
  };
}

async function deviceStart(db: D1Database, body: Record<string, unknown>, pepper: string) {
  await db.prepare("DELETE FROM device_codes WHERE expires_at < ?").bind(nowIso()).run();
  const expires = new Date(Date.now() + 15 * 60_000).toISOString();
  let user = "";
  let device = "";
  for (let i = 0; i < 5; i++) {
    user = userCode();
    device = randomHex(32);
    const userHash = await userCodeHash(user, pepper);
    const exists = await db.prepare("SELECT 1 AS ok FROM device_codes WHERE user_code_hash = ?")
      .bind(userHash).first();
    if (exists) continue;
    try {
      await db.prepare(
        `INSERT INTO device_codes (
          id, user_code_hash, device_code_hash, hostname, os, agent_version, created_at, expires_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        uuid(), userHash, await sha256Hex(device),
        asString(body.p_hostname, 200), asString(body.p_os, 200), asString(body.p_agent_version, 50),
        nowIso(), expires,
      ).run();
      return { user_code: user, device_code: device, expires_at: expires, interval: 5 };
    } catch {
      continue;
    }
  }
  throw new RpcError("could not allocate a pairing code, try again");
}

async function devicePoll(db: D1Database, body: Record<string, unknown>) {
  const code = asString(body.p_device_code, 128);
  if (!code) return { status: "not_found" };
  const row = await db.prepare("SELECT * FROM device_codes WHERE device_code_hash = ?")
    .bind(await sha256Hex(code))
    .first<{
      id: string; expires_at: string; node_id: string | null; token_claimed: number;
    }>();
  if (!row) return { status: "not_found" };
  if (row.expires_at <= nowIso()) return { status: "expired" };
  if (!row.node_id) return { status: "pending", interval: 5 };
  if (row.token_claimed) return { status: "claimed" };
  const nodeToken = randomHex(32);
  const hash = await sha256Hex(nodeToken);
  await db.batch([
    db.prepare("UPDATE nodes SET token_hash = ? WHERE id = ?").bind(hash, row.node_id),
    db.prepare("UPDATE device_codes SET token_claimed = 1, node_token_hash = ? WHERE id = ?").bind(hash, row.id),
  ]);
  const node = await db.prepare("SELECT name FROM nodes WHERE id = ?").bind(row.node_id).first<{ name: string }>();
  return { status: "approved", node_id: row.node_id, node_token: nodeToken, node_name: node?.name ?? "node" };
}

async function claimCommand(db: D1Database, body: Record<string, unknown>) {
  const node = await requireLiveNode(db, await sha256Hex(token(body)));
  if (node.is_demo) throw new RpcError("invalid or inactive node token", 401);
  const now = nowIso();
  const command = await db.prepare(
    `SELECT * FROM node_commands
     WHERE node_id = ? AND command IN ('update', 'sync')
       AND (status = 'queued' OR (status = 'running' AND (lease_expires_at IS NULL OR lease_expires_at <= ?)))
     ORDER BY requested_at LIMIT 1`,
  ).bind(node.id, now).first<{ id: string; command: string; stage: string }>();
  if (!command) return { status: "idle" };
  const message = command.command === "sync"
    ? "Machine accepted the synchronization request"
    : "Machine accepted the update request";
  const lease = new Date(Date.now() + 20 * 60_000).toISOString();
  await db.prepare(
    `UPDATE node_commands SET status = 'running', stage = 'accepted', message = ?,
     started_at = COALESCE(started_at, ?), updated_at = ?, lease_expires_at = ?
     WHERE id = ?`,
  ).bind(message, now, now, lease, command.id).run();
  return { status: "command", id: command.id, action: command.command, stage: "accepted" };
}

async function reportCommand(db: D1Database, body: Record<string, unknown>) {
  const node = await requireLiveNode(db, await sha256Hex(token(body)));
  const id = asString(body.p_command_id, 64);
  const status = asString(body.p_status, 20);
  const stage = asString(body.p_stage, 40) ?? "running";
  if (!id || !status) throw new RpcError("invalid command report");
  if (!["running", "succeeded", "failed"].includes(status)) throw new RpcError("invalid command status");
  const now = nowIso();
  const terminal = status === "succeeded" || status === "failed";
  const updated = await db.prepare(
    `UPDATE node_commands SET status = ?, stage = ?, message = ?,
     target_version = COALESCE(?, target_version), result_version = COALESCE(?, result_version),
     updated_at = ?, finished_at = CASE WHEN ? = 1 THEN ? ELSE finished_at END
     WHERE id = ? AND node_id = ? AND status = 'running'`,
  ).bind(
    status, stage, asString(body.p_message, 300) ?? "",
    asString(body.p_target_version, 50), asString(body.p_result_version, 50),
    now, terminal ? 1 : 0, now, id, node.id,
  ).run();
  if ((updated.meta.changes ?? 0) === 0) throw new RpcError("active command not found");
  return { status, stage, updated_at: now };
}

async function reportNotification(db: D1Database, body: Record<string, unknown>) {
  const node = await requireLiveNode(db, await sha256Hex(token(body)));
  const events = Array.isArray(body.p_events) ? body.p_events : [];
  let written = 0;
  for (const item of events) {
    const event = asRecord(item);
    if (!event) continue;
    await db.prepare(
      `INSERT INTO notification_log (node_id, owner, ts, kind, target, severity, subject, status, error, category)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      node.id, node.owner, parseIso(event.ts, nowIso()),
      asString(event.kind, 40) ?? "unknown", asString(event.target, 200),
      event.severity === "warn" || event.severity === "crit" ? event.severity : "info",
      asString(event.subject, 300),
      event.status === "sent" || event.status === "skipped" ? event.status : "failed",
      asString(event.error, 500),
      event.category === "alert" || event.category === "report" || event.category === "test" ? event.category : "other",
    ).run();
    written += 1;
  }
  return { status: "ok", written };
}

async function queueWebNotification(db: D1Database, body: Record<string, unknown>) {
  const node = await requireLiveNode(db, await sha256Hex(token(body)));
  const event = asRecord(body.p_event) ?? {};
  const id = uuid();
  await db.prepare(
    "INSERT INTO web_notification_jobs (id, node_id, event, status, created_at) VALUES (?, ?, ?, 'queued', ?)",
  ).bind(id, node.id, JSON.stringify(event), nowIso()).run();
  return { status: "ok", id };
}

async function recordNodeBandwidth(db: D1Database, body: Record<string, unknown>) {
  const node = await requireLiveNode(db, await sha256Hex(token(body)));
  const iface = asString(body.p_iface, 64);
  const boot = asString(body.p_boot_id, 64);
  const rx = asFiniteNumber(body.p_rx);
  const tx = asFiniteNumber(body.p_tx);
  if (!iface || !/^[a-zA-Z0-9_.:-]{1,64}$/.test(iface)
    || !boot || !/^[a-zA-Z0-9-]{1,64}$/.test(boot)
    || rx == null || tx == null || rx < 0 || tx < 0 || !Number.isInteger(rx) || !Number.isInteger(tx)) {
    throw new RpcError("invalid network counters");
  }
  return recordBandwidth(db, node.id, iface, boot, BigInt(rx), BigInt(tx));
}

async function transientSnapshot(db: D1Database, body: Record<string, unknown>) {
  const payload = asRecord(body.p_payload);
  if (!payload) throw new RpcError("snapshot must be an object");
  if (utf8Bytes(JSON.stringify(payload)) > SNAPSHOT_MAX) throw new RpcError("snapshot exceeds 256 KiB", 413);
  const beat = await heartbeat(db, body, true);
  if (beat.node_status !== "active") throw new RpcError(`node ${beat.node_status}`, 403);
  const expires = new Date(Date.now() + 5 * 60_000).toISOString();
  await db.prepare(
    `INSERT INTO transient_snapshots (node_id, payload, expires_at) VALUES (?, ?, ?)
     ON CONFLICT (node_id) DO UPDATE SET payload = excluded.payload, expires_at = excluded.expires_at`,
  ).bind(beat.node_id, JSON.stringify(payload), expires).run();
  return { status: 200, node_id: beat.node_id, storage: "transient", expires_in: 300 };
}

export async function handleAgentRpc(
  db: D1Database,
  name: string,
  body: Record<string, unknown>,
  pepper: string,
): Promise<unknown> {
  switch (name) {
    case "hyn_device_start": return deviceStart(db, body, pepper);
    case "hyn_device_poll": return devicePoll(db, body);
    case "hyn_heartbeat": return heartbeat(db, body, false);
    case "hyn_local_heartbeat": return heartbeat(db, body, true);
    case "hyn_ingest": return ingest(db, body);
    case "hyn_fetch_config": return fetchConfig(db, body, false);
    case "hyn_fetch_local_config": return fetchConfig(db, body, true);
    case "hyn_record_bandwidth": return recordNodeBandwidth(db, body);
    case "hyn_claim_node_command": return claimCommand(db, body);
    case "hyn_report_node_command": return reportCommand(db, body);
    case "hyn_report_notification": return reportNotification(db, body);
    case "hyn_queue_web_notification": return queueWebNotification(db, body);
    case "hyn_transient_snapshot": return transientSnapshot(db, body);
    case "hyn_prune_telemetry": return { deleted: await pruneTelemetry(db, Number(body.p_batch) || 5000) };
    default: throw new RpcError("unknown agent action", 404);
  }
}

export { pruneTelemetry };
