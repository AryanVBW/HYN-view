import { after, NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { normalizeInternalPath } from "@/lib/legal-consent";
import { observedPublicIp } from "@/lib/agent-api";
import { buildSignInContent, renderHynEmailShell, sendResendEmail } from "@/lib/cloud-email";

// Where Google (and the email confirmation link) come back to. Exchanges the
// one-time code for a session cookie, then forwards the user on.
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const next = normalizeInternalPath(searchParams.get("next"));
  const oauthError = searchParams.get("error_description") ?? searchParams.get("error");

  if (oauthError) {
    return NextResponse.redirect(
      `${origin}/signin?error=${encodeURIComponent(oauthError)}`
    );
  }

  if (!isSupabaseConfigured) {
    return NextResponse.redirect(
      `${origin}/signin?error=${encodeURIComponent("Supabase is not configured")}`
    );
  }

  if (!code) {
    return NextResponse.redirect(
      `${origin}/signin?error=${encodeURIComponent("No authorization code returned")}`
    );
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    return NextResponse.redirect(
      `${origin}/signin?error=${encodeURIComponent(error.message)}`
    );
  }

  const { data: auth } = await supabase.auth.getUser();
  if (auth.user?.email) {
    const email = auth.user.email;
    const signedInAt = new Date().toISOString();
    const ip = observedPublicIp(
      request.headers.get("x-forwarded-for") ?? request.headers.get("x-real-ip"),
    );
    const userAgent = request.headers.get("user-agent")?.slice(0, 300) ?? null;
    after(async () => {
      const subject = "Welcome, you signed in";
      // Every other sender in this codebase captures the delivery result and
      // records it. This one discarded it, which is why "email is not sending"
      // had no error anywhere to find: the send runs inside after(), so a failure
      // never touched the response, was never logged, and never reached
      // notification_log. The result is now inspected and the provider's own
      // message is logged verbatim -- "API key is invalid", "Domain is not
      // verified", a quota refusal -- because that string is the whole diagnosis.
      const delivery = await sendResendEmail({
        apiKey: process.env.RESEND_API_KEY ?? "",
        from: process.env.EMAIL_FROM ?? "HYN-view <reports@hyn-view.info>",
        to: email,
        subject,
        html: renderHynEmailShell({
          subject,
          preview: "A successful sign-in to your HYN-view account was recorded.",
          hostname: email,
          severity: "info",
          content: buildSignInContent({ email, signedInAt, ip, userAgent }),
        }),
        idempotencyKey: `sign-in:${auth.user.id}:${signedInAt}`,
      });
      if (!delivery.ok) {
        console.error("[sign-in email] delivery failed:", delivery.error, {
          configured: {
            RESEND_API_KEY: Boolean(process.env.RESEND_API_KEY),
            EMAIL_FROM: process.env.EMAIL_FROM ?? "(unset, using the built-in default)",
          },
        });
      }
    });
  }

  return NextResponse.redirect(`${origin}${next}`);
}
