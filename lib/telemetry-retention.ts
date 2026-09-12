import { createClient } from "@supabase/supabase-js";
import { SUPABASE_URL } from "@/lib/supabase/config";

export async function pruneTelemetry() {
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
