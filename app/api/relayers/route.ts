import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { readAssignedRelayers } from "@/lib/relayer-data";
import type { RelayerAssignment } from "@/lib/relayer";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;
const headers = { "Cache-Control": "private, no-store" };
export async function GET(request: Request) {
  const fail = (error: string, status: number) =>
    NextResponse.json({ error, readings: [] }, { status, headers });
  if (!isSupabaseConfigured)
    return fail("Portal connection is not configured.", 503);
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return fail("Sign in to view your relayers.", 401);
  const { data: active, error: activeError } =
    await supabase.rpc("hyn_is_active");
  if (activeError || active !== true)
    return fail("An active account is required.", 403);
  const params = new URL(request.url).searchParams;
  if (params.has("node")) {
    const nodeId = params.get("node") ?? "";
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(nodeId)) {
      return fail("Select a valid server.", 400);
    }
    // The RPC checks server access and returns at most its one linked assignment.
    // Account and relayer query parameters cannot change this scope.
    const { data, error } = await supabase.rpc("hyn_node_relayer", { p_node: nodeId });
    if (error) return error.code === "42501"
      ? fail("This server is unavailable or you no longer have access.", 404)
      : fail("Server relay links are unavailable. Ask a Super admin to finish portal setup.", 503);
    const assignments = (data ?? []) as RelayerAssignment[];
    const dashboard = assignments.length ? await readAssignedRelayers(assignments) : { readings: [], error: null };
    return NextResponse.json(dashboard, { headers });
  }
  const requestedOwner = new URL(request.url).searchParams.get("owner");
  const owner = requestedOwner ?? auth.user.id;
  const all = owner === "all";
  if (all) {
    const {data: admin, error} = await supabase.rpc("hyn_is_admin");
    if (error || admin !== true) return fail("An Admin or Super admin account is required to view all relayers.",403);
  } else if (owner !== auth.user.id) {
    const { data: admin, error } = await supabase.rpc("hyn_can_view_dashboard", { p_owner: owner });
    if (error || admin !== true)
      return fail("You cannot view another account's relayers.", 403);
  }
  // Every scope reads authorized assignment rows through RLS. A URL relayer ID
  // only chooses which of those assignments to enrich with provider readings.
  let assignments = supabase.from("relayer_assignments")
    .select("id,owner,relayer_id,relayer_name,created_at");
  if (!all) assignments = assignments.eq("owner",owner);
  const {data, error} = await assignments.order("created_at");
  if (error)
    return fail(
      "Relayer assignments could not be loaded. Ask an administrator to apply the relayer database migration.",
      503,
    );
  const dashboard = await readAssignedRelayers(
      (data ?? []) as RelayerAssignment[],
      Number(new URL(request.url).searchParams.get("relayer")),
  );
  if (!requestedOwner) {
    const [requests,admin,monitor] = await Promise.all([
      supabase.from("relayer_requests").select("id,relayer_id,relayer_name,status,created_at")
        .eq("owner",owner).in("status",["pending","rejected"]).order("created_at",{ascending:false}).limit(50),
      supabase.rpc("hyn_is_super_admin"),
      supabase.rpc("hyn_can_monitor"),
    ]);
    dashboard.canRequest = monitor.data === true;
    dashboard.requests = requests.data ?? [];
    dashboard.requestsError = requests.error ? "Relayer requests are not available yet. Ask an administrator to finish portal setup." : null;
    dashboard.manageHref = admin.data === true ? `/admin?tab=client&client=${owner}` : null;
  }
  return NextResponse.json(dashboard,{headers});
}
