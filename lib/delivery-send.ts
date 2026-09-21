import { createClient } from "@supabase/supabase-js";
import { sendResendEmail } from "./cloud-email.ts";
import { automaticEmailAllowed, manualOnlyReason } from "./email-automation.ts";
import { runManagedDelivery, type DeliveryReservation, type ManagedDeliveryResult } from "./managed-delivery.ts";
import type { MessageKind } from "./delivery-controls.ts";

export const deliveryControlsEnabled = () => process.env.HYN_DELIVERY_CONTROLS_ENABLED === "true";
export async function sendManagedEmail(args: Parameters<typeof sendResendEmail>[0] & {
  delivery: { kind: MessageKind; ownerId?: string; nodeId?: string; nodeIds?: string[]; manual?: boolean };
}): Promise<ManagedDeliveryResult> {
  // The automation gate lives here, and only here, because every email this
  // portal sends passes through this function -- the scheduled digests, the
  // agent-queued alerts, the command results, the outage watchdog, device
  // linking and the admin reports all import it. A per-caller check would be
  // nine checks to keep in sync and one forgotten check away from mailing a
  // customer anyway, so a new sender is refused by default rather than
  // silently automatic.
  //
  // It is deliberately ahead of the D1 short-circuit below: "stopped" has to
  // mean stopped on either store, not just on Postgres.
  //
  // `manual: true` is the administrator saying "send this now", which is the
  // only thing that lifts it.
  if (!args.delivery.manual && !automaticEmailAllowed(args.delivery.kind)) {
    return { ok: false, deferred: true, error: manualOnlyReason(args.delivery.kind) };
  }
  // D1 holds application data. Delivery-budget RPCs live on Postgres, so skip
  // them when the Worker is the store and send through Resend directly.
  if (!deliveryControlsEnabled() || (process.env.HYN_DATA_API_URL ?? "").replace(/\/$/, "")) {
    return sendResendEmail(args);
  }
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key || !args.idempotencyKey || (!args.delivery.ownerId && !args.delivery.nodeId)) {
    return { ok: false, deferred: true, error: "Managed delivery controls are not configured. No email was sent." };
  }
  if (!args.apiKey || !args.from || !args.to) return { ok: false, deferred: true, error: "Email delivery is not configured." };
  const database = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return runManagedDelivery({
    reserve: async () => {
      const { data, error } = await database.rpc("hyn_reserve_delivery", {
        p_key: args.idempotencyKey, p_kind: args.delivery.kind,
        p_owner: args.delivery.ownerId ?? null, p_node: args.delivery.nodeId ?? null,
        p_recipient: args.to, p_subject: args.subject, p_nodes: args.delivery.nodeIds ?? null,
      });
      if (error) throw error;
      return data as DeliveryReservation;
    },
    send: async () => {
      let responded = false;
      const delivery = await sendResendEmail({ ...args, fetchImpl: async (input, init) => {
        const response = await (args.fetchImpl ?? fetch)(input, { ...init, signal: AbortSignal.timeout(20000) });
        responded = true;
        return response;
      } });
      return !delivery.ok && !responded ? { ...delivery, uncertain: true } : delivery;
    },
    complete: async (attempt, status, providerId, errorMessage) => {
      const { error } = await database.rpc("hyn_complete_delivery", {
        p_attempt: attempt, p_status: status, p_provider_id: providerId, p_error: errorMessage,
      });
      if (error) throw error;
    },
  });
}
