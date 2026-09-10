import Link from "next/link";
import { redirect } from "next/navigation";
import { BandwidthPanel } from "@/components/admin/bandwidth-panel";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const metadata = { title: "Data usage / HYN-view" };

export default async function UsagePage() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/signin?next=%2Fusage");
  // RLS determines this fleet for the current session, including per-node blocks.
  const { data, error } = await supabase.from("nodes").select("id,name,is_demo").eq("revoked", false).eq("is_demo", false).order("name");
  return <main className="container max-w-6xl space-y-6 pb-16 pt-36">
    <Link href="/dashboard" className="text-primary underline">Back to dashboard</Link>
    <h1 className="font-sentient text-4xl">Overall data usage</h1>
    <p className="text-sm leading-7 text-muted-foreground">Combine usage across every server you can access, or inspect one server. Server-to-server transfers can appear on both servers; these totals describe observed interface traffic.</p>
    {error ? <p role="alert">Could not load your servers. Refresh to try again.</p> : <BandwidthPanel nodes={data ?? []} expanded />}
  </main>;
}
