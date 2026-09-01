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

export type CommandTargetState = {
  status: "active" | "paused" | "suspended";
  revoked: boolean;
  is_demo: boolean;
};

// Why this machine cannot accept a command right now, or null when it can. These
// are the same states the database refuses on (_hyn_command_node), checked before
// the button is offered rather than only after it is clicked: a dialog explaining
// why a click could never have worked is a worse answer than a disabled control
// that says so up front. The database check stays -- this one is a courtesy, and
// the row could change between render and click.
export function commandBlockedReason(node: CommandTargetState): string | null {
  if (node.is_demo) return "Demo data has no machine behind it to command.";
  if (node.revoked) {
    return "The credential was revoked, so the portal cannot reach this machine. Pair it again with sudo hyn link.";
  }
  if (node.status === "suspended") {
    return "This machine is suspended, so it accepts nothing until an administrator lifts it.";
  }
  if (node.status === "paused") {
    return "Monitoring is paused, so readings and commands are refused until it is resumed.";
  }
  return null;
}

export type CommandRecovery = {
  /** Where the person reading this has to act. */
  where: "portal" | "server";
  hint: string;
  /** Shell lines to run on the monitored machine; empty when `where` is portal. */
  commands: string[];
};

const SERVER_RECOVERY = [
  "sudo hyn doctor",
  "systemctl status hyn-agent.service hyn-push.timer",
  "sudo hyn doctor --fix",
];

// A failed command used to print one fixed recovery block -- `sudo hyn doctor`,
// then restart the push timer -- whatever had gone wrong. For every
// administrative refusal that advice is not merely useless but misleading: no
// command on the machine can lift a pause, reinstate a suspended machine, or
// restore a credential the portal revoked, and someone who has just been told to
// ssh in and run doctor will conclude the agent is broken when it is fine.
//
// The refusal texts are the database's own (see _hyn_command_node), so matching
// on them is matching on our own vocabulary, not on a provider's error strings.
// Anything unrecognised keeps the server recovery, because that is where an
// agent-side failure or a timeout genuinely is fixed.
export function commandRecovery(message: string | null | undefined): CommandRecovery {
  const text = (message ?? "").toLowerCase();
  if (text.includes("paused")) {
    return {
      where: "portal",
      hint: "Nothing on the machine can clear this. Resume the machine from the admin panel — a paused machine refuses readings and commands until it is resumed, and a timed pause resumes by itself when it expires.",
      commands: [],
    };
  }
  if (text.includes("suspended")) {
    return {
      where: "portal",
      hint: "An administrator has to lift the suspension; until then the machine is refused, and the agent treats that as an administrative decision rather than a fault.",
      commands: [],
    };
  }
  if (text.includes("revoked")) {
    return {
      where: "server",
      hint: "The credential was invalidated in the portal, so the machine has to be paired again. This is the one refusal that is fixed on the machine.",
      commands: ["sudo hyn link"],
    };
  }
  if (text.includes("demo")) {
    return {
      where: "portal",
      hint: "Demo data is a synthetic node with no machine behind it. Remove it and pair a real server to use these controls.",
      commands: [],
    };
  }
  if (text.includes("another account") || text.includes("no longer exists")) {
    return {
      where: "portal",
      hint: "Reload the dashboard and pick the machine again — this one is no longer on this account.",
      commands: [],
    };
  }
  return {
    where: "server",
    hint: "The request reached the portal but the machine did not complete it. Check the resident agent and the timers on the machine.",
    commands: SERVER_RECOVERY,
  };
}
