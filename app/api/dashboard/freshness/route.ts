import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { heartbeatTime, monitoringRevision, type MonitoringState } from "@/lib/monitoring-state";

export const dynamic = "force-dynamic";

function result(body: unknown, status = 200) {
  return NextResponse.json(body, {status, headers: {"Cache-Control": "private, no-store"}});
}

export async function GET(request: Request) {
  const id = new URL(request.url).searchParams.get("node");
  if (!id || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
    return result({message: "Invalid server"}, 400);
  }
  try {
    const db = await createClient();
    const {data: auth, error: authError} = await db.auth.getUser();
    if (authError || !auth.user) return result({message: "Sign in required"}, 401);
    const {data: profile, error: profileError} = await db.from("profiles").select("status")
      .eq("id", auth.user.id).maybeSingle();
    if (profileError) return result({message: "Monitoring temporarily unavailable"}, 503);
    if (profile?.status !== "active") return result({message: "Account unavailable"}, 403);
    // User-session RLS checks current ownership/shared access on every poll.
    const {data, error} = await db.from("nodes")
      .select("id,status,revoked,telemetry_mode,last_metric_at,last_seen_at,last_heartbeat_at,last_config_pull_at,agent_version,config")
      .eq("id", id).eq("revoked", false).maybeSingle();
    if (error) return result({message: "Monitoring temporarily unavailable"}, 503);
    if (!data) return result({message: "Server unavailable"}, 404);
    const node = data as MonitoringState;
    return result({nodeId: node.id, revision: monitoringRevision(node), heartbeatAt: heartbeatTime(node)});
  } catch {
    return result({message: "Monitoring temporarily unavailable"}, 503);
  }
}
