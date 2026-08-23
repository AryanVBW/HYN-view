export type HeartbeatKey = "connected" | "delayed" | "quiet" | "unknown";

export type HeartbeatState = {
  key: HeartbeatKey;
  ageSeconds: number | null;
  label: string;
};

function elapsed(seconds: number) {
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;
  return remainder === 0 ? `${minutes}m` : `${minutes}m ${remainder}s`;
}

export function heartbeatState(iso: string | null | undefined, now = Date.now()): HeartbeatState {
  const receivedAt = typeof iso === "string" ? Date.parse(iso) : Number.NaN;
  if (!Number.isFinite(receivedAt) || !Number.isFinite(now)) {
    return { key: "unknown", ageSeconds: null, label: "Heartbeat unknown" };
  }
  const ageSeconds = Math.max(0, Math.floor((now - receivedAt) / 1_000));
  const key: HeartbeatKey = ageSeconds < 90
    ? "connected"
    : ageSeconds < 180
      ? "delayed"
      : "quiet";
  const prefix = key === "connected" ? "Connected" : key === "delayed" ? "Delayed" : "Gone quiet";
  return { key, ageSeconds, label: `${prefix} · ${elapsed(ageSeconds)} ago` };
}
