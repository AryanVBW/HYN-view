"use client";

import { useState } from "react";
import Link from "next/link";
import { EmailReports } from "@/components/email-reports";

const benchmarkRows = [
  ["nextjs.org", "200", "200", "8.5ms", "—"],
  ["github.com", "200", "200", "42ms", "—"],
  ["api.stripe.com", "200", "200", "118ms", "—"],
  ["cdn.example.dev", "404", "200", "12ms", "path"],
];

export const INSTALL_COMMAND = "curl -fsSL https://www.hyn-view.in/install.sh | sudo bash";

// The command is a selectable <code> first and a copy button second. Clipboard
// access needs a secure context and a user gesture, and it is refused outright in
// some embedded browsers -- so the button is an accelerator for something that
// already works by hand, never the only way to get the text.
function InstallCommand() {
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");

  async function copy() {
    try {
      await navigator.clipboard.writeText(INSTALL_COMMAND);
      setState("copied");
    } catch {
      setState("failed");
    }
    window.setTimeout(() => setState("idle"), 2400);
  }

  return (
    <div className="terminal-panel p-5">
      <div className="flex items-start justify-between gap-4">
        <p className="font-mono text-xs uppercase text-foreground/50">install on the server</p>
        <button
          type="button"
          onClick={copy}
          aria-label={`Copy the install command: ${INSTALL_COMMAND}`}
          className="border border-border px-3 py-1 font-mono text-xs uppercase text-foreground/60 transition-colors hover:border-primary hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          {state === "copied" ? "copied" : state === "failed" ? "select it" : "copy"}
        </button>
      </div>
      <code className="mt-4 block overflow-x-auto whitespace-pre font-mono text-sm text-foreground/90">
        <span className="select-none text-foreground/40">$ </span>
        {INSTALL_COMMAND}
      </code>
      {/* Announced rather than only coloured, so the outcome reaches a screen
          reader; polite because it must not interrupt anything being read. */}
      <p aria-live="polite" className="mt-3 h-4 font-mono text-xs text-primary">
        {state === "copied"
          ? "copied to clipboard"
          : state === "failed"
            ? "this browser blocked the clipboard — select the line above"
            : ""}
      </p>
    </div>
  );
}

export function ProductSections() {
  const [profile, setProfile] = useState<"best" | "performance">("best");
  const [rule, setRule] = useState("if status >= 500");

  return (
    <main className="relative z-10 border-t border-border bg-background">
      <section id="about" className="container section-pad grid gap-12 lg:grid-cols-[0.8fr_1.2fr]">
        <div>
          <p className="section-kicker">// observe without the ceremony</p>
          <h2 className="section-title">The terminal view for what your network is doing.</h2>
        </div>
        <div className="space-y-6 font-mono text-sm leading-7 text-foreground/60">
          <p>HYN-view is a network-first monitor for Ubuntu servers that run 24/7. It covers what htop and btop cover, but inverts the priority: throughput, packet errors, retransmits and latency come first, because on a server the network is usually the story.</p>
          <p className="text-foreground/80">Pure bash on the box — no Node runtime, no compiled binary. One small resident bash process sends a heartbeat every 24 seconds and keeps itself updated; everything else runs from systemd timers. Pair a server and the dashboard shows it from anywhere in the world.</p>
        </div>
      </section>

      <section id="benchmark" className="container section-pad border-t border-border">
        <div className="mb-8 flex flex-col justify-between gap-4 md:flex-row md:items-end">
          <div>
            <p className="section-kicker">// benchmark</p>
            <h2 className="section-title">See the response, not the story.</h2>
          </div>
          <div className="flex border border-border p-1 font-mono text-xs">
            {(["best", "performance"] as const).map((item) => (
              <button
                key={item}
                onClick={() => setProfile(item)}
                className={`px-3 py-2 uppercase transition-colors ${profile === item ? "bg-primary text-primary-foreground" : "text-foreground/50 hover:text-foreground"}`}
              >
                {item}
              </button>
            ))}
          </div>
        </div>
        <div className="terminal-panel overflow-x-auto">
          <div className="grid min-w-[620px] grid-cols-5 border-b border-border px-4 py-3 font-mono text-xs uppercase text-foreground/50">
            <span>request</span><span>status</span><span>expected</span><span>latency</span><span>note</span>
          </div>
          {benchmarkRows.map((row) => (
            <div key={row[0]} className="grid min-w-[620px] grid-cols-5 border-b border-border/60 px-4 py-4 font-mono text-sm last:border-0">
              <span className="text-foreground/80">{row[0]}</span>
              <span className={row[1] === "200" ? "text-primary" : "text-foreground"}>{row[1]}</span>
              <span>{row[2]}</span>
              <span>{profile === "performance" ? row[3] : row[3].replace("ms", " ms")}</span>
              <span className="text-foreground/50">{row[4]}</span>
            </div>
          ))}
        </div>
      </section>

      <section id="rules" className="container section-pad grid gap-12 border-t border-border lg:grid-cols-2">
        <div>
          <p className="section-kicker">// alert rules</p>
          <h2 className="section-title">Make the quiet failures loud.</h2>
          <p className="mt-6 max-w-lg font-mono text-sm leading-7 text-foreground/60">Write rules the way you think about incidents. HYN-view evaluates them locally and gives you a readable output before a small issue becomes a pager.</p>
        </div>
        <div className="terminal-panel p-5">
          <label htmlFor="rule" className="mb-3 block font-mono text-xs uppercase text-foreground/50">rule expression</label>
          <input
            id="rule"
            value={rule}
            onChange={(e) => setRule(e.target.value)}
            className="w-full border border-border bg-transparent px-3 py-3 font-mono text-sm text-foreground/80 outline-none focus:border-primary"
          />
          <div className="mt-6 border-t border-border pt-4 font-mono text-xs leading-6">
            <span className="text-primary">ok</span> rule compiled<br />
            <span className="text-foreground/50">watching 4 endpoints · local mode</span>
          </div>
        </div>
      </section>

      <EmailReports />

      <section id="limitations" className="container section-pad border-t border-border">
        <div className="terminal-panel grid gap-6 p-6 md:grid-cols-[1fr_auto] md:items-center">
          <div>
            <p className="section-kicker">// known limitations</p>
            <p className="mt-3 max-w-2xl font-mono text-sm leading-7 text-foreground/60">HYN-view is intentionally small. It is not a distributed tracing platform, it will not retain history for you, and it cannot fix a slow upstream. It can show you where to look next.</p>
          </div>
          <span className="font-mono text-xs uppercase text-primary">honest tooling</span>
        </div>
      </section>

      <section id="install" className="container section-pad border-t border-border">
        <div className="grid gap-10 lg:grid-cols-[1fr_1.2fr] lg:items-start">
          <div>
            <p className="section-kicker">// install</p>
            <h2 className="section-title">One command. Nothing to answer.</h2>
            <p className="mt-6 font-mono text-sm leading-7 text-foreground/60">Ubuntu 22.04 or 24.04. Paste it, enter your sudo password, and walk away: it installs node if the box has none, installs the CLI, writes the config, and starts the resident agent that beats every 24 seconds and updates itself.</p>
            <p className="mt-4 font-mono text-xs leading-6 text-foreground/40">Pure bash on the box — no runtime, no compiled binary. npm is only the delivery channel. Read the script before you run it: <a className="hover:text-primary" href="/install.sh">hyn-view.in/install.sh</a>.</p>
          </div>
          <div className="space-y-4">
            <InstallCommand />
            <div className="terminal-panel p-5 font-mono text-xs leading-6 text-foreground/50">
              <p className="text-foreground/70">what it does</p>
              <ul className="mt-3 space-y-1">
                <li>1 · curl, CA certificates and node ≥ 18 if missing</li>
                <li>2 · npm install -g hyn-view</li>
                <li>3 · /etc/hyn-view/config, state dir, five systemd timers</li>
                <li>4 · hyn-agent.service — 24s heartbeat, self-update, self-repair</li>
                <li>5 · verifies the agent is running, and repairs it if not</li>
              </ul>
              <p className="mt-4 text-foreground/50">then, to watch it from anywhere:</p>
              <p className="mt-1 text-foreground/80">$ sudo hyn link</p>
            </div>
          </div>
        </div>
      </section>

      <footer id="contact" className="container flex flex-col gap-4 border-t border-border py-8 font-mono text-xs text-foreground/50 md:flex-row md:items-center md:justify-between">
        <span>
          HYN-view · <Link className="hover:text-primary" href="/legal">MIT license</Link>
        </span>
        <span className="flex flex-wrap items-center gap-x-4 gap-y-2">
          <Link className="hover:text-primary" href="/privacy">Privacy</Link>
          <Link className="hover:text-primary" href="/terms">Terms</Link>
          <Link className="hover:text-primary" href="/acceptable-use">Acceptable use</Link>
          <Link className="hover:text-primary" href="/security">Security</Link>
          <Link className="hover:text-primary" href="/legal">Disclaimer</Link>
          <span>
            Built by{" "}
            <a className="text-foreground/80 hover:text-primary" href="mailto:vivek.aryanvbw@gmail.com">
              NEXUSV TECHNOLOGIES PRIVATE LIMITED
            </a>
          </span>
        </span>
      </footer>
    </main>
  );
}

export function ProductCTA() {
  return null;
}
