"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { Search } from "lucide-react";

export type ResourceOption = { id: string; name: string; detail?: string; href: string; searchText?: string };

/** A shared, keyboard-accessible pill navigation for accounts, servers and relayers. */
export function ResourceSwitcher({ label, items, current, searchThreshold = 2 }: {
  label: string; items: ResourceOption[]; current?: string; searchThreshold?: number;
}) {
  const [query, setQuery] = useState("");
  const navigation = useRef<HTMLElement>(null);
  useEffect(() => {
    const nav = navigation.current;
    const active = nav?.querySelector('[aria-current="page"]');
    if (!nav || !active) return;
    const bounds = nav.getBoundingClientRect();
    const selected = active.getBoundingClientRect();
    // Keep the selected pill visible without scrolling the page or moving focus.
    if (selected.left < bounds.left) nav.scrollLeft += selected.left - bounds.left;
    else if (selected.right > bounds.right) nav.scrollLeft += selected.right - bounds.right;
  },[current,query]);
  const matching = items.filter(item => `${item.name} ${item.detail ?? ""} ${item.searchText ?? ""}`.toLowerCase().includes(query.trim().toLowerCase()));
  return <section className="min-w-0 space-y-3" aria-label={`${label} switcher`}>
    <div className="flex flex-wrap items-center justify-between gap-3">
      <p className="font-mono text-xs text-muted-foreground">{label} <span className="ml-1 text-foreground">{items.length}</span></p>
      {items.length >= searchThreshold ? <label className="flex w-full items-center gap-2 rounded-full border border-border bg-background px-3 py-2 focus-within:border-primary sm:w-64">
        <Search className="size-3.5 shrink-0 text-muted-foreground" aria-hidden />
        <input aria-label={`Search ${label.toLowerCase()}`} placeholder={`Find ${label.toLowerCase()}…`} value={query} onChange={e => setQuery(e.target.value)} className="min-w-0 flex-1 bg-transparent font-mono text-xs outline-none" />
      </label> : null}
    </div>
    <nav ref={navigation} aria-label={label} className="flex gap-2 overflow-x-auto pb-2 pt-1">
      {matching.map(item => <Link key={item.id} href={item.href} scroll={false} aria-current={item.id === current ? "page" : undefined} title={[item.name,item.detail].filter(Boolean).join(" · ")}
        className={`flex max-w-80 shrink-0 items-center gap-2 rounded-full border px-4 py-2.5 font-mono text-xs transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary ${item.id === current ? "border-primary bg-primary text-primary-foreground" : "border-border bg-background text-muted-foreground hover:border-primary/50 hover:text-foreground"}`}>
        <span className="truncate">{item.name}</span>{item.detail ? <span className="max-w-36 truncate text-[10px] opacity-75">{item.detail}</span> : null}
      </Link>)}
      {!matching.length ? <p role="status" className="py-2 font-mono text-xs text-muted-foreground">{query ? `No ${label.toLowerCase()} match this search.` : `No ${label.toLowerCase()} in this view.`}</p> : null}
    </nav>
  </section>;
}
