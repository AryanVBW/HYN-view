import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft, RadioTower } from "lucide-react";
import { LiveRefresh } from "@/components/live-refresh";
import { ServerNotifications } from "@/components/dashboard/server-notifications";
import { createClient } from "@/lib/supabase/server";
import type { ServerNotification } from "@/lib/server-notifications";

export const dynamic = "force-dynamic";
export const metadata = { title: "Notifications / HYN-view" };

export default async function NotificationsPage() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/signin?next=%2Fnotifications");
  const { data, error } = await supabase.rpc("hyn_server_notifications", { p_limit: 50 });
  return <main className="container w-full max-w-6xl space-y-6 px-4 pb-16 pt-36 sm:px-6">
    <LiveRefresh />
    <div className="flex flex-wrap items-center justify-between gap-3">
      <Link href="/dashboard" className="inline-flex items-center gap-2 rounded-full border border-border bg-background px-3 py-1.5 font-mono text-xs uppercase text-muted-foreground transition-colors hover:border-foreground/40 hover:text-foreground">
        <ArrowLeft className="size-3.5" aria-hidden />
        Back to dashboard
      </Link>
      <div className="inline-flex items-center rounded-full border border-border p-0.5 text-xs font-mono uppercase">
        <Link href="/dashboard?section=relayers" className="rounded-full px-3 py-1.5 transition-colors text-foreground/70 hover:bg-accent/20 hover:text-foreground">
          <span className="inline-flex items-center gap-2"><RadioTower className="size-3.5" aria-hidden />Server relay</span>
        </Link>
        <span className="rounded-full bg-primary px-3 py-1.5 text-primary-foreground shadow-sm">Notifications</span>
      </div>
    </div>
    <div className="space-y-3">
      <h1 className="font-sentient text-4xl">Server notifications</h1>
      <p className="max-w-3xl text-sm leading-7 text-muted-foreground">This inbox shows alerts from the last seven days: server updates, completed tasks, and heartbeat misses. It refreshes every minute while this page is open. Browser notifications are optional. Detailed local alerts appear only when cloud sharing is enabled on the server.</p>
    </div>
    {error ? <p role="alert" className="terminal-panel p-6">Notifications are unavailable. Ask a Super admin to check your access and the server reporting setup.</p> : <ServerNotifications key={auth.user.id} events={(data ?? []) as ServerNotification[]} userId={auth.user.id} />}
  </main>;
}
