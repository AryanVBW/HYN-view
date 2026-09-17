import { redirect } from "next/navigation";
import { permissions } from "@/lib/permissions";
import { isD1Data, storeRpc } from "@/lib/hyn-data";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const metadata = { title: "Data usage / HYN-view" };

export default async function UsagePage() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/signin?next=%2Fusage");
  // Keep old bookmarks working while reports now live in the admin dashboard.
  const { data: profile, error } = isD1Data()
    ? await storeRpc<{ role?: string; status?: string }>("hyn_profile")
    : await supabase.from("profiles").select("role,status").eq("id", auth.user.id).maybeSingle();
  redirect(!error && profile?.status === "active" && permissions(profile.role).canAdmin ? "/admin?tab=bandwidth" : "/dashboard");
}
