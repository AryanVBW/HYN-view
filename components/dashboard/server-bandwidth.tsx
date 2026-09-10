import { createClient } from "@/lib/supabase/server";
import type { BandwidthReport } from "@/lib/bandwidth";
import { BandwidthSummary } from "./bandwidth-summary";

export async function ServerBandwidth({ nodeId }: { nodeId: string }) {
  let report: BandwidthReport | null = null;
  let failed = false;
  try {
    const supabase = await createClient();
    // Session-scoped RPC rechecks ownership/sharing; never use fleet totals here.
    const { data, error } = await supabase.rpc("hyn_bandwidth_report", { p_node: nodeId, p_days: 7 });
    report = error ? null : data as BandwidthReport | null;
    failed = Boolean(error);
  } catch {
    failed = true;
  }
  return <BandwidthSummary report={report} error={failed} />;
}
