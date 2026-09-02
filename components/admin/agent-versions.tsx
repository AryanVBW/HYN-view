import { compareVersions, newestVersion } from "@/lib/dashboard-data";
import { AdminFleetUpdateButton } from "@/components/admin/client-actions";
import type { AdminNode } from "@/lib/types";

// The registry result is reported by the agents themselves during telemetry, so
// this page does not make an outbound request and the update button can use the
// exact release each machine observed.
export function AgentVersions({ nodes }: { nodes: AdminNode[] }) {
  const real = nodes.filter((n) => !n.is_demo);
  if (real.length === 0) return null;

  const newestInstalled = newestVersion(real.map((n) => n.agent_version));
  const newestRelease = newestVersion(real.map((n) => n.latest_agent_version));
  const newest = newestRelease ?? newestInstalled;
  const counts = new Map<string, number>();
  for (const n of real) {
    const key = n.agent_version ?? "unknown";
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  const rows = [...counts.entries()].sort((a, b) => compareVersions(b[0], a[0]));
  const behind = real.filter((n) => n.update_available || (
    n.latest_agent_version !== null &&
    (!n.agent_version || compareVersions(n.agent_version, n.latest_agent_version) < 0)
  )).length;

  return (
    <div className="terminal-panel rounded-xl p-6 duration-500 animate-in fade-in slide-in-from-bottom-2 md:p-7">
      <div className="flex flex-col gap-2 md:flex-row md:items-baseline md:justify-between">
        <div>
          <p className="section-kicker">// hyn cli</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">
            Agent versions in the fleet
          </p>
        </div>
        <p className="font-mono text-xs text-muted-foreground">
          latest reported release:{" "}
          <span className="text-card-foreground">hyn {newest ?? "unknown"}</span>
          {behind > 0 ? (
            <span className="text-[color:var(--chart-2)]">
              {" "}
              · {behind} machine{behind === 1 ? "" : "s"} behind
            </span>
          ) : (
            <span className="text-primary"> · all current</span>
          )}
        </p>
      </div>

      <ul className="mt-6 grid gap-px overflow-hidden rounded-lg border border-border bg-border sm:grid-cols-2 lg:grid-cols-4">
        {rows.map(([version, count]) => {
          const isNewest =
            version !== "unknown" && newest !== null && compareVersions(version, newest) === 0;
          return (
            <li key={version} className="bg-card px-4 py-4">
              <p className="font-mono text-[0.6rem] uppercase tracking-wide text-muted-foreground">
                {version === "unknown" ? "not reported" : `hyn ${version}`}
              </p>
              <p className={`mt-2 font-sentient text-xl ${isNewest ? "text-primary" : "text-[color:var(--chart-2)]"}`}>
                {count}
              </p>
              <p className="font-mono text-[0.6rem] text-muted-foreground">
                {isNewest ? "current" : "upgrade: sudo npm i -g hyn-view"}
              </p>
            </li>
          );
        })}
      </ul>
      <AdminFleetUpdateButton nodes={real} />
    </div>
  );
}
