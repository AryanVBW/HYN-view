"use client";

import Link from "next/link";
import { useState, useTransition, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { ArrowUpRight, Check, Search, Server, Users } from "lucide-react";
import { portalRpc } from "@/lib/data-browser";
import type { AdminClient, AdminNode } from "@/lib/types";

export type ServerGrant = { viewer_id: string; node_id: string; allowed: boolean; notifications_allowed?: boolean };
export type AccessEvent = ServerGrant & { id: number; ts: string; actor: string };
type DashboardShare = { viewer_id: string; owner_id: string };
const personName = (person: AdminClient) => person.full_name || person.email || "Unnamed user";
const sameSelection = (left: string[], right: string[]) => left.length === right.length && left.every(id => right.includes(id));
const inputClass = "w-full rounded-lg border border-border bg-background py-2.5 pl-9 pr-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-primary";

export function ServerAccess({ clients, nodes, grants, shares = [], events, error, relayerPanels = {}, nodeRelayPanels = {}, relayerCounts = {} }: {
  clients: AdminClient[]; nodes: AdminNode[]; grants: ServerGrant[]; shares?: DashboardShare[];
  events: AccessEvent[]; error?: string | null;
  relayerPanels?: Record<string, ReactNode>; nodeRelayPanels?: Record<string, ReactNode>; relayerCounts?: Record<string, number>;
}) {
  const people = clients.filter(client => client.status === "active" && (client.role === "viewer" || client.role === "monitor"));
  const servers = nodes.filter(node => !node.revoked && !node.is_demo && node.owner_status !== "suspended");
  const [chosen, setChosen] = useState(people[0]?.id ?? "");
  const [search, setSearch] = useState("");
  const [locked, setLocked] = useState(false);
  const current = people.find(person => person.id === chosen) ?? people[0];
  const canSee = (viewer: string, node: AdminNode) => node.owner_id === viewer ||
    (grants.find(grant => grant.viewer_id === viewer && grant.node_id === node.id)?.allowed ??
      shares.some(share => share.viewer_id === viewer && share.owner_id === node.owner_id));
  const assigned = current ? servers.filter(node => canSee(current.id, node)).map(node => node.id).sort() : [];
  const person = (id: string) => clients.find(client => client.id === id);
  const matches = people.filter(client => `${personName(client)} ${client.email ?? ""}`.toLowerCase().includes(search.toLowerCase()));

  return <section className="terminal-panel overflow-hidden rounded-xl" aria-labelledby="server-access-title">
    <header className="flex flex-wrap items-center justify-between gap-4 border-b border-border p-5 md:p-7">
      <div>
        <h2 id="server-access-title" className="font-sentient text-3xl">Assignments</h2>
        <p className="mt-2 text-sm text-muted-foreground">Choose a person to manage their servers and relayers. Link one relay to a Highway Node; other assigned relays stay available in their Relayers tab.</p>
      </div>
      <span className="inline-flex items-center gap-2 text-xs text-muted-foreground"><Users className="size-4" aria-hidden />Super admins only</span>
    </header>
    {error ? <p role="alert" className="m-5 rounded-lg border border-destructive/40 p-3 text-sm text-destructive">{error}</p> : null}
    <div className="grid lg:grid-cols-[minmax(220px,0.8fr)_minmax(0,2fr)]">
      <aside className="border-b border-border bg-secondary/20 p-4 lg:border-b-0 lg:border-r">
        <label className="relative block">
          <span className="sr-only">Find a user</span><Search className="absolute left-3 top-3 size-4 text-muted-foreground" aria-hidden />
          <input value={search} onChange={event => setSearch(event.target.value)} placeholder="Find a user" className={inputClass} />
        </label>
        <div className="mt-3 max-h-72 space-y-1 overflow-y-auto lg:max-h-[36rem]" aria-label="Users to assign">
          {matches.map(client => {
            const count = servers.filter(node => canSee(client.id, node)).length;
            return <button key={client.id} type="button" aria-pressed={current?.id === client.id}
              disabled={locked && current?.id !== client.id}
              onClick={() => { if (current?.id !== client.id) { setChosen(client.id); setLocked(false); } }}
              className={`flex w-full items-center gap-3 rounded-lg border p-3 text-left focus-visible:outline-2 focus-visible:outline-primary disabled:opacity-40 ${current?.id === client.id ? "border-primary/40 bg-primary/10" : "border-transparent hover:bg-secondary/60"}`}>
              <span className="flex size-9 shrink-0 items-center justify-center rounded-full border border-border bg-background text-sm font-medium" aria-hidden>{personName(client).slice(0, 1).toUpperCase()}</span>
              <span className="min-w-0 flex-1"><span className="block truncate text-sm font-medium">{personName(client)}</span><span className="mt-0.5 block truncate text-xs text-muted-foreground">{client.email || (client.role === "viewer" ? "Viewer" : "Monitor")}</span></span>
              <span className="shrink-0 rounded-md bg-background px-2 py-1 text-right text-xs tabular-nums"><span className="block">{count} servers</span><span className="mt-1 block text-muted-foreground">{relayerCounts[client.id] ?? 0} relays</span></span>
            </button>;
          })}
          {!matches.length ? <p className="p-3 text-sm text-muted-foreground">{people.length ? "No users match your search." : "Add an active Viewer or Monitor to assign servers."}</p> : null}
        </div>
        <p className="mt-4 px-1 text-xs leading-5 text-muted-foreground">Owners keep access to their own devices. Admins have fleet access.</p>
      </aside>
      {current ? <UserServerAssignments
        key={`${current.id}:${assigned.join(",")}:${grants.filter(grant => grant.viewer_id === current.id).map(grant => `${grant.node_id}:${grant.notifications_allowed}`).join(",")}`}
        client={current} nodes={servers} initial={assigned} grants={grants}
        sharedCounts={Object.fromEntries(servers.map(node => [node.id, people.filter(client => canSee(client.id, node)).length]))}
        inherited={shares.some(share => share.viewer_id === current.id)} error={error} onLockChange={setLocked}
        relayerPanel={relayerPanels[current.id]} nodeRelayPanels={nodeRelayPanels}
        relayerCount={relayerCounts[current.id] ?? 0}
      /> : <div className="flex min-h-64 items-center justify-center p-8 text-sm text-muted-foreground">Users and their assigned servers will appear here.</div>}
    </div>
    <details className="border-t border-border px-5 py-4 md:px-7">
      <summary className="cursor-pointer text-sm text-muted-foreground">Recent assignment activity</summary>
      <ul className="mt-4 max-h-64 space-y-3 overflow-y-auto text-sm">{events.map(event => <li key={event.id}>
        <span>{person(event.actor) ? personName(person(event.actor)!) : "Administrator"} {event.allowed ? "assigned" : "removed"} {nodes.find(node => node.id === event.node_id)?.name ?? "Deleted server"} {event.allowed ? "to" : "from"} {person(event.viewer_id) ? personName(person(event.viewer_id)!) : "Deleted user"}</span>
        <time className="mt-1 block text-xs text-muted-foreground" dateTime={event.ts}>{new Date(event.ts).toISOString().replace("T", " ").slice(0, 19)} UTC</time>
      </li>)}</ul>
      {!events.length ? <p className="mt-3 text-sm text-muted-foreground">Saved assignment changes will appear here.</p> : null}
    </details>
  </section>;
}

function UserServerAssignments({ client, nodes, initial, grants, sharedCounts, inherited, error, onLockChange, relayerPanel, nodeRelayPanels, relayerCount }: {
  client: AdminClient; nodes: AdminNode[]; initial: string[]; grants: ServerGrant[];
  sharedCounts: Record<string, number>; inherited: boolean; error?: string | null; onLockChange: (locked: boolean) => void;
  relayerPanel?: ReactNode; nodeRelayPanels: Record<string, ReactNode>;
  relayerCount: number;
}) {
  const router = useRouter();
  const [selected, setSelected] = useState(initial);
  const [saved, setSaved] = useState(initial);
  const [search, setSearch] = useState("");
  const [assignedOnly, setAssignedOnly] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const dirty = !sameSelection(selected, saved);
  const owned = nodes.filter(node => node.owner_id === client.id).map(node => node.id);
  const matches = nodes.filter(node => (!assignedOnly || selected.includes(node.id)) &&
    `${node.name} ${node.hostname ?? ""} ${node.owner_email ?? ""}`.toLowerCase().includes(search.toLowerCase()));
  function choose(next: string[]) {
    const ids = [...new Set([...owned, ...next])];
    setSelected(ids);
    setMessage(null);
    setFailure(null);
    onLockChange(!sameSelection(ids, saved));
  }
  function save() {
    const target = [...selected];
    onLockChange(true);
    startTransition(async () => {
      setMessage(null);
      setFailure(null);
      try {
        const { error: result } = await portalRpc("hyn_admin_set_user_servers", {
          p_viewer: client.id, p_nodes: target.filter(id => !owned.includes(id)),
        });
        if (result) { setFailure(result.message); onLockChange(dirty); return; }
        setSaved(target);
        setMessage(`Assignments saved. ${personName(client)} can view ${target.length} server${target.length === 1 ? "" : "s"}.`);
        onLockChange(false);
        router.refresh();
      } catch { setFailure("Could not save assignments. Your selection is kept; try again."); onLockChange(dirty); }
    });
  }
  function notifications(nodeId: string, allow: boolean) {
    onLockChange(true);
    startTransition(async () => {
      setFailure(null);
      try {
        const { error: result } = await portalRpc("hyn_admin_share_server", {
          p_viewers: [client.id], p_node: nodeId, p_allow: true, p_notify: allow,
        });
        if (result) setFailure(result.message);
        else { setMessage("Notification preference saved."); router.refresh(); }
      } catch { setFailure("Could not save the notification preference. Try again."); }
      finally { onLockChange(dirty); }
    });
  }

  return <div className="min-w-0 p-5 md:p-7">
    <div className="flex flex-wrap items-center justify-between gap-3">
      <div><h3 className="font-sentient text-2xl">{personName(client)}</h3><p className="mt-1 text-sm text-muted-foreground">{selected.length} server{selected.length === 1 ? "" : "s"} selected</p></div>
      <span className={`rounded-full border px-3 py-1 text-xs ${dirty ? "border-primary/40 text-primary" : "border-border text-muted-foreground"}`}>{dirty ? "Unsaved changes" : "Saved assignments"}</span>
    </div>
    <nav className="mt-5 grid gap-3 sm:grid-cols-2" aria-label={`Assignment relationships for ${personName(client)}`}>
      <a href={`#server-assignments-${client.id}`} className="flex items-start gap-3 rounded-lg border border-border bg-secondary/20 p-4 focus-visible:outline-2 focus-visible:outline-primary">
        <Server className="mt-0.5 size-5 shrink-0 text-primary" aria-hidden /><span><strong className="block text-sm">{saved.length} server{saved.length === 1 ? "" : "s"} with access</strong><span className="mt-1 block text-xs leading-5 text-muted-foreground">User can open these computers in Servers.</span></span>
      </a>
      {relayerPanel ? <a href={`#relay-assignments-${client.id}`} className="flex items-start gap-3 rounded-lg border border-primary/30 bg-primary/5 p-4 focus-visible:outline-2 focus-visible:outline-primary">
        <ArrowUpRight className="mt-0.5 size-5 shrink-0 text-primary" aria-hidden /><span><strong className="block text-sm">{relayerCount} relay{relayerCount === 1 ? "" : "s"} assigned</strong><span className="mt-1 block text-xs leading-5 text-muted-foreground">User can select any of these in Relayers. Manage relays here.</span></span>
      </a> : null}
    </nav>
    <div id={`server-assignments-${client.id}`} className="mt-5 flex scroll-mt-24 flex-wrap items-center gap-2">
      <label className="relative min-w-0 flex-1"><span className="sr-only">Find a server</span><Search className="absolute left-3 top-3 size-4 text-muted-foreground" aria-hidden /><input value={search} onChange={event => setSearch(event.target.value)} placeholder="Find a server" className={inputClass} /></label>
      <button type="button" aria-pressed={assignedOnly} onClick={() => setAssignedOnly(value => !value)} className={`rounded-lg border px-3 py-2.5 text-xs focus-visible:outline-2 focus-visible:outline-primary ${assignedOnly ? "border-primary text-primary" : "border-border text-muted-foreground"}`}>Assigned only</button>
    </div>
    <div className="mb-3 mt-3 flex items-center justify-between text-xs">
      <span className="text-muted-foreground">{matches.length} server{matches.length === 1 ? "" : "s"} shown</span>
      <div className="flex gap-4"><button type="button" disabled={pending || !!error || !matches.length} onClick={() => choose([...selected, ...matches.map(node => node.id)])} className="text-primary underline-offset-4 hover:underline disabled:opacity-40">Select shown</button><button type="button" disabled={pending || !!error || selected.length === owned.length} onClick={() => choose([])} className="text-muted-foreground underline-offset-4 hover:underline disabled:opacity-40">Clear selection</button></div>
    </div>
    <div className="grid max-h-[32rem] gap-3 overflow-y-auto p-0.5 sm:grid-cols-2" aria-label={`Servers for ${personName(client)}`}>
      {matches.map(node => {
        const checked = selected.includes(node.id);
        const isOwner = node.owner_id === client.id;
        return <div key={node.id} className={`rounded-xl border p-4 ${checked ? "border-primary/50 bg-primary/5" : "border-border bg-card"}`}>
          <label className="flex cursor-pointer items-start gap-3">
            <input type="checkbox" checked={checked} disabled={isOwner || pending || !!error}
              onChange={event => choose(event.target.checked ? [...selected, node.id] : selected.filter(id => id !== node.id))}
              className="mt-1 size-4 shrink-0 accent-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary" />
            <span className="min-w-0 flex-1"><span className="flex items-center gap-2 text-sm font-medium"><Server className="size-4 shrink-0 text-muted-foreground" aria-hidden /><span className="break-words">{node.name}</span></span><span className="mt-1 block truncate text-xs text-muted-foreground">{node.hostname || node.owner_email || "Linked server"}</span></span>
            {checked ? <Check className="size-4 shrink-0 text-primary" aria-hidden /> : null}
          </label>
          <div className="mt-4 flex flex-wrap items-center justify-between gap-2 border-t border-border/60 pt-3 text-xs">
            <span className="text-muted-foreground">{isOwner ? "Owner access" : `${sharedCounts[node.id] ?? 0} users with access`}</span>
            <Link href={`/dashboard?node=${node.id}`} className="inline-flex items-center gap-1 rounded-sm text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary">Open dashboard<ArrowUpRight className="size-3" aria-hidden /><span className="sr-only"> for {node.name}</span></Link>
          </div>
          {checked && saved.includes(node.id) && nodeRelayPanels[node.id] ? <details className="mt-3 border-t border-border/60 pt-3">
            <summary className="cursor-pointer text-xs font-medium text-primary">Highway Node relay</summary>
            <p className="mt-3 text-xs leading-5 text-muted-foreground">One relay per server. Everyone with access to this computer sees the same linked relay below Running.</p>
            <fieldset disabled={pending || dirty || !!error} className="mt-3 min-w-0 disabled:opacity-60">{nodeRelayPanels[node.id]}</fieldset>
          </details> : null}
        </div>;
      })}
    </div>
    {!matches.length ? <p className="rounded-lg border border-dashed border-border p-8 text-center text-sm text-muted-foreground">{nodes.length ? "No servers match this filter." : "Link a server to start assigning access."}</p> : null}
    {inherited ? <p className="mt-4 text-xs leading-5 text-muted-foreground">Saving limits this user&apos;s shared access to the servers selected here, replacing their existing whole-dashboard shares.</p> : null}
    {failure ? <p role="alert" className="mt-4 text-sm text-destructive">{failure}</p> : null}
    {message ? <p role="status" className="mt-4 text-sm text-primary">{message}</p> : null}
    <div className="mt-5 flex flex-wrap items-center gap-3 border-t border-border pt-4">
      <button type="button" onClick={save} disabled={pending || !!error || (!dirty && !inherited)} className="rounded-lg bg-primary px-5 py-2.5 text-sm font-medium text-primary-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:opacity-40">{pending ? "Saving..." : "Save assignments"}</button>
      {dirty ? <button type="button" disabled={pending} onClick={() => choose(saved)} className="rounded-lg border border-border px-4 py-2.5 text-sm focus-visible:outline-2 focus-visible:outline-primary">Discard changes</button> : null}
      <span className="text-xs text-muted-foreground">{dirty ? "Save or discard before choosing another user." : "Users can view only the servers they have access to."}</span>
    </div>
    {saved.some(id => !owned.includes(id)) ? <details className="mt-5 border-t border-border pt-4">
      <summary className="cursor-pointer text-sm text-muted-foreground">Notification settings</summary>
      <div className="mt-3 space-y-3">{nodes.filter(node => saved.includes(node.id) && !owned.includes(node.id)).map(node => <label key={node.id} className="flex items-center gap-3 text-sm">
        <input type="checkbox" checked={grants.find(grant => grant.viewer_id === client.id && grant.node_id === node.id)?.notifications_allowed !== false} disabled={pending || dirty || !!error} onChange={event => notifications(node.id, event.target.checked)} className="size-4 accent-primary" />
        Allow notifications for {node.name}
      </label>)}</div>
    </details> : null}
    {relayerPanel ? <section id={`relay-assignments-${client.id}`} className="mt-7 scroll-mt-24 border-t border-border pt-6" aria-label={`Relayers assigned to ${personName(client)}`}>
      <h4 className="font-sentient text-xl">User relayers</h4>
      <p className="mb-4 mt-2 text-sm text-muted-foreground">These assignments are separate from server access. The user can view all of them in Relayers, including relays without a server link.</p>
      {dirty ? <p className="mb-3 text-xs text-muted-foreground">Save or discard server changes before editing relayers.</p> : null}
      <fieldset disabled={pending || dirty} className="min-w-0 disabled:opacity-60">{relayerPanel}</fieldset>
    </section> : null}
  </div>;
}
