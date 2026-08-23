export const MAX_AGENT_BODY_BYTES = 1_048_576;

const AGENT_RPCS = new Set([
  "hyn_device_start",
  "hyn_device_poll",
  "hyn_ingest",
  "hyn_fetch_config",
  "hyn_report_notification",
]);

export function agentRpcForAction(action: string): string | null {
  return AGENT_RPCS.has(action) ? action : null;
}
