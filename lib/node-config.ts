export const PORTAL_CONFIG_KEYS = new Set([
  "alert_mem_pct",
  "alert_disk_pct",
  "alert_temp_c",
  "alert_load_per_core",
  "alert_latency_ms",
  "alert_min_severity",
  "alert_repeat_hours",
  "report_at",
  "notify_max_per_day",
  "cloud_push_min",
  "auto_update",
]);

export function mergePortalConfig(
  existing: Record<string, unknown>,
  draft: Record<string, string>,
): Record<string, string> {
  const merged: Record<string, string> = {};
  for (const [key, value] of Object.entries(existing)) {
    if (PORTAL_CONFIG_KEYS.has(key) && (typeof value === "string" || typeof value === "number")) {
      merged[key] = String(value);
    }
  }
  for (const [key, value] of Object.entries(draft)) {
    if (!PORTAL_CONFIG_KEYS.has(key)) continue;
    if (value.trim() === "") delete merged[key];
    else merged[key] = value.trim();
  }
  return merged;
}
