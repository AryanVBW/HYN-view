import type { Metric, Node } from "@/lib/types";
import { formatBytes, formatRelative } from "@/lib/dashboard-data";
import { readCloudPlatform } from "@/lib/cloud-platform";

export function ServerDetailsPanel({ node, latest }: { node: Node; latest: Metric }) {
  const platform = readCloudPlatform(latest.payload);
  const details: { label: string; value: string }[] = [
    { label: "Node name", value: node.name },
    { label: "Hostname", value: node.hostname ?? "—" },
    { label: "Operating system", value: node.os ?? "—" },
    { label: "Agent version", value: node.agent_version ? `hyn ${node.agent_version}` : "—" },
    { label: "CPU", value: latest.cpu_model ?? "—" },
    { label: "System CPU cores", value: latest.cpu_cores ? String(latest.cpu_cores) : "—" },
    { label: "System memory", value: formatBytes(latest.mem_total) },
    { label: "WAN interface", value: latest.net_iface ?? "—" },
    { label: "Last push", value: formatRelative(node.last_seen_at) },
    { label: "Linked", value: new Date(node.created_at).toLocaleDateString() },
  ];
  if (platform) {
    details.push({ label: "Cloud provider", value: `${platform.providerLabel}${platform.providerInferred ? " (inferred)" : ""}` });
    const environment = platform.environment === "container" ? "Container" : platform.environment === "vm" ? "Virtual machine" : "Not identified";
    details.push({ label: "Environment", value: platform.virtualizationLabel ? `${environment} · ${platform.virtualizationLabel}` : environment });
    if (platform.cgroupVersion !== null) {
      details.push(
        { label: "Workload CPU limit", value: platform.cpuLimitCores === null ? "No finite limit reported" : `${platform.cpuLimitCores.toLocaleString("en-US", { maximumFractionDigits: 3 })} cores` },
        { label: "Workload memory limit", value: platform.memoryLimitBytes === null ? "No finite limit reported" : formatBytes(platform.memoryLimitBytes) },
        { label: "Workload memory used", value: formatBytes(platform.memoryCurrentBytes) },
        { label: "CPU throttling periods", value: platform.cpuThrottledPeriods === null ? "—" : platform.cpuThrottledPeriods.toLocaleString("en-US") },
      );
    }
  }

  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 p-6 duration-500">
      <p className="section-kicker">// node specification</p>
      <p className="mt-2 font-sentient text-2xl text-card-foreground">
        What is reporting in
      </p>
      <dl className="mt-6 grid grid-cols-1 gap-x-8 gap-y-3 sm:grid-cols-2 lg:grid-cols-3">
        {details.map((detail) => (
          <div key={detail.label} className="border-b border-border/60 pb-2">
            <dt className="font-mono text-[0.6rem] uppercase text-muted-foreground">
              {detail.label}
            </dt>
            <dd className="mt-1 truncate font-mono text-sm text-card-foreground" title={detail.value}>
              {detail.value}
            </dd>
          </div>
        ))}
      </dl>
      {platform && platform.cgroupVersion !== null ? (
        <p className="mt-4 font-mono text-xs leading-6 text-muted-foreground">
          Workload limits and usage apply to the HYN process&apos;s resource group.
          System CPU and memory readings can cover a wider view. Throttling periods are a cumulative count.
        </p>
      ) : null}
    </div>
  );
}
