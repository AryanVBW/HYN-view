"use client";

import Link from "next/link";
import { GL } from "./gl";
import { Pill } from "./pill";
import { Button } from "./ui/button";
import { useState } from "react";

export function Hero() {
  const [hovering, setHovering] = useState(false);
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

        <Link className="contents max-sm:hidden" href="#install">
          <Button
            className="mt-14"
            onMouseEnter={() => setHovering(true)}
            onMouseLeave={() => setHovering(false)}
          >
            [Install HYN-view]
          </Button>
        </Link>
        <Link className="contents sm:hidden" href="#install">
          <Button
            size="sm"
            className="mt-14"
            onMouseEnter={() => setHovering(true)}
            onMouseLeave={() => setHovering(false)}
          >
            [Install HYN-view]
          </Button>
        </Link>
      </div>
    </div>
  );
}
