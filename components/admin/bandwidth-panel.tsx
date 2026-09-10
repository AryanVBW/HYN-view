"use client";
import { useState, useTransition } from "react";
import { createClient } from "@/lib/supabase/client";
import { byteCount, formatBytes, type BandwidthReport } from "@/lib/bandwidth";
import type { Node } from "@/lib/types";

export function BandwidthPanel({ nodes, initialNodeId = "", expanded = false }: { nodes: (Pick<Node, "id" | "name" | "is_demo"> & { owner_email?: string | null })[]; initialNodeId?: string; expanded?: boolean }) {
  const [node, setNode] = useState(initialNodeId);
  const [days, setDays] = useState("30");
  const [report, setReport] = useState<BandwidthReport | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const [loadedName, setLoadedName] = useState("");
  function load() {
    startTransition(async () => {
      setError(null); setReport(null);
      try {
        const result = node
          ? await createClient().rpc("hyn_bandwidth_report", { p_node: node, p_days: Number(days) })
          : await createClient().rpc("hyn_fleet_bandwidth_report", { p_days: Number(days) });
        if (result.error) { setError("Bandwidth reporting is unavailable. Ask a Super admin to check the server reporting setup."); return; }
        setReport(result.data as BandwidthReport);
        setLoadedName(node ? nodes.find(n=>n.id===node)?.name || "Server" : "All accessible servers");
      } catch { setError("Could not load consumption. Try again."); }
    });
  }
  return <section className="terminal-panel rounded-xl p-6 md:p-8">
    <h2 className="font-sentient text-3xl">Bandwidth consumption</h2>
    <p className="mt-3 max-w-2xl text-sm leading-7 text-muted-foreground">Data transferred through the server’s selected WAN interface. Ingress is received data; egress is sent data. Total is both combined.</p>
    <details open={expanded} className="mt-6 border-t border-border pt-5">
      <summary className="cursor-pointer text-lg font-medium">Advanced view · daily consumption</summary>
      <form className="mt-5 flex flex-wrap items-end gap-4" onSubmit={e=>{e.preventDefault();load();}}>
        <label className="min-w-0 flex-1 space-y-2 text-sm">Server<select disabled={pending} className="block w-full rounded border border-input bg-background p-3" value={node} onChange={e=>{setNode(e.target.value);setReport(null);}}>
          <option value="">All accessible servers</option>{nodes.filter(n=>!n.is_demo).map(n=><option key={n.id} value={n.id}>{n.name}{n.owner_email ? ` — ${n.owner_email}` : ""}</option>)}
        </select></label>
        <label className="space-y-2 text-sm">Daily history<select disabled={pending} className="block rounded border border-input bg-background p-3" value={days} onChange={e=>{setDays(e.target.value);setReport(null);}}><option value="7">7 days</option><option value="30">30 days</option><option value="90">90 days</option><option value="366">1 year</option></select></label>
        <button disabled={pending} className="rounded bg-primary px-5 py-3 text-sm text-primary-foreground disabled:opacity-40">{pending ? "Loading…" : "Show consumption"}</button>
      </form>
      {error ? <p role="alert" className="mt-5 text-sm text-destructive">{error}</p> : null}
      {report && !report.sampled_at ? <p role="status" className="mt-6 text-sm text-muted-foreground">No counters received yet. Update this server’s HYN agent to enable consumption reporting. Past usage cannot be reconstructed.</p> : null}
      {report?.sampled_at ? <div className="mt-7 space-y-6" aria-live="polite">
        <div><h3 className="text-xl">{loadedName}</h3><p className="mt-2 text-xs text-muted-foreground">{report.iface || "Combined WAN traffic"} · Last sample {new Date(report.sampled_at).toISOString().replace("T"," ").slice(0,19)} UTC</p></div>
        {report.node_count !== undefined ? <p className="text-sm text-muted-foreground">{report.reporting_count} of {report.node_count} servers have reported consumption. {report.stale_count ? `${report.stale_count} reporting servers have stale samples.` : ""} Missing servers are excluded from totals.</p> : null}
        <dl className="grid gap-5 border-y border-border py-6 sm:grid-cols-3">
          {[["Ingress",byteCount(report.ingress_bytes)],["Egress",byteCount(report.egress_bytes)],["Total consumed",byteCount(report.ingress_bytes)+byteCount(report.egress_bytes)]].map(([label,value])=><div key={String(label)}><dt className="text-sm text-muted-foreground">{String(label)}</dt><dd className="mt-2 font-mono text-2xl tabular-nums" title={`${value} bytes`}>{formatBytes(value as bigint)}</dd></div>)}
        </dl>
        <p className="text-sm">Selected {days}-day window: {formatBytes(report.days.reduce((sum, day) => sum + byteCount(day.ingress_bytes) + byteCount(day.egress_bytes), BigInt(0)))}</p>
        <p className="text-xs leading-6 text-muted-foreground">Observed totals since {report.since}. The first sample and counter resets establish a baseline. Unobserved traffic is excluded. Daily boundaries are estimated when a sample spans midnight; gaps are marked incomplete. These are interface measurements, not provider billing totals.</p>
        <div className="overflow-x-auto"><table className="w-full min-w-[620px] text-sm tabular-nums"><caption className="sr-only">Daily consumption in UTC for {loadedName}</caption><thead><tr className="border-b border-border text-left text-muted-foreground">{["Day (UTC)","Ingress","Egress","Total","Coverage"].map(h=><th scope="col" className="py-3 pr-4 font-normal" key={h}>{h}</th>)}</tr></thead><tbody>
          {report.days.map(d=><tr className="border-b border-border/50" key={d.day}><th scope="row" className="py-4 pr-4 text-left font-normal">{d.day}</th><td className="pr-4">{formatBytes(byteCount(d.ingress_bytes))}</td><td className="pr-4">{formatBytes(byteCount(d.egress_bytes))}</td><td className="pr-4 font-medium">{formatBytes(byteCount(d.ingress_bytes)+byteCount(d.egress_bytes))}</td><td className="text-xs text-muted-foreground">{[d.incomplete ? "Incomplete" : "Observed",d.estimated ? "Estimated day split" : null].filter(Boolean).join(" · ")}</td></tr>)}
        </tbody></table></div>
        {!report.days.length ? <p className="text-sm text-muted-foreground">No samples in this date range.</p> : null}
      </div> : null}
    </details>
  </section>;
}
