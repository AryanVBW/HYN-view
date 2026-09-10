import Link from "next/link";
import { redirect } from "next/navigation";
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
  return <main className="container max-w-5xl space-y-6 pb-16 pt-36">
    <LiveRefresh />
    <Link href="/dashboard" className="text-primary underline">Back to dashboard</Link>
    <h1 className="font-sentient text-4xl">Server notifications</h1>
    <p className="max-w-3xl text-sm leading-7 text-muted-foreground">Alerts received during the last seven days, completed updates, and servers missing heartbeats. This inbox refreshes every minute while visible. Browser notifications are optional and work while this page is open. Detailed local alerts appear here only when cloud sharing is enabled on the server.</p>
    {error ? <p role="alert" className="terminal-panel p-6">Notifications are unavailable. Ask a Super admin to check your access and the server reporting setup.</p> : <ServerNotifications key={auth.user.id} events={(data ?? []) as ServerNotification[]} userId={auth.user.id} />}
  </main>;
}
