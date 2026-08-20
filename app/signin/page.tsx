import type { Metadata } from "next";
import { Suspense } from "react";
import Link from "next/link";
import { redirect } from "next/navigation";
import { Logo } from "@/components/logo";
import { SignInForm } from "@/components/signin-form";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Sign in / HYN-view",
  description: "Sign in to your HYN-view dashboard with Google or an email and password.",
};

export default async function SignInPage() {
  // Already signed in? Don't make them look at a login form.
  if (isSupabaseConfigured) {
    const supabase = await createClient();
    const { data } = await supabase.auth.getUser();
    if (data.user) redirect("/dashboard");
  }

  return (
    <div className="flex min-h-svh flex-col items-center justify-center px-4 py-16">
      <Link href="/" className="mb-10">
        <Logo className="w-[120px]" />
      </Link>

      <div className="terminal-panel w-full max-w-sm p-8">
        <p className="section-kicker text-center">// authenticate</p>
        <h1 className="mt-2 text-center font-sentient text-2xl text-card-foreground">
          Sign in to your dashboard
        </h1>

        {!isSupabaseConfigured ? (
          <p className="mt-6 border border-destructive/40 bg-destructive/5 p-3 font-mono text-xs leading-5 text-destructive">
            Supabase is not configured. Copy{" "}
            <code>.env.local.example</code> to <code>.env.local</code> and fill in your
            project URL and anon key.
          </p>
        ) : null}

        <Suspense
          fallback={
            <p className="mt-8 font-mono text-xs text-muted-foreground">Loading…</p>
          }
        >
          <SignInForm />
        </Suspense>
      </div>

      <p className="mt-8 max-w-sm text-center font-mono text-xs leading-5 text-muted-foreground">
        Linking a server? Sign in first, then open{" "}
        <Link href="/link" className="text-primary underline underline-offset-4">
          /link
        </Link>{" "}
        and enter the code shown by <code>sudo hyn link</code>.
      </p>
    </div>
  );
}
