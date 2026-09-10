"use client";

import Link from "next/link";
import { normalizeRole, permissions, roleDescriptions, roleLabels, type DashboardAccount } from "@/lib/permissions";
import { ResourceSwitcher } from "./resource-switcher";

export function DashboardContext({ role, accounts, owner }: {
  role: unknown; accounts: DashboardAccount[]; owner: string;
}) {
  const normalized = normalizeRole(role);
  const access = permissions(role);
  const options = accounts.map(account => ({id: account.id, name: account.own ? "My devices" : account.name, href: `/dashboard?owner=${encodeURIComponent(account.id)}`}));
  if (access.canAdmin) options.unshift({id: "all",name: "All servers",href: "/dashboard?owner=all"});
  return <section className="mb-6 min-w-0 space-y-6 border-b border-border pb-6" aria-label="Dashboard access">
    <div className="flex flex-wrap items-start justify-between gap-4">
      <div>
        <div className="flex flex-wrap items-center gap-3">
          <p className="section-kicker">// your workspace</p>
          <span className="rounded-full border border-primary/40 bg-primary/10 px-3 py-1 font-mono text-xs text-primary">{roleLabels[normalized]}</span>
        </div>
        <p className="mt-3 max-w-2xl font-mono text-xs leading-6 text-muted-foreground">{roleDescriptions[normalized]}</p>
      </div>
      <div className="flex flex-wrap gap-2 font-mono text-xs">
        {access.canAdmin ? <Link href="/admin" className="rounded-full border border-border px-4 py-2.5 hover:border-primary hover:text-primary">Admin dashboard</Link> : null}
        {access.canLink ? <Link href="/link" className="rounded-full border border-primary/50 px-4 py-2.5 text-primary hover:bg-primary/10">+ Link server</Link> : null}
      </div>
    </div>
    <ResourceSwitcher label="Dashboards" items={options} current={owner} searchThreshold={6} />
  </section>;
}
