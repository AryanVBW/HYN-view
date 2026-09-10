import { ArrowDownLeft, ArrowUpRight } from "lucide-react";
import { byteCount, formatBytes, type BandwidthReport } from "@/lib/bandwidth";

/** Read-only counters for the selected server; reporting controls live in Admin. */
export function BandwidthSummary({ report, error = false }: { report: BandwidthReport | null; error?: boolean }) {
  const sampled = !error && report?.sampled_at;
  const received = sampled ? byteCount(report.ingress_bytes) : null;
  const sent = sampled ? byteCount(report.egress_bytes) : null;
  const total = received !== null && sent !== null ? received + sent : null;
  const counters = [
    { label: "Received", value: received, icon: ArrowDownLeft },
    { label: "Sent", value: sent, icon: ArrowUpRight },
  ];
  return <section aria-label="Bandwidth consumption" className="rounded-xl border border-border p-5 md:p-6">
    <div className="flex flex-wrap items-baseline justify-between gap-2">
      <h2 className="text-lg font-medium">Data usage</h2>
      <p className="text-xs text-muted-foreground">{sampled ? `Last reading ${new Date(report.sampled_at!).toISOString().replace("T", " ").slice(0, 16)} UTC` : "Selected server"}</p>
    </div>
    <dl className="mt-5 grid gap-5 sm:grid-cols-3">
      <div>
        <dt className="text-sm text-muted-foreground">Total transferred</dt>
        <dd key={total?.toString() ?? "empty"} className="mt-2 font-mono text-3xl tabular-nums motion-safe:animate-in motion-safe:fade-in motion-safe:duration-200" title={total !== null ? `${total} bytes` : undefined}>{total !== null ? formatBytes(total) : "—"}</dd>
      </div>
      {counters.map(({label, value, icon: Icon}) => <div key={label}>
        <dt className="flex items-center gap-1.5 text-sm text-muted-foreground"><Icon className="size-4" aria-hidden />{label}</dt>
        <dd key={value?.toString() ?? "empty"} className="mt-2 font-mono text-2xl tabular-nums motion-safe:animate-in motion-safe:fade-in motion-safe:duration-200" title={value !== null ? `${value} bytes` : undefined}>{value !== null ? formatBytes(value) : "—"}</dd>
      </div>)}
    </dl>
    <p role={error ? "status" : undefined} className="mt-5 text-xs leading-6 text-muted-foreground">
      {error ? "Data usage is temporarily unavailable. It will retry when the dashboard refreshes." : !sampled ? "No usage readings yet. Totals will appear when this server reports them." : `Measured traffic${report.since ? ` since ${report.since}` : ""}. Gaps in reporting are excluded.`}
    </p>
  </section>;
}
