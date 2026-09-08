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
  const requestedOwner = new URL(request.url).searchParams.get("owner");
  const owner = requestedOwner ?? auth.user.id;
  if (owner !== auth.user.id) {
    const { data: admin, error } = await supabase.rpc("hyn_can_view_dashboard", { p_owner: owner });
    if (error || admin !== true)
      return fail("You cannot view another account's relayers.", 403);
  }
  // Never accept a relayer ID from a customer as authorization. Even an admin
  // preview is scoped to the assignments of the selected account.
  const { data, error } = await supabase
    .from("relayer_assignments")
    .select("id,owner,relayer_id,relayer_name,created_at")
    .eq("owner", owner)
    .order("created_at");
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
