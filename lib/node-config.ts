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
  "dashboard_view",
]);

function integer(value: string, max: number, allowZero = true) {
  const pattern = allowZero ? /^(0|[1-9][0-9]*)$/ : /^[1-9][0-9]*$/;
  return pattern.test(value) && Number(value) <= max;
}

function validExistingValue(key: string, value: string) {
  switch (key) {
    case "alert_mem_pct":
    case "alert_disk_pct": return integer(value, 100);
    case "alert_temp_c": return integer(value, 200);
    case "alert_load_per_core": return integer(value, 10_000);
    case "alert_latency_ms": return integer(value, 600_000);
    case "alert_repeat_hours": return integer(value, 8_760);
    case "notify_max_per_day": return integer(value, 10_000);
    case "cloud_push_min": return integer(value, 1_440, false);
    case "alert_min_severity": return value === "crit" || value === "warn" || value === "info";
    case "auto_update": return value === "install" || value === "check" || value === "off";
    case "dashboard_view": return value === "dash" || value === "simple";
    case "report_at": return /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value);
    default: return false;
  }
}

export function mergePortalConfig(
  existing: Record<string, unknown>,
  draft: Record<string, string>,
): Record<string, string> {
  const merged: Record<string, string> = {};
  for (const [key, value] of Object.entries(existing)) {
    if (PORTAL_CONFIG_KEYS.has(key) && (typeof value === "string" || typeof value === "number")) {
      const normalized = String(value);
      if (validExistingValue(key, normalized)) merged[key] = normalized;
    }
  }
  for (const [key, value] of Object.entries(draft)) {
    if (!PORTAL_CONFIG_KEYS.has(key)) continue;
    if (value.trim() === "") delete merged[key];
    else merged[key] = value.trim();
  }
  return merged;
}
