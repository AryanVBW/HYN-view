import { ServerAccess, type ServerGrant, type AccessEvent } from "@/components/admin/server-access";
import { BandwidthPanel } from "@/components/admin/bandwidth-panel";
import { permissions, roleLabels, roleDescriptions, normalizeRole } from "@/lib/permissions";
import { DashboardAccess, type DashboardShare } from "@/components/admin/dashboard-access";
import { RelayerDashboard } from "@/components/dashboard/relayer-dashboard";
import { readTransientSnapshot, snapshotMetric } from "@/lib/transient-snapshot";
import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { AlertTriangle, Mail, ShieldAlert, ShieldCheck } from "lucide-react";
import { AdminTabs, type AdminTabId } from "@/components/admin/admin-tabs";
import { AgentVersions } from "@/components/admin/agent-versions";
import { AdminClientDashboard } from "@/components/admin/client-dashboard";
import { RelayerManager } from "@/components/admin/relayer-manager";
import { RelayerRequestQueue } from "@/components/admin/relayer-request-queue";
import type { RelayerAssignment } from "@/lib/relayer";
import { ClearDeliveryLogButton } from "@/components/admin/clear-delivery-log-button";
import { EmailTemplateManager } from "@/components/admin/email-template-manager";
import {
  AnimatedAdminStats,
  FleetOverviewCharts,
  type AdminStat,
  type FleetStatusSlice,
} from "@/components/admin/overview";
import { PromoteAdminForm } from "@/components/admin/promote-admin-form";
import { ClientTable, NodeTable } from "@/components/admin/tables";
import { ParticleField } from "@/components/particle-field";
import { DashboardMagicRings } from "@/components/dashboard-magic-rings";
import { LiveRefresh } from "@/components/live-refresh";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";
import { claimAdminIfAllowed } from "@/lib/admin-claim";
import { fleetFreshness, toFleetTrend } from "@/lib/admin-data";
import { formatRelative } from "@/lib/dashboard-data";
import type {
  AdminClient,
  AdminNode,
  AdminNotification,
  AdminOverview,
  AuditEntry,
  Metric,
  NotificationTemplate,
  Profile,
} from "@/lib/types";

export const metadata: Metadata = {
  title: "Admin / HYN-view",
  description: "Fleet-wide view of every client and every machine.",
};

export const dynamic = "force-dynamic";

export default async function AdminPage({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string; client?: string; node?: string }>;
}) {
  if (!isSupabaseConfigured) {
    return (
      <Shell>
        <div className="terminal-panel p-8">
          <p className="section-kicker">// not configured</p>
          <h1 className="mt-2 font-sentient text-2xl text-card-foreground">
            Supabase is not configured
          </h1>
        </div>
      </Shell>
    );
  }

  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/signin?next=%2Fadmin");
  const query = await searchParams;

  await claimAdminIfAllowed(supabase, auth.user.email);

  const { data: profileRow } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", auth.user.id)
    .maybeSingle();
  const profile = profileRow as Profile | null;

  const { canWrite, canAdmin } = permissions(profile?.role);

  // The UI check is a courtesy so a non-admin gets an explanation instead of a
  // wall of errors. It is not the security boundary -- every admin RPC re-checks
  // the role in the database, because anyone can call them with the anon key.
  if (!canAdmin || profile?.status !== "active") {
    return (
      <Shell email={auth.user.email}>
        <div className="terminal-panel rounded-xl p-8 duration-500 animate-in fade-in slide-in-from-bottom-2 md:p-12">
          <div className="mx-auto max-w-lg text-center">
            <span className="mx-auto flex size-16 items-center justify-center rounded-full border-2 border-border bg-muted">
              <ShieldAlert className="size-8 text-muted-foreground" aria-hidden />
            </span>
            <h1 className="mt-6 font-sentient text-2xl text-card-foreground md:text-3xl">
              Administrators only
            </h1>
            <p className="mt-3 font-mono text-sm leading-7 text-muted-foreground">
              This account does not have the administrator role, so it cannot see
              other clients or their machines. Your own servers are on the{" "}
              <Link href="/dashboard" className="text-primary underline underline-offset-4">
                dashboard
              </Link>
              .
            </p>
            <p className="mt-6 rounded-lg border border-border/60 bg-card/60 p-4 text-left font-mono text-xs leading-6 text-muted-foreground">
              An existing administrator can promote you from the admin panel. The
              only other way in is the SQL editor, on purpose: add your address to{" "}
              <code className="text-primary">public.admin_allowlist</code> and sign in again. That table is
              unreadable and unwritable from any browser session, so who may
              become an administrator cannot be changed from the app.
            </p>
          </div>
        </div>
      </Shell>
    );
  }

  // This dynamic Server Component needs one request-time snapshot so every
  // freshness calculation and query uses the same instant.
  // eslint-disable-next-line react-hooks/purity
  const renderedAt = Date.now();
  const since = new Date(renderedAt - 24 * 60 * 60 * 1000).toISOString();
  const [overviewRes, nodesRes, clientsRes, notifRes, auditRes, templatesRes, fleetMetricsRes] = await Promise.all([
    supabase.rpc("hyn_admin_overview"),
    supabase.rpc("hyn_admin_nodes"),
    supabase.rpc("hyn_admin_clients"),
    supabase.rpc("hyn_admin_notifications", { p_limit: 100 }),
    supabase.rpc("hyn_admin_audit", { p_limit: 50 }),
    supabase.rpc("hyn_admin_templates"),
    supabase
      .from("metrics")
      .select("node_id,ts,cpu_pct,net_rx_bps,net_tx_bps,nodes!inner(is_demo)")
      .eq("nodes.is_demo", false)
      .gte("ts", since)
      .order("ts", { ascending: true })
      .limit(5000),
  ]);

  const rpcError =
    overviewRes.error ??
    nodesRes.error ??
    clientsRes.error ??
    notifRes.error ??
    auditRes.error ??
    templatesRes.error ??
    fleetMetricsRes.error;
  if (rpcError) {
    return (
      <Shell email={auth.user.email}>
        <div className="terminal-panel p-8">
          <p className="section-kicker">// error</p>
          <h1 className="mt-2 font-sentient text-2xl text-card-foreground">
            Could not load the fleet
          </h1>
          <p className="mt-4 font-mono text-sm leading-7 text-destructive">{rpcError.message}</p>
          <p className="mt-4 font-mono text-xs leading-6 text-muted-foreground">
            If this mentions a missing function, re-apply <code>supabase/schema.sql</code>.
          </p>
        </div>
      </Shell>
    );
  }

  const overview = overviewRes.data as AdminOverview;
  const nodes = (nodesRes.data ?? []) as AdminNode[];
  const clients = (clientsRes.data ?? []) as AdminClient[];
  const serverGrants = canWrite ? await supabase.from("server_access").select("viewer_id,node_id,allowed,notifications_allowed").order("updated_at", { ascending: false }) : null;
  const accessEvents = canWrite ? await supabase.from("server_access_events").select("id,ts,actor,viewer_id,node_id,allowed").order("ts", { ascending: false }).limit(50) : null;
  const shareResult = canWrite ? await supabase.from("dashboard_access").select("viewer_id,owner_id").order("created_at", {ascending:false}) : null;
  const pendingRequests = await supabase.from("relayer_requests")
    .select("id,owner,relayer_id,relayer_name,status,created_at").eq("status","pending")
    .order("created_at").limit(200);
  const notifications = (notifRes.data ?? []) as AdminNotification[];
  const audit = (auditRes.data ?? []) as AuditEntry[];
  const templates = (templatesRes.data ?? []) as NotificationTemplate[];
  const fleetMetrics = (fleetMetricsRes.data ?? []) as Pick<
    Metric,
    "node_id" | "ts" | "cpu_pct" | "net_rx_bps" | "net_tx_bps"
  >[];
  const fleetTrend = toFleetTrend(fleetMetrics);

  const cards: AdminStat[] = [
    { label: "Clients", value: overview.clients_total, note: `${overview.admins} administrators` },
    { label: "Machines", value: overview.nodes_total, note: `${overview.nodes_active} enabled` },
    { label: "Gone quiet", value: overview.nodes_stale, note: "Missed expected check-ins", tone: overview.nodes_stale ? "bad" : undefined },
    { label: "Open alerts", value: overview.alerts_open, note: "Across the whole fleet", tone: overview.alerts_open ? "warn" : undefined },
    { label: "Paused", value: overview.nodes_paused, note: "Maintenance or operator hold", tone: overview.nodes_paused ? "warn" : undefined },
    { label: "Suspended", value: overview.nodes_suspended, note: "Telemetry refused", tone: overview.nodes_suspended ? "bad" : undefined },
    { label: "Readings · 24h", value: overview.metrics_24h, note: "Telemetry samples received" },
    {
      label: "Failed deliveries · 24h",
      value: overview.notifications_failed_24h,
      note: `${overview.notifications_24h} total attempts`,
      tone: overview.notifications_failed_24h ? "bad" : undefined,
    },
  ];

  const statusCounts = nodes.filter((node) => !node.is_demo).reduce(
    (counts, node) => {
      counts[fleetFreshness(node, renderedAt).key] += 1;
      return counts;
    },
    { reporting: 0, quiet: 0, paused: 0, suspended: 0, revoked: 0 }
  );
  const statusSlices: FleetStatusSlice[] = [
    { key: "reporting", label: "Reporting", value: statusCounts.reporting, color: "var(--chart-1)" },
    { key: "quiet", label: "Gone quiet", value: statusCounts.quiet, color: "var(--chart-5)" },
    { key: "paused", label: "Paused", value: statusCounts.paused, color: "var(--chart-2)" },
    { key: "suspended", label: "Suspended", value: statusCounts.suspended, color: "var(--destructive)" },
    { key: "revoked", label: "Revoked", value: statusCounts.revoked, color: "var(--chart-4)" },
  ];

  const selectedClient = clients.find((client) => client.id === query.client) ?? null;
  const assignmentResult = selectedClient ? await supabase.from("relayer_assignments")
    .select("id,owner,relayer_id,relayer_name,created_at").eq("owner", selectedClient.id).order("created_at") : null;
  const selectedNodes = selectedClient
    ? nodes.filter((node) => node.owner_id === selectedClient.id)
    : [];
  const selectedNode =
    selectedNodes.find((node) => node.id === query.node) ?? selectedNodes[0] ?? null;
  let selectedMetrics: Metric[] = [];
  if (selectedNode) {
    const { data: storageNode, error: storageError } = await supabase.from("nodes")
      .select("telemetry_mode,status,revoked").eq("id", selectedNode.id).maybeSingle();
    if (storageError) throw new Error(storageError.message);
    const localMode = storageNode?.telemetry_mode === "local";
    selectedNode.telemetry_mode = localMode ? "local" : "cloud";
    const transient = localMode && storageNode.status === "active" && !storageNode.revoked
      && selectedNode.owner_status === "active" ? readTransientSnapshot(selectedNode.id) : null;
    const { data, error } = localMode ? { data: [], error: null } : await supabase
      .from("metrics")
      .select("*")
      .eq("node_id", selectedNode.id)
      .gte("ts", since)
      .order("ts", { ascending: true })
      .limit(600);
    if (error) {
      return (
        <Shell email={auth.user.email}>
          <div className="terminal-panel p-8 font-mono text-sm text-destructive">
            Could not load the selected client dashboard: {error.message}
          </div>
        </Shell>
      );
    }
    selectedMetrics = transient ? [snapshotMetric(selectedNode.id, transient)] : (data ?? []) as Metric[];
  }

  const allowedTabs: AdminTabId[] = ["overview", "clients", "client", "fleet", "templates", "notifications", "audit", "access", "bandwidth"];
  const requestedTab = allowedTabs.includes(query.tab as AdminTabId)
    ? (query.tab as AdminTabId)
    : selectedClient
      ? "client"
      : "overview";
  const initialActive = requestedTab === "client" && !selectedClient ? "clients" : requestedTab;

  const attentionCount = overview.nodes_stale + overview.notifications_failed_24h;

  const overviewPanel = (
    <div className="space-y-8">
      {attentionCount > 0 ? (
        <div className="flex flex-col gap-3 rounded-lg border border-destructive/40 bg-destructive/5 p-4 duration-500 animate-in fade-in slide-in-from-bottom-2 sm:flex-row sm:items-start sm:justify-between">
          <div className="flex items-start gap-3">
            <AlertTriangle className="mt-0.5 size-4 shrink-0 text-destructive" aria-hidden />
            <p className="font-mono text-xs leading-6 text-destructive">
              {overview.nodes_stale > 0
                ? `${overview.nodes_stale} machine${overview.nodes_stale === 1 ? "" : "s"} gone quiet. `
                : ""}
              {overview.notifications_failed_24h > 0
                ? `${overview.notifications_failed_24h} notification${overview.notifications_failed_24h === 1 ? "" : "s"} failed in the last 24h. `
                : ""}
              See the Fleet and Deliveries tabs.
            </p>
          </div>
          {/* Clearing from here defaults to everything: the sentence above is about
              the last 24 hours, so a 30-day cutoff would report success and leave
              the banner exactly as it was. It empties the counters this banner and
              the failed-deliveries card are drawn from -- it does not fix what
              failed, and a number this size is one broken thing, not 4501. */}
          {canWrite && overview.notifications_failed_24h > 0 ? (
            <ClearDeliveryLogButton defaultScope="all" />
          ) : null}
        </div>
      ) : null}

      <AnimatedAdminStats stats={cards} />

      <FleetOverviewCharts trend={fleetTrend} statuses={statusSlices} />

      <p className="max-w-3xl font-mono text-sm leading-7 text-muted-foreground">
        {overview.nodes_total} machines across {overview.clients_total} accounts ·{" "}
        {overview.metrics_24h} readings and {overview.notifications_24h} notifications in
        the last 24 hours. A machine that has gone quiet has stopped checking
        in — this cannot tell you the box is down, only that it stopped talking.
      </p>

      <AgentVersions nodes={nodes} />

      <PromoteAdminForm />
    </div>
  );

  const notificationsPanel = (
    <div className="terminal-panel rounded-xl p-6 duration-500 animate-in fade-in slide-in-from-bottom-2 md:p-7">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="section-kicker">// notifications, all clients</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">Delivery log</p>
        </div>
        {canWrite && notifications.length > 0 ? <ClearDeliveryLogButton /> : null}
      </div>
      {notifications.length === 0 ? (
        <div className="mt-6 flex flex-col items-center justify-center gap-3 rounded-lg border border-dashed border-border/60 px-6 py-14">
          <span className="flex size-12 items-center justify-center rounded-full border border-border bg-secondary">
            <Mail className="size-5 text-muted-foreground" aria-hidden />
          </span>
          <p className="max-w-md text-center font-mono text-xs leading-6 text-muted-foreground">
            No notifications have been reported yet across the fleet.
          </p>
        </div>
      ) : (
        <div className="mt-6 overflow-x-auto rounded-lg border border-border/60">
          <table className="w-full min-w-[900px] border-collapse font-mono text-xs">
            <thead>
              <tr className="border-b border-border bg-card/60 text-left uppercase text-muted-foreground">
                <th className="py-3 pr-4 pl-4 font-normal">when</th>
                <th className="py-3 pr-4 font-normal">client</th>
                <th className="py-3 pr-4 font-normal">machine</th>
                <th className="py-3 pr-4 font-normal">channel</th>
                <th className="py-3 pr-4 font-normal">subject</th>
                <th className="py-3 pr-4 font-normal">result</th>
              </tr>
            </thead>
            <tbody>
              {notifications.map((n) => (
                <tr key={n.id} className="border-b border-border/40 align-top transition-colors hover:bg-card/40">
                  <td className="py-3 pr-4 pl-4 whitespace-nowrap text-muted-foreground">
                    {formatRelative(n.ts)}
                  </td>
                  <td className="py-3 pr-4 text-card-foreground/80">{n.owner_email ?? "—"}</td>
                  <td className="py-3 pr-4 text-card-foreground/80">{n.node_name ?? "—"}</td>
                  <td className="py-3 pr-4 text-muted-foreground">{n.kind}</td>
                  <td className="py-3 pr-4 text-card-foreground/90">
                    {n.subject ?? "—"}
                    {n.error ? (
                      <span className="mt-1 block leading-5 text-destructive">{n.error}</span>
                    ) : null}
                  </td>
                  <td className="py-3 pr-4 whitespace-nowrap">
                    <AdminStatusPill status={n.status} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );

  const auditPanel = (
    <div className="terminal-panel rounded-xl p-6 duration-500 animate-in fade-in slide-in-from-bottom-2 md:p-7">
      <p className="section-kicker">// audit trail</p>
      <p className="mt-2 font-sentient text-2xl text-card-foreground">Who changed what</p>
      <p className="mt-2 font-mono text-xs leading-6 text-muted-foreground">
        Every pause, suspension and role change, attributed. Written by the
        database, not the UI, so it cannot be skipped.
      </p>
      {audit.length === 0 ? (
        <div className="mt-6 flex flex-col items-center justify-center gap-3 rounded-lg border border-dashed border-border/60 px-6 py-14">
          <span className="flex size-12 items-center justify-center rounded-full border border-border bg-secondary">
            <ShieldCheck className="size-5 text-muted-foreground" aria-hidden />
          </span>
          <p className="max-w-md text-center font-mono text-xs leading-6 text-muted-foreground">
            No administrative actions recorded yet.
          </p>
        </div>
      ) : (
        <ul className="mt-6 divide-y divide-border/60 rounded-lg border border-border/60">
          {audit.map((a) => (
            <li key={a.id} className="px-4 py-3 font-mono text-xs transition-colors hover:bg-card/40">
              <span className="text-card-foreground/90">{a.action}</span>
              <span className="text-muted-foreground">
                {" "}
                by {a.actor_email ?? "unknown"}
                {a.target_node_name ? ` on ${a.target_node_name}` : ""}
                {a.target_user_email ? ` for ${a.target_user_email}` : ""} ·{" "}
                {formatRelative(a.ts)}
              </span>
              {typeof a.detail?.reason === "string" && a.detail.reason ? (
                <span className="block text-muted-foreground">
                  reason: {a.detail.reason as string}
                </span>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );

  return (
    <Shell email={auth.user.email}>
      <AdminHeader profile={profile} clientCount={overview.clients_total} nodeCount={overview.nodes_total} />

      <p className="mt-5 rounded-lg border border-primary/30 bg-primary/5 px-5 py-4 font-mono text-xs leading-6"><strong className="text-primary">{roleLabels[normalizeRole(profile.role)]}</strong> · {roleDescriptions[normalizeRole(profile.role)]}</p>
      <div className="mt-10">
        <AdminTabs
          access={canWrite ? <ServerAccess clients={clients} nodes={nodes} grants={(serverGrants?.data ?? []) as ServerGrant[]} events={(accessEvents?.data ?? []) as AccessEvent[]} error={serverGrants?.error || accessEvents?.error ? "Server access is unavailable. Finish the server permissions setup, then refresh." : null} /> : undefined}
          bandwidth={<BandwidthPanel nodes={nodes} />}
          overview={overviewPanel}
          clients={<div className="space-y-8">
            <RelayerRequestQueue canWrite={canWrite} requests={(pendingRequests.data ?? []).map(request=>{
              const owner = clients.find(c=>c.id === request.owner);
              return {...request,ownerName:owner?.full_name || owner?.email || "Portal account",active:owner?.status === "active"};
            })} error={pendingRequests.error ? "Relayer requests are unavailable. Apply the relayer requests migration to enable this queue." : null} />
            <ClientTable clients={clients} selfId={auth.user.id} canWrite={canWrite} />
            {canWrite ? <DashboardAccess clients={clients} shares={(shareResult?.data ?? []) as DashboardShare[]} error={shareResult?.error ? "Dashboard sharing is unavailable. Apply the portal roles migration." : null} /> : null}
          </div>}
          client={
            selectedClient ? (
              <AdminClientDashboard
                canWrite={canWrite}
                client={selectedClient}
                nodes={selectedNodes}
                current={selectedNode}
                metrics={selectedMetrics}
                relayers={canWrite ? <RelayerManager key={selectedClient.id} ownerId={selectedClient.id}
                  ownerName={selectedClient.full_name || selectedClient.email || "this client"}
                  assignments={(assignmentResult?.data ?? []) as RelayerAssignment[]}
                  error={assignmentResult?.error ? "Apply the relayer database migration to enable assignments."
                    : selectedClient.status !== "active" ? "Restore this account before assigning a relayer." : null} /> : <RelayerDashboard ownerId={selectedClient.id} />}
              />
            ) : undefined
          }
          fleet={<NodeTable nodes={nodes} canWrite={canWrite} />}
          templates={<EmailTemplateManager templates={templates} canWrite={canWrite} />}
          notifications={notificationsPanel}
          audit={auditPanel}
          initialActive={initialActive}
          badges={{
            clients: pendingRequests.data?.length || undefined,
            fleet: overview.nodes_stale || undefined,
            notifications: overview.notifications_failed_24h || undefined,
          }}
        />
      </div>
    </Shell>
  );
}

// One function deciding what a fleet-wide delivery status looks like, the
// same discipline the account page's deliveryStatusTone established for its
// own delivery history -- a status pill's colour is decided once, here, not
// re-decided per row.
function AdminStatusPill({ status }: { status: "sent" | "failed" | "skipped" }) {
  const color = status === "sent" ? "var(--primary)" : status === "failed" ? "var(--destructive)" : "var(--muted-foreground)";
  return (
    <span
      className="inline-flex items-center rounded-full border px-2.5 py-1 text-[0.7rem]"
      style={{ borderColor: `color-mix(in oklab, ${color} 40%, transparent)`, backgroundColor: `color-mix(in oklab, ${color} 10%, transparent)`, color }}
    >
      {status}
    </span>
  );
}

// The admin page's own identity block -- an accent card matching
// AccountHeader's treatment (app/account/page.tsx), so the two top-level
// pages an administrator moves between read as the same product rather than
// one premium and one plain. The shield-in-a-ring echoes the account page's
// own admin badge rather than inventing a second "this person is an admin"
// visual.
function AdminHeader({
  profile,
  clientCount,
  nodeCount,
}: {
  profile: Profile | null;
  clientCount: number;
  nodeCount: number;
}) {
  return (
    <div className="terminal-panel relative overflow-hidden rounded-xl p-6 duration-500 animate-in fade-in slide-in-from-bottom-2 md:p-7">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 -z-10 bg-gradient-to-br from-primary/[0.07] via-transparent to-transparent"
      />
      <div className="flex items-start gap-4">
        <span className="relative hidden size-14 shrink-0 items-center justify-center rounded-full border-2 border-primary/40 bg-primary/10 sm:flex">
          <ShieldCheck className="size-7 text-primary" aria-hidden />
        </span>
        <div>
          <p className="section-kicker">// administration</p>
          <h1 className="mt-1 font-sentient text-3xl text-foreground md:text-4xl">
            Every client, every machine
          </h1>
          <div className="mt-4 flex flex-wrap items-center gap-x-6 gap-y-2 font-mono text-sm text-muted-foreground">
            <span>{profile?.full_name || "administrator"}</span>
            <span>{clientCount} client{clientCount === 1 ? "" : "s"}</span>
            <span>{nodeCount} machine{nodeCount === 1 ? "" : "s"}</span>
          </div>
        </div>
      </div>
    </div>
  );
}

function Shell({ children, email }: { children: React.ReactNode; email?: string | null }) {
  return (
    <div className="min-h-screen bg-background">
      {email ? <LiveRefresh /> : null}
      <ParticleField blur="subtle" />
      <DashboardMagicRings />
      <main className="container pt-32 pb-10 md:pt-44">{children}</main>
      <footer className="container flex flex-col gap-3 border-t border-border py-8 font-mono text-xs text-muted-foreground md:flex-row md:items-center md:justify-between">
        <span className="flex flex-wrap items-center gap-x-4 gap-y-2">
          <span>HYN-view</span>
          <Link href="/privacy" className="hover:text-foreground">Privacy</Link>
          <Link href="/terms" className="hover:text-foreground">Terms</Link>
          <Link href="/legal" className="hover:text-foreground">Disclaimer</Link>
        </span>
        <span className="flex flex-wrap items-center gap-4">
          <Link href="/dashboard" className="hover:text-foreground">
            Dashboard
          </Link>
          <Link href="/account" className="hover:text-foreground">
            Account
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
