export const MAX_AGENT_BODY_BYTES = 1_048_576;

const AGENT_RPCS = new Set([
  "hyn_device_start",
  "hyn_device_poll",
  "hyn_ingest",
  "hyn_fetch_config",
  "hyn_report_notification",
  "hyn_claim_node_command",
  "hyn_report_node_command",
]);

export function agentRpcForAction(action: string): string | null {
  return AGENT_RPCS.has(action) ? action : null;
}

const IP_ADDRESS = /^[0-9A-Fa-f:.]+$/;

export function observedPublicIp(forwardedFor: string | null): string | null {
  const value = forwardedFor?.split(",", 1)[0]?.trim() ?? "";
  return value.length > 0 && value.length <= 64 && IP_ADDRESS.test(value) ? value : null;
}

export function enrichIngestWithPublicIp(
  body: Record<string, unknown>,
  forwardedFor: string | null,
): Record<string, unknown> {
  const ip = observedPublicIp(forwardedFor);
  const payload = body.p_payload;
  if (!ip || !payload || Array.isArray(payload) || typeof payload !== "object") return body;
  const network = (payload as Record<string, unknown>).network;
  const safeNetwork = network && !Array.isArray(network) && typeof network === "object"
    ? network as Record<string, unknown>
    : {};
  return {
    ...body,
    p_payload: {
      ...(payload as Record<string, unknown>),
      network: { ...safeNetwork, public_ip: ip },
    },
  };
}
