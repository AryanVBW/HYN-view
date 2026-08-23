export const NODE_COMMAND_COLUMNS =
  "id,node_id,command,status,stage,message,target_version,result_version,requested_at,started_at,finished_at,updated_at" as const;

export type NodeUpdateStatus = "queued" | "running" | "succeeded" | "failed" | "expired";
export type NodeUpdateStage =
  | "queued"
  | "accepted"
  | "checking"
  | "installing"
  | "restarting"
  | "verifying"
  | "completed"
  | "failed"
  | "expired";

export type NodeUpdateCommand = {
  id: string;
  node_id: string;
  command: "update";
  status: NodeUpdateStatus;
  stage: NodeUpdateStage;
  message: string;
  target_version: string | null;
  result_version: string | null;
  requested_at: string;
  started_at: string | null;
  finished_at: string | null;
  updated_at: string;
};

export type AgentRelease = {
  latest: string | null;
  available: boolean;
  checkedAt: number | null;
};

export const UPDATE_STEPS = [
  { key: "queued", label: "Queued" },
  { key: "checking", label: "Registry check" },
  { key: "installing", label: "Package install" },
  { key: "restarting", label: "Restart services" },
  { key: "verifying", label: "Verify & sync" },
  { key: "completed", label: "Complete" },
] as const;

const STATUSES = new Set<NodeUpdateStatus>(["queued", "running", "succeeded", "failed", "expired"]);
const STAGES = new Set<NodeUpdateStage>([
  "queued", "accepted", "checking", "installing", "restarting", "verifying",
  "completed", "failed", "expired",
]);

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

export function readAgentRelease(payload: Record<string, unknown> | null): AgentRelease {
  const raw = payload?.agent_update;
  if (!raw || Array.isArray(raw) || typeof raw !== "object") {
    return { latest: null, available: false, checkedAt: null };
  }
  const update = raw as Record<string, unknown>;
  const checked = Number(update.checked_at);
  return {
    latest: text(update.latest),
    available: update.available === true || update.available === 1 || update.available === "1",
    checkedAt: Number.isFinite(checked) && checked > 0 ? checked : null,
  };
}

export function normalizeNodeUpdate(value: unknown): NodeUpdateCommand | null {
  if (!value || Array.isArray(value) || typeof value !== "object") return null;
  const row = value as Record<string, unknown>;
  const status = text(row.status) as NodeUpdateStatus | null;
  const stage = text(row.stage) as NodeUpdateStage | null;
  const id = text(row.id);
  const nodeId = text(row.node_id);
  const requestedAt = text(row.requested_at);
  const updatedAt = text(row.updated_at);
  if (!id || !nodeId || !requestedAt || !updatedAt || !status || !stage) return null;
  if (!STATUSES.has(status) || !STAGES.has(stage)) return null;
  return {
    id,
    node_id: nodeId,
    command: "update",
    status,
    stage,
    message: text(row.message) ?? stage,
    target_version: text(row.target_version),
    result_version: text(row.result_version),
    requested_at: requestedAt,
    started_at: text(row.started_at),
    finished_at: text(row.finished_at),
    updated_at: updatedAt,
  };
}

export function updateStageIndex(stage: NodeUpdateStage): number {
  if (stage === "accepted") return 1;
  if (stage === "failed" || stage === "expired") return -1;
  return UPDATE_STEPS.findIndex((step) => step.key === stage);
}

export function updateIsActive(command: NodeUpdateCommand | null): boolean {
  return command?.status === "queued" || command?.status === "running";
}
