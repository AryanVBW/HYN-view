import { ServerBandwidth } from "@/components/dashboard/server-bandwidth";
import { ServerSwitcher } from "@/components/dashboard/server-switcher";
import { selectDashboard } from "@/lib/dashboard-selection";
import { DashboardContext } from "@/components/dashboard/dashboard-context";
import { permissions, type DashboardAccount } from "@/lib/permissions";
import type { Metadata } from "next";
import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { ParticleField } from "@/components/particle-field";
import { DashboardMagicRings } from "@/components/dashboard-magic-rings";
import { StatCards, ThroughputCard } from "@/components/dashboard/stat-cards";
import { HighwayPanel } from "@/components/dashboard/highway-panel";
import { RelayerDashboard } from "@/components/dashboard/relayer-dashboard";
import { SimpleDashboard } from "@/components/dashboard/simple-dashboard";
import { CpuUsageChart } from "@/components/dashboard/cpu-usage-chart";
import { TemperatureChart } from "@/components/dashboard/temperature-chart";
import { NetworkChart } from "@/components/dashboard/network-chart";
import { SpeedChart } from "@/components/dashboard/speed-chart";
import { HealthPanel } from "@/components/dashboard/uptime-panel";
import { ServerDetailsPanel } from "@/components/dashboard/server-details";
import { EventLog } from "@/components/dashboard/event-log";
import {
  FilesystemsPanel,
  NetworkDetailPanel,
  PowerPanel,
  PressurePanel,
  ProcessesPanel,
} from "@/components/dashboard/telemetry-detail";
import { AgentUpdateControl } from "@/components/dashboard/agent-update-control";
import { HeartbeatIndicator } from "@/components/dashboard/heartbeat-indicator";
import { DemoDataButton } from "@/components/dashboard/demo-data-button";
import { LiveRefresh } from "@/components/live-refresh";
import { AwaitingFirstPushState, NoNodesState } from "@/components/dashboard/empty-states";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";
import type { AlertEvent, Metric, Node, Speedtest } from "@/lib/types";
import { NODE_COLUMNS } from "@/lib/types";
import {
  compareVersions,
  toCpuSeries,
  toMemSeries,
  toNetSeries,
  toSpeedSeries,
  toTempSeries,
} from "@/lib/dashboard-data";
import { heartbeatState } from "@/lib/heartbeat";
import { commandBlockedReason, readAgentRelease } from "@/lib/node-command";
import { readTransientSnapshot, snapshotMetric } from "@/lib/transient-snapshot";
import { monitoringRevision, TELEMETRY_HOURS } from "@/lib/monitoring-state";
import { mergeMonitoringHistory } from "@/lib/monitoring-data";
import { MonitoringLog } from "@/components/dashboard/monitoring-log";
import { ReadingAge } from "@/components/dashboard/reading-age";

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
  searchParams: Promise<{ node?: string; owner?: string; section?: string; relayer?: string; relayScope?: string }>;
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

  const { node: requestedNode, owner: requestedOwner, section: requestedSection, relayer: requestedRelayer, relayScope } = await searchParams;
  const [profileResult, accountsResult] = await Promise.all([
    supabase.from("profiles").select("role,status").eq("id", auth.user.id).maybeSingle(),
    supabase.rpc("hyn_dashboard_accounts"),
  ]);
  if (profileResult.error || accountsResult.error || profileResult.data?.status !== "active") {
    return <Shell email={auth.user.email}><div className="terminal-panel p-8"><h1 className="font-sentient text-2xl">Dashboard access unavailable</h1><p className="mt-4 font-mono text-sm leading-7">{profileResult.data?.status === "suspended" ? "Your account is suspended. Contact a Super admin." : "Ask a Super admin to finish the portal roles setup, then refresh this page."}</p></div></Shell>;
  }
  const accounts = (accountsResult.data ?? []) as DashboardAccount[];
  const access = permissions(profileResult.data.role);

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

  const selection = selectDashboard({selfId: auth.user.id, canAdmin: access.canAdmin, accounts,
    nodes: (nodeRows ?? []) as Node[], requestedOwner, requestedNode});
  if (!selection) return <Shell email={auth.user.email}><div className="terminal-panel p-8"><h1 className="font-sentient text-2xl">This server or dashboard is unavailable</h1><p className="mt-3 text-sm text-muted-foreground">It may have been unlinked or access may have changed.</p><Link href="/dashboard" className="mt-4 inline-block text-primary underline">Return to your dashboards</Link></div></Shell>;
  const {owner, nodes, node} = selection;
  // User relayers belong to the signed-in account, independently of the owner
  // of the server currently being viewed. Staff retain their fleet relay view.
  const canViewRelayers = true;
  const relayerOwner = access.canAdmin ? "all" : undefined;
  // Preserve old links that selected a relayer before there were separate sections.
  const section = requestedSection === "relayers" || (!requestedSection && requestedRelayer) ? "relayers" : "servers";
  const context = {role: profileResult.data.role, accounts, owner, section, nodeId: node?.id, canViewRelayers,
    computers: ((nodeRows ?? []) as Node[]).map(({id, name, hostname, owner: computerOwner}) => ({id, name, hostname, owner: computerOwner}))} as const;

  if (section === "relayers") {
    return <Shell email={auth.user.email} context={context}>
      {relayScope === "server"
        ? node && !node.is_demo
          ? <RelayerDashboard key={node.id} nodeId={node.id} />
          : <p className="py-8 text-sm text-muted-foreground">Select a server to see its linked relayer.</p>
        : <RelayerDashboard key={relayerOwner ?? auth.user.id} ownerId={relayerOwner} />}
    </Shell>;
  }

  if (!node) {
    return (
      <Shell email={auth.user.email} context={context}>
        {access.canLink && owner === auth.user.id ? <NoNodesState canDemo={access.canWrite} /> : <div className="terminal-panel p-8"><h1 className="font-sentient text-2xl">No machines on this dashboard</h1><p className="mt-3 font-mono text-sm leading-7 text-muted-foreground">Devices you link appear in My devices immediately. A Super admin can share other servers with you. Highway relayers are managed separately.</p></div>}
      </Shell>
    );
  }

  // The DB-managed setting is the default an administrator or the account
  // page picked for this node; the header's DashboardViewToggle is a personal,
  // client-side override that wins when present, stored in a cookie (not
  // localStorage) precisely so this server component can read it on every
  // render without a client round-trip. Simple is the platform default for
  // every node that hasn't been explicitly set to "dash" -- a node whose
  // config never mentions the key, or mentions anything other than "dash",
  // lands on simple; an admin who has deliberately chosen "dash" for a node
  // keeps that choice.
  const dbDefaultView = node.config?.dashboard_view === "dash" ? "dash" : "simple";
  const viewOverride = (await cookies()).get("hyn_view_mode")?.value;
  const dashboardView =
    viewOverride === "simple" || viewOverride === "dash" ? viewOverride : dbDefaultView;

  const localMode = node.config?.cloud_storage === "local"
    || (node.telemetry_mode === "local" && node.config?.cloud_storage !== "cloud");
  const transient = localMode && node.status === "active" ? readTransientSnapshot(node.id) : null;
  const since = new Date(Date.now() - TELEMETRY_HOURS * 60 * 60 * 1000).toISOString();

  const [metricsRes, historyRes, speedRes, alertRes] = await Promise.all([
    localMode ? Promise.resolve({ data: [] }) : supabase
      .from("metrics")
      .select("*")
      .eq("node_id", node.id)
      .gte("ts", since)
      .order("ts", { ascending: false })
      .limit(1),
    localMode ? Promise.resolve({data: [], error: null}) : supabase.rpc("hyn_metric_history", {p_node: node.id}),
    localMode ? Promise.resolve({ data: [] }) : supabase
      .from("speedtests")
      .select("*")
      .eq("node_id", node.id)
      .gte("ts", since)
      .order("ts", { ascending: false })
      .limit(14),
    localMode ? Promise.resolve({ data: [] }) : supabase
      .from("alert_events")
      .select("*")
      .eq("node_id", node.id)
      .gte("ts", since)
      .order("ts", { ascending: false })
      .limit(8),
  ]);

  const metrics = mergeMonitoringHistory((historyRes.data ?? []) as Metric[], (metricsRes.data?.[0] ?? null) as Metric | null);
  if (transient) metrics.push(snapshotMetric(node.id, transient));
  const speedtests = (speedRes.data ?? []) as Speedtest[];
  const alerts = (alertRes.data ?? []) as AlertEvent[];

  if (metrics.length === 0) {
    return (
      <Shell email={auth.user.email} nodes={nodes} current={node} context={context}>
        {localMode ? (
          <div className="space-y-6">
            <p className="font-mono text-sm text-muted-foreground">Local-only monitoring is enabled for {node.name}. A Super admin can enable cloud history for automatic dashboard readings. You can also refresh a reading below.</p>
            <AgentUpdateControl compact canSync={access.canSync} nodeId={node.id} nodeName={node.name} currentVersion={node.agent_version}
              release={{ latest: null, available: false, checkedAt: null }}
              automatic={node.config?.auto_update === "install"} blocked={commandBlockedReason(node)} />
          </div>
        ) : <div className="space-y-6">
          <HeartbeatIndicator nodeId={node.id} heartbeatAt={node.last_heartbeat_at ?? node.last_config_pull_at ?? node.last_seen_at} />
          {("error" in metricsRes && metricsRes.error) || historyRes.error
            ? <p className="font-mono text-sm text-muted-foreground">Readings are temporarily unavailable. This page checks again automatically.</p>
            : <><AwaitingFirstPushState nodeName={node.name} /><p className="font-mono text-xs text-muted-foreground">Cloud history updates automatically after the agent checks in. CLI 1.10 or later applies the current monitoring settings.</p></>}
          <AgentUpdateControl compact canSync={access.canSync} nodeId={node.id} nodeName={node.name} currentVersion={node.agent_version}
            release={{latest: null, available: false, checkedAt: null}} automatic={node.config?.auto_update === "install"} blocked={commandBlockedReason(node)} />
        </div>}
        {dashboardView === "dash" && !node.is_demo ? <div className="mt-6"><ServerBandwidth nodeId={node.id} /></div> : null}
      </Shell>
    );
  }

  const latest = metrics[metrics.length - 1];
  const durableHeartbeat = node.last_heartbeat_at ?? node.last_config_pull_at ?? node.last_seen_at;
  const configuredInterval = Number(node.config?.cloud_push_min ?? 10);
  const legacyQuietSeconds = Math.max(
    15,
    Number.isInteger(configuredInterval) && configuredInterval >= 1 && configuredInterval <= 1440
      ? configuredInterval * 3
      : 30,
  ) * 60;
  const quietAfterSeconds = node.agent_version && compareVersions(node.agent_version, "1.7.0") >= 0
    ? 180
    : legacyQuietSeconds;
  const heartbeatCapable = quietAfterSeconds === 180;
  const heartbeat = heartbeatState(durableHeartbeat, Date.now(), quietAfterSeconds);
  const agentRelease = readAgentRelease(latest.payload);

  return (
    <Shell email={auth.user.email} nodes={nodes} current={node} context={context}>
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
              · {localMode ? "requested reading" : "latest reading"} <ReadingAge sampleAt={latest.ts} intervalMinutes={node.config?.cloud_push_min} /> · {localMode ? "local history" : "48-hour history · charts sampled every 5 minutes"}
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
            ) : (
              <HeartbeatIndicator nodeId={node.id} heartbeatAt={durableHeartbeat} quietAfterSeconds={quietAfterSeconds} />
            )}
            {node.is_demo && access.canWrite && owner === auth.user.id ? <DemoDataButton mode="clear" /> : null}
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

        {node.status === "active" && heartbeat.key === "quiet" && !node.is_demo ? (
          <p className="border border-destructive/40 bg-destructive/5 p-3 font-mono text-xs leading-6 text-destructive">
            {heartbeatCapable
              ? "No heartbeat has arrived for three minutes. "
              : `This machine missed three configured telemetry intervals (${configuredInterval} minutes each). `}
            HYN-view retries automatically; the charts show the last received values. A queued
            synchronization or update will run as soon as the machine checks in. On the server,
            run <code>sudo hyn doctor --fix</code>, which reinstalls the timers and sends a
            reading immediately.
          </p>
        ) : null}

        {dashboardView === "simple" ? (
          <SimpleDashboard node={node} latest={latest} speedtests={speedtests} metrics={metrics}
            relayerNodeId={!node.is_demo ? node.id : undefined} />
        ) : (
          <>
            <StatCards latest={latest} />

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
              {!node.is_demo ? <ServerBandwidth nodeId={node.id} /> : null}
              {/* The counters that say whether the link itself is healthy, not just
                  how much went through it. Errors, drops, retransmits, socket states
                  and first-hop latency are the difference between "my connection is
                  bad" and "my provider's is". */}
              <NetworkDetailPanel latest={latest} />
            </section>

            <section className="space-y-6">
              <p className="section-kicker border-b border-border pb-3">// storage</p>
              <FilesystemsPanel latest={latest} />
            </section>

            <section className="space-y-6">
              <p className="section-kicker border-b border-border pb-3">
                // pressure &amp; alerts
              </p>
              <PowerPanel latest={latest} />
              <PressurePanel latest={latest} />
              <HealthPanel latest={latest} />
              <EventLog events={alerts} />
              <MonitoringLog payload={latest.payload} />
            </section>

            <section className="space-y-6">
              <p className="section-kicker border-b border-border pb-3">// processes</p>
              <ProcessesPanel latest={latest} />
            </section>

            {/* Highway moved below the graphs at explicit request: this dashboard
                now leads with the visual/telemetry sections and treats services as
                the detail you check after the shape of the machine already looks
                right, rather than the first thing on the page. That reverses the
                original placement (see the terminal's render_simple and this
                repo's README, "The Highway node comes first" / "a node that is not
                running earns nothing however cool it is") — the terminal view and
                daily report still lead with it. Kept as its own section, immediately
                before the machine/controls, so it still reads as "and here is
                whether the thing this box exists for is actually up" before you act
                on anything below it. */}
            <section className="space-y-6">
              <p className="section-kicker border-b border-border pb-3">// highway services</p>
              <HighwayPanel latest={latest} />
            </section>

            <section className="space-y-6">
              <p className="section-kicker border-b border-border pb-3">// the machine</p>
              <ServerDetailsPanel node={node} latest={latest} />
            </section>

            {/* Memory and disk trend, kept last: it is the slowest-moving panel. */}
            <TrendNote data={toMemSeries(metrics)} />
          </>
        )}

        {/* The controls sit at the bottom, after everything they act on. Sync and
            update are deliberate actions taken *because* of something read above,
            so putting them last means the page reads as "here is the machine" and
            then "here is what you can do about it" -- rather than offering a
            button before the reader knows whether they need it. */}
        {!node.is_demo ? (
          <AgentUpdateControl compact canSync={access.canSync}
            nodeId={node.id}
            nodeName={node.name}
            currentVersion={node.agent_version}
            release={agentRelease}
            automatic={node.config?.auto_update === "install"}
            blocked={commandBlockedReason(node)}
          />
        ) : null}
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
  context,
}: {
  children: React.ReactNode;
  email?: string | null;
  nodes?: Node[];
  current?: Node;
  context?: { role: unknown; accounts: DashboardAccount[]; owner: string; section: "servers" | "relayers"; nodeId?: string; canViewRelayers: boolean; computers?: Pick<Node, "id" | "name" | "hostname" | "owner">[] };
}) {
  return (
    <div className="min-h-screen bg-background">
      {email ? <LiveRefresh nodeId={current?.id} revision={current ? monitoringRevision(current) : undefined} /> : null}
      <ParticleField blur="subtle" />
      <DashboardMagicRings />
      <main className="container pt-32 pb-10 md:pt-44">
        {context ? <DashboardContext {...context} /> : null}
        {nodes && context && !context.computers ? <div className="mb-8"><ServerSwitcher nodes={nodes} current={current?.id} baseHref={`/dashboard?owner=${context.owner}&section=servers`} accounts={context.owner === "all" ? context.accounts : []} /></div> : null}

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
          {permissions(context?.role).canLink ? <Link href="/link" className="hover:text-foreground">Link another server</Link> : null}
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
