"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type { AdminClient, AdminNode } from "@/lib/types";

export type ServerGrant = { viewer_id: string; node_id: string; allowed: boolean; notifications_allowed?: boolean };
export type AccessEvent = ServerGrant & { id: number; ts: string; actor: string };

export function ServerAccess({ clients, nodes, grants, events, error }: {
  clients: AdminClient[]; nodes: AdminNode[]; grants: ServerGrant[];
  events: AccessEvent[]; error?: string | null;
}) {
  const router = useRouter();
  const [viewers, setViewers] = useState<string[]>([]);
  const [notify, setNotify] = useState(true);
  const [node, setNode] = useState("");
  const [search, setSearch] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const person = (id: string) => {
    const client = clients.find(c => c.id === id);
    return client?.full_name || client?.email || "Deleted account";
  };
  const server = (id: string) => nodes.find(n => n.id === id)?.name || "Deleted server";
  function save(viewerIds: string[], nodeId: string, allowed: boolean, notifications = notify) {
    startTransition(async () => {
      setMessage(null);
      try {
        const { error: failure } = await createClient().rpc("hyn_admin_share_server", {
          p_viewers: viewerIds, p_node: nodeId, p_allow: allowed, p_notify: notifications,
        });
        setMessage(failure ? failure.message : allowed ? `Read-only server access saved for ${viewerIds.length} user${viewerIds.length === 1 ? "" : "s"}.` : "Server access blocked, including dashboard sharing.");
        if (!failure) router.refresh();
      } catch { setMessage("Could not save server access. Try again."); }
    });
  }
  const input = "w-full rounded-md border border-input bg-background px-3 py-3 text-sm focus-visible:outline-primary";
  return <section className="terminal-panel rounded-xl p-6 md:p-8" aria-labelledby="server-access-title">
    <h2 id="server-access-title" className="font-sentient text-3xl">Server access</h2>
    <p className="mt-3 max-w-2xl text-sm leading-7 text-muted-foreground">Share one server with multiple Viewers or Monitors. They can see its statistics and settings; only a Super admin can change the server or install updates. Blocking a server overrides ownership and dashboard sharing. Administrators retain fleet access.</p>
    {error ? <p role="alert" className="mt-4 text-destructive">{error}</p> : null}
    <form className="mt-6 grid items-end gap-4 lg:grid-cols-2" onSubmit={e => { e.preventDefault(); save(viewers,node,true); }}>
      <label className="space-y-2 text-sm">Users<select multiple size={5} required className={input} value={viewers} onChange={e=>setViewers(Array.from(e.target.selectedOptions, option=>option.value))}>
        {clients.filter(c=>c.status === "active" && (c.role === "viewer" || c.role === "monitor")).map(c=><option key={c.id} value={c.id}>{person(c.id)}</option>)}
      </select><span className="block text-xs text-muted-foreground">Choose several accounts with Ctrl or Command. {viewers.length} selected.</span></label>
      <label className="space-y-2 text-sm">Find a server<input className={input} placeholder="Server, hostname, or owner" value={search} onChange={e=>setSearch(e.target.value)} /></label>
      <label className="space-y-2 text-sm lg:col-span-2">Server<select required className={input} value={node} onChange={e=>setNode(e.target.value)}>
        <option value="">Choose from the fleet</option>
        {nodes.filter(n=>!n.revoked && `${n.name} ${n.hostname} ${n.owner_email}`.toLowerCase().includes(search.toLowerCase())).map(n=><option key={n.id} value={n.id}>{n.name} — {n.owner_email || "No owner email"}</option>)}
      </select></label>
      <label className="flex items-center gap-3 text-sm lg:col-span-2"><input type="checkbox" checked={notify} onChange={e=>setNotify(e.target.checked)} />Allow server notifications</label>
      <div className="flex flex-wrap gap-3 lg:col-span-2">
        <button disabled={pending || !!error || !viewers.length || !node} className="rounded-md bg-primary px-5 py-3 text-sm text-primary-foreground disabled:opacity-40">Grant access</button>
        <button type="button" disabled={pending || !!error || !viewers.length || !node} onClick={()=>save(viewers,node,false)} className="rounded-md border border-destructive/50 px-5 py-3 text-sm text-destructive disabled:opacity-40">Block access</button>
      </div>
    </form>
    {message ? <p role="status" className="mt-4 text-sm">{message}</p> : null}
    <h3 className="mt-9 text-lg font-medium">Server permissions</h3>
    <ul className="mt-3 divide-y divide-border">
      {grants.filter(g=>!viewers.length || viewers.includes(g.viewer_id)).map(g=><li key={`${g.viewer_id}:${g.node_id}`} className="flex flex-wrap items-center justify-between gap-3 py-4 text-sm">
        <span>{person(g.viewer_id)} <span className="text-muted-foreground">{g.allowed ? "can view" : "is blocked from"}</span> {server(g.node_id)}</span>
        {g.allowed ? <label className="flex items-center gap-2"><input type="checkbox" checked={g.notifications_allowed !== false} disabled={pending || !!error} onChange={e=>save([g.viewer_id],g.node_id,true,e.target.checked)} />Notifications<span className="sr-only"> for {person(g.viewer_id)} on {server(g.node_id)}</span></label> : null}
        <button disabled={pending || !!error} onClick={()=>save([g.viewer_id],g.node_id,!g.allowed,g.notifications_allowed !== false)} className="rounded border border-border px-3 py-2 disabled:opacity-40">{g.allowed ? "Block access" : "Grant access"}<span className="sr-only"> for {person(g.viewer_id)} to {server(g.node_id)}</span></button>
      </li>)}
    </ul>
    {!grants.length ? <p className="mt-3 text-sm text-muted-foreground">No server permissions set. Existing ownership and dashboard sharing still apply.</p> : null}
    <details className="mt-8 border-t border-border pt-5" open>
      <summary className="cursor-pointer text-lg font-medium">Access activity <span className="text-sm text-muted-foreground">· Super admins only</span></summary>
      <ul className="mt-4 space-y-3 text-sm">{events.map(e=><li key={e.id}><span>{person(e.actor)} {e.allowed ? "granted" : "blocked"} {person(e.viewer_id)} access to {server(e.node_id)}</span><time className="mt-1 block text-xs text-muted-foreground" dateTime={e.ts}>{new Date(e.ts).toISOString().replace("T"," ").slice(0,19)} UTC</time></li>)}</ul>
      {!events.length ? <p className="mt-4 text-sm text-muted-foreground">Server access changes will appear here.</p> : null}
    </details>
  </section>;
}
