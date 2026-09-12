import { AlertTriangle, Info } from "lucide-react";
import { readMonitoringLogs } from "@/lib/cloud-platform";

const levelStyles = {
  info: "text-primary border-primary/40",
  warn: "text-[#e8a400] border-[#e8a400]/40",
  crit: "text-destructive border-destructive/40",
};
const levelLabels = { info: "Info", warn: "Warning", crit: "Critical" };

export function MonitoringLog({ payload }: { payload: Record<string, unknown> | null }) {
  const entries = readMonitoringLogs(payload);
  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 p-6 duration-500">
      <p className="section-kicker">// monitoring summary</p>
      <p className="mt-2 font-sentient text-2xl text-card-foreground">Monitoring activity</p>
      <p className="mt-3 font-mono text-xs leading-6 text-muted-foreground">
        Status and counts from the latest reading. Detailed system logs remain on the server.
      </p>
      {entries.length === 0 ? (
        <div className="mt-6 rounded-sm border border-dashed border-border/60 px-6 py-8">
          <p className="text-center font-mono text-xs leading-6 text-muted-foreground">
            No monitoring summary has been reported for this reading yet.
          </p>
        </div>
      ) : (
        <>
          <ul className="mt-4 divide-y divide-border/60">
            {entries.map((entry, index) => {
              const Icon = entry.level === "info" ? Info : AlertTriangle;
              return (
                <li key={`${entry.ts}-${entry.code}-${index}`} className="flex items-start gap-3 py-4">
                  <span className={`mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full border ${levelStyles[entry.level]}`}>
                    <Icon className="size-3.5" aria-hidden />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="font-mono text-sm leading-6 text-card-foreground/90">{entry.label}</p>
                    <p className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 font-mono text-[0.65rem] text-muted-foreground">
                      <span>{levelLabels[entry.level]}</span>
                      <span>Count: {entry.count.toLocaleString("en-US")}</span>
                      <time dateTime={entry.ts}>{entry.ts.slice(0, 19).replace("T", " ")} UTC</time>
                    </p>
                  </div>
                </li>
              );
            })}
          </ul>
          <p className="mt-3 font-mono text-xs leading-6 text-muted-foreground">
            Repeated readings can contain the same totals; these counts are not new events per refresh.
          </p>
        </>
      )}
    </div>
  );
}
