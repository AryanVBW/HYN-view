import { createClient } from "@supabase/supabase-js";
import {
  applyEmailTemplate,
  buildCommandResultContent,
  escapeHtml,
  renderHynEmailShell,
  renderManagedHynEmail,
  sendResendEmail,
} from "./cloud-email.ts";
import { SUPABASE_URL } from "./supabase/config.ts";

export type WebNotificationJob = {
  id: string;
  nodeId: string;
  nodeName: string;
  hostname: string | null;
  recipient: string;
  fingerprint: string;
  category: "alert" | "report" | "test" | "other";
  severity: "info" | "warn" | "crit";
  subject: string;
  textBody: string;
  htmlBody: string | null;
  template?: string | null;
};

type Delivery = { ok: true; providerId: string | null } | { ok: false; error: string };

export type WebNotificationDependencies = {
  claim: (jobId?: string | null) => Promise<WebNotificationJob | null>;
  send: (args: {
    job: WebNotificationJob;
    html: string;
    idempotencyKey: string;
  }) => Promise<Delivery>;
  complete: (
    jobId: string,
    status: "sent" | "failed",
    recipient: string,
    providerId: string | null,
    error: string | null,
  ) => Promise<void>;
};

export async function dispatchWebNotificationJob(
  jobId: string | null,
  dependencies: WebNotificationDependencies,
) {
  const job = await dependencies.claim(jobId);
  if (!job) return { status: "idle" as const };

  // A monitored machine is untrusted email input. Use its plain body and
  // escape it here rather than accepting agent-supplied active HTML.
  const generated = `<pre style="white-space:pre-wrap;word-break:break-word;margin:0;border:1px solid #17333d;background:#05090c;padding:16px;color:#dcecf2">${escapeHtml(job.textBody)}</pre>`;
  const content = applyEmailTemplate(job.template ?? "{{content}}", {
    subject: job.subject,
    hostname: job.hostname ?? job.nodeName,
    severity: job.severity,
    version: "",
    content: generated,
  });
  const html = renderHynEmailShell({
    subject: job.subject,
    preview: job.textBody.slice(0, 160),
    hostname: job.hostname ?? job.nodeName,
    severity: job.severity,
    content,
  });
  const delivery = await dependencies.send({
    job,
    html,
    idempotencyKey: `web-notification:${job.id}`,
  });
  await dependencies.complete(
    job.id,
    delivery.ok ? "sent" : "failed",
    job.recipient,
    delivery.ok ? delivery.providerId : null,
    delivery.ok ? null : delivery.error,
  );
  return delivery.ok
    ? { status: "sent" as const, providerId: delivery.providerId }
    : { status: "failed" as const, error: delivery.error };
}

export async function dispatchQueuedWebNotification(jobId: string | null = null) {
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
  const resendKey = process.env.RESEND_API_KEY ?? "";
  const from = process.env.EMAIL_FROM ?? "HYN-view <reports@hyn-view.info>";
  if (!SUPABASE_URL || !serviceKey) throw new Error("Supabase service credentials are not configured");
  const supabase = createClient(SUPABASE_URL, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return dispatchWebNotificationJob(jobId, {
    claim: async (requestedId) => {
      const { data, error } = await supabase.rpc("hyn_claim_web_notification", {
        p_job_id: requestedId,
      });
      if (error) throw error;
      const claim = data as Record<string, unknown> | null;
      if (!claim || claim.status !== "send") return null;
      const id = typeof claim.id === "string" ? claim.id : "";
      const nodeId = typeof claim.node_id === "string" ? claim.node_id : "";
      const recipient = typeof claim.recipient === "string" ? claim.recipient : "";
      if (!id || !nodeId || !recipient) {
        throw new Error("queued web notification is missing delivery metadata");
      }
      const category = claim.category === "report" || claim.category === "test" || claim.category === "other"
        ? claim.category
        : "alert";
      const severity = claim.severity === "crit" || claim.severity === "warn" ? claim.severity : "info";
      const templateKey = category === "alert" ? "alert" : "report";
      const { data: template } = await supabase
        .from("notification_templates")
        .select("html_template")
        .eq("template_key", templateKey)
        .maybeSingle();
      return {
        id,
        nodeId,
        nodeName: typeof claim.node_name === "string" ? claim.node_name : "linked machine",
        hostname: typeof claim.hostname === "string" ? claim.hostname : null,
        recipient,
        fingerprint: typeof claim.fingerprint === "string" ? claim.fingerprint : id,
        category,
        severity,
        subject: typeof claim.subject === "string" ? claim.subject : "HYN-view notification",
        textBody: typeof claim.text_body === "string" ? claim.text_body : "No details supplied",
        htmlBody: typeof claim.html_body === "string" ? claim.html_body : null,
        template: template?.html_template ?? null,
      };
    },
    send: async ({ job, html, idempotencyKey }) => sendResendEmail({
      apiKey: resendKey,
      from,
      to: job.recipient,
      subject: job.subject,
      html,
      idempotencyKey,
    }),
    complete: async (id, status, recipient, providerId, errorMessage) => {
      const { error } = await supabase.rpc("hyn_complete_web_notification", {
        p_job_id: id,
        p_status: status,
        p_target: recipient,
        p_provider_id: providerId,
        p_error: errorMessage,
      });
      if (error) throw error;
    },
  });
}

export async function dispatchCommandNotification(commandId: string) {
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
  const resendKey = process.env.RESEND_API_KEY ?? "";
  const from = process.env.EMAIL_FROM ?? "HYN-view <reports@hyn-view.info>";
  if (!SUPABASE_URL || !serviceKey) throw new Error("Supabase service credentials are not configured");
  const supabase = createClient(SUPABASE_URL, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: command, error: commandError } = await supabase
    .from("node_commands")
    .select("id,node_id,command,status,message,target_version,result_version,updated_at")
    .eq("id", commandId)
    .in("status", ["succeeded", "failed", "expired"])
    .maybeSingle();
  if (commandError) throw commandError;
  if (!command) return { status: "pending" as const };
  const idempotencyKey = `command:${command.id}:${command.status}`;
  const { error: claimError } = await supabase.from("cloud_email_dispatches").insert({
    idempotency_key: idempotencyKey,
    node_id: command.node_id,
    kind: "system",
  });
  if (claimError?.code === "23505") return { status: "already-sent" as const };
  if (claimError) throw claimError;

  const [{ data: node, error: nodeError }, { data: preference, error: preferenceError }, { data: template }] = await Promise.all([
    supabase.from("nodes").select("id,owner,name,hostname,agent_version").eq("id", command.node_id).single(),
    supabase.from("email_preferences").select("recipient,system_enabled").eq("node_id", command.node_id).maybeSingle(),
    supabase.from("notification_templates").select("html_template").eq("template_key", "system").maybeSingle(),
  ]);
  if (nodeError || preferenceError || !node || !preference?.recipient || !preference.system_enabled) {
    await supabase.from("cloud_email_dispatches").delete().eq("idempotency_key", idempotencyKey);
    if (nodeError) throw nodeError;
    if (preferenceError) throw preferenceError;
    return { status: "disabled" as const };
  }
  const action = command.command === "sync" ? "Synchronization" : "HYN CLI update";
  const succeeded = command.status === "succeeded";
  const subject = `${action} ${succeeded ? "completed" : "failed"} · ${node.name}`;
  const content = buildCommandResultContent({
    command: command.command === "sync" ? "sync" : "update",
    status: command.status === "succeeded" ? "succeeded" : command.status === "expired" ? "expired" : "failed",
    message: command.message,
    targetVersion: command.target_version,
    resultVersion: command.result_version ?? node.agent_version,
    updatedAt: command.updated_at,
  });
  const html = renderManagedHynEmail({
    template: template?.html_template ?? "{{content}}",
    values: {
      subject,
      hostname: node.hostname ?? node.name,
      version: command.result_version ?? node.agent_version ?? "unknown",
      severity: succeeded ? "info" : "crit",
      content,
    },
    preview: command.message,
  });
  const delivery = await sendResendEmail({
    apiKey: resendKey,
    from,
    to: preference.recipient,
    subject,
    html,
    idempotencyKey,
  });
  await supabase.from("notification_log").insert({
    node_id: node.id,
    owner: node.owner,
    kind: "resend-cloud",
    target: preference.recipient,
    severity: succeeded ? "info" : "crit",
    subject,
    status: delivery.ok ? "sent" : "failed",
    error: delivery.ok ? null : delivery.error,
    category: "other",
  });
  if (!delivery.ok) {
    await supabase.from("cloud_email_dispatches").delete().eq("idempotency_key", idempotencyKey);
    return { status: "failed" as const, error: delivery.error };
  }
  await supabase.from("cloud_email_dispatches").update({ provider_id: delivery.providerId })
    .eq("idempotency_key", idempotencyKey);
  return { status: "sent" as const, providerId: delivery.providerId };
}

export async function retryNodeCommandNotification(nodeId: string) {
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
  if (!SUPABASE_URL || !serviceKey) throw new Error("Supabase service credentials are not configured");
  const supabase = createClient(SUPABASE_URL, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: commands, error } = await supabase
    .from("node_commands")
    .select("id,status")
    .eq("node_id", nodeId)
    .in("status", ["succeeded", "failed", "expired"])
    .order("updated_at", { ascending: false })
    .limit(10);
  if (error) throw error;
  for (const command of commands ?? []) {
    const key = `command:${command.id}:${command.status}`;
    const { data: existing } = await supabase.from("cloud_email_dispatches")
      .select("idempotency_key").eq("idempotency_key", key).maybeSingle();
    if (!existing) return dispatchCommandNotification(command.id);
  }
  return { status: "idle" as const };
}
