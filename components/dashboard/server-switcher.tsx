"use client";
import { useSearchParams } from "next/navigation";
import { ResourceSwitcher } from "./resource-switcher";

export function ServerSwitcher({ nodes, current, baseHref, accounts = [] }: {
  nodes: {id: string; name: string; hostname: string | null; owner: string; is_demo: boolean; status: string}[];
  current?: string; baseHref: string; accounts?: {id: string; name: string; own: boolean}[];
}) {
  const params = useSearchParams();
  return <ResourceSwitcher label="Servers" current={current} items={nodes.map(node => {
    const [path, query] = baseHref.split("?");
    const next = new URLSearchParams(query);
    next.set("node",node.id);
    const relayer = params.get("relayer");
    if (relayer) next.set("relayer",relayer);
    const account = accounts.find(a => a.id === node.owner);
    const ownerName = account?.own ? "Mine" : account?.name;
    return {id: node.id, name: node.name, detail: [node.is_demo ? "Demo" : ownerName, node.status !== "active" ? node.status : null].filter(Boolean).join(" · "), searchText: `${node.hostname ?? ""} ${node.id}`, href: `${path}?${next}`};
  })} />;
}
