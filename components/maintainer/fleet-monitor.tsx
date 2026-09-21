import Link from "next/link";
import { AlertTriangle, Activity, ServerOff, ThermometerSun } from "lucide-react";
import { bytesPerSecToMbit, formatRelative } from "@/lib/dashboard-data";
import { formatBytes, summariseFleet, type Concern, type FleetServer } from "@/lib/fleet-monitor";
import { NodeSendControls } from "./node-send-controls";

const panel = "terminal-panel rounded-xl p-5 md:p-6";
const pct = (value: number | null | undefined) =>
  value === null || value === undefined || !Number.isFinite(Number(value)) ? "—" : `${Math.round(Number(value))}%`;
const degrees = (value: number | null | undefined) =>
  value === null || value === undefined || !Number.isFinite(Number(value)) ? "—" : `${Math.round(Number(value))}°C`;
const mbps = (value: number | null | undefined) =>
  value === null || value === undefined || !Number.isFinite(Number(value))
    ? "—"
    : `${bytesPerSecToMbit(Number(value))} Mbps`;

function ConcernPills({ concerns }: { concerns: Concern[] }) {
  return (
    <span className="flex flex-wrap gap-1">
      {concerns.map((concern) => (
        <span
          key={concern.label}
          className={`rounded-full border px-2 py-0.5 font-mono text-[0.6rem] uppercase ${
            concern.severity === "crit"
              ? "border-destructive/50 bg-destructive/10 text-destructive"
              : "border-[#e8a400]/50 bg-[#e8a400]/10 text-[#e8a400]"
          }`}
        >
          {concern.label}
        </span>
      ))}
    </span>
  );
}

export function FleetMonitor({ servers }: { servers: FleetServer[] }) {
  const summary = summariseFleet(servers);

  const cards: { label: string; value: string; tone?: string; icon: typeof Activity }[] = [
    { label: "servers reporting", value: `${summary.reporting}/${summary.total}`, icon: Activity,
      tone: summary.notReporting > 0 ? "text-[#e8a400]" : "text-primary" },
    { label: "not reporting", value: String(summary.notReporting), icon: ServerOff,
      tone: summary.notReporting > 0 ? "text-destructive" : undefined },
    { label: "open alerts", value: `${summary.openAlerts}${summary.criticalAlerts ? ` · ${summary.criticalAlerts} crit` : ""}`,
      icon: AlertTriangle, tone: summary.criticalAlerts > 0 ? "text-destructive" : summary.openAlerts > 0 ? "text-[#e8a400]" : undefined },
    { label: "hottest server", value: degrees(summary.hottestC), icon: ThermometerSun,
      tone: (summary.hottestC ?? 0) >= 80 ? "text-destructive" : undefined },
  ];

  return (
    <div className="space-y-10">
      <section aria-label="Fleet status" className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {cards.map((card) => (
          <div key={card.label} className={panel}>
            <div className="flex items-center justify-between gap-2">
              <p className="font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">{card.label}</p>
              <card.icon className={`size-4 ${card.tone ?? "text-muted-foreground"}`} aria-hidden />
            </div>
            <p className={`mt-3 font-sentient text-3xl tabular-nums ${card.tone ?? "text-card-foreground"}`}>{card.value}</p>
          </div>
        ))}
      </section>

      <section aria-label="Aggregate consumption" className={panel}>
        <p className="section-kicker">// across every server</p>
        <div className="mt-4 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {[
            { label: "download now", value: `${summary.downMbps} Mbps` },
            { label: "upload now", value: `${summary.upMbps} Mbps` },
            { label: "data recorded", value: formatBytes(summary.bytes) },
            { label: "peak cpu · disk", value: `${pct(summary.peakCpuPct)} · ${pct(summary.peakDiskPct)}` },
          ].map((item) => (
            <div key={item.label}>
              <p className="font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">{item.label}</p>
              <p className="mt-2 font-sentient text-2xl tabular-nums text-card-foreground">{item.value}</p>
            </div>
          ))}
        </div>
        <p className="mt-4 font-mono text-[0.65rem] leading-5 text-muted-foreground">
          Throughput is the combined rate from the newest reading of every reporting server. Data recorded is the
          retained cloud window, not a billing figure. A value that was never measured shows as{" "}
          <span className="text-card-foreground">—</span> rather than zero.
        </p>
      </section>

      <section aria-label="Needs attention" className="space-y-4">
        <p className="section-kicker border-b border-border pb-3">
          // needs attention {summary.attention.length ? `(${summary.attention.length})` : ""}
        </p>
        {summary.attention.length === 0 ? (
          <p className={`${panel} font-mono text-sm text-muted-foreground`}>
            Every server is reporting, with no open alert and nothing over threshold. Nothing needs action right now.
          </p>
        ) : (
          <ul className="space-y-3">
            {summary.attention.map(({ server, concerns }) => (
              <li key={server.node.id} className={`${panel} flex flex-wrap items-start justify-between gap-4`}>
                <div className="min-w-0">
                  <Link
                    href={`/dashboard?owner=${encodeURIComponent(server.node.owner)}&node=${server.node.id}`}
                    className="font-mono text-sm text-card-foreground hover:text-primary"
                  >
                    {server.node.name}
                  </Link>
                  <p className="mt-1 font-mono text-xs text-muted-foreground">
                    {server.node.hostname ?? "unknown host"} · last seen {formatRelative(server.node.last_seen_at)}
                  </p>
                  <div className="mt-2">
                    <ConcernPills concerns={concerns} />
                  </div>
                </div>
                <NodeSendControls nodeId={server.node.id} nodeName={server.node.name} />
              </li>
            ))}
          </ul>
        )}
      </section>

      <section aria-label="Every server" className="space-y-4">
        <p className="section-kicker border-b border-border pb-3">// every server ({servers.length})</p>
        <div className="overflow-x-auto rounded-lg border border-border/60">
          <table className="w-full min-w-[1100px] border-collapse font-mono text-xs">
            <thead>
              <tr className="border-b border-border bg-card/60 text-left uppercase text-muted-foreground">
                {["server", "state", "cpu", "mem", "disk", "temp", "now (down/up)", "speed test", "data", "alerts", "send"].map((head) => (
                  <th key={head} className="py-3 pr-4 pl-4 font-normal">{head}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {servers.map((server) => {
                const { node, metric, speedtest, freshness, openAlerts } = server;
                const crit = openAlerts.filter((alert) => alert.severity === "crit").length;
                return (
                  <tr key={node.id} className="border-b border-border/40 align-top transition-colors hover:bg-card/40">
                    <td className="py-3 pr-4 pl-4">
                      <Link
                        href={`/dashboard?owner=${encodeURIComponent(node.owner)}&node=${node.id}`}
                        className="text-card-foreground hover:text-primary"
                      >
                        {node.name}
                      </Link>
                      <span className="block text-muted-foreground">{node.hostname ?? "—"}{node.is_demo ? " · demo" : ""}</span>
                      <span className="block text-muted-foreground">hyn {node.agent_version ?? "unknown"}</span>
                    </td>
                    <td className="py-3 pr-4 whitespace-nowrap">
                      <span className={freshness.tone}>{freshness.label}</span>
                      <span className="block text-muted-foreground">{formatRelative(node.last_seen_at)}</span>
                    </td>
                    <td className="py-3 pr-4 text-card-foreground/80">{pct(metric?.cpu_pct)}</td>
                    <td className="py-3 pr-4 text-card-foreground/80">{pct(metric?.mem_pct)}</td>
                    <td className="py-3 pr-4 text-card-foreground/80">{pct(metric?.disk_pct)}</td>
                    <td className="py-3 pr-4 text-card-foreground/80">{degrees(metric?.cpu_temp_c)}</td>
                    <td className="py-3 pr-4 text-card-foreground/80 whitespace-nowrap">
                      {mbps(metric?.net_rx_bps)} <span className="text-muted-foreground">/</span> {mbps(metric?.net_tx_bps)}
                    </td>
                    <td className="py-3 pr-4 text-card-foreground/80 whitespace-nowrap">
                      {speedtest
                        ? <>{mbps(speedtest.down_bps)} <span className="text-muted-foreground">/</span> {mbps(speedtest.up_bps)}</>
                        : "—"}
                    </td>
                    <td className="py-3 pr-4 text-card-foreground/80">{formatBytes(server.bytes)}</td>
                    <td className="py-3 pr-4">
                      <span className={crit ? "text-destructive" : openAlerts.length ? "text-[#e8a400]" : "text-muted-foreground"}>
                        {openAlerts.length}{crit ? ` · ${crit} crit` : ""}
                      </span>
                    </td>
                    <td className="py-3 pr-4">
                      <NodeSendControls nodeId={node.id} nodeName={node.name} />
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        {servers.length === 0 ? (
          <p className={`${panel} font-mono text-sm text-muted-foreground`}>
            No servers are visible to this account yet. A Super admin links machines; they appear here as soon as they exist.
          </p>
        ) : null}
      </section>
    </div>
  );
}
