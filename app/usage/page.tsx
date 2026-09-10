import { redirect } from "next/navigation";
import { permissions } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const metadata = { title: "Data usage / HYN-view" };

export default async function UsagePage() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/signin?next=%2Fusage");
  // Keep old bookmarks working while reports now live in the admin dashboard.
  const { data: profile, error } = await supabase.from("profiles").select("role,status").eq("id", auth.user.id).maybeSingle();
  redirect(!error && profile?.status === "active" && permissions(profile.role).canAdmin ? "/admin?tab=bandwidth" : "/dashboard");
}
