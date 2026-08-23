import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ParticleField } from "@/components/particle-field";
import { StatCards, ThroughputCard } from "@/components/dashboard/stat-cards";
import { HighwayPanel } from "@/components/dashboard/highway-panel";
import { CpuUsageChart } from "@/components/dashboard/cpu-usage-chart";
import { TemperatureChart } from "@/components/dashboard/temperature-chart";
import { NetworkChart } from "@/components/dashboard/network-chart";
import { SpeedChart } from "@/components/dashboard/speed-chart";
import { HealthPanel } from "@/components/dashboard/uptime-panel";
import { ServerDetailsPanel } from "@/components/dashboard/server-details";
import { EventLog } from "@/components/dashboard/event-log";
import { DemoDataButton } from "@/components/dashboard/demo-data-button";
import { LiveRefresh } from "@/components/live-refresh";
import { AwaitingFirstPushState, NoNodesState } from "@/components/dashboard/empty-states";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";
import type { AlertEvent, Metric, Node, Speedtest } from "@/lib/types";
import { NODE_COLUMNS } from "@/lib/types";
import {
  formatRelative,
  toCpuSeries,
  toMemSeries,
  toNetSeries,
  toSpeedSeries,
  toTempSeries,
} from "@/lib/dashboard-data";
import { fleetFreshness } from "@/lib/admin-data";

export const metadata: Metadata = {
  title: "Dashboard / HYN-view",
  description: "Live server telemetry pushed from your own machines.",
};

// Telemetry is live data; caching it would show stale numbers behind a "live"
// badge.
export const dynamic = "force-dynamic";

export default async function DashboardPage({
  searchParams,
}: {
  searchParams: Promise<{ node?: string }>;
}) {
  if (!isSupabaseConfigured) {
    return (
      <Shell>
        <div className="terminal-panel p-8">
          <p className="section-kicker">// not configured</p>
          <h1 className="mt-2 font-sentient text-2xl text-card-foreground">
            Supabase is not configured
          </h1>
          <p className="mt-4 max-w-xl font-mono text-sm leading-7 text-muted-foreground">
            Copy <code>web-portal/.env.local.example</code> to{" "}
            <code>.env.local</code>, set <code>NEXT_PUBLIC_SUPABASE_URL</code> and{" "}
            <code>NEXT_PUBLIC_SUPABASE_ANON_KEY</code>, then apply{" "}
            <code>supabase/schema.sql</code> to your project.
          </p>
        </div>
      </Shell>
    );
  }

  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/signin?next=%2Fdashboard");

  const { node: requestedNode } = await searchParams;

  // Real nodes first, demo last, so a paired machine is what you land on.
  const { data: nodeRows, error: nodesError } = await supabase
    .from("nodes")
    .select(NODE_COLUMNS)
    .eq("revoked", false)
    .order("is_demo", { ascending: true })
    .order("created_at", { ascending: true });

  if (nodesError) {
    return (
      <Shell>
        <div className="terminal-panel p-8">
          <p className="section-kicker">// error</p>
          <h1 className="mt-2 font-sentient text-2xl text-card-foreground">
            Could not read your nodes
          </h1>
          <p className="mt-4 font-mono text-sm leading-7 text-destructive">
            {nodesError.message}
          </p>
          <p className="mt-4 max-w-xl font-mono text-xs leading-6 text-muted-foreground">
            If this mentions a missing relation or function, the schema has not been
            applied yet — run <code>supabase/schema.sql</code> against your project.
          </p>
        </div>
      </Shell>
    );
  }

  const nodes = (nodeRows ?? []) as Node[];

  if (nodes.length === 0) {
    return (
      <Shell email={auth.user.email}>
        <NoNodesState />
      </Shell>
    );
  }

  const node = nodes.find((n) => n.id === requestedNode) ?? nodes[0];
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const [metricsRes, speedRes, alertRes] = await Promise.all([
    supabase
      .from("metrics")
      .select("*")
      .eq("node_id", node.id)
      .gte("ts", since)
      .order("ts", { ascending: true })
      .limit(600),
    supabase
      .from("speedtests")
      .select("*")
      .eq("node_id", node.id)
      .order("ts", { ascending: false })
      .limit(14),
    supabase
      .from("alert_events")
      .select("*")
      .eq("node_id", node.id)
      .order("ts", { ascending: false })
      .limit(8),
  ]);

  const metrics = (metricsRes.data ?? []) as Metric[];
  const speedtests = (speedRes.data ?? []) as Speedtest[];
  const alerts = (alertRes.data ?? []) as AlertEvent[];

  if (metrics.length === 0) {
    return (
      <Shell email={auth.user.email} nodes={nodes} current={node}>
        <AwaitingFirstPushState nodeName={node.name} />
      </Shell>
    );
  }

  const latest = metrics[metrics.length - 1];
  const freshness = fleetFreshness(node);

  return (
    <Shell email={auth.user.email} nodes={nodes} current={node}>
      <div className="space-y-12">
        <div className="flex flex-col gap-4 border-b border-border pb-8 md:flex-row md:items-end md:justify-between">
          <div>
            <p className="section-kicker">// live dashboard</p>
            <h1 className="mt-2 font-sentient text-3xl text-foreground md:text-4xl">
              {node.name}
            </h1>
            <p className="mt-3 max-w-2xl font-mono text-sm leading-7 text-muted-foreground">
              {node.hostname ?? "unknown host"} · {node.os ?? "unknown OS"} ·{" "}
              <span className="text-card-foreground">
                hyn {node.agent_version ?? "version unknown"}
              </span>{" "}
              · last push {formatRelative(node.last_seen_at)} · {metrics.length} samples in
              the last 24h
            </p>
          </div>
          <div className="flex flex-col items-start gap-3 md:items-end">
            {node.is_demo ? (
              <span className="flex w-fit items-center gap-2 rounded-full border border-[#e8a400]/50 bg-[#e8a400]/10 px-3 py-1.5 font-mono text-xs uppercase text-[#e8a400]">
                demo data · not a real server
              </span>
            ) : node.status === "paused" ? (
              <span className="flex w-fit items-center gap-2 rounded-full border border-[#e8a400]/50 bg-[#e8a400]/10 px-3 py-1.5 font-mono text-xs uppercase text-[#e8a400]">
                paused by an administrator
              </span>
            ) : node.status === "suspended" ? (
              <span className="flex w-fit items-center gap-2 rounded-full border border-destructive/50 bg-destructive/10 px-3 py-1.5 font-mono text-xs uppercase text-destructive">
                suspended
              </span>
            ) : freshness.key === "quiet" ? (
              <span className="flex w-fit items-center gap-2 rounded-full border border-destructive/50 bg-destructive/10 px-3 py-1.5 font-mono text-xs uppercase text-destructive">
                gone quiet · {freshness.label}
              </span>
            ) : (
              <span className={`flex w-fit items-center gap-2 rounded-full border border-primary/40 px-3 py-1.5 font-mono text-xs uppercase ${freshness.tone}`}>
                <span className="size-1.5 animate-pulse rounded-full bg-current" />
                {freshness.label}
              </span>
            )}
            {node.is_demo ? <DemoDataButton mode="clear" /> : null}
          </div>
        </div>

        {/* Why the data stopped, stated where someone looking at a stale chart
            will actually see it. */}
        {node.status !== "active" && !node.is_demo ? (
          <p
            className={`border p-3 font-mono text-xs leading-6 ${
              node.status === "suspended"
                ? "border-destructive/40 bg-destructive/5 text-destructive"
                : "border-[#e8a400]/40 bg-[#e8a400]/5 text-[#e8a400]"
            }`}
          >
            {node.status === "paused"
              ? "Monitoring is paused, so no new readings are being accepted."
              : "This machine is suspended and is not accepting readings."}
            {node.status_reason ? ` Reason: ${node.status_reason}.` : ""}
            {node.paused_until
              ? ` It resumes automatically at ${new Date(node.paused_until).toLocaleString()}.`
              : " An administrator can lift this."}{" "}
            Everything below is the last data received.
          </p>
        ) : null}

        {node.status === "active" && freshness.key === "quiet" && !node.is_demo ? (
          <p className="border border-destructive/40 bg-destructive/5 p-3 font-mono text-xs leading-6 text-destructive">
            This machine missed three configured telemetry intervals. The charts show the
            last received values. On the server, run <code>sudo hyn doctor</code> and{" "}
            <code>systemctl status hyn-push.timer</code>.
          </p>
        ) : null}

        <StatCards latest={latest} />

        {/* Highway first, above the processor. On a relay node the question that
            matters is whether its services are up: a box with a failed unit is
            earning nothing however cool the CPU is running. */}
        <section className="space-y-6">
          <p className="section-kicker border-b border-border pb-3">// highway services</p>
          <HighwayPanel latest={latest} />
        </section>

        <section className="space-y-6">
          <p className="section-kicker border-b border-border pb-3">// processor</p>
          <div className="grid gap-6 lg:grid-cols-2">
            <CpuUsageChart data={toCpuSeries(metrics)} />
            <TemperatureChart data={toTempSeries(metrics)} />
          </div>
        </section>

        <section className="space-y-6">
          <p className="section-kicker border-b border-border pb-3">// network</p>
          <div className="grid gap-6 lg:grid-cols-[1.6fr_1fr]">
            <NetworkChart data={toNetSeries(metrics)} />
            <ThroughputCard latest={latest} />
          </div>
          <SpeedChart data={toSpeedSeries(speedtests)} />
        </section>

        <section className="space-y-6">
          <p className="section-kicker border-b border-border pb-3">
            // pressure &amp; alerts
          </p>
          <HealthPanel latest={latest} />
          <EventLog events={alerts} />
        </section>

        <section className="space-y-6">
          <p className="section-kicker border-b border-border pb-3">// the machine</p>
          <ServerDetailsPanel node={node} latest={latest} />
        </section>

        {/* Memory and disk trend, kept last: it is the slowest-moving panel. */}
        <TrendNote data={toMemSeries(metrics)} />
      </div>
    </Shell>
  );
}

function TrendNote({ data }: { data: { memory: number | null; disk: number | null }[] }) {
  const first = data[0];
  const last = data[data.length - 1];
  if (!first || !last || first.disk === null || last.disk === null) return null;
  const delta = Number(last.disk) - Number(first.disk);
  if (Math.abs(delta) < 0.1) return null;
  return (
    <p className="font-mono text-xs text-muted-foreground">
      Disk {delta > 0 ? "up" : "down"} {Math.abs(delta).toFixed(1)} points over the
      last 24h.
    </p>
  );
}

function Shell({
  children,
  email,
  nodes,
  current,
}: {
  children: React.ReactNode;
  email?: string | null;
  nodes?: Node[];
  current?: Node;
}) {
  return (
    <div className="min-h-screen bg-background">
      {email ? <LiveRefresh /> : null}
      <ParticleField blur="subtle" />
      <main className="container pt-32 pb-10 md:pt-44">
        {nodes && nodes.length > 1 ? (
          <nav className="mb-8 flex flex-wrap gap-2" aria-label="Linked nodes">
            {nodes.map((n) => (
              <Link
                key={n.id}
                href={`/dashboard?node=${n.id}`}
                className={`border px-3 py-1.5 font-mono text-xs transition-colors ${
                  n.id === current?.id
                    ? "border-primary text-primary"
                    : "border-border text-muted-foreground hover:text-foreground"
                }`}
              >
                {n.name}
                {n.is_demo ? " (demo)" : ""}
              </Link>
            ))}
          </nav>
        ) : null}

        {children}
      </main>

      <footer className="container flex flex-col gap-3 border-t border-border py-8 font-mono text-xs text-muted-foreground md:flex-row md:items-center md:justify-between">
        <span className="flex flex-wrap items-center gap-x-4 gap-y-2">
          <span>HYN-view</span>
          <Link href="/privacy" className="hover:text-foreground">Privacy</Link>
          <Link href="/terms" className="hover:text-foreground">Terms</Link>
          <Link href="/legal" className="hover:text-foreground">Disclaimer</Link>
        </span>
        <span className="flex flex-wrap items-center gap-4">
          <Link href="/link" className="hover:text-foreground">
            Link another server
          </Link>
          {email ? (
            <>
              <span>{email}</span>
              <form action="/auth/signout" method="post" className="contents">
                <button type="submit" className="text-primary hover:text-primary/80">
                  Sign out
                </button>
              </form>
            </>
          ) : null}
        </span>
      </footer>
    </div>
  );
}
