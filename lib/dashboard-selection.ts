// Inputs must already be filtered by database RLS. This resolves navigation,
// never authorization, and rejects links that would show the wrong server.
//
// `canViewFleet` (not `canAdmin`) is what unlocks the combined owner === "all"
// view, because a Maintainer sees the whole fleet without being an administrator.
export function selectDashboard<T extends {id: string; owner: string}>({
  selfId, canViewFleet, accounts, nodes, requestedOwner, requestedNode,
}: {
  selfId: string; canViewFleet: boolean; accounts: {id: string}[]; nodes: T[];
  requestedOwner?: string; requestedNode?: string;
}): {owner: string; nodes: T[]; node: T | undefined} | null {
  const requested = requestedNode ? nodes.find(n => n.id === requestedNode) : undefined;
  if (requestedNode && !requested) return null;
  const defaultOwner = canViewFleet ? "all"
    : nodes.some(node => node.owner === selfId) ? selfId : nodes[0]?.owner ?? selfId;
  const owner = requestedOwner ?? requested?.owner ?? defaultOwner;
  if (owner === "all" ? !canViewFleet : !accounts.some(a => a.id === owner)) return null;
  const visible = owner === "all" ? nodes : nodes.filter(n => n.owner === owner);
  if (requested && !visible.includes(requested)) return null;
  return {owner, nodes: visible, node: requested ?? visible[0]};
}
