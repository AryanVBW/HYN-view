import { AlertTriangle, CheckCircle2, Info } from "lucide-react";
import type { AlertEvent } from "@/lib/types";
import { formatRelative } from "@/lib/dashboard-data";

const severityStyles: Record<AlertEvent["severity"], string> = {
  info: "text-primary border-primary/40",
  warn: "text-[#e8a400] border-[#e8a400]/40",
  crit: "text-destructive border-destructive/40",
};

const severityIcon: Record<AlertEvent["severity"], React.ComponentType<{ className?: string }>> = {
  info: Info,
  warn: AlertTriangle,
  crit: AlertTriangle,
};

export function EventLog({ events }: { events: AlertEvent[] }) {
  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 p-6 duration-500">
      <div className="flex items-center justify-between">
        <div>
          <p className="section-kicker">// alert log</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">What has fired</p>
        </div>
        {events.length === 0 ? <CheckCircle2 className="size-5 text-primary" aria-hidden /> : null}
      </div>

      {events.length === 0 ? (
        <div className="mt-6 flex items-center justify-center rounded-sm border border-dashed border-border/60 px-6 py-12">
          <p className="max-w-xs text-center font-mono text-xs leading-6 text-muted-foreground">
            Nothing has fired. Alert rules are evaluated on the server every 5
            minutes and pushed here with the metrics.
          </p>
        </div>
      ) : (
        <ul className="mt-6 divide-y divide-border/60">
          {events.map((event) => {
            const Icon = severityIcon[event.severity];
            return (
              <li key={event.id} className="flex items-start gap-4 py-4">
                <span
                  className={`mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full border ${severityStyles[event.severity]}`}
                >
                  <Icon className="size-3.5" />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="font-mono text-sm leading-6 text-card-foreground/90">
                    {event.message}
                  </p>
                  <p className="mt-1 flex flex-wrap items-center gap-2 font-mono text-[0.65rem] uppercase text-muted-foreground">
                    <span>{formatRelative(event.ts)}</span>
                    {event.rule ? <span>· {event.rule}</span> : null}
                    {event.resolved ? <span className="text-primary">· resolved</span> : null}
                  </p>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
