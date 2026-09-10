"use client";

import { useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { notificationLink, unreadNotifications, type ServerNotification } from "@/lib/server-notifications";

function subscribeRead(callback: () => void) {
  window.addEventListener("storage", callback);
  window.addEventListener("hyn-notifications-read", callback);
  return () => {
    window.removeEventListener("storage", callback);
    window.removeEventListener("hyn-notifications-read", callback);
  };
}

export function ServerNotifications({ events, userId }: { events: ServerNotification[]; userId: string }) {
  const router = useRouter();
  const [sessionRead, setSessionRead] = useState<string[] | null>(null);
  const [browserEnabled, setBrowserEnabled] = useState(false);
  const [message, setMessage] = useState("");
  const seen = useRef<Set<string> | null>(null);
  const readKey = `hyn:notifications:read:${userId}`;

  const stored = useSyncExternalStore(subscribeRead, () => {
    try { return localStorage.getItem(readKey) ?? "[]"; } catch { return "[]"; }
  }, () => "[]");
  const read = useMemo(() => {
    if (sessionRead) return sessionRead;
    try {
      const ids: unknown = JSON.parse(stored);
      return Array.isArray(ids) ? ids.filter((id): id is string => typeof id === "string").slice(-500) : [];
    } catch { return []; }
  }, [stored, sessionRead]);

  useEffect(() => {
    const previous = seen.current;
    seen.current = new Set(events.map(event => event.id));
    if (!browserEnabled || !previous || typeof Notification === "undefined" || Notification.permission !== "granted") return;
    // No notification bodies in browser storage; no historical flood on enable.
    for (const event of events.filter(event => !previous.has(event.id)).slice(0, 3)) {
      try {
        const notification = new Notification(`${event.node_name} · ${event.severity}`, { body: event.message, tag: event.id });
        notification.onclick = () => { window.focus(); router.push(notificationLink(event)); notification.close(); };
        notification.onerror = () => setMessage("This browser could not show a notification. Alerts remain available here.");
      } catch { /* Some mobile browsers require push support. The inbox remains available. */ }
    }
  }, [events, browserEnabled, router]);

  async function enableBrowser() {
    if (typeof Notification === "undefined") { setMessage("Browser notifications are unavailable. Use this inbox to follow server events."); return; }
    try {
      const permission = await Notification.requestPermission();
      setBrowserEnabled(permission === "granted");
      setMessage(permission === "granted" ? "Browser notifications enabled while this page is open." : "Notifications were not enabled. You can still read all events here.");
    } catch { setMessage("Could not enable browser notifications. Alerts remain available here."); }
  }

  function markRead() {
    const ids = [...new Set([...read, ...events.map(event => event.id)])].slice(-500);
    try {
      localStorage.setItem(readKey, JSON.stringify(ids));
      window.dispatchEvent(new Event("hyn-notifications-read"));
    } catch { setSessionRead(ids); }
  }

  const unread = unreadNotifications(events, read);
  return <section className="terminal-panel rounded-xl p-6 md:p-8" aria-label="Server notification inbox">
    <div className="flex flex-wrap items-center justify-between gap-4 border-b border-border pb-4">
      <p className="text-sm font-mono text-muted-foreground" role="status">{unread.length} unread · {events.length} recent events</p>
      <div className="flex flex-wrap gap-2">
        <button onClick={markRead} disabled={!unread.length} className="rounded-full border border-border px-4 py-2 text-xs uppercase tracking-wide text-muted-foreground transition-colors hover:border-foreground/50 hover:text-foreground disabled:cursor-not-allowed disabled:opacity-40">Mark all read</button>
        <button onClick={browserEnabled ? () => setBrowserEnabled(false) : enableBrowser} className="rounded-full bg-primary px-4 py-2 text-xs uppercase tracking-wide text-primary-foreground transition-colors hover:bg-primary/90">{browserEnabled ? "Disable browser notifications" : "Enable browser notifications"}</button>
      </div>
    </div>
    {message ? <p className="mt-4 text-sm text-muted-foreground" role="status">{message}</p> : null}
    {!events.length ? <p className="py-12 text-sm text-muted-foreground">No recent server notifications. Your administrator controls which assigned servers can notify you.</p> : <ul className="mt-6 divide-y divide-border">
      {events.map(event => <li key={event.id} className={`py-5 px-3 ${!read.includes(event.id) ? "rounded-lg bg-primary/5 ring-1 ring-primary/20" : ""}`}>
        <div className="flex flex-wrap items-center gap-3">
          <Link className="font-medium text-primary" href={notificationLink(event)}>{event.node_name}</Link>
          <span className={`rounded-full border px-2 py-0.5 text-[11px] font-mono uppercase ${event.severity === "crit" ? "border-destructive/40 text-destructive" : "border-border/70 text-muted-foreground"}`}>{event.severity}</span>
          {!read.includes(event.id) ? <span className="rounded-full border border-primary/40 bg-primary/10 px-2 py-0.5 text-[11px] font-mono uppercase text-primary">Unread</span> : null}
        </div>
        <p className="mt-3 text-sm leading-7">{event.message}</p>
        <time className="mt-2 block text-xs text-muted-foreground" dateTime={event.ts}>{new Date(event.ts).toISOString().replace("T", " ").slice(0, 19)} UTC</time>
      </li>)}
    </ul>}
  </section>;
}
