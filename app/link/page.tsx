import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { Logo } from "@/components/logo";
import { LinkForm } from "@/components/link-form";
import { ParticleField } from "@/components/particle-field";
import { DashboardMagicRings } from "@/components/dashboard-magic-rings";
import { isD1Data, userDataRpc } from "@/lib/hyn-data";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Link a server / HYN-view",
  description: "Pair a headless Ubuntu server with your HYN-view dashboard using a one-time code.",
};

export default async function LinkPage() {
  if (!isSupabaseConfigured) {
    return (
      <div className="flex min-h-svh flex-col items-center justify-center px-4 py-16">
        <ParticleField blur="soft" />
        <DashboardMagicRings />
        <div className="terminal-panel w-full max-w-md p-8">
          <p className="section-kicker">// link a server</p>
          <h1 className="mt-2 font-sentient text-2xl text-card-foreground">
            Supabase is not configured
          </h1>
          <p className="mt-4 font-mono text-xs leading-6 text-muted-foreground">
            Device pairing needs a backend. Copy <code>.env.local.example</code> to{" "}
            <code>.env.local</code>, set your project URL and anon key, and apply{" "}
            <code>supabase/schema.sql</code>.
          </p>
        </div>
      </div>
    );
  }

  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/signin?next=%2Flink");

  const { data: canLink } = isD1Data()
    ? await userDataRpc<boolean>("hyn_can_link")
    : await supabase.rpc("hyn_can_link");

  const nodes = isD1Data()
    ? await userDataRpc<Array<{ id: string; is_demo?: boolean; owner?: string }>>("hyn_list_nodes")
    : null;
  const count = isD1Data()
    ? (nodes.data ?? []).filter((row) => !row.is_demo && row.owner === auth.user.id).length
    : ((await supabase.from("nodes").select("id", { count: "exact", head: true }).eq("is_demo", false).eq("owner", auth.user.id)).count ?? 0);

  return (
    <div className="flex min-h-svh flex-col items-center justify-center px-4 py-16">
      <ParticleField blur="soft" />
      <DashboardMagicRings />
      <Link href="/" className="mb-10">
        <Logo className="w-[120px]" />
      </Link>

      <div className="terminal-panel w-full max-w-md p-8">
        <p className="section-kicker text-center">// device pairing</p>
        <h1 className="mt-2 text-center font-sentient text-2xl text-card-foreground">
          Link a server
        </h1>
        <p className="mt-2 text-center font-mono text-xs text-muted-foreground">
          signed in as {auth.user.email}
        </p>

        {canLink === true ? <LinkForm nodeCount={count ?? 0} /> : <p className="mt-6 font-mono text-sm leading-7 text-muted-foreground">Linking needs an active Monitor, Admin or Super admin account. Viewers can view devices shared with them. <Link href="/dashboard" className="text-primary underline">View dashboards</Link></p>}
      </div>
    </div>
  );
}
