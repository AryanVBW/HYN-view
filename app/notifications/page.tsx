import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { LiveRefresh } from "@/components/live-refresh";
import { DashboardNavigation } from "@/components/dashboard/dashboard-navigation";
import { ServerNotifications } from "@/components/dashboard/server-notifications";
import { storeRpc } from "@/lib/hyn-data";
import { createClient } from "@/lib/supabase/server";
import type { ServerNotification } from "@/lib/server-notifications";

export const dynamic = "force-dynamic";
export const metadata = { title: "Notifications / HYN-view" };

export default async function NotificationsPage() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/signin?next=%2Fnotifications");
  const { data, error } = await storeRpc("hyn_server_notifications", { p_limit: 50 });
  return <main className="container w-full max-w-6xl space-y-6 px-4 pb-16 pt-36 sm:px-6">
    <LiveRefresh />
    <div className="flex flex-col gap-4 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
      <DashboardNavigation section="notifications" />
      <Link href="/dashboard" className="inline-flex self-start items-center gap-2 rounded-full border border-border bg-background px-3 py-1.5 font-mono text-xs uppercase text-muted-foreground transition-colors hover:border-foreground/40 hover:text-foreground sm:self-auto">
        <ArrowLeft className="size-3.5" aria-hidden />
        Back to dashboard
      </Link>
    </div>
    <div className="space-y-3">
      <h1 className="font-sentient text-4xl">Server notifications</h1>
      <p className="max-w-3xl text-sm leading-7 text-muted-foreground">This inbox shows alerts from the last seven days: server updates, completed tasks, and heartbeat misses. It refreshes every minute while this page is open. Browser notifications are optional. Detailed local alerts appear only when cloud sharing is enabled on the server.</p>
    </div>
    {error ? <p role="alert" className="terminal-panel p-6">Notifications are unavailable. Ask a Super admin to check your access and the server reporting setup.</p> : <ServerNotifications key={auth.user.id} events={(data ?? []) as ServerNotification[]} userId={auth.user.id} />}
  </main>;
}
