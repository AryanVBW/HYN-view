"use client";

import Link from "next/link";
import { GL } from "./gl";
import { Pill } from "./pill";
import { Button } from "./ui/button";
import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { isSupabaseConfigured } from "@/lib/supabase/config";

export function Hero() {
  const [hovering, setHovering] = useState(false);
  // undefined while the session check is in flight, so the button does not
  // flash "Sign in" for a moment on every load for people who are actually
  // signed in. Same session-tracking approach as components/header.tsx, for
  // the same reason: sign-in navigates client-side, so a one-time server
  // check would go stale without a full reload.
  const [signedIn, setSignedIn] = useState<boolean | undefined>(undefined);

  useEffect(() => {
    if (!isSupabaseConfigured) {
      setSignedIn(false);
      return;
    }
    const supabase = createClient();
    supabase.auth.getUser().then(({ data }) => setSignedIn(Boolean(data.user)));
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      setSignedIn(Boolean(session?.user));
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  const href = signedIn ? "#install" : "/signin";
  const label = signedIn ? "[Install HYN-view]" : "[Sign in]";
  // Reserve the button's place immediately so the layout does not jump once
  // the session check resolves; just don't commit to a label until it does.
  const ready = signedIn !== undefined;

  return (
    <div className="flex flex-col h-svh justify-between">
      <GL hovering={hovering} />

      <div className="pb-16 mt-auto text-center relative">
        <Pill className="mb-6 max-sm:text-xs">MONITOR SERVERS FROM ANYWHERE</Pill>
        <h1 className="text-5xl sm:text-6xl md:text-7xl font-sentient">
          Know what&apos;s <br />
          <i className="font-light">actually</i> happening
        </h1>
        <p className="font-mono text-sm sm:text-base text-foreground/60 text-balance mt-8 max-w-[460px] mx-auto">
          Monitor your servers from anywhere in the world. A terminal-first monitor
          for Ubuntu, with a web dashboard you can open on any device.
        </p>

        <Link className="contents max-sm:hidden" href={href} aria-hidden={!ready} tabIndex={ready ? undefined : -1}>
          <Button
            className="mt-14"
            onMouseEnter={() => setHovering(true)}
            onMouseLeave={() => setHovering(false)}
          >
            {ready ? label : "\u00A0"}
          </Button>
        </Link>
        <Link className="contents sm:hidden" href={href} aria-hidden={!ready} tabIndex={ready ? undefined : -1}>
          <Button
            size="sm"
            className="mt-14"
            onMouseEnter={() => setHovering(true)}
            onMouseLeave={() => setHovering(false)}
          >
            {ready ? label : "\u00A0"}
          </Button>
        </Link>
      </div>
    </div>
  );
}
