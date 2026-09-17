import { createClient } from "@supabase/supabase-js";
import { SUPABASE_URL } from "@/lib/supabase/config";

async function pruneD1() {
  const base = (process.env.HYN_DATA_API_URL ?? "").replace(/\/$/, "");
  const key = process.env.HYN_DATA_SERVICE_KEY ?? "";
  if (!base || !key) throw new Error("Telemetry maintenance is not configured");
  let result: Record<string, unknown> = {};
  for (let batch = 0; batch < 4; batch++) {
    const res = await fetch(`${base}/rpc/hyn_prune_telemetry`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
      body: JSON.stringify({ p_batch: 5000 }),
    });
    if (!res.ok) throw new Error("Telemetry maintenance failed");
    result = await res.json() as Record<string, unknown>;
    if (result.has_more !== true) break;
  }
  return result;
}

export async function pruneTelemetry() {
  if ((process.env.HYN_DATA_API_URL ?? "").replace(/\/$/, "")) return pruneD1();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key || !SUPABASE_URL) throw new Error("Telemetry maintenance is not configured");
  const db = createClient(SUPABASE_URL, key, {auth: {persistSession: false, autoRefreshToken: false}});
  // Bound every invocation, even after a long outage. The database also schedules
  // cleanup with pg_cron, so a sleeping web process does not stop retention.
  let result: Record<string, unknown> = {};
  for (let batch = 0; batch < 4; batch++) {
    const {data, error} = await db.rpc("hyn_prune_telemetry", {p_batch: 5000});
    if (error) throw new Error("Telemetry maintenance failed");
    result = data ?? {};
    if (result.has_more !== true) break;
  }
  return result;
}
