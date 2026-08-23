import Link from "next/link";
import { ArrowLeft, Bell, Server } from "lucide-react";
import { CpuUsageChart } from "@/components/dashboard/cpu-usage-chart";
import { NetworkChart } from "@/components/dashboard/network-chart";
import { StatCards } from "@/components/dashboard/stat-cards";
import { AdminClientActions } from "@/components/admin/client-actions";
import { formatRelative, toCpuSeries, toNetSeries } from "@/lib/dashboard-data";
import type { AdminClient, AdminNode, Metric } from "@/lib/types";

export function AdminClientDashboard({
  client,
  nodes,
  current,
  metrics,
}: {
  client: AdminClient;
  nodes: AdminNode[];
  current: AdminNode | null;
  metrics: Metric[];
}) {
  return (
    <div className="space-y-8">
      <section className="terminal-panel overflow-hidden">
        <div className="border-b border-border p-6 md:flex md:items-end md:justify-between md:gap-6">
          <div>
            <Link
              href="/admin?tab=clients"
              className="inline-flex items-center gap-2 font-mono text-xs text-muted-foreground transition-colors hover:text-primary"
            >
              <ArrowLeft className="size-3.5" aria-hidden /> All clients
            </Link>
            <p className="section-kicker mt-6">// client control room</p>
            <h2 className="mt-2 font-sentient text-3xl text-card-foreground">
              {client.full_name || client.email || "Unnamed client"}
            </h2>
            {client.full_name && client.email ? (
              <p className="mt-2 font-mono text-xs text-muted-foreground">{client.email}</p>
            ) : null}
          </div>
          <div className="mt-5 grid grid-cols-2 gap-px border border-border bg-border font-mono text-xs md:mt-0">
            <div className="flex items-center gap-2 bg-card px-4 py-3">
              <Server className="size-3.5 text-primary" aria-hidden />
              {client.nodes_active}/{client.nodes} active
            </div>
            <div className="flex items-center gap-2 bg-card px-4 py-3">
              <Bell className="size-3.5 text-primary" aria-hidden />
              {client.notifications_30d} deliveries
            </div>
          </div>
        </div>

        <div className="flex flex-wrap gap-2 p-4" aria-label="Client machines">
          {nodes.length > 0 ? (
            nodes.map((node) => (
              <Link
                key={node.id}
                href={`/admin?tab=client&client=${client.id}&node=${node.id}`}
                className={`border px-3 py-2 font-mono text-xs transition-colors ${
                  node.id === current?.id
                    ? "border-primary bg-primary/10 text-primary"
                    : "border-border text-muted-foreground hover:text-foreground"
                }`}
              >
                {node.name}
                {node.status !== "active" ? ` · ${node.status}` : ""}
              </Link>
            ))
          ) : (
            <p className="font-mono text-xs text-muted-foreground">
              This client has not linked a machine yet.
            </p>
          )}
        </div>
      </section>

      <AdminClientActions client={client} nodes={nodes} current={current} />

      {current ? (
        <>
          <div className="flex flex-col gap-2 border-b border-border pb-5 md:flex-row md:items-end md:justify-between">
            <div>
              <p className="section-kicker">// embedded machine dashboard</p>
              <h3 className="mt-2 font-sentient text-2xl text-foreground">{current.name}</h3>
            </div>
            <p className="font-mono text-xs text-muted-foreground">
              {current.hostname ?? "unknown host"} · last push {formatRelative(current.last_seen_at)}
            </p>
          </div>

          {metrics.length > 0 ? (
            <>
              <StatCards latest={metrics[metrics.length - 1]} />
              <div className="grid gap-6 xl:grid-cols-2">
                <CpuUsageChart data={toCpuSeries(metrics)} />
                <NetworkChart data={toNetSeries(metrics)} />
              </div>
            </>
          ) : (
            <div className="terminal-panel p-8 font-mono text-xs leading-6 text-muted-foreground">
              No telemetry has arrived for this machine in the last 24 hours.
            </div>
          )}
        </>
      ) : null}
    </div>
  );
}
