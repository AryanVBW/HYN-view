import { NextResponse } from "next/server";
import { buildDeviceLinkedContent, renderHynEmailShell } from "@/lib/cloud-email";
import { sendManagedEmail as sendResendEmail } from "@/lib/delivery-send";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const resendKey = process.env.RESEND_API_KEY ?? "";
  const from = process.env.EMAIL_FROM ?? "HYN-view <reports@hyn-view.info>";
  if (!resendKey) {
    return NextResponse.json({ message: "managed email is not configured" }, { status: 503 });
  }

  const body = await request.json().catch(() => null) as { nodeId?: string } | null;
  if (!body?.nodeId || !/^[0-9a-f-]{36}$/i.test(body.nodeId)) {
    return NextResponse.json({ message: "a valid node id is required" }, { status: 400 });
  }

  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return NextResponse.json({ message: "not authenticated" }, { status: 401 });

  const { data, error } = await supabase.rpc("hyn_claim_device_linked_email", {
    p_node_id: body.nodeId,
  });
  if (error) return NextResponse.json({ message: error.message }, { status: 400 });
  const claim = data as {
    status?: string;
    node_name?: string;
    hostname?: string | null;
    os?: string | null;
    agent_version?: string | null;
    recipient?: string;
    linked_at?: string;
  };
  if (claim.status !== "send" || !claim.recipient) {
    return NextResponse.json({ status: "skipped", reason: "already sent" });
  }

  const subject = `HYN device linked · ${claim.node_name ?? "new machine"}`;
  const delivery = await sendResendEmail({
    delivery: { kind: "device", ownerId: auth.user.id, nodeId: body.nodeId },
    apiKey: resendKey,
    from,
    to: claim.recipient,
    subject,
    html: renderHynEmailShell({
      subject,
      preview: "Your machine is linked and its first complete report is being collected.",
      hostname: claim.hostname ?? claim.node_name ?? "new machine",
      severity: "info",
      content: buildDeviceLinkedContent({
        nodeName: claim.node_name ?? "new machine",
        hostname: claim.hostname ?? null,
        os: claim.os ?? null,
        agentVersion: claim.agent_version ?? null,
        linkedAt: claim.linked_at ?? new Date().toISOString(),
      }),
    }),
    idempotencyKey: `device-linked:${body.nodeId}`,
  });
  if (!delivery.ok) {
    await supabase.rpc("hyn_release_device_linked_email", { p_node_id: body.nodeId });
    return NextResponse.json({ message: delivery.error }, { status: 502 });
  }
  await supabase.rpc("hyn_complete_device_linked_email", {
    p_node_id: body.nodeId,
    p_provider_id: delivery.providerId,
  });
  return NextResponse.json({ status: "sent" });
}
