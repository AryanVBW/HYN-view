import {
  normalizeRelayer,
  record,
  timestamp,
  type Relayer,
} from "./relayer.ts";

const FLEET_URL = "https://highwayp2p.com/api/fleet/relayers";
export type FleetSnapshot = {
  relayers: Relayer[];
  sourceAt: string | null;
  fetchedAt: string;
  latencyMs: number;
};
let cached: FleetSnapshot | null = null;
let pending: Promise<FleetSnapshot> | null = null;

export function parseFleet(
  value: unknown,
  fetchedAt: string,
  latencyMs: number,
): FleetSnapshot {
  const raw = record(value);
  if (!Array.isArray(raw.relayers))
    throw new Error("Highway returned an unrecognized relayer feed.");
  const relayers = raw.relayers
    .map(normalizeRelayer)
    .filter((r): r is Relayer => r !== null);
  if (
    relayers.length !== raw.relayers.length ||
    new Set(relayers.map((r) => r.id)).size !== relayers.length
  ) {
    throw new Error(
      "Highway returned invalid or duplicate relayer identities.",
    );
  }
  return {
    relayers,
    sourceAt: timestamp(raw.generatedAt),
    fetchedAt,
    latencyMs,
  };
}

export async function fetchFleet(): Promise<FleetSnapshot> {
  if (cached && Date.now() - Date.parse(cached.fetchedAt) < 15_000)
    return cached;
  if (pending) return pending;
  pending = (async () => {
    const start = performance.now();
    const response = await fetch(FLEET_URL, {
      cache: "no-store",
      redirect: "error",
      signal: AbortSignal.timeout(8000),
      headers: { Accept: "application/json" },
    });
    if (!response.ok)
      throw new Error(
        response.status === 401 || response.status === 403
          ? "Highway now requires authentication for its relayer feed. Contact your administrator."
          : "Highway is unavailable. The dashboard will retry automatically.",
      );
    // Bound the body as well as the request time.
    const reader = response.body?.getReader();
    if (!reader) throw new Error("Highway returned an empty response.");
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > 4_000_000) {
          await reader.cancel();
          throw new Error(
            "Highway's relayer feed exceeded the supported size.",
          );
        }
        chunks.push(value);
      }
    } finally {
      reader.releaseLock();
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    cached = parseFleet(
      JSON.parse(new TextDecoder().decode(bytes)),
      new Date().toISOString(),
      Math.round(performance.now() - start),
    );
    return cached;
  })();
  try {
    return await pending;
  } finally {
    pending = null;
  }
}

export function lastFleetSnapshot(): FleetSnapshot | null {
  return cached;
}
