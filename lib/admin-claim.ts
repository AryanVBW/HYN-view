import type { SupabaseClient } from "@supabase/supabase-js";

// Asks the database whether this signed-in user may be an administrator.
//
// The decision is made entirely by hyn_claim_env_admin, which checks the
// caller's own verified email in auth.users against public.admin_allowlist — a
// table with RLS on and no policies, so no browser session can read or write it.
//
// This deliberately does NOT pre-filter against an environment variable. The
// previous version did, and that made the app the only thing enforcing who
// could be an admin: the RPC is granted to `authenticated`, so any signed-in
// user could call it directly with the public anon key and their own address and
// be promoted. A check in a Server Component is not a boundary when the endpoint
// it guards is reachable without it.
//
// A refused claim is the normal case (every non-admin signs in too), so the RPC
// returns a status rather than raising, and nothing here treats it as an error.
export async function claimAdminIfAllowed(
  supabase: SupabaseClient,
  email: string | null | undefined
) {
  if (!email) return;
  await supabase.rpc("hyn_claim_env_admin", { p_caller_email: email });
}
