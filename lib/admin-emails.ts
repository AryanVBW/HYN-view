import type { SupabaseClient } from "@supabase/supabase-js";

// ADMIN_EMAILS is a comma-separated list read server-side only, never exposed
// to the client bundle (no NEXT_PUBLIC_ prefix). If the signed-in user's own
// verified email is on the list, hyn_claim_env_admin promotes them; the RPC
// re-checks the email against auth.users itself; this call only decides
// whether to bother asking.
export async function claimEnvAdminIfListed(supabase: SupabaseClient, email: string | null | undefined) {
  if (!email) return;
  const listed = (process.env.ADMIN_EMAILS ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  if (!listed.includes(email.toLowerCase())) return;
  await supabase.rpc("hyn_claim_env_admin", { p_caller_email: email });
}
