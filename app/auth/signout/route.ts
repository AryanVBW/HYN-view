import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { portalOrigin } from "@/lib/portal-origin";

// POST-only: a GET sign-out can be triggered by any image tag or prefetch,
// which would log people out at random.
export async function POST(request: NextRequest) {
  const origin = portalOrigin(request);
  if (isSupabaseConfigured) {
    const supabase = await createClient();
    await supabase.auth.signOut();
  }
  return NextResponse.redirect(`${origin}/signin`, { status: 303 });
}
