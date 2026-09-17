import { NextResponse } from "next/server";
import { storeRpc } from "@/lib/hyn-data";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { fetchFleet } from "@/lib/relayer-provider";
import { requestedRelayer } from "@/lib/relayer-request";
import { portalOrigin } from "@/lib/portal-origin";

export const runtime = "nodejs";
const headers = { "Cache-Control": "private, no-store" };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function POST(request: Request) {
  const fail = (error: string, status: number) =>
    NextResponse.json({ error }, { status, headers });
  // Cookie-authenticated JSON writes must come from this portal's origin.
  if (request.headers.get("origin") !== portalOrigin(request))
    return fail("Refresh this page before submitting a request.", 403);
  if (!isSupabaseConfigured)
    return fail("Portal connection is not configured.", 503);
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return fail("Sign in to request a relayer.", 401);
  const { data: active, error: activeError } =
    await storeRpc("hyn_is_active");
  if (activeError || active !== true)
    return fail("An active account is required.", 403);
  const { data: canRequest, error: roleError } = await storeRpc("hyn_can_monitor");
  if (roleError || canRequest !== true) return fail("A Monitor or Super admin role is required to request relayers.", 403);
  let body;
  try {
    body = await request.json();
  } catch {
    return fail("Invalid request.", 400);
  }
  if (!body || typeof body !== "object") return fail("Invalid request.", 400);
  let result;
  if (
    body.action === "cancel" &&
    typeof body.requestId === "string" &&
    UUID.test(body.requestId)
  ) {
    result = await storeRpc("hyn_cancel_relayer_request", {
      p_request_id: body.requestId,
    });
  } else if (
    body.action === "request" &&
    typeof body.query === "string" &&
    body.query.trim() &&
    body.query.length <= 100
  ) {
    let fleet;
    try {
      fleet = await fetchFleet();
    } catch {
      return fail("Highway search is unavailable. Try again shortly.", 502);
    }
    let relayer;
    try {
      relayer = requestedRelayer(fleet.relayers, body.query);
    } catch (error) {
      return fail(
        error instanceof Error ? error.message : "Relayer not found.",
        400,
      );
    }
    // The caller cannot choose an owner or submit a name trusted by the portal.
    result = await storeRpc("hyn_request_relayer", {
      p_relayer_id: relayer.id,
      p_relayer_name: relayer.name.slice(0, 160),
    });
  } else return fail("Enter your Highway name or numeric relayer ID.", 400);
  if (result.error) {
    if (result.error.code === "PGRST202" || result.error.code === "42883")
      return fail(
        "Relayer requests are not enabled yet. Ask an administrator to finish portal setup.",
        503,
      );
    return fail(result.error.message, 400);
  }
  return NextResponse.json({ ok: true }, { headers });
}
