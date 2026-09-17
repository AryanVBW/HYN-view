import Link from "next/link";
import { redirect } from "next/navigation";
import { isD1Data, storeRpc } from "@/lib/hyn-data";
import { createClient } from "@/lib/supabase/server";
import { permissions } from "@/lib/permissions";
import { deliveryKinds, type DeliverySnapshot, type DeliveryKind } from "@/lib/delivery-controls";
import { buildDailyDigestContent, renderManagedHynEmail } from "@/lib/cloud-email";
import { DeliveryDashboard } from "@/components/admin/delivery-dashboard";

export const dynamic = "force-dynamic";

export default async function DeliveriesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/signin");
  const { data: profile } = isD1Data()
    ? await storeRpc<{ role?: string; status?: string }>("hyn_profile")
    : await supabase.from("profiles").select("role,status").eq("id", auth.user.id).single();
  const access = permissions(profile?.role);
  if (!access.canAdmin || profile?.status !== "active") redirect("/dashboard");
  const params = await searchParams;
  const owner = typeof params.owner === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(params.owner) ? params.owner : null;
  const kind = typeof params.kind === "string" && deliveryKinds.some(k => k.key === params.kind) ? params.kind as DeliveryKind : "all";
  const statuses = ["all", "pending", "sending", "sent", "failed", "suppressed", "unknown", "cancelled"];
  const status = typeof params.status === "string" && statuses.includes(params.status) ? params.status : "all";
  const page = Math.min(4001, Math.max(1, Number.parseInt(String(params.page ?? "1"), 10) || 1));
  const result = await storeRpc("hyn_admin_delivery_dashboard", { p_owner: owner, p_kind: kind, p_status: status, p_offset: (page - 1) * 25 });
  const template = isD1Data()
    ? { data: ((await storeRpc<Array<{ template_key: string; html_template: string }>>("hyn_admin_templates")).data ?? []).find((row) => row.template_key === "report") }
    : await supabase.from("notification_templates").select("html").eq("kind", "report").maybeSingle();
  const previewHtml = renderManagedHynEmail({ template: (template.data as { html?: string; html_template?: string } | null)?.html ?? (template.data as { html_template?: string } | null)?.html_template, values: {
    subject: "Your daily server digest - sample", hostname: "2 permitted servers", severity: "info", version: "daily digest",
    content: `<p>This is sample data. One email combines all servers this user is allowed to monitor.</p>${["Mumbai gateway", "Pune worker"].map(nodeName => buildDailyDigestContent({ nodeName, sampleCount: 288, cpuAverage: 24, cpuPeak: 68, memoryAverage: 42, temperaturePeak: 57, downloadAverageBps: 12000, uploadAverageBps: 8000, latencyAverageMs: 19, uptimeSeconds: 86400 })).join("")}`,
  }, preview: "A combined daily overview of your permitted servers." });
  return <main className="min-h-screen bg-background px-4 py-8 text-foreground sm:px-8">
    <div className="mx-auto max-w-7xl">
      <Link href="/admin?tab=notifications" className="font-mono text-xs text-muted-foreground underline underline-offset-4 hover:text-foreground">Back to admin</Link>
      <header className="my-8 border-b border-border pb-6">
        <p className="section-kicker">// delivery operations</p>
        <h1 className="mt-3 font-sentient text-4xl sm:text-5xl">Every alert, accounted for.</h1>
        <p className="mt-3 max-w-2xl text-sm text-muted-foreground">Set sending budgets, schedule one daily summary per user, and follow every attempt without losing the history.</p>
      </header>
      {result.error || !result.data ? <section role="alert" className="terminal-panel rounded-xl border border-destructive/50 p-6">
        <h2 className="font-sentient text-2xl">Delivery controls are unavailable</h2>
        <p className="mt-2 text-sm">The database could not load the delivery dashboard. Check the delivery migration and your administrator access before enabling sending.</p>
        <p className="mt-3 font-mono text-xs text-muted-foreground">{result.error?.message ?? "No dashboard data returned."}</p>
      </section> : <DeliveryDashboard key={`${owner ?? "global"}:${kind}:${status}:${page}:${result.data.as_of}`} snapshot={result.data as DeliverySnapshot} owner={owner} kind={kind} status={status} page={page} canWrite={access.canWrite}
        enforced={process.env.HYN_DELIVERY_CONTROLS_ENABLED === "true"} providerConfigured={Boolean(process.env.RESEND_API_KEY && process.env.SUPABASE_SERVICE_ROLE_KEY)} previewHtml={previewHtml} />}
    </div>
  </main>;
}
