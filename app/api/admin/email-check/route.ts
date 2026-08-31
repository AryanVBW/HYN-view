import { NextResponse } from "next/server";
import { diagnoseEmailDelivery } from "@/lib/cloud-email";
import { createClient } from "@/lib/supabase/server";

// Why is email not sending?
//
// Delivery is the portal's job alone -- the monitored machines hold no provider
// credential, no sender address and no recipient list -- so the portal has to be
// able to say why it is failing. Until this existed there was no way to ask: the
// provider's error was either discarded at the call site or written into a
// notification_log row nobody queries, so a broken key and an unverified domain
// looked identical from the outside, which is to say they looked like nothing.
//
// Reads configuration and asks Resend about it. Sends no message: a check that
// mails someone to prove mail works is useless precisely when mail is broken.
//
// Admin-only, and the check runs in the database rather than here. `hyn_is_admin`
// re-checks the caller's role server-side for the same reason every other admin
// RPC does -- anyone can call this route directly with the public anon key, so a
// hidden button is a courtesy and not a boundary.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) {
    return NextResponse.json({ message: "not authenticated" }, { status: 401 });
  }
  const { data: isAdmin, error } = await supabase.rpc("hyn_is_admin");
  if (error) {
    return NextResponse.json({ message: error.message }, { status: 403 });
  }
  if (isAdmin !== true) {
    return NextResponse.json({ message: "administrator access is required" }, { status: 403 });
  }

  const diagnosis = await diagnoseEmailDelivery({
    apiKey: process.env.RESEND_API_KEY,
    from: process.env.EMAIL_FROM,
  });

  // The remedy belongs next to the cause. An operator reading this is trying to
  // fix it, not classify it.
  const fix: Record<typeof diagnosis.cause, string> = {
    ok: "Nothing to fix. If mail still does not arrive, check the recipient in Account and the delivery log.",
    "missing-key": "Set RESEND_API_KEY in the deployment environment (Production and Preview), then redeploy.",
    "missing-from": 'Set EMAIL_FROM to a verified sender, for example "HYN-view <reports@your-domain>".',
    "invalid-key": "The key was rejected. Create a new API key in Resend, replace RESEND_API_KEY, then redeploy.",
    "sender-domain-unverified": "Finish DNS verification for this domain in Resend, or set EMAIL_FROM to a domain that is already verified.",
    "sender-domain-unknown": "Add and verify this domain in Resend, or set EMAIL_FROM to one of the verified domains listed here.",
    "provider-unreachable": "Resend could not be reached or returned an unexpected error. Check Resend's status and the detail above.",
  };

  return NextResponse.json(
    {
      ok: diagnosis.ok,
      cause: diagnosis.cause,
      detail: diagnosis.detail,
      fix: fix[diagnosis.cause],
      // Never the key itself, only whether it is present. A diagnostic that
      // leaks the credential it is checking is a worse bug than the one it finds.
      configured: {
        RESEND_API_KEY: Boolean(process.env.RESEND_API_KEY),
        EMAIL_FROM: diagnosis.fromAddress,
      },
      senderDomain: diagnosis.senderDomain,
      resendDomains: diagnosis.domains,
    },
    { status: diagnosis.ok ? 200 : 503, headers: { "Cache-Control": "no-store" } },
  );
}
