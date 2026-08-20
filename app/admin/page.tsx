import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ShieldAlert } from "lucide-react";
import { ClientTable, NodeTable } from "@/components/admin/tables";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";
import { formatRelative } from "@/lib/dashboard-data";
import type {
  AdminClient,
  AdminNode,
  AdminNotification,
  AdminOverview,
  AuditEntry,
  Profile,
} from "@/lib/types";

export const metadata: Metadata = {
  title: "Admin / HYN-view",
  description: "Fleet-wide view of every client and every machine.",
};

export const dynamic = "force-dynamic";

export default async function AdminPage() {
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

  const { data: profileRow } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", auth.user.id)
    .maybeSingle();
  const profile = profileRow as Profile | null;

  // The UI check is a courtesy so a non-admin gets an explanation instead of a
  // wall of errors. It is not the security boundary -- every admin RPC re-checks
  // the role in the database, because anyone can call them with the anon key.
  if (profile?.role !== "admin" || profile?.status !== "active") {
    return (
      <Shell email={auth.user.email}>
        <div className="terminal-panel p-8 md:p-12">
          <div className="mx-auto max-w-lg text-center">
            <ShieldAlert className="mx-auto size-10 text-muted-foreground" aria-hidden />
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
            <p className="mt-6 font-mono text-xs leading-6 text-muted-foreground">
              To grant the first administrator, run this once in the Supabase SQL
              editor:
            </p>
            <pre className="mt-3 overflow-x-auto border border-border bg-black/60 p-3 text-left font-mono text-xs text-primary">
{`update public.profiles
   set role = 'admin'
 where email = '${auth.user.email}';`}
            </pre>
          </div>
        </div>
      </Shell>
    );
  }

  const [overviewRes, nodesRes, clientsRes, notifRes, auditRes] = await Promise.all([
    supabase.rpc("hyn_admin_overview"),
    supabase.rpc("hyn_admin_nodes"),
    supabase.rpc("hyn_admin_clients"),
    supabase.rpc("hyn_admin_notifications", { p_limit: 100 }),
    supabase.rpc("hyn_admin_audit", { p_limit: 50 }),
  ]);

  const rpcError =
    overviewRes.error ?? nodesRes.error ?? clientsRes.error ?? notifRes.error ?? auditRes.error;
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
  const notifications = (notifRes.data ?? []) as AdminNotification[];
  const audit = (auditRes.data ?? []) as AuditEntry[];

  const cards: { label: string; value: number; tone?: "bad" | "warn" }[] = [
    { label: "Clients", value: overview.clients_total },
    { label: "Machines", value: overview.nodes_total },
    { label: "Reporting", value: overview.nodes_active },
    { label: "Gone quiet", value: overview.nodes_stale, tone: overview.nodes_stale ? "bad" : undefined },
    { label: "Paused", value: overview.nodes_paused, tone: overview.nodes_paused ? "warn" : undefined },
    { label: "Suspended", value: overview.nodes_suspended, tone: overview.nodes_suspended ? "bad" : undefined },
    { label: "Open alerts", value: overview.alerts_open, tone: overview.alerts_open ? "warn" : undefined },
    {
      label: "Notifs failed 24h",
      value: overview.notifications_failed_24h,
      tone: overview.notifications_failed_24h ? "bad" : undefined,
    },
  ];

  return (
    <Shell email={auth.user.email}>
      <div className="space-y-10">
        <div className="border-b border-border pb-8">
          <p className="section-kicker">// administration</p>
          <h1 className="mt-2 font-sentient text-3xl text-foreground md:text-4xl">
            Every client, every machine
          </h1>
          <p className="mt-3 max-w-3xl font-mono text-sm leading-7 text-muted-foreground">
            {overview.nodes_total} machines across {overview.clients_total} accounts ·{" "}
            {overview.metrics_24h} readings and {overview.notifications_24h} notifications in
            the last 24 hours. A machine that has gone quiet has stopped checking
            in — this cannot tell you the box is down, only that it stopped talking.
          </p>
        </div>

        <div className="grid gap-px overflow-hidden border border-border bg-border sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-8">
          {cards.map((c) => (
            <div key={c.label} className="bg-card px-4 py-5">
              <p className="font-mono text-[0.6rem] uppercase tracking-wide text-muted-foreground">
                {c.label}
              </p>
              <p
                className={`mt-3 font-sentient text-2xl ${
                  c.tone === "bad"
                    ? "text-destructive"
                    : c.tone === "warn"
                      ? "text-[#e8a400]"
                      : "text-card-foreground"
                }`}
              >
                {c.value}
              </p>
            </div>
          ))}
        </div>

        <NodeTable nodes={nodes} />

        <ClientTable clients={clients} selfId={auth.user.id} />

        <div className="terminal-panel p-6">
          <p className="section-kicker">// notifications, all clients</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">
            Delivery log
          </p>
          {notifications.length === 0 ? (
            <p className="mt-6 font-mono text-xs text-muted-foreground">
              No notifications have been reported yet.
            </p>
          ) : (
            <div className="mt-6 overflow-x-auto">
              <table className="w-full min-w-[900px] border-collapse font-mono text-xs">
                <thead>
                  <tr className="border-b border-border text-left uppercase text-muted-foreground">
                    <th className="py-2 pr-4 font-normal">when</th>
                    <th className="py-2 pr-4 font-normal">client</th>
                    <th className="py-2 pr-4 font-normal">machine</th>
                    <th className="py-2 pr-4 font-normal">channel</th>
                    <th className="py-2 pr-4 font-normal">subject</th>
                    <th className="py-2 font-normal">result</th>
                  </tr>
                </thead>
                <tbody>
                  {notifications.map((n) => (
                    <tr key={n.id} className="border-b border-border/50 align-top">
                      <td className="py-3 pr-4 whitespace-nowrap text-muted-foreground">
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
                      <td
                        className={`py-3 whitespace-nowrap ${
                          n.status === "sent" ? "text-primary" : "text-destructive"
                        }`}
                      >
                        {n.status}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        <div className="terminal-panel p-6">
          <p className="section-kicker">// audit trail</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">
            Who changed what
          </p>
          <p className="mt-2 font-mono text-xs leading-6 text-muted-foreground">
            Every pause, suspension and role change, attributed. Written by the
            database, not the UI, so it cannot be skipped.
          </p>
          {audit.length === 0 ? (
            <p className="mt-6 font-mono text-xs text-muted-foreground">
              No administrative actions recorded yet.
            </p>
          ) : (
            <ul className="mt-6 divide-y divide-border/60">
              {audit.map((a) => (
                <li key={a.id} className="py-3 font-mono text-xs">
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
      </div>
    </Shell>
  );
}

function Shell({ children, email }: { children: React.ReactNode; email?: string | null }) {
  return (
    <div className="min-h-screen bg-background">
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
