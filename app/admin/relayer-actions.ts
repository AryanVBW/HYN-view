"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { fetchFleet } from "@/lib/relayer-provider";

type Result = { ok: boolean; error?: string };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
async function adminClient() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) throw new Error("Sign in again.");
  const { data, error } = await supabase.rpc("hyn_is_admin");
  if (error || data !== true)
    throw new Error("An active administrator account is required.");
  return supabase;
}
export async function assignRelayer(
  owner: string,
  relayerId: number,
): Promise<Result> {
  if (
    !UUID.test(owner) ||
    !Number.isSafeInteger(relayerId) ||
    relayerId <= 0 ||
    relayerId > 2147483647
  )
    return { ok: false, error: "Select a user and a valid relayer ID." };
  try {
    const supabase = await adminClient();
    const fleet = await fetchFleet();
    const relayer = fleet.relayers.find((r) => r.id === relayerId);
    if (!relayer)
      return {
        ok: false,
        error: "This ID is not in the current Highway feed. Search again.",
      };
    const { error } = await supabase.rpc("hyn_admin_assign_relayer", {
      p_owner: owner,
      p_relayer_id: relayerId,
      p_relayer_name: relayer.name.slice(0, 160),
    });
    if (error) return { ok: false, error: error.message };
    revalidatePath("/admin");
    revalidatePath("/dashboard");
    return { ok: true };
  } catch (error) {
    return {
      ok: false,
      error:
        error instanceof Error
          ? error.message
          : "Assignment could not be saved.",
    };
  }
}
export async function removeRelayer(assignmentId: string): Promise<Result> {
  if (!UUID.test(assignmentId))
    return { ok: false, error: "Invalid assignment." };
  try {
    const supabase = await adminClient();
    const { error } = await supabase.rpc("hyn_admin_remove_relayer", {
      p_assignment_id: assignmentId,
    });
    if (error) return { ok: false, error: error.message };
    revalidatePath("/admin");
    revalidatePath("/dashboard");
    return { ok: true };
  } catch (error) {
    return {
      ok: false,
      error:
        error instanceof Error
          ? error.message
          : "Assignment could not be removed.",
    };
  }
}
