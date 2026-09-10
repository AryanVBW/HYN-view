// Inputs must already be filtered by database RLS. This resolves navigation,
// never authorization, and rejects links that would show the wrong server.
export function selectDashboard<T extends {id: string; owner: string}>({
  selfId, canAdmin, accounts, nodes, requestedOwner, requestedNode,
}: {
  selfId: string; canAdmin: boolean; accounts: {id: string}[]; nodes: T[];
  requestedOwner?: string; requestedNode?: string;
}): {owner: string; nodes: T[]; node: T | undefined} | null {
  const requested = requestedNode ? nodes.find(n => n.id === requestedNode) : undefined;
  if (requestedNode && !requested) return null;
  const owner = requestedOwner ?? requested?.owner ?? (canAdmin ? "all" : selfId);
  if (owner === "all" ? !canAdmin : !accounts.some(a => a.id === owner)) return null;
  const visible = owner === "all" ? nodes : nodes.filter(n => n.owner === owner);
  if (requested && !visible.includes(requested)) return null;
  return {owner, nodes: visible, node: requested ?? visible[0]};
}
