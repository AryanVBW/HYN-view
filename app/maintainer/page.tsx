import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ShieldAlert } from "lucide-react";
import { FleetMonitor } from "@/components/maintainer/fleet-monitor";
import { ParticleField } from "@/components/particle-field";
import { DashboardMagicRings } from "@/components/dashboard-magic-rings";
import { LiveRefresh } from "@/components/live-refresh";
import { permissions } from "@/lib/permissions";
import { toFleetServers } from "@/lib/fleet-monitor";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";
import { NODE_COLUMNS, type AlertEvent, type Metric, type Node, type Speedtest } from "@/lib/types";

export const metadata: Metadata = {
  title: "Fleet monitor / HYN-view",
  description: "Every linked server in one continuous 24/7 view.",
};

// Live data. Caching it would put stale numbers behind a "now" label, which on a
// 24/7 monitoring page is the one thing that must never happen.
export const dynamic = "force-dynamic";

export default async function MaintainerPage() {
  if (!isSupabaseConfigured) {
    return (
      <Shell>
        <div className="terminal-panel p-8">
          <p className="section-kicker">// not configured</p>
          <h1 className="mt-2 font-sentient text-2xl text-card-foreground">Supabase is not configured</h1>
        </div>
      </Shell>
    );
  }

  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/signin?next=%2Fmaintainer");

  const { data: profile } = await supabase
    .from("profiles").select("role,status").eq("id", auth.user.id).maybeSingle();
  const access = permissions(profile?.role);

  // A courtesy explanation, not the boundary: the RLS policies and
  // hyn_can_view_fleet() decide what this session can actually read, so a
  // non-maintainer who calls the API directly still sees only their own rows.
  if (!access.canViewFleet || profile?.status !== "active") {
    return (
      <Shell email={auth.user.email}>
        <div className="terminal-panel rounded-xl p-8 md:p-12">
          <div className="mx-auto max-w-lg text-center">
            <span className="mx-auto flex size-16 items-center justify-center rounded-full border-2 border-border bg-muted">
              <ShieldAlert className="size-8 text-muted-foreground" aria-hidden />
            </span>
            <h1 className="mt-6 font-sentient text-2xl text-card-foreground md:text-3xl">
              Maintainers only
            </h1>
            <p className="mt-3 font-mono text-sm leading-7 text-muted-foreground">
              This combined fleet view needs the Maintainer, Admin or Super admin role. Your own servers are on
              the{" "}
              <Link href="/dashboard" className="text-primary underline underline-offset-4">dashboard</Link>.
            </p>
          </div>
        </div>
      </Shell>
    );
  }

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const [nodesRes, metricsRes, speedRes, alertRes, bandwidthRes] = await Promise.all([
    supabase.from("nodes").select(NODE_COLUMNS).eq("revoked", false)
      .order("is_demo", { ascending: true }).order("name"),
    // Newest-first with a generous cap; toFleetServers keeps only the latest per
    // server, so this is "enough rows to be sure every server is represented".
    supabase.from("metrics").select("*").gte("ts", since).order("ts", { ascending: false }).limit(2000),
    supabase.from("speedtests").select("*").gte("ts", since).order("ts", { ascending: false }).limit(500),
    supabase.from("alert_events").select("*").gte("ts", since).order("ts", { ascending: false }).limit(500),
    supabase.from("bandwidth_daily").select("node_id,ingress_bytes,egress_bytes"),
  ]);

  const failure = nodesRes.error ?? metricsRes.error ?? alertRes.error;
  if (failure) {
    return (
      <Shell email={auth.user.email}>
        <div className="terminal-panel p-8">
          <p className="section-kicker">// error</p>
          <h1 className="mt-2 font-sentient text-2xl text-card-foreground">The fleet could not be read</h1>
          <p className="mt-4 font-mono text-sm leading-7 text-destructive">{failure.message}</p>
          <p className="mt-4 max-w-xl font-mono text-xs leading-6 text-muted-foreground">
            If this mentions a missing function, apply{" "}
            <code>supabase/migrations/20260921140000_maintainer_role.sql</code> — the combined view needs
            <code> hyn_can_view_fleet()</code>.
          </p>
        </div>
      </Shell>
    );
  }

  const bytesByNode: Record<string, number | null> = {};
  for (const row of (bandwidthRes.data ?? []) as { node_id: string; ingress_bytes: string | number; egress_bytes: string | number }[]) {
    const total = Number(row.ingress_bytes ?? 0) + Number(row.egress_bytes ?? 0);
    if (!Number.isFinite(total)) continue;
    bytesByNode[row.node_id] = (bytesByNode[row.node_id] ?? 0) + total;
  }

  const servers = toFleetServers({
    nodes: (nodesRes.data ?? []) as Node[],
    metrics: (metricsRes.data ?? []) as Metric[],
    speedtests: (speedRes.data ?? []) as Speedtest[],
    alerts: (alertRes.data ?? []) as AlertEvent[],
    bytesByNode,
  });

  return (
    <Shell email={auth.user.email} live>
      <div className="mb-10 border-b border-border pb-8">
        <p className="section-kicker">// fleet monitor</p>
        <h1 className="mt-2 font-sentient text-3xl text-foreground md:text-4xl">Every server, one view</h1>
        <p className="mt-3 max-w-2xl font-mono text-sm leading-7 text-muted-foreground">
          {servers.length} linked machine{servers.length === 1 ? "" : "s"} · refreshed continuously · readings from the
          last 24 hours. Use <span className="text-card-foreground">notify</span> or{" "}
          <span className="text-card-foreground">report</span> on any server to send yourself its current state —
          scheduled email is off, so nothing is sent unless somebody asks for it.
        </p>
      </div>
      <FleetMonitor servers={servers} />
    </Shell>
  );
}

function Shell({ children, email, live = false }: { children: React.ReactNode; email?: string | null; live?: boolean }) {
  return (
    <div className="min-h-screen bg-background">
      {live ? <LiveRefresh /> : null}
      <ParticleField blur="subtle" />
      <DashboardMagicRings />
      <main className="container pt-32 pb-10 md:pt-44">{children}</main>
      <footer className="container flex flex-col gap-3 border-t border-border py-8 font-mono text-xs text-muted-foreground md:flex-row md:items-center md:justify-between">
        <span className="flex flex-wrap items-center gap-x-4 gap-y-2">
          <span>HYN-view</span>
          <Link href="/dashboard" className="hover:text-foreground">Dashboard</Link>
          <Link href="/account" className="hover:text-foreground">Account</Link>
        </span>
        <span className="flex flex-wrap items-center gap-4">
          {email ? (
            <>
              <span>{email}</span>
              <form action="/auth/signout" method="post" className="contents">
                <button type="submit" className="text-primary hover:text-primary/80">Sign out</button>
              </form>
            </>
          ) : null}
        </span>
      </footer>
    </div>
  );
}
