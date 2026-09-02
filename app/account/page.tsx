import type { Metadata } from "next";
import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { AlertTriangle, CheckCircle2, LayoutDashboard, Mail, ShieldCheck, UserCircle2, XCircle, type LucideIcon } from "lucide-react";
import { NodeSettings } from "@/components/account/node-settings";
import { ClearDeliveryHistoryButton } from "@/components/account/delivery-history-clear";
import { EmailPreferences } from "@/components/account/email-preferences";
import { StatRing } from "@/components/account/stat-ring";
import { Button } from "@/components/ui/button";
import { ParticleField } from "@/components/particle-field";
import { DashboardMagicRings } from "@/components/dashboard-magic-rings";
import { LiveRefresh } from "@/components/live-refresh";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";
import { claimAdminIfAllowed } from "@/lib/admin-claim";
import { formatRelative } from "@/lib/dashboard-data";
import { DELIVERY_CLEARED_COOKIE, visibleDeliveries } from "@/lib/delivery-history";
import type {
  Node,
  EmailPreference,
  NotificationLogRow,
  Profile,
} from "@/lib/types";
import { NODE_COLUMNS } from "@/lib/types";

export const metadata: Metadata = {
  title: "Account / HYN-view",
  description: "Your account, server settings and notification delivery history.",
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

  const [profileRes, nodesRes, logRes, emailPrefsRes] = await Promise.all([
    supabase.from("profiles").select("*").eq("id", auth.user.id).maybeSingle(),
    supabase.from("nodes").select(NODE_COLUMNS).eq("revoked", false).order("created_at"),
    supabase
      .from("notification_log")
      .select("*")
      .order("ts", { ascending: false })
      .limit(50),
    supabase.from("email_preferences").select("*").order("node_id"),
  ]);

  const profile = profileRes.data as Profile | null;
  const nodes = (nodesRes.data ?? []) as Node[];
  const log = (logRes.data ?? []) as NotificationLogRow[];
  const emailPreferences = (emailPrefsRes.data ?? []) as EmailPreference[];

  // A client who has cleared their delivery history keeps the records: the cutoff
  // is a cookie this render filters by, so the 30-day counters below and the
  // administrator's fleet-wide log are untouched by it.
  const { rows: visibleLog, cleared: logCleared } = visibleDeliveries(
    log,
    (await cookies()).get(DELIVERY_CLEARED_COOKIE)?.value
  );

  // Counted over a 30-day window rather than all time: "how many emails have
  // come" is a question about recent behaviour, and an all-time total only ever
  // grows, so it stops being informative.
  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const [total30, sent30, failed30] = await Promise.all([
    supabase.from("notification_log").select("id", { count: "exact", head: true }).gte("ts", since),
    supabase.from("notification_log").select("id", { count: "exact", head: true }).gte("ts", since).eq("status", "sent"),
    supabase.from("notification_log").select("id", { count: "exact", head: true }).gte("ts", since).eq("status", "failed"),
  ]);

  const byKind = visibleLog.reduce<Record<string, number>>((acc, row) => {
    acc[row.kind] = (acc[row.kind] ?? 0) + 1;
    return acc;
  }, {});

  const sent = sent30.count ?? 0;
  const failed = failed30.count ?? 0;
  const total = total30.count ?? 0;
  const stats = [
    { label: "Sent, 30 days", value: sent, tone: "ok" as const, icon: CheckCircle2 },
    { label: "Failed, 30 days", value: failed, tone: (failed ? "crit" : "idle") as "crit" | "idle", icon: XCircle },
    { label: "Total attempts", value: total, tone: "idle" as const, icon: Mail },
  ];
  // Rings read relative to the busiest of the three counts, not a fixed
  // scale -- "how does this compare to the others" is the question this
  // strip answers, and a fixed ceiling would either clip a busy account's
  // ring or leave a quiet one looking like a rounding error.
  const statScale = Math.max(sent, failed, total, 1);

  return (
    <Shell email={auth.user.email}>
      <div className="space-y-10">
        <AccountHeader profile={profile} authUser={auth.user} nodeCount={nodes.filter((n) => !n.is_demo).length} />

        <div className="grid gap-4 sm:grid-cols-3">
          {stats.map((s) => (
            <StatRing
              key={s.label}
              label={s.label}
              value={s.value}
              scale={statScale}
              tone={s.tone}
              icon={<s.icon width={18} height={18} />}
            />
          ))}
        </div>

        <EmailPreferences nodes={nodes} preferences={emailPreferences} accountEmail={auth.user.email ?? ""} />

        <NodeSettings nodes={nodes} />

        <DeliveryHistory log={visibleLog} byKind={byKind} cleared={logCleared} />
      </div>
    </Shell>
  );
}

// The identity block: a SectionCard-style accent card (same gradient wash
// SimpleDashboard's own SectionCard uses for its lead panel) rather than the
// plain icon-and-text row this used to be, so the account page's first thing
// on screen reads with the same weight the dashboard's own lead card does --
// premium is largely about matching that established hierarchy, not
// inventing a new one. All the same real data as before: name, email, role,
// member-since, server count, suspended state -- nothing added, nothing
// hidden.
function AccountHeader({
  profile,
  authUser,
  nodeCount,
}: {
  profile: Profile | null;
  authUser: { email?: string | null; created_at: string };
  nodeCount: number;
}) {
  const suspended = profile?.status === "suspended";
  return (
    <div className="terminal-panel relative overflow-hidden rounded-xl p-6 duration-500 animate-in fade-in slide-in-from-bottom-2 md:p-7">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 -z-10 bg-gradient-to-br from-primary/[0.07] via-transparent to-transparent"
      />
      <div className="flex flex-col gap-6 md:flex-row md:items-start md:justify-between">
        <div className="flex items-start gap-4">
          {/* A ring around the avatar rather than a plain circle: the same
              "instrument" language as the stat rings below, and it doubles as
              a status tell -- primary when the account is fine, destructive
              the moment it's suspended, without adding a second badge. */}
          <span
            className={`relative hidden size-14 shrink-0 items-center justify-center rounded-full border-2 sm:flex ${
              suspended ? "border-destructive/50 bg-destructive/10" : "border-primary/40 bg-primary/10"
            }`}
          >
            <UserCircle2 className={`size-7 ${suspended ? "text-destructive" : "text-primary"}`} aria-hidden />
          </span>
          <div>
            <p className="section-kicker">// your account</p>
            <h1 className="mt-1 font-sentient text-3xl text-foreground md:text-4xl">
              {profile?.full_name || authUser.email}
            </h1>
            <div className="mt-4 flex flex-wrap items-center gap-x-6 gap-y-2 font-mono text-sm text-muted-foreground">
              <span className="flex items-center gap-2">
                <Mail className="size-4 text-primary" aria-hidden />
                {authUser.email}
              </span>
              {profile?.role === "admin" ? (
                <Link
                  href="/admin"
                  className="flex items-center gap-2 rounded-full border border-primary/40 bg-primary/10 px-3 py-1 text-primary transition-colors hover:bg-primary/20"
                >
                  <ShieldCheck className="size-3.5" aria-hidden />
                  administrator
                </Link>
              ) : null}
              <span>member since {new Date(profile?.created_at ?? authUser.created_at).toLocaleDateString()}</span>
              <span>{nodeCount} server{nodeCount === 1 ? "" : "s"} linked</span>
            </div>

            {suspended ? (
              <p className="mt-4 max-w-lg border border-destructive/40 bg-destructive/5 p-3 font-mono text-xs leading-6 text-destructive">
                This account is suspended
                {profile?.suspended_reason ? `: ${profile.suspended_reason}` : ""}. Your
                servers have stopped reporting. Contact your administrator.
              </p>
            ) : null}
          </div>
        </div>

        <Link href="/dashboard" className="shrink-0">
          <Button size="sm" className="gap-2 whitespace-nowrap">
            <LayoutDashboard className="size-4" aria-hidden />
            Go to dashboard
          </Button>
        </Link>
      </div>
    </div>
  );
}

// The 30-day delivery counters render via StatRing (components/account/stat-ring.tsx)
// -- a client component, since its ring-fill sweep needs useAnimatedPct's ref
// and effect, which a server component (this file) cannot use directly.

// One function deciding what a delivery status looks like, the same
// discipline thermalColor (components/dashboard/thermal-gauge.tsx) already
// established for temperature: a status pill's colour comes from here, once,
// rather than being re-decided inline at every place a status is shown --
// which is exactly how the previous version drifted (three separate inline
// colour choices for the same three statuses).
function deliveryStatusTone(status: NotificationLogRow["status"]): { color: string; icon: LucideIcon; label: string } {
  switch (status) {
    case "sent":
      return { color: "var(--primary)", icon: CheckCircle2, label: "sent" };
    case "failed":
      return { color: "var(--destructive)", icon: XCircle, label: "failed" };
    default:
      return { color: "var(--muted-foreground)", icon: AlertTriangle, label: "skipped" };
  }
}

function DeliveryStatusPill({ status }: { status: NotificationLogRow["status"] }) {
  const { color, icon: Icon, label } = deliveryStatusTone(status);
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[0.7rem]"
      style={{ borderColor: `color-mix(in oklab, ${color} 40%, transparent)`, backgroundColor: `color-mix(in oklab, ${color} 10%, transparent)`, color }}
    >
      <Icon className="size-3" aria-hidden />
      {label}
    </span>
  );
}

// The delivery-history table: a premium empty state (an icon and real
// explanation, not blank space) and a properly weighted loaded table with
// the semantic status pill above, instead of three inline colour choices
// repeated per row.
function DeliveryHistory({
  log,
  byKind,
  cleared,
}: {
  log: NotificationLogRow[];
  byKind: Record<string, number>;
  cleared: boolean;
}) {
  return (
    <div className="terminal-panel rounded-xl p-6 duration-500 animate-in fade-in slide-in-from-bottom-2 md:p-7">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="section-kicker">// delivery history</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">
            Every notification, and whether it arrived
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-4">
          {Object.keys(byKind).length > 0 ? (
            <p className="font-mono text-xs text-muted-foreground">
              {Object.entries(byKind)
                .map(([k, n]) => `${k} ${n}`)
                .join(" · ")}
            </p>
          ) : null}
          <ClearDeliveryHistoryButton latestTs={log[0]?.ts} cleared={cleared} />
        </div>
      </div>

      {log.length === 0 ? (
        <div className="mt-6 flex flex-col items-center justify-center gap-3 rounded-lg border border-dashed border-border/60 px-6 py-14">
          <span className="flex size-12 items-center justify-center rounded-full border border-border bg-secondary">
            <Mail className="size-5 text-muted-foreground" aria-hidden />
          </span>
          <p className="max-w-md text-center font-mono text-xs leading-6 text-muted-foreground">
            {cleared
              ? "Cleared from your view. Nothing was deleted — every record is still kept, the counters above still count it, and anything sent from now on appears here. Show all again to bring it back."
              : "Nothing has been sent yet. Each server reports its deliveries when it next checks in, so this fills in as alerts and daily reports go out."}
          </p>
        </div>
      ) : (
        <div className="mt-6 overflow-x-auto rounded-lg border border-border/60">
          <table className="w-full min-w-[720px] border-collapse font-mono text-xs">
            <thead>
              <tr className="border-b border-border bg-card/60 text-left uppercase text-muted-foreground">
                <th className="py-3 pr-4 pl-4 font-normal">when</th>
                <th className="py-3 pr-4 font-normal">channel</th>
                <th className="py-3 pr-4 font-normal">subject</th>
                <th className="py-3 pr-4 font-normal">kind</th>
                <th className="py-3 pr-4 font-normal">result</th>
              </tr>
            </thead>
            <tbody>
              {log.map((row) => (
                <tr key={row.id} className="border-b border-border/40 align-top transition-colors hover:bg-card/40">
                  <td className="py-3 pr-4 pl-4 whitespace-nowrap text-muted-foreground">
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
                  <td className="py-3 pr-4 whitespace-nowrap">
                    <DeliveryStatusPill status={row.status} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
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
