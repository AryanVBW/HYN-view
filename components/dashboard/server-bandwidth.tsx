import { isD1Data, userDataRpc } from "@/lib/hyn-data";
import { createClient } from "@/lib/supabase/server";
import type { BandwidthReport } from "@/lib/bandwidth";
import { BandwidthSummary } from "./bandwidth-summary";

export async function ServerBandwidth({ nodeId }: { nodeId: string }) {
  let report: BandwidthReport | null = null;
  let failed = false;
  try {
    const result = isD1Data()
      ? await userDataRpc<BandwidthReport>("hyn_bandwidth_report", { p_node: nodeId, p_days: 7 })
      : await (await createClient()).rpc("hyn_bandwidth_report", { p_node: nodeId, p_days: 7 });
    report = result.error ? null : result.data as BandwidthReport | null;
    failed = Boolean(result.error);
  } catch {
    failed = true;
  }
  return <BandwidthSummary report={report} error={failed} />;
}
