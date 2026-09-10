// Shared presentation model. Only explicitly selected public provider fields
// cross the server boundary; an owner never receives the provider's fleet.
export const CHECKIN_LIMIT_S = 300;
export const HEARTBEAT_LIMIT_S = 660;
export const SOURCE_STALE_S = 120;
export type RelayerAssignment = {
  id: string;
  owner: string;
  relayer_id: number;
  relayer_name: string;
  created_at: string;
};
export type NodeRelayerLink = {
  node_id: string;
  assignment_id: string;
};
export type Relayer = {
  id: number;
  name: string;
  tier: string | null;
  registered: boolean | null;
  authorized: boolean | null;
  inActiveSet: boolean | null;
  heartbeating: boolean | null;
  online: boolean | null;
  lastCheckinAt: string | null;
  lastHeartbeatAt: string | null;
  registration: string | null;
  relayerCount: number | null;
  configVersion: number | null;
  packageId: string | null;
  deviceId: string | null;
  country: string | null;
  city: string | null;
  latitude: number | null;
  longitude: number | null;
};
export type RelayerChain = {
  observedAt: string;
  block: number;
  epoch: number | null;
  registered: boolean;
  authorized: boolean | null;
  inActiveSet: boolean | null;
  earningWeight: string | null;
  rewardsBalance: string | null;
  managerBalance: string | null;
  managerExists: boolean | null;
  tokenSymbol: string;
  rewardsWallet: string | null;
  managerWallet: string | null;
  operationalKeys: { chain: string; key: string; balance: string | null }[];
  blsKey: string | null;
  p2pKey: string | null;
};
export type RelayerReading = {
  assignment: RelayerAssignment;
  relayer: Relayer | null;
  chain: RelayerChain | null;
  sourceAt: string | null;
  fetchedAt: string | null;
  providerLatencyMs: number | null;
  error: string | null;
  chainError: string | null;
};
export type RelayerDashboardData = {
  readings: RelayerReading[];
  error: string | null;
  canRequest?: boolean;
  requests?: RelayerRequest[];
  requestsError?: string | null;
  manageHref?: string | null;
};
export type RelayerRequest = {
  id: string;
  relayer_id: number;
  relayer_name: string;
  status: "pending" | "approved" | "rejected" | "cancelled";
  created_at: string;
};

export function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}
export function textValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.slice(0, 512) : null;
}
export function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? value
    : null;
}
export function booleanValue(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}
export function timestamp(value: unknown): string | null {
  const t = textValue(value);
  return t && Number.isFinite(Date.parse(t)) ? new Date(t).toISOString() : null;
}
export function normalizeRelayer(raw: unknown): Relayer | null {
  const r = record(raw),
    flags = record(r.flags);
  const id = numberValue(r.chainRelayerId);
  if (id === null || !Number.isSafeInteger(id) || id < 1 || id > 2147483647)
    return null;
  const coordinate = (v: unknown, limit: number) =>
    typeof v === "number" && Number.isFinite(v) && Math.abs(v) <= limit
      ? v
      : null;
  return {
    id,
    name: textValue(r.onChainName) ?? `Relayer ${id}`,
    tier: textValue(r.tier),
    registered: booleanValue(flags.registered),
    authorized: booleanValue(flags.authorized),
    inActiveSet:
      booleanValue(flags.inActiveSet) ?? booleanValue(flags.inActiveSetMosaic),
    online: booleanValue(flags.online),
    heartbeating: booleanValue(flags.heartbeating),
    lastCheckinAt: timestamp(r.lastCheckinAt),
    lastHeartbeatAt: timestamp(r.lastHeartbeatAt),
    registration: textValue(r.registrationStatus),
    relayerCount: numberValue(r.relayerCount),
    configVersion: numberValue(r.configVersion),
    packageId: textValue(r.userPackageId),
    deviceId: textValue(r.shortDeviceId),
    country: textValue(r.country),
    city: textValue(r.city),
    latitude: coordinate(r.latitude, 90),
    longitude: coordinate(r.longitude, 180),
  };
}
export function ageSeconds(at: string | null, now: number): number | null {
  if (!at) return null;
  const delta = (now - Date.parse(at)) / 1000;
  // Allow small clock skew, but do not treat a future-dated feed as live.
  return Number.isFinite(delta) && delta >= -30 ? Math.max(0, delta) : null;
}
export function freshness(
  at: string | null,
  limit: number,
  now: number,
): boolean | null {
  const age = ageSeconds(at, now);
  return age === null ? null : age < limit;
}
export function relayerChecks(reading: RelayerReading, now: number) {
  const r = reading.relayer;
  const sourceFresh =
    !reading.error && freshness(reading.sourceAt, SOURCE_STALE_S, now) === true;
  const chainFresh =
    freshness(reading.chain?.observedAt ?? null, SOURCE_STALE_S, now) === true;
  const checkin =
    sourceFresh && r ? freshness(r.lastCheckinAt, CHECKIN_LIMIT_S, now) : null;
  const heartbeat =
    sourceFresh && r
      ? freshness(r.lastHeartbeatAt, HEARTBEAT_LIMIT_S, now)
      : null;
  const checks = [
    {
      label: "Registered",
      value: chainFresh
        ? reading.chain!.registered
        : sourceFresh
          ? (r?.registered ?? null)
          : null,
    },
    {
      label: "Check-in",
      value:
        checkin === false || (sourceFresh && r?.online === false)
          ? false
          : checkin,
    },
    // These two flags are verified against finalized chain state, matching
    // Highway's own UI. Its fleet service can lag behind the registry.
    {
      label: "Authorized",
      value: chainFresh ? reading.chain!.authorized : null,
    },
    {
      label: "In active set",
      value: chainFresh ? reading.chain!.inActiveSet : null,
    },
    {
      label: "Heartbeat",
      value:
        heartbeat === false || (sourceFresh && r?.heartbeating === false)
          ? false
          : heartbeat,
    },
  ];
  const passed = checks.filter((c) => c.value === true).length;
  const failed = checks.some((c) => c.value === false);
  return {
    checks,
    passed,
    sourceFresh,
    chainFresh,
    label: failed
      ? "Needs attention"
      : passed === checks.length
        ? "Healthy"
        : "Awaiting verification",
    tone: failed ? "warning" : passed === checks.length ? "healthy" : "unknown",
  };
}
export function bitmapMember(hex: unknown, id: number): boolean | null {
  if (
    typeof hex !== "string" ||
    !/^0x(?:[0-9a-f]{2})*$/i.test(hex) ||
    !Number.isInteger(id) ||
    id < 1
  )
    return null;
  const bit = id - 1; // Highway IDs are one-based; bitmap positions are not.
  const byte = Math.floor(bit / 8);
  if (byte * 2 >= hex.length - 2) return false;
  return (
    (parseInt(hex.slice(2 + byte * 2, 4 + byte * 2), 16) & (1 << (bit % 8))) !==
    0
  );
}
// Preserve token precision instead of converting a u128 balance to a float.
export function tokenAmount(raw: unknown, decimals: number): string | null {
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 30) return null;
  if (typeof raw !== "string" && typeof raw !== "number") return null;
  if (typeof raw === "number" && (!Number.isSafeInteger(raw) || raw < 0))
    return null;
  if (!/^(?:\d+|0x[0-9a-f]+)$/i.test(String(raw))) return null;
  const digits = BigInt(raw)
    .toString()
    .padStart(decimals + 1, "0");
  if (!decimals) return digits;
  const fraction = digits.slice(-decimals).replace(/0+$/, "");
  return `${digits.slice(0, -decimals)}${fraction ? `.${fraction}` : ""}`;
}
