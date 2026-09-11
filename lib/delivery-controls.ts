export const deliveryKinds = [
  { key: "all", label: "All managed email", description: "Shared sending budget across every email type." },
  { key: "daily", label: "Daily digest", description: "One combined HTML email per user, with their permitted servers and 24-hour health summary." },
  { key: "incident", label: "Incident and heartbeat alerts", description: "HTML email with severity, server name, event and recovery details. Eligible events also appear independently in the web inbox." },
  { key: "system", label: "System reports", description: "HTML inventory of hardware, software and Highway services." },
  { key: "command", label: "Command results", description: "HTML confirmation of a refresh or update, its result and recovery guidance." },
  { key: "signin", label: "Sign-in notices", description: "HTML notice of a successful sign-in. Authentication and password-reset messages are managed separately by Supabase Auth." },
  { key: "device", label: "Device linked", description: "HTML confirmation that a computer has been linked." },
  { key: "first_report", label: "First system report", description: "HTML report after the first complete telemetry upload." },
  { key: "admin_report", label: "Admin-requested reports", description: "HTML report for a selected account, sent only after an administrator requests it." },
  { key: "other", label: "Other managed messages", description: "Other web-managed email, including agent test messages." },
] as const;
export type DeliveryKind = typeof deliveryKinds[number]["key"];
export type MessageKind = Exclude<DeliveryKind, "all">;
export type DeliveryRule = {
  scope: string; owner: string | null; kind: DeliveryKind; enabled: boolean;
  daily_limit: number | null; max_attempts: number; retry_minutes: number;
};
export type RuleInput = Pick<DeliveryRule, "kind" | "enabled" | "daily_limit" | "max_attempts" | "retry_minutes">;
export type DigestSetting = { scope: string; owner: string | null; configured: boolean; enabled: boolean; send_at: string; timezone: string };
export type DeliveryAttempt = { id: string; started_at: string; finished_at: string | null; status: string; error: string | null; provider_id: string | null };
export type DeliveryEvent = {
  id: string; owner: string; owner_name: string; owner_email: string | null; node_name: string | null;
  kind: MessageKind; subject: string; recipient: string; status: string; reason: string | null;
  attempt_count: number; attempt_limit: number; terminal: boolean; updated_at: string;
  next_retry_at: string | null; attempts: DeliveryAttempt[];
};
export type DeliveryUsage = { kind: MessageKind; attempts: number; sent: number; failed: number; unknown: number };
export type DeliverySnapshot = {
  as_of: string; day_start: string; started_at: string;
  rules: DeliveryRule[]; digest_settings: DigestSetting[];
  users: { id: string; name: string; email: string | null; status: string }[];
  usage: DeliveryUsage[]; global_usage: DeliveryUsage[];
  events: DeliveryEvent[]; total: number;
  legacy: { id: number; ts: string; owner_name: string; node_name: string | null; kind: string; status: string; subject: string | null; error: string | null }[];
};
export const kindLabel = (kind: string) => deliveryKinds.find(item => item.key === kind)?.label ?? kind;
export function defaultRule(kind: DeliveryKind): RuleInput {
  return { kind, enabled: true, daily_limit: null, max_attempts: kind === "all" ? 3 : 5, retry_minutes: kind === "all" ? 15 : 1 };
}
export function validRules(value: unknown): value is RuleInput[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > deliveryKinds.length) return false;
  const kinds = new Set<string>();
  return value.every(rule => {
    if (!rule || typeof rule !== "object" || !deliveryKinds.some(kind => kind.key === rule.kind) || kinds.has(rule.kind)) return false;
    kinds.add(rule.kind);
    return typeof rule.enabled === "boolean"
      && (rule.daily_limit === null || (Number.isInteger(rule.daily_limit) && rule.daily_limit >= 0 && rule.daily_limit <= 100000))
      && Number.isInteger(rule.max_attempts) && rule.max_attempts >= 1 && rule.max_attempts <= 5
      && Number.isInteger(rule.retry_minutes) && rule.retry_minutes >= 1 && rule.retry_minutes <= 1440;
  });
}
export function effectiveDigest(settings: DigestSetting[], owner: string | null) {
  return settings.find(setting => owner && setting.owner === owner)
    ?? settings.find(setting => setting.scope === "global")
    ?? { scope: "global", owner: null, configured: false, enabled: false, send_at: "08:00", timezone: "UTC" };
}
export function attemptTotal(usage: DeliveryUsage[], kind: DeliveryKind = "all") {
  return usage.filter(row => kind === "all" || row.kind === kind).reduce((total, row) => total + Number(row.attempts), 0);
}
