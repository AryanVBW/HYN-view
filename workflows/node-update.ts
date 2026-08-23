import { createClient } from "@supabase/supabase-js";
import { FatalError, sleep } from "workflow";

// A legacy agent can have a registry result cached for up to 12 hours. Keeping
// the first rollout command alive for a full day lets it self-bootstrap; agents
// with the command-polling release normally finish within a few minutes.
const UPDATE_TIMEOUT = "24h";

async function expireStuckUpdate(commandId: string) {
  "use step";

  console.log(`[node-update] checking timeout for command ${commandId}`);
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) {
    throw new FatalError("Supabase service credentials are not configured");
  }

  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await supabase
    .from("node_commands")
    .update({
      status: "expired",
      stage: "expired",
      message:
        "The machine did not finish within 24 hours. Run sudo hyn doctor, then try the update again.",
      finished_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      lease_expires_at: null,
    })
    .eq("id", commandId)
    .in("status", ["queued", "running"])
    .select("id,status")
    .maybeSingle();
  if (error) throw error;

  if (data) console.warn(`[node-update] command ${commandId} expired`);
  else console.log(`[node-update] command ${commandId} already reached a terminal state`);
  return data ?? { id: commandId, status: "already-terminal" };
}

export async function monitorNodeUpdate(commandId: string) {
  "use workflow";

  console.log(`[node-update] monitoring command ${commandId}`);
  await sleep(UPDATE_TIMEOUT);
  return expireStuckUpdate(commandId);
}
