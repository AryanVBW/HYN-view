import type { RelayerAssignment, RelayerDashboardData } from "./relayer.ts";
import { fetchFleet, lastFleetSnapshot } from "./relayer-provider.ts";
import { fetchRelayerChain, lastRelayerChain } from "./relayer-chain.ts";

// Call only after loading assignments through the authenticated RLS client.
export async function readAssignedRelayers(
  assignments: RelayerAssignment[],
  selectedId?: number,
): Promise<RelayerDashboardData> {
  if (!assignments.length) return { readings: [], error: null };
  let snapshot;
  let error: string | null = null;
  try {
    snapshot = await fetchFleet();
  } catch {
    snapshot = lastFleetSnapshot();
    error =
      "Highway could not be reached. Last available readings are shown; retrying automatically.";
  }
  // Only enrich the selected assignment. A large account must not multiply
  // registry requests (or its page latency) by its number of relayers.
  const target =
    assignments.find((a) => a.relayer_id === selectedId) ?? assignments[0];
  const readings = await Promise.all(
    assignments.map(async (assignment) => {
      let chain = lastRelayerChain(assignment.relayer_id);
      let chainError: string | null = null;
      try {
        if (assignment.id === target.id)
          chain = await fetchRelayerChain(assignment.relayer_id);
      } catch {
        chain = lastRelayerChain(assignment.relayer_id);
        chainError =
          "The Mosaic registry could not be refreshed. Chain details may be delayed.";
      }
      const relayer =
        snapshot?.relayers.find((r) => r.id === assignment.relayer_id) ?? null;
      return {
        assignment,
        relayer,
        chain,
        chainError,
        sourceAt: snapshot?.sourceAt ?? null,
        fetchedAt: snapshot?.fetchedAt ?? null,
        providerLatencyMs: snapshot?.latencyMs ?? null,
        error:
          error ??
          (!relayer
            ? "This assigned ID is missing from Highway's current feed. Ask an administrator to check the assignment."
            : null),
      };
    }),
  );
  return { readings, error: null };
}
