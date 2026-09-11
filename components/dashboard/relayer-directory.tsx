"use client";

import { useState } from "react";
import Link from "next/link";
import { ArrowUpRight, Check, Radio, Search } from "lucide-react";
import type { RelayerReading } from "@/lib/relayer";

export function RelayerDirectory({ readings, current, hrefFor, fleet = false }: {
  readings: RelayerReading[];
  current: number | null;
  hrefFor: (relayerId: number) => string;
  fleet?: boolean;
}) {
  const [query, setQuery] = useState("");
  const relays = [...new Map(readings.map(reading => [reading.assignment.relayer_id, reading])).values()];
  const search = query.trim().toLowerCase();
  const matches = relays.filter(({ assignment, relayer }) =>
    [assignment.relayer_name, assignment.relayer_id, relayer?.name, relayer?.city, relayer?.tier]
      .filter(value => value !== null && value !== undefined).join(" ").toLowerCase().includes(search));

  return <section className="my-6 overflow-hidden rounded-xl border border-border bg-card" aria-label="Assigned relay directory">
    <header className="flex flex-wrap items-start justify-between gap-4 border-b border-border p-4 sm:p-5">
      <div className="min-w-0 flex-1">
        <h3 className="text-base font-medium text-foreground">{fleet ? "Fleet relays" : "Assigned relays"}<span className="ml-2 rounded-full border border-primary/30 bg-primary/5 px-2.5 py-0.5 text-sm tabular-nums text-primary">{relays.length}</span></h3>
        <p className="mt-2 max-w-xl text-xs leading-6 text-muted-foreground">Select a relay to view its details. All assigned relays stay available here, even without a server link.</p>
      </div>
      <label className="relative block w-full sm:w-60">
        <span className="sr-only">Find an assigned relay</span><Search className="absolute left-3 top-3 size-4 text-muted-foreground" aria-hidden />
        <input value={query} onChange={event => setQuery(event.target.value)} placeholder="Find a relay by name" className="w-full min-w-0 rounded-lg border border-border bg-background py-2.5 pl-9 pr-3 text-sm text-foreground outline-none focus-visible:ring-2 focus-visible:ring-primary" />
      </label>
    </header>
    <ul className="grid max-h-[28rem] gap-3 overflow-y-auto p-4 sm:grid-cols-2 sm:p-5" aria-label="Relays you can view">
      {matches.map(({ assignment, relayer }) => {
        const active = current === assignment.relayer_id;
        const name = relayer?.name || assignment.relayer_name;
        const location = [relayer?.city, relayer?.tier].filter(Boolean).join(" / ");
        return <li key={assignment.relayer_id} className={`flex min-w-0 flex-col gap-4 rounded-lg border p-4 ${active ? "border-primary/50 bg-primary/5" : "border-border bg-background"}`}>
          <div className="flex items-start gap-3"><Radio className={`mt-0.5 size-4 shrink-0 ${active ? "text-primary" : "text-muted-foreground"}`} aria-hidden /><div className="min-w-0 flex-1"><h4 className="break-words text-sm font-medium text-foreground [overflow-wrap:anywhere]">{name}</h4><p className="mt-1 text-xs text-muted-foreground">{location || "Assigned relay"}</p></div></div>
          <div className="mt-auto flex flex-wrap items-center justify-between gap-2 text-xs">
            <span className={active ? "inline-flex items-center gap-1 text-primary" : "text-muted-foreground"}>{active ? <><Check className="size-3.5" aria-hidden />Viewing</> : "Available to view"}</span>
            <Link href={hrefFor(assignment.relayer_id)} aria-current={active ? "page" : undefined} className="inline-flex items-center gap-1 rounded-md border border-border px-3 py-2 font-medium text-primary hover:border-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary">View relay<ArrowUpRight className="size-3.5" aria-hidden /><span className="sr-only"> {name}</span></Link>
          </div>
        </li>;
      })}
    </ul>
    {!matches.length ? <p className="px-5 pb-5 text-sm text-muted-foreground">No assigned relays match this search. <button type="button" onClick={() => setQuery("")} className="rounded-sm text-primary underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-primary">Show all assigned relays</button></p> : null}
    {search ? <p className="border-t border-border px-5 py-3 text-xs text-muted-foreground" role="status">{matches.length} of {relays.length} assigned relays shown</p> : null}
  </section>;
}
