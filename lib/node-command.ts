export const NODE_COMMAND_COLUMNS =
  "id,node_id,command,status,stage,message,target_version,result_version,requested_at,started_at,finished_at,updated_at" as const;

export type CommandKind = "update" | "sync";
export type NodeCommandStatus = "queued" | "running" | "succeeded" | "failed" | "expired";
export type NodeCommandStage =
  | "queued"
  | "accepted"
  | "checking"
  | "installing"
  | "restarting"
  | "collecting"
  | "uploading"
  | "verifying"
  | "completed"
  | "failed"
  | "expired";

export type NodeCommand = {
  id: string;
  node_id: string;
  command: CommandKind;
  status: NodeCommandStatus;
  stage: NodeCommandStage;
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

export const COMMAND_STEPS = {
  update: [
    { key: "queued", label: "Queued" },
    { key: "checking", label: "Registry check" },
    { key: "installing", label: "Package install" },
    { key: "restarting", label: "Restart services" },
    { key: "verifying", label: "Verify & sync" },
    { key: "completed", label: "Complete" },
  ],
  sync: [
    { key: "queued", label: "Queued" },
    { key: "collecting", label: "Collect system" },
    { key: "uploading", label: "Upload reading" },
    { key: "verifying", label: "Verify portal" },
    { key: "completed", label: "Complete" },
  ],
} as const;

const KINDS = new Set<CommandKind>(["update", "sync"]);
const STATUSES = new Set<NodeCommandStatus>(["queued", "running", "succeeded", "failed", "expired"]);
const COMMON_STAGES = new Set<NodeCommandStage>([
  "queued", "accepted", "verifying", "completed", "failed", "expired",
]);
const UPDATE_STAGES = new Set<NodeCommandStage>([
  ...COMMON_STAGES, "checking", "installing", "restarting",
]);
const SYNC_STAGES = new Set<NodeCommandStage>([
  ...COMMON_STAGES, "collecting", "uploading",
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

export function commandSteps(kind: CommandKind) {
  return COMMAND_STEPS[kind];
}

export function normalizeNodeCommand(value: unknown): NodeCommand | null {
  if (!value || Array.isArray(value) || typeof value !== "object") return null;
  const row = value as Record<string, unknown>;
  const command = text(row.command) ?? text(row.action);
  const status = text(row.status) as NodeCommandStatus | null;
  const stage = text(row.stage) as NodeCommandStage | null;
  const id = text(row.id);
  const nodeId = text(row.node_id);
  const requestedAt = text(row.requested_at);
  const updatedAt = text(row.updated_at);
  if (!id || !nodeId || !requestedAt || !updatedAt || !command || !status || !stage) return null;
  if (!KINDS.has(command as CommandKind) || !STATUSES.has(status)) return null;
  const kind = command as CommandKind;
  if (!(kind === "update" ? UPDATE_STAGES : SYNC_STAGES).has(stage)) return null;
  return {
    id,
    node_id: nodeId,
    command: kind,
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

export function commandStageIndex(kind: CommandKind, stage: NodeCommandStage): number {
  if (stage === "accepted") return 1;
  if (stage === "failed" || stage === "expired") return -1;
  return commandSteps(kind).findIndex((step) => step.key === stage);
}

export function commandIsActive(command: NodeCommand | null): boolean {
  return command?.status === "queued" || command?.status === "running";
}
