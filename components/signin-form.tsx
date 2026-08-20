"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Loader2, Lock, Mail } from "lucide-react";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { buildPasswordSignUpRequest, normalizeInternalPath } from "@/lib/legal-consent";

const GoogleIcon = (props: React.SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden {...props}>
    <path
      fill="#4285F4"
      d="M23.52 12.27c0-.82-.07-1.6-.2-2.36H12v4.47h6.47c-.28 1.5-1.13 2.77-2.4 3.62v3.01h3.87c2.27-2.09 3.58-5.17 3.58-8.74Z"
    />
    <path
      fill="#34A853"
      d="M12 24c3.24 0 5.95-1.07 7.94-2.9l-3.87-3a7.15 7.15 0 0 1-4.07 1.14c-3.13 0-5.78-2.11-6.73-4.96H1.2v3.1A12 12 0 0 0 12 24Z"
    />
    <path
      fill="#FBBC05"
      d="M5.27 14.28a7.2 7.2 0 0 1 0-4.56v-3.1H1.2a12 12 0 0 0 0 10.76l4.07-3.1Z"
    />
    <path
      fill="#EA4335"
      d="M12 4.75c1.76 0 3.34.6 4.58 1.79l3.43-3.43C17.94 1.19 15.24 0 12 0A12 12 0 0 0 1.2 6.62l4.07 3.1C6.22 6.87 8.87 4.75 12 4.75Z"
    />
  </svg>
);

type Mode = "signin" | "signup";

export function SignInForm() {
  const router = useRouter();
  const params = useSearchParams();
  const nextPath = normalizeInternalPath(params.get("next"));

  const [mode, setMode] = useState<Mode>("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [acceptedTerms, setAcceptedTerms] = useState(false);
  const [busy, setBusy] = useState<null | "google" | "password">(null);
  const [error, setError] = useState<string | null>(params.get("error"));
  const [notice, setNotice] = useState<string | null>(null);

  async function handleGoogle() {
    setError(null);
    setNotice(null);
    if (!isSupabaseConfigured) {
      setError("Supabase is not configured. See web-portal/.env.local.example.");
      return;
    }
    setBusy("google");
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(nextPath)}`,
      },
    });
    // On success the browser navigates away, so only failures land here.
    if (error) {
      setError(error.message);
      setBusy(null);
    }
  }

  async function handlePassword(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setNotice(null);
    if (!isSupabaseConfigured) {
      setError("Supabase is not configured. See web-portal/.env.local.example.");
      return;
    }
    if (!email.trim() || !password) return;

    setBusy("password");
    const supabase = createClient();

    if (mode === "signup") {
      let request;
      try {
        request = buildPasswordSignUpRequest({
          email,
          password,
          emailRedirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(nextPath)}`,
          acceptedTerms,
        });
      } catch (registrationError) {
        setBusy(null);
        setError(
          registrationError instanceof Error
            ? registrationError.message
            : "Legal acceptance is required to register.",
        );
        return;
      }
      const { data, error } = await supabase.auth.signUp(request);
      setBusy(null);
      if (error) {
        setError(error.message);
        return;
      }
      // With email confirmation on (the Supabase default) there is no session
      // yet — saying "welcome" here would be a lie.
      if (!data.session) {
        setNotice("Check your email to confirm the account, then sign in.");
        return;
      }
      router.push(nextPath);
      router.refresh();
      return;
    }

    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });
    setBusy(null);
    if (error) {
      setError(error.message);
      return;
    }
    router.push(nextPath);
    router.refresh();
  }

  return (
    <div className="mt-8 space-y-6">
      <Button
        type="button"
        onClick={handleGoogle}
        disabled={busy !== null}
        className="w-full !bg-white !text-black !border-white/20 gap-3 normal-case"
      >
        {busy === "google" ? <Loader2 className="size-4 animate-spin" /> : <GoogleIcon />}
        Sign in with Google
      </Button>

      <div className="flex items-center gap-3">
        <span className="h-px flex-1 bg-border" />
        <span className="font-mono text-xs uppercase text-muted-foreground">or</span>
        <span className="h-px flex-1 bg-border" />
      </div>

      <form onSubmit={handlePassword} className="space-y-4">
        <label className="block">
          <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">
            Email
          </span>
          <span className="flex items-center gap-2 border border-input bg-input/20 px-3 py-2.5 focus-within:border-ring">
            <Mail className="size-4 shrink-0 text-muted-foreground" aria-hidden />
            <input
              type="email"
              required
              autoComplete="username"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="you@example.com"
              className="w-full bg-transparent font-mono text-sm text-foreground outline-none placeholder:text-muted-foreground/60"
            />
          </span>
        </label>

        {mode === "signup" ? (
          <label className="flex items-start gap-3 border border-input bg-input/10 px-3 py-3">
            <input
              type="checkbox"
              required
              checked={acceptedTerms}
              onChange={(event) => setAcceptedTerms(event.target.checked)}
              className="mt-0.5 size-4 shrink-0 accent-current"
            />
            <span className="font-mono text-xs leading-5 text-muted-foreground">
              I am at least 18 and accept the{" "}
              <Link href="/terms" target="_blank" className="text-primary underline underline-offset-4">
                Terms of Use
              </Link>{" "}
              and acknowledge the{" "}
              <Link href="/privacy" target="_blank" className="text-primary underline underline-offset-4">
                Privacy Notice
              </Link>
              .
            </span>
          </label>
        ) : null}

        <label className="block">
          <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">
            Password
          </span>
          <span className="flex items-center gap-2 border border-input bg-input/20 px-3 py-2.5 focus-within:border-ring">
            <Lock className="size-4 shrink-0 text-muted-foreground" aria-hidden />
            <input
              type="password"
              required
              minLength={6}
              autoComplete={mode === "signup" ? "new-password" : "current-password"}
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="••••••••"
              className="w-full bg-transparent font-mono text-sm text-foreground outline-none placeholder:text-muted-foreground/60"
            />
          </span>
        </label>

        {error ? (
          <p role="alert" className="font-mono text-xs leading-5 text-destructive">
            {error}
          </p>
        ) : null}
        {notice ? (
          <p role="status" className="font-mono text-xs leading-5 text-primary">
            {notice}
          </p>
        ) : null}

        <Button
          type="submit"
          size="sm"
          disabled={busy !== null || (mode === "signup" && !acceptedTerms)}
          className="w-full gap-2"
        >
          {busy === "password" ? <Loader2 className="size-4 animate-spin" /> : null}
          {mode === "signup" ? "Create account" : "Sign in"}
        </Button>
      </form>

      {mode === "signin" ? (
        <p className="text-center font-mono text-[0.65rem] leading-5 text-muted-foreground">
          By continuing, you confirm that you are at least 18 and accept the{" "}
          <Link href="/terms" target="_blank" className="text-primary underline underline-offset-4">
            Terms of Use
          </Link>{" "}
          and acknowledge the{" "}
          <Link href="/privacy" target="_blank" className="text-primary underline underline-offset-4">
            Privacy Notice
          </Link>
          .
        </p>
      ) : null}

      <p className="text-center font-mono text-xs text-muted-foreground">
        {mode === "signup" ? "Already have an account?" : "No account yet?"}{" "}
        <button
          type="button"
          onClick={() => {
            setMode(mode === "signup" ? "signin" : "signup");
            setError(null);
            setNotice(null);
            setAcceptedTerms(false);
          }}
          className="text-primary underline underline-offset-4 hover:text-primary/80"
        >
          {mode === "signup" ? "Sign in" : "Sign up"}
        </button>
      </p>
    </div>
  );
}
