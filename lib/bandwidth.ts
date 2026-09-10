export type BandwidthDay = { day: string; ingress_bytes: string; egress_bytes: string; samples: number; incomplete: boolean; estimated: boolean };
export type BandwidthReport = { node_count?: number; reporting_count?: number; stale_count?: number; iface: string | null; sampled_at: string | null; since: string | null; ingress_bytes: string; egress_bytes: string; days: BandwidthDay[] };
export function byteCount(value: string): bigint {
  return /^\d+$/.test(value) ? BigInt(value) : BigInt(0);
}
export function formatBytes(value: bigint): string {
  const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"];
  let divisor = BigInt(1), unit = 0;
  while (value >= divisor * BigInt(1024) && unit < units.length - 1) { divisor *= BigInt(1024); unit++; }
  const hundredths = value * BigInt(100) / divisor;
  return `${hundredths / BigInt(100)}.${String(hundredths % BigInt(100)).padStart(2,"0")} ${units[unit]}`;
}
