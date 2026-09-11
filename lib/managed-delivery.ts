export type ProviderDelivery = { ok: true; providerId: string | null } | { ok: false; error: string; uncertain?: boolean };
export type ManagedDeliveryResult = { ok: true; providerId: string | null; reused?: boolean } | { ok: false; error: string; deferred?: boolean };
export type DeliveryReservation = {
  allowed: boolean; already_sent?: boolean; provider_id?: string | null;
  attempt_id?: string; reason?: string;
};

// The sender is dependency-injected so refusal, duplicate and failure paths can
// be tested without sending a real email or using any production credentials.
export async function runManagedDelivery(deps: {
  reserve: () => Promise<DeliveryReservation>;
  send: () => Promise<ProviderDelivery>;
  complete: (attempt: string, status: "sent" | "failed" | "unknown", providerId: string | null, error: string | null) => Promise<void>;
}): Promise<ManagedDeliveryResult> {
  let reservation: DeliveryReservation;
  try { reservation = await deps.reserve(); }
  catch { return { ok: false, deferred: true, error: "Delivery controls could not be checked. No email was sent." }; }
  if (reservation.already_sent) return { ok: true, providerId: reservation.provider_id ?? null, reused: true };
  if (!reservation.allowed || !reservation.attempt_id) return { ok: false, deferred: true, error: reservation.reason ?? "Delivery is not permitted." };
  let delivery: ProviderDelivery;
  try { delivery = await deps.send(); }
  catch { delivery = { ok: false, uncertain: true, error: "Provider outcome is unknown. Review the provider before resending." }; }
  try {
    await deps.complete(reservation.attempt_id, delivery.ok ? "sent" : delivery.uncertain ? "unknown" : "failed",
      delivery.ok ? delivery.providerId : null, delivery.ok ? null : delivery.error);
  } catch {
    // A provider acceptance must never be turned into a second send merely
    // because recording the result failed. The reservation remains visible.
    return delivery.ok ? delivery : { ok: false, deferred: true, error: "Delivery outcome could not be recorded. Review this attempt before resending." };
  }
  return delivery;
}
