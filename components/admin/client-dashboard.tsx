import Link from "next/link";
import { ArrowLeft, Bell, Server } from "lucide-react";
import { CpuUsageChart } from "@/components/dashboard/cpu-usage-chart";
import { HighwayPanel } from "@/components/dashboard/highway-panel";
import { NetworkChart } from "@/components/dashboard/network-chart";
import { StatCards } from "@/components/dashboard/stat-cards";
import {
  FilesystemsPanel,
  NetworkDetailPanel,
  PowerPanel,
  PressurePanel,
  ProcessesPanel,
} from "@/components/dashboard/telemetry-detail";
import { AdminClientActions } from "@/components/admin/client-actions";
import { DeleteNodeButton } from "@/components/admin/delete-node-button";
import { TemperatureChart } from "@/components/dashboard/temperature-chart";
import { neverLinked } from "@/lib/admin-data";
import { formatRelative, toCpuSeries, toNetSeries, toTempSeries } from "@/lib/dashboard-data";
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
      <section className="terminal-panel overflow-hidden rounded-xl duration-500 animate-in fade-in slide-in-from-bottom-2">
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
          <div className="mt-5 grid grid-cols-2 gap-px overflow-hidden rounded-lg border border-border bg-border font-mono text-xs md:mt-0">
            <div className="flex items-center gap-2 bg-card px-4 py-3">
              <Server className="size-3.5 text-primary" aria-hidden />
              {client.nodes_active}/{client.nodes} active
              {client.nodes_unlinked > 0 ? (
                <span className="text-[color:var(--chart-2)]">· {client.nodes_unlinked} never linked</span>
              ) : null}
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
                className={`rounded-full border px-3 py-2 font-mono text-xs transition-colors ${
                  node.id === current?.id
                    ? "border-primary bg-primary/10 text-primary"
                    : "border-border text-muted-foreground hover:text-foreground"
                }`}
              >
                {node.name}
                {node.status !== "active" ? ` · ${node.status}` : ""}
                {neverLinked(node) ? " · never linked" : ""}
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
            <div className="flex flex-col items-start gap-1 md:items-end">
              <p className="font-mono text-xs text-muted-foreground">
                {current.hostname ?? "unknown host"} · last push {formatRelative(current.last_seen_at)}
              </p>
              {neverLinked(current) ? (
                <p className="font-mono text-xs text-[color:var(--chart-2)]">
                  never linked · approved {formatRelative(current.created_at)}, the agent never
                  checked in
                </p>
              ) : null}
              <DeleteNodeButton node={current} />
            </div>
          </div>

          {metrics.length > 0 ? (
            <>
              <StatCards latest={metrics[metrics.length - 1]} />
              <div className="grid gap-6 xl:grid-cols-2">
                <CpuUsageChart data={toCpuSeries(metrics)} />
                <NetworkChart data={toNetSeries(metrics)} />
              </div>
              {/* The same thermal trace the client gets, hover readout included:
                  an administrator asked "was it hot at 04:00" needs the value at
                  a point, not the shape of the curve. */}
              <TemperatureChart data={toTempSeries(metrics)} />
              {/* Same detail the client sees on their own dashboard. An
                  administrator diagnosing a machine for someone who cannot reach
                  it needs the filesystems, the link counters and the process
                  list, not a summary that sends them back to asking for ssh. */}
              <HighwayPanel latest={metrics[metrics.length - 1]} />
              <NetworkDetailPanel latest={metrics[metrics.length - 1]} />
              <FilesystemsPanel latest={metrics[metrics.length - 1]} />
              <PowerPanel latest={metrics[metrics.length - 1]} />
              <PressurePanel latest={metrics[metrics.length - 1]} />
              <ProcessesPanel latest={metrics[metrics.length - 1]} />
            </>
          ) : (
            <div className="terminal-panel rounded-xl p-8 font-mono text-xs leading-6 text-muted-foreground">
              No telemetry has arrived for this machine in the last 24 hours.
            </div>
          )}
        </>
      ) : null}
    </div>
  );
}
