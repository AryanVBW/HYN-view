import Link from "next/link";
import { Button } from "@/components/ui/button";
import { currentStats } from "@/lib/mock-metrics";

const dailyMetrics = [
  { label: "CPU temperature", value: "avg / peak per hour" },
  { label: "Uptime", value: "rolling 30-day percentage" },
  { label: "Latency", value: "p50 / p95 to your edge" },
  { label: "Overall speed", value: "throughput under load" },
  { label: "Average internet speed", value: "download / upload Mbps" },
];

const alertTriggers = [
  "Server crash or unexpected restart",
  "Temperature above your configured threshold",
  "Any malfunction, timeout, or degraded service",
];

export function EmailReports() {
  return (
    <section id="reports" className="container section-pad border-t border-border">
      <div className="grid gap-14 lg:grid-cols-[0.9fr_1.1fr] lg:items-start">
        <div>
          <p className="section-kicker">// daily email reports</p>
          <h2 className="section-title">
            Your infrastructure&apos;s health, delivered to your inbox every morning.
          </h2>
          <p className="mt-6 max-w-lg font-mono text-sm leading-7 text-foreground/60">
            HYN-view compiles a complete daily report of your server&apos;s vitals — temperature,
            uptime, latency, overall speed, and average internet speed — and sends it straight
            to your email. No dashboard login required to stay informed.
          </p>

          <ul className="mt-8 space-y-4">
            {dailyMetrics.map((metric) => (
              <li
                key={metric.label}
                className="flex items-baseline justify-between gap-4 border-b border-border/60 pb-3 font-mono text-sm"
              >
                <span className="text-foreground/80">{metric.label}</span>
                <span className="text-right text-foreground/40">{metric.value}</span>
              </li>
            ))}
          </ul>

          <div className="mt-10 terminal-panel p-5">
            <p className="section-kicker">// incident notifications</p>
            <p className="mt-3 font-mono text-sm leading-7 text-foreground/60">
              Beyond the daily digest, HYN-view emails you the moment something goes wrong —
              with full configuration context attached, so you can act without opening a
              dashboard first.
            </p>
            <ul className="mt-4 space-y-2">
              {alertTriggers.map((trigger) => (
                <li key={trigger} className="flex items-start gap-3 font-mono text-sm text-foreground/70">
                  <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-primary" aria-hidden="true" />
                  {trigger}
                </li>
              ))}
            </ul>
          </div>

          <div className="mt-10 flex flex-wrap items-center gap-4">
            <Button asChild size="sm">
              <Link href="/dashboard">[view live dashboard]</Link>
            </Button>
            <span className="font-mono text-xs uppercase text-foreground/40">
              professional-grade · hassle-free · zero setup
            </span>
          </div>
        </div>

        <div className="terminal-panel overflow-hidden">
          <div className="flex items-center justify-between border-b border-border px-5 py-4 font-mono text-xs uppercase text-foreground/50">
            <span>inbox / daily-report.eml</span>
            <span className="text-primary">delivered</span>
          </div>
          <div className="space-y-1 border-b border-border px-5 py-4 font-mono text-xs text-foreground/50">
            <p>
              <span className="text-foreground/70">From:</span> reports@hyn-view.dev
            </p>
            <p>
              <span className="text-foreground/70">To:</span> ops@yourcompany.com
            </p>
            <p>
              <span className="text-foreground/70">Subject:</span>{" "}
              <span className="text-foreground/80">Daily server report — SKAL-FRA-04</span>
            </p>
          </div>

          <div className="grid grid-cols-2 gap-px border-b border-border bg-border/40 sm:grid-cols-4">
            {[
              { label: "Temp", value: `${currentStats.temperature}°C` },
              { label: "Uptime", value: `${currentStats.uptime}%` },
              { label: "Latency", value: `${currentStats.latency}ms` },
              { label: "Download", value: `${currentStats.downloadSpeed} Mbps` },
            ].map((item) => (
              <div key={item.label} className="bg-background px-4 py-4 font-mono">
                <p className="text-[0.65rem] uppercase text-foreground/40">{item.label}</p>
                <p className="mt-1 text-lg text-foreground">{item.value}</p>
              </div>
            ))}
          </div>

          <div className="space-y-3 px-5 py-5 font-mono text-xs leading-6 text-foreground/60">
            <p>
              <span className="text-primary">ok</span> all systems nominal over the trailing 24
              hours.
            </p>
            <p>Average internet speed: 842↓ / 431↑ Mbps · Node uptime: 112 days</p>
            <p className="text-foreground/40">
              This report was generated automatically at 06:00 UTC. Configuration and raw
              metrics are attached for your records.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
