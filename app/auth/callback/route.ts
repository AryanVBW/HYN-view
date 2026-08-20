import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { normalizeInternalPath } from "@/lib/legal-consent";

// Where Google (and the email confirmation link) come back to. Exchanges the
// one-time code for a session cookie, then forwards the user on.
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const next = normalizeInternalPath(searchParams.get("next"));
  const oauthError = searchParams.get("error_description") ?? searchParams.get("error");

  if (oauthError) {
    return NextResponse.redirect(
      `${origin}/signin?error=${encodeURIComponent(oauthError)}`
    );
  }

  if (!isSupabaseConfigured) {
    return NextResponse.redirect(
      `${origin}/signin?error=${encodeURIComponent("Supabase is not configured")}`
    );
  }

  if (!code) {
    return NextResponse.redirect(
      `${origin}/signin?error=${encodeURIComponent("No authorization code returned")}`
    );
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    return NextResponse.redirect(
      `${origin}/signin?error=${encodeURIComponent(error.message)}`
    );
  }

  return NextResponse.redirect(`${origin}${next}`);
}
