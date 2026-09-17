"use server";

import { revalidatePath } from "next/cache";
import { storeRpc } from "@/lib/hyn-data";
import { createClient } from "@/lib/supabase/server";
import { validRules, type RuleInput } from "@/lib/delivery-controls";

type Result = { ok: true } | { ok: false; error: string };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const validOwner = (owner: string | null) => owner === null || (typeof owner === "string" && UUID.test(owner));

async function mutate(name: string, args: Record<string, unknown>): Promise<Result> {
  try {
    const supabase = await createClient();
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) return { ok: false, error: "Sign in again." };
    const permission = await storeRpc("hyn_is_super_admin");
    if (permission.error || permission.data !== true) return { ok: false, error: "An active super admin account is required." };
    const { error } = await storeRpc(name, args);
    if (error) return { ok: false, error: error.message };
    revalidatePath("/admin/deliveries");
    return { ok: true };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : "Delivery settings could not be saved." };
  }
}

export async function saveDeliveryRules(owner: string | null, rules: RuleInput[]): Promise<Result> {
  if (!validOwner(owner) || !validRules(rules)) return { ok: false, error: "Use valid daily limits, 1-5 attempts, and 1-1440 minutes between retries." };
  return mutate("hyn_admin_set_delivery_rules", { p_owner: owner, p_rules: rules });
}

export async function saveDailyDigest(owner: string | null, enabled: boolean, at: string, timezone: string, inherit = false, confirmAll = false): Promise<Result> {
  if (!validOwner(owner) || typeof enabled !== "boolean" || typeof inherit !== "boolean" || typeof confirmAll !== "boolean" ||
      typeof at !== "string" || !/^([01]\d|2[0-3]):[0-5]\d$/.test(at) || typeof timezone !== "string" || !timezone.trim() || timezone.length > 100) {
    return { ok: false, error: "Choose a user, a valid time, and an IANA timezone." };
  }
  if (owner === null && !confirmAll) return { ok: false, error: "Confirm the global change before saving." };
  return mutate("hyn_admin_set_digest", { p_owner: owner, p_enabled: enabled, p_at: at, p_timezone: timezone.trim(), p_inherit: inherit, p_confirm_all: confirmAll });
}

export async function stopDelivery(eventId: string): Promise<Result> {
  if (typeof eventId !== "string" || !UUID.test(eventId)) return { ok: false, error: "Select a valid delivery." };
  return mutate("hyn_admin_stop_delivery", { p_event: eventId });
}
