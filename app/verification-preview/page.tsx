import { notFound } from "next/navigation";
import { BandwidthPanel } from "@/components/admin/bandwidth-panel";
import { ServerAccess } from "@/components/admin/server-access";
import { ServerNotifications } from "@/components/dashboard/server-notifications";
import { NodeSettings } from "@/components/account/node-settings";
import type { AdminClient, AdminNode, Node } from "@/lib/types";
export default function Preview() {
  if (process.env.NODE_ENV !== "development") notFound();
  const clients = [{id:"fixture-user",role:"viewer",status:"active",full_name:"Operations viewer"},{id:"fixture-user-2",role:"viewer",status:"active",full_name:"On-call engineer"}] as AdminClient[];
  const nodes = [{id:"fixture-node",name:"Mumbai relay 01",hostname:"mum-relay-01",owner_email:"operator@example.test",revoked:false,is_demo:false}] as AdminNode[];
  return <main className="container max-w-6xl space-y-8 py-36"><p>Local visual verification — fixture data</p><ServerAccess clients={clients} nodes={nodes} grants={[]} events={[]} /><BandwidthPanel nodes={nodes}/><NodeSettings nodes={[{...nodes[0],config:{auto_update:"check",alert_mem_pct:"85",keep_awake:"on"}} as unknown as Node]} /><ServerNotifications userId="fixture-user" events={[{id:"fixture-alert",node_id:"fixture-node",owner:"fixture-owner",node_name:"Mumbai relay 01",ts:"2026-09-10T10:00:00Z",severity:"warn",kind:"alert",message:"Memory usage is above the configured threshold."}]} /></main>;
}
