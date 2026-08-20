import { compareVersions, newestVersion } from "@/lib/dashboard-data";
import type { AdminNode } from "@/lib/types";

// Which hyn CLI versions are running across the fleet, and how many machines are
// behind. The yardstick is the newest version reporting in, not the npm registry:
// no page load should depend on an outbound request, and "older than one of your
// own boxes" is a claim that cannot be wrong. Demo nodes carry a fake version and
// are excluded from both the yardstick and the counts.
export function AgentVersions({ nodes }: { nodes: AdminNode[] }) {
  const real = nodes.filter((n) => !n.is_demo);
  if (real.length === 0) return null;

  const newest = newestVersion(real.map((n) => n.agent_version));
  const counts = new Map<string, number>();
  for (const n of real) {
    const key = n.agent_version ?? "unknown";
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  const rows = [...counts.entries()].sort((a, b) => compareVersions(b[0], a[0]));
  const behind = real.filter(
    (n) => !n.agent_version || (newest !== null && compareVersions(n.agent_version, newest) < 0)
  ).length;

  return (
    <div className="terminal-panel p-6">
      <div className="flex flex-col gap-2 md:flex-row md:items-baseline md:justify-between">
        <div>
          <p className="section-kicker">// hyn cli</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">
            Agent versions in the fleet
          </p>
        </div>
        <p className="font-mono text-xs text-muted-foreground">
          newest reporting:{" "}
          <span className="text-card-foreground">hyn {newest ?? "unknown"}</span>
          {behind > 0 ? (
            <span className="text-[#e8a400]">
              {" "}
              · {behind} machine{behind === 1 ? "" : "s"} behind
            </span>
          ) : (
            <span className="text-primary"> · all current</span>
          )}
        </p>
      </div>

      <ul className="mt-6 grid gap-px overflow-hidden border border-border bg-border sm:grid-cols-2 lg:grid-cols-4">
        {rows.map(([version, count]) => {
          const isNewest =
            version !== "unknown" && newest !== null && compareVersions(version, newest) === 0;
          return (
            <li key={version} className="bg-card px-4 py-4">
              <p className="font-mono text-[0.6rem] uppercase tracking-wide text-muted-foreground">
                {version === "unknown" ? "not reported" : `hyn ${version}`}
              </p>
              <p className={`mt-2 font-sentient text-xl ${isNewest ? "text-primary" : "text-[#e8a400]"}`}>
                {count}
              </p>
              <p className="font-mono text-[0.6rem] text-muted-foreground">
                {isNewest ? "current" : "upgrade: sudo npm i -g hyn-view"}
              </p>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
