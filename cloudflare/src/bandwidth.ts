function utcDay(iso: string): string {
  return iso.slice(0, 10);
}

function nextUtcMidnight(iso: string): string {
  const day = utcDay(iso);
  const next = new Date(`${day}T00:00:00.000Z`);
  next.setUTCDate(next.getUTCDate() + 1);
  return next.toISOString();
}

export type BandwidthResult = { status: "ok" | "ignored" };

export async function recordBandwidth(
  db: D1Database,
  nodeId: string,
  iface: string,
  bootId: string,
  rx: bigint,
  tx: bigint,
  sampledAt = new Date().toISOString(),
): Promise<BandwidthResult> {
  const prev = await db.prepare("SELECT * FROM bandwidth_counters WHERE node_id = ?")
    .bind(nodeId)
    .first<{ iface: string; boot_id: string; rx: string; tx: string; sampled_at: string }>();
  let deltaRx = 0n;
  let deltaTx = 0n;
  let incomplete = false;
  if (!prev || prev.iface !== iface || prev.boot_id !== bootId || rx < BigInt(prev.rx) || tx < BigInt(prev.tx)) {
    incomplete = true;
  } else {
    deltaRx = rx - BigInt(prev.rx);
    deltaTx = tx - BigInt(prev.tx);
  }
  if (prev && prev.iface === iface && prev.boot_id === bootId
    && (rx < BigInt(prev.rx) || tx < BigInt(prev.tx))) {
    const lag = Date.parse(sampledAt) - Date.parse(prev.sampled_at);
    if (lag >= 0 && lag < 30_000) return { status: "ignored" };
  }
  if (prev) {
    const lag = Date.parse(sampledAt) - Date.parse(prev.sampled_at);
    if (lag > 3 * 60_000) incomplete = true;
    if (lag > 7 * 24 * 3600_000) {
      deltaRx = 0n;
      deltaTx = 0n;
    }
  }
  let cursor = deltaRx + deltaTx > 0n && prev ? prev.sampled_at : sampledAt;
  const split = utcDay(cursor) !== utcDay(sampledAt);
  let remainingRx = deltaRx;
  let remainingTx = deltaTx;
  const span = Math.max(1, Date.parse(sampledAt) - Date.parse(prev?.sampled_at ?? sampledAt));
  while (true) {
    const until = Date.parse(nextUtcMidnight(cursor)) < Date.parse(sampledAt)
      ? nextUtcMidnight(cursor)
      : sampledAt;
    const fraction = Date.parse(sampledAt) === Date.parse(cursor) || !prev
      ? 1
      : (Date.parse(until) - Date.parse(cursor)) / span;
    const partRx = until === sampledAt ? remainingRx : BigInt(Math.floor(Number(deltaRx) * fraction));
    const partTx = until === sampledAt ? remainingTx : BigInt(Math.floor(Number(deltaTx) * fraction));
    const day = utcDay(cursor);
    await db.prepare(
      `INSERT INTO bandwidth_daily (node_id, day, ingress_bytes, egress_bytes, samples, incomplete, estimated)
       VALUES (?, ?, ?, ?, 1, ?, ?)
       ON CONFLICT (node_id, day) DO UPDATE SET
         ingress_bytes = CAST(CAST(ingress_bytes AS INTEGER) + CAST(excluded.ingress_bytes AS INTEGER) AS TEXT),
         egress_bytes = CAST(CAST(egress_bytes AS INTEGER) + CAST(excluded.egress_bytes AS INTEGER) AS TEXT),
         samples = samples + 1,
         incomplete = incomplete OR excluded.incomplete,
         estimated = estimated OR excluded.estimated`,
    ).bind(nodeId, day, partRx.toString(), partTx.toString(), incomplete ? 1 : 0, split ? 1 : 0).run();
    if (until === sampledAt) break;
    remainingRx -= partRx;
    remainingTx -= partTx;
    cursor = until;
  }
  await db.prepare(
    `INSERT INTO bandwidth_counters (node_id, iface, boot_id, rx, tx, sampled_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT (node_id) DO UPDATE SET
       iface = excluded.iface, boot_id = excluded.boot_id, rx = excluded.rx, tx = excluded.tx, sampled_at = excluded.sampled_at`,
  ).bind(nodeId, iface, bootId, rx.toString(), tx.toString(), sampledAt).run();
  return { status: "ok" };
}

export function utcDays(days: number, end = new Date()): string[] {
  const out: string[] = [];
  for (let i = 0; i < days; i++) {
    const d = new Date(Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate() - i));
    out.push(d.toISOString().slice(0, 10));
  }
  return out;
}
