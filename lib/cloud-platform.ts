const providerLabels = {
  aws: "Amazon Web Services",
  gcp: "Google Cloud",
  azure: "Microsoft Azure",
  oracle: "Oracle Cloud",
  digitalocean: "DigitalOcean",
  hetzner: "Hetzner",
} as const;

const virtualizationLabels = {
  kvm: "KVM", qemu: "QEMU", xen: "Xen", vmware: "VMware",
  microsoft: "Hyper-V", oracle: "VirtualBox", bhyve: "bhyve",
  parallels: "Parallels", amazon: "Amazon virtualization", google: "Google virtualization",
  docker: "Docker", podman: "Podman", lxc: "LXC", "lxc-libvirt": "LXC",
  containerd: "containerd", openvz: "OpenVZ", "systemd-nspawn": "systemd-nspawn",
} as const;

function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown> : null;
}

function number(value: unknown, { integer = true, positive = false, max = Number.MAX_SAFE_INTEGER } = {}): number | null {
  if (typeof value !== "number" && typeof value !== "string") return null;
  if (typeof value === "string" && !/^(0|[1-9]\d*)(\.\d+)?$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= (positive ? Number.MIN_VALUE : 0)
    && parsed <= max && (!integer || Number.isSafeInteger(parsed)) ? parsed : null;
}

export type CloudPlatform = {
  providerLabel: string;
  providerInferred: boolean;
  virtualizationLabel: string | null;
  environment: "container" | "vm" | "unknown";
  hostCpuCount: number | null;
  hostMemoryBytes: number | null;
  cgroupVersion: 1 | 2 | null;
  cpuLimitCores: number | null;
  memoryLimitBytes: number | null;
  memoryCurrentBytes: number | null;
  cpuThrottledUsec: number | null;
  cpuThrottledPeriods: number | null;
};

// Never promote an arbitrary agent string or a generic Hyper-V signal into a
// verified provider claim. CPU/memory limits describe the agent's cgroup;
// existing CPU and memory telemetry continues to describe its procfs view.
export function readCloudPlatform(payload: unknown): CloudPlatform | null {
  const platform = object(object(payload)?.platform);
  if (!platform) return null;
  const provider = platform.provider;
  const inferred = typeof provider === "string" && Object.hasOwn(providerLabels, provider)
    && platform.provider_confidence === "inferred"
    && (platform.provider_source === "dmi" || platform.provider_source === "device-tree");
  const virtualization = platform.virtualization;
  const cgroupVersion = number(platform.cgroup_version);
  return {
    providerLabel: inferred ? providerLabels[provider as keyof typeof providerLabels] : "Not identified",
    providerInferred: inferred,
    virtualizationLabel: typeof virtualization === "string" && Object.hasOwn(virtualizationLabels, virtualization)
      ? virtualizationLabels[virtualization as keyof typeof virtualizationLabels] : null,
    environment: platform.environment === "container" || platform.environment === "vm" ? platform.environment : "unknown",
    hostCpuCount: number(platform.host_cpu_count, { positive: true, max: 1_000_000 }),
    hostMemoryBytes: number(platform.host_memory_bytes, { positive: true }),
    cgroupVersion: cgroupVersion === 1 || cgroupVersion === 2 ? cgroupVersion : null,
    cpuLimitCores: number(platform.cpu_limit_cores, { integer: false, positive: true, max: 1_000_000 }),
    memoryLimitBytes: number(platform.memory_limit_bytes),
    memoryCurrentBytes: number(platform.memory_current_bytes),
    cpuThrottledUsec: number(platform.cpu_throttled_usec),
    cpuThrottledPeriods: number(platform.cpu_throttled_periods),
  };
}

const monitoringLabels = {
  sample_collected: "Reading collected",
  heartbeat_ok: "Last heartbeat accepted",
  heartbeat_failed: "Last heartbeat unsuccessful",
  cloud_upload_ok: "Last cloud upload accepted",
  cloud_upload_failed: "Last cloud upload unsuccessful",
  cloud_upload_paused: "Cloud uploads paused",
  cloud_upload_suspended: "Cloud uploads suspended",
  agent_restarts: "Service restarts reported",
  service_failed: "Failed services reported",
  service_warning: "Warnings reported in service logs",
  service_error: "Errors reported in service logs",
  alerts_active: "Active alerts",
} as const;

export type MonitoringEntry = {
  ts: string;
  code: keyof typeof monitoringLabels;
  level: "info" | "warn" | "crit";
  label: string;
  count: number;
};

// These are structured snapshot summaries, not arbitrary journal messages or
// a deduplicated event stream. Bound both scanning and rendering work.
export function readMonitoringLogs(payload: unknown): MonitoringEntry[] {
  const raw = object(payload)?.monitoring_logs;
  if (!Array.isArray(raw)) return [];
  const entries: MonitoringEntry[] = [];
  for (const value of raw.slice(0, 64)) {
    const entry = object(value);
    if (!entry || typeof entry.code !== "string" || !Object.hasOwn(monitoringLabels, entry.code)) continue;
    if (entry.level !== "info" && entry.level !== "warn" && entry.level !== "crit") continue;
    if (typeof entry.ts !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:?\d{2})$/.test(entry.ts)) continue;
    const timestamp = Date.parse(entry.ts);
    const count = number(entry.count, { positive: true, max: 999_999_999 });
    if (!Number.isFinite(timestamp) || count === null) continue;
    const code = entry.code as keyof typeof monitoringLabels;
    entries.push({ ts: new Date(timestamp).toISOString(), code, level: entry.level, label: monitoringLabels[code], count });
    if (entries.length === 16) break;
  }
  return entries;
}
