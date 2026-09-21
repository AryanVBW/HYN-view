"use client";

import Link from "next/link";
import { permissions, type DashboardAccount } from "@/lib/permissions";
import type { Node } from "@/lib/types";
import { DashboardNavigation } from "./dashboard-navigation";
import { ResourceSwitcher } from "./resource-switcher";

export function DashboardContext({ role, accounts, owner, section = "servers", nodeId, canViewRelayers = true, computers }: {
  role: unknown; accounts: DashboardAccount[]; owner: string;
  section?: "servers" | "relayers"; nodeId?: string; canViewRelayers?: boolean;
  computers?: Pick<Node, "id" | "name" | "hostname" | "owner">[];
}) {
  const access = permissions(role);
  const query = new URLSearchParams({ owner });
  if (nodeId) query.set("node", nodeId);
  const serverHref = `/dashboard?${query}`;
  const sectionQuery = section === "relayers" ? "&section=relayers" : "";
  const options = accounts.map(account => ({id: account.id, name: account.own ? "My devices" : account.name, href: `/dashboard?owner=${encodeURIComponent(account.id)}${sectionQuery}`}));
  if (access.canViewFleet) options.unshift({id: "all",name: "All servers",href: `/dashboard?owner=all${sectionQuery}`});
  const computerOptions = computers?.map(computer => {
    const hostname = computer.hostname?.trim();
    const savedName = computer.name.trim();
    const next = new URLSearchParams({owner: computer.owner, node: computer.id, section: "servers"});
    return {
      id: computer.id,
      name: hostname || savedName || "Unnamed computer",
      detail: hostname && savedName && hostname !== savedName ? savedName : undefined,
      searchText: computer.id,
      href: `/dashboard?${next}`,
    };
  });
  return <section className="mb-6 min-w-0 space-y-6 border-b border-border pb-6" aria-label="Dashboard access">
    <div className="flex flex-col gap-4 text-sm sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
      <DashboardNavigation section={section} serverHref={serverHref} canViewRelayers={canViewRelayers} />
      <div className="flex flex-wrap items-center gap-4">
        {access.canAdmin ? <Link href="/admin" className="text-muted-foreground hover:text-foreground">Admin dashboard</Link> : null}
        {access.isMaintainer ? <Link href="/maintainer" className="text-muted-foreground hover:text-foreground">Fleet monitor</Link> : null}
        {access.canLink ? <Link href="/link" className="rounded-full border border-primary/50 px-4 py-2.5 text-primary hover:bg-primary/10">+ Link server</Link> : null}
      </div>
    </div>
    {section === "servers" ? computerOptions
      ? computerOptions.length ? <ResourceSwitcher label="Computers" items={computerOptions} current={nodeId} /> : null
      : options.length > 1 ? <ResourceSwitcher label="Dashboards" items={options} current={owner} searchThreshold={6} /> : options[0] && !accounts[0]?.own ? <p className="text-sm text-muted-foreground">{options[0].name}</p> : null : null}
  </section>;
}
