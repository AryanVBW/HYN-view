import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { heartbeatTime, monitoringRevision, type MonitoringState } from "@/lib/monitoring-state";
import { isD1Data, userDataRpc } from "@/lib/hyn-data";

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
    if (isD1Data()) {
      const profile = await userDataRpc<{status?: string}>("hyn_profile");
      if (profile.error) return result({message: "Monitoring temporarily unavailable"}, 503);
      if (profile.data?.status !== "active") return result({message: "Account unavailable"}, 403);
      const node = await userDataRpc<MonitoringState>("hyn_node_freshness", {p_node: id});
      if (node.error) {
        const status = /unavailable|access/i.test(node.error.message) ? 404 : 503;
        return result({message: node.error.message}, status);
      }
      if (!node.data) return result({message: "Server unavailable"}, 404);
      return result({nodeId: node.data.id, revision: monitoringRevision(node.data), heartbeatAt: heartbeatTime(node.data)});
    }
    const {data: profile, error: profileError} = await db.from("profiles").select("status")
      .eq("id", auth.user.id).maybeSingle();
    if (profileError) return result({message: "Monitoring temporarily unavailable"}, 503);
    if (profile?.status !== "active") return result({message: "Account unavailable"}, 403);
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
