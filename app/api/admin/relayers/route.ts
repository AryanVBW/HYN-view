import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { fetchFleet } from "@/lib/relayer-provider";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
const headers = { "Cache-Control": "private, no-store" };
export async function GET(request: Request) {
  const fail = (error: string, status: number) =>
    NextResponse.json({ error, relayers: [] }, { status, headers });
  if (!isSupabaseConfigured)
    return fail("Portal connection is not configured.", 503);
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return fail("Sign in again.", 401);
  const { data: admin, error } = await supabase.rpc("hyn_is_admin");
  if (error || admin !== true)
    return fail("An active administrator account is required.", 403);
  const query = (new URL(request.url).searchParams.get("q") ?? "")
    .trim()
    .toLowerCase();
  if (!query || query.length > 100)
    return NextResponse.json({ relayers: [] }, { headers });
  try {
    const snapshot = await fetchFleet();
    const matches = snapshot.relayers
      .filter(
        (r) => String(r.id) === query || r.name.toLowerCase().includes(query),
      )
      .sort(
        (a, b) =>
          Number(String(b.id) === query) - Number(String(a.id) === query) ||
          a.name.localeCompare(b.name),
      );
    return NextResponse.json(
      {
        relayers: matches
          .slice(0, 30)
          .map((r) => ({ id: r.id, name: r.name, tier: r.tier, city: r.city })),
        total: matches.length,
      },
      { headers },
    );
  } catch {
    return fail("Highway search is unavailable. Try again shortly.", 502);
  }
}
