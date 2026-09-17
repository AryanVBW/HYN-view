import { NextResponse } from "next/server";
import { start } from "workflow/api";
import { isD1Data, storeRpc } from "@/lib/hyn-data";
import { createClient } from "@/lib/supabase/server";
import { NODE_COMMAND_COLUMNS, normalizeNodeCommand } from "@/lib/node-command";
import { monitorNodeUpdate } from "@/workflows/node-update";

export const runtime = "nodejs";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function authenticatedClient() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  return { supabase, user: auth.user };
}

export async function GET(request: Request) {
  const nodeId = new URL(request.url).searchParams.get("nodeId") ?? "";
  if (!UUID.test(nodeId)) {
    return NextResponse.json({ message: "a valid node id is required" }, { status: 400 });
  }
  const { supabase, user } = await authenticatedClient();
  if (!user) return NextResponse.json({ message: "not authenticated" }, { status: 401 });

  const { data, error } = isD1Data()
    ? await storeRpc("hyn_latest_node_command", { p_node_id: nodeId, p_command: "update" })
    : await supabase
    .from("node_commands")
    .select(NODE_COMMAND_COLUMNS)
    .eq("node_id", nodeId)
    .eq("command", "update")
    .order("requested_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) return NextResponse.json({ message: error.message }, { status: 400 });
  return NextResponse.json({ command: normalizeNodeCommand(data) }, {
    headers: { "Cache-Control": "no-store" },
  });
}

export async function POST(request: Request) {
  const body = await request.json().catch(() => null) as { nodeId?: string } | null;
  const nodeId = body?.nodeId ?? "";
  if (!UUID.test(nodeId)) {
    return NextResponse.json({ message: "a valid node id is required" }, { status: 400 });
  }
  const { supabase, user } = await authenticatedClient();
  if (!user) return NextResponse.json({ message: "not authenticated" }, { status: 401 });

  const { data, error } = await storeRpc("hyn_request_node_command", {
    p_node_id: nodeId,
    p_command: "update",
  });
  if (error) return NextResponse.json({ message: error.message }, { status: 400 });
  const raw = data as Record<string, unknown> | null;
  const command = normalizeNodeCommand(raw);
  if (!command) {
    return NextResponse.json({ message: "the update request returned an invalid response" }, { status: 502 });
  }

  let workflowRunId: string | null = null;
  if (process.env.HYN_ENABLE_WORKFLOW_WATCHDOG === "true" && raw?.created === true) {
    try {
      const run = await start(monitorNodeUpdate, [command.id]);
      workflowRunId = run.runId;
    } catch (workflowError) {
      // The database command remains valid and the agent can still complete it.
      // Log the watchdog failure without turning an accepted update into a UI
      // error or asking the user to create a duplicate command.
      console.error("[node-update] could not start timeout monitor", workflowError);
    }
  }

  return NextResponse.json({ command, workflowRunId }, {
    status: 202,
    headers: { "Cache-Control": "no-store" },
  });
}
