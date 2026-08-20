import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured } from "@/lib/supabase/config";

// POST-only: a GET sign-out can be triggered by any image tag or prefetch,
// which would log people out at random.
export async function POST(request: NextRequest) {
  const { origin } = new URL(request.url);
  if (isSupabaseConfigured) {
    const supabase = await createClient();
    await supabase.auth.signOut();
  }
  return NextResponse.redirect(`${origin}/signin`, { status: 303 });
}
