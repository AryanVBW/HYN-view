"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { UserCircle2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { Logo } from "./logo";
import { MobileMenu } from "./mobile-menu";
import { ThemeToggle } from "./theme-toggle";

export const Header = () => {
  // null = still checking, so neither state flashes before the real answer
  // arrives. Sign-in and sign-out both happen through client-side navigation
  // (router.push, not a full reload) elsewhere in the app, so this has to
  // track the session live rather than read it once.
  const [email, setEmail] = useState<string | null | undefined>(undefined);

  useEffect(() => {
    if (!isSupabaseConfigured) {
      setEmail(null);
      return;
    }
    const supabase = createClient();
    supabase.auth.getUser().then(({ data }) => setEmail(data.user?.email ?? null));
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      setEmail(session?.user?.email ?? null);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  const signedIn = Boolean(email);

  return (
    <div className="fixed z-50 pt-8 md:pt-14 top-0 left-0 w-full">
      <header className="flex items-center justify-between container">
        <Link href="/">
          <Logo className="w-[100px] md:w-[120px]" />
        </Link>
        <div className="flex max-lg:hidden items-center gap-x-8">
          <Link className="uppercase transition-colors ease-out duration-150 font-mono text-foreground/60 hover:text-foreground/100" href="/dashboard">
            Dashboard
          </Link>
          {signedIn ? (
            <Link
              href="/account"
              className="flex items-center gap-2 font-mono text-foreground/80 transition-colors ease-out duration-150 hover:text-foreground"
              title={email ?? undefined}
            >
              <UserCircle2 className="size-4 text-primary" aria-hidden />
              <span className="max-w-[16ch] truncate normal-case">{email}</span>
            </Link>
          ) : email === null ? (
            <Link className="uppercase transition-colors ease-out duration-150 font-mono text-primary hover:text-primary/80" href="/signin">
              Sign in
            </Link>
          ) : null}
          <ThemeToggle />
        </div>
        <div className="flex items-center gap-x-2 lg:hidden">
          <ThemeToggle />
          <MobileMenu signedIn={signedIn} email={email ?? null} />
        </div>
      </header>
    </div>
  );
};
