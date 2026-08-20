import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { AlertTriangle, CheckCircle2, Mail, ShieldCheck, XCircle } from "lucide-react";
import { NotifyPreferences } from "@/components/account/notify-preferences";
import { NodeSettings } from "@/components/account/node-settings";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";
import { claimAdminIfAllowed } from "@/lib/admin-claim";
import { formatRelative } from "@/lib/dashboard-data";
import type {
  AdminOption,
  Node,
  NotifyPrefs,
  NotificationLogRow,
  Profile,
} from "@/lib/types";
import { NODE_COLUMNS } from "@/lib/types";

export const metadata: Metadata = {
  title: "Account / HYN-view",
  description: "Your account, notification channels and delivery history.",
};

export const dynamic = "force-dynamic";

export default async function AccountPage() {
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
  if (!auth.user) redirect("/signin?next=%2Faccount");

  await claimAdminIfAllowed(supabase, auth.user.email);

  const [profileRes, nodesRes, prefsRes, adminsRes, logRes] = await Promise.all([
    supabase.from("profiles").select("*").eq("id", auth.user.id).maybeSingle(),
    supabase.from("nodes").select(NODE_COLUMNS).eq("revoked", false).order("created_at"),
    supabase.from("notify_prefs").select("*").eq("user_id", auth.user.id).maybeSingle(),
    supabase.rpc("hyn_list_admins"),
    supabase
      .from("notification_log")
      .select("*")
      .order("ts", { ascending: false })
      .limit(50),
  ]);

  const profile = profileRes.data as Profile | null;
  const nodes = (nodesRes.data ?? []) as Node[];
  const prefs = prefsRes.data as NotifyPrefs | null;
  const admins = (adminsRes.data ?? []) as AdminOption[];
  const log = (logRes.data ?? []) as NotificationLogRow[];

  // Counted over a 30-day window rather than all time: "how many emails have
  // come" is a question about recent behaviour, and an all-time total only ever
  // grows, so it stops being informative.
  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const [total30, sent30, failed30] = await Promise.all([
    supabase.from("notification_log").select("id", { count: "exact", head: true }).gte("ts", since),
    supabase.from("notification_log").select("id", { count: "exact", head: true }).gte("ts", since).eq("status", "sent"),
    supabase.from("notification_log").select("id", { count: "exact", head: true }).gte("ts", since).eq("status", "failed"),
  ]);

  const byKind = log.reduce<Record<string, number>>((acc, row) => {
    acc[row.kind] = (acc[row.kind] ?? 0) + 1;
    return acc;
  }, {});

  const stats = [
    { label: "Sent, 30 days", value: sent30.count ?? 0, tone: "primary" as const },
    { label: "Failed, 30 days", value: failed30.count ?? 0, tone: (failed30.count ? "bad" : "muted") as "bad" | "muted" },
    { label: "Total attempts", value: total30.count ?? 0, tone: "muted" as const },
    { label: "Admin assigned", value: prefs?.admin_id ? 1 : 0, tone: "muted" as const },
  ];

  return (
    <Shell email={auth.user.email}>
      <div className="space-y-10">
        <div className="border-b border-border pb-8">
          <p className="section-kicker">// your account</p>
          <h1 className="mt-2 font-sentient text-3xl text-foreground md:text-4xl">
            {profile?.full_name || auth.user.email}
          </h1>
          <div className="mt-4 flex flex-wrap items-center gap-x-6 gap-y-2 font-mono text-sm text-muted-foreground">
            <span className="flex items-center gap-2">
              <Mail className="size-4 text-primary" aria-hidden />
              {auth.user.email}
            </span>
            {profile?.role === "admin" ? (
              <Link
                href="/admin"
                className="flex items-center gap-2 text-primary underline underline-offset-4"
              >
                <ShieldCheck className="size-4" aria-hidden />
                administrator · open admin dashboard
              </Link>
            ) : null}
            <span>member since {new Date(profile?.created_at ?? auth.user.created_at).toLocaleDateString()}</span>
            <span>{nodes.filter((n) => !n.is_demo).length} server(s) linked</span>
          </div>

          {profile?.status === "suspended" ? (
            <p className="mt-4 border border-destructive/40 bg-destructive/5 p-3 font-mono text-xs leading-6 text-destructive">
              This account is suspended
              {profile.suspended_reason ? `: ${profile.suspended_reason}` : ""}. Your
              servers have stopped reporting. Contact your administrator.
            </p>
          ) : null}
        </div>

        <div className="grid gap-px overflow-hidden border border-border bg-border sm:grid-cols-2 lg:grid-cols-4">
          {stats.map((s) => (
            <div key={s.label} className="bg-card px-5 py-5">
              <p className="font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">
                {s.label}
              </p>
              <p
                className={`mt-3 font-sentient text-3xl ${
                  s.tone === "primary"
                    ? "text-primary"
                    : s.tone === "bad"
                      ? "text-destructive"
                      : "text-card-foreground"
                }`}
              >
                {s.value}
              </p>
            </div>
          ))}
        </div>

        <NotifyPreferences prefs={prefs} admins={admins} userEmail={auth.user.email} />

        <NodeSettings nodes={nodes} />

        <div className="terminal-panel p-6">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p className="section-kicker">// delivery history</p>
              <p className="mt-2 font-sentient text-2xl text-card-foreground">
                Every notification, and whether it arrived
              </p>
            </div>
            {Object.keys(byKind).length > 0 ? (
              <p className="font-mono text-xs text-muted-foreground">
                {Object.entries(byKind)
                  .map(([k, n]) => `${k} ${n}`)
                  .join(" · ")}
              </p>
            ) : null}
          </div>

          {log.length === 0 ? (
            <div className="mt-6 flex items-center justify-center rounded-sm border border-dashed border-border/60 px-6 py-10">
              <p className="max-w-md text-center font-mono text-xs leading-6 text-muted-foreground">
                Nothing has been sent yet. Each server reports its deliveries when
                it next checks in, so this fills in as alerts and daily reports go
                out.
              </p>
            </div>
          ) : (
            <div className="mt-6 overflow-x-auto">
              <table className="w-full min-w-[720px] border-collapse font-mono text-xs">
                <thead>
                  <tr className="border-b border-border text-left uppercase text-muted-foreground">
                    <th className="py-2 pr-4 font-normal">when</th>
                    <th className="py-2 pr-4 font-normal">channel</th>
                    <th className="py-2 pr-4 font-normal">subject</th>
                    <th className="py-2 pr-4 font-normal">kind</th>
                    <th className="py-2 font-normal">result</th>
                  </tr>
                </thead>
                <tbody>
                  {log.map((row) => (
                    <tr key={row.id} className="border-b border-border/50 align-top">
                      <td className="py-3 pr-4 whitespace-nowrap text-muted-foreground">
                        {formatRelative(row.ts)}
                      </td>
                      <td className="py-3 pr-4 whitespace-nowrap text-card-foreground/80">
                        {row.kind}
                        {row.target ? (
                          <span className="block text-muted-foreground">{row.target}</span>
                        ) : null}
                      </td>
                      <td className="py-3 pr-4 text-card-foreground/90">
                        {row.subject ?? "—"}
                        {row.error ? (
                          <span className="mt-1 block leading-5 text-destructive">
                            {row.error}
                          </span>
                        ) : null}
                      </td>
                      <td className="py-3 pr-4 whitespace-nowrap text-muted-foreground">
                        {row.category}
                      </td>
                      <td className="py-3 whitespace-nowrap">
                        {row.status === "sent" ? (
                          <span className="flex items-center gap-1.5 text-primary">
                            <CheckCircle2 className="size-3.5" /> sent
                          </span>
                        ) : row.status === "failed" ? (
                          <span className="flex items-center gap-1.5 text-destructive">
                            <XCircle className="size-3.5" /> failed
                          </span>
                        ) : (
                          <span className="flex items-center gap-1.5 text-muted-foreground">
                            <AlertTriangle className="size-3.5" /> skipped
                          </span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
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
          <Link href="/link" className="hover:text-foreground">
            Link a server
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
