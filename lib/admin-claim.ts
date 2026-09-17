import { storeRpc } from "@/lib/hyn-data";

// Asks the data plane whether this signed-in user may be an administrator.
//
// The decision is made entirely by hyn_claim_env_admin, which checks the
// caller's own verified email against admin_allowlist. On D1 that table lives
// in Cloudflare; otherwise it is public.admin_allowlist in Postgres, which has
// RLS on and no policies, so no browser session can read or write it.
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
export async function claimAdminIfAllowed(email: string | null | undefined) {
  if (!email) return;
  await storeRpc("hyn_claim_env_admin", { p_caller_email: email });
}
