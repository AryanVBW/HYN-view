"use client";

import { useId, useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { setNodeRelayer } from "@/app/admin/relayer-actions";
import type { NodeRelayerLink, RelayerAssignment } from "@/lib/relayer";

export function NodeRelayerSetting({
  nodeId,
  nodeName,
  assignments,
  links,
  nodes,
  canWrite = false,
  error = null,
}: {
  nodeId: string;
  nodeName: string;
  assignments: RelayerAssignment[];
  links: NodeRelayerLink[];
  nodes: { id: string; name: string }[];
  canWrite?: boolean;
  error?: string | null;
}) {
  const id = useId();
  const router = useRouter();
  const initial = links.find(link => link.node_id === nodeId)?.assignment_id ?? "";
  const [selected, setSelected] = useState(initial);
  const [saved, setSaved] = useState(initial);
  const [message, setMessage] = useState("");
  const [failure, setFailure] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const savedAssignment = assignments.find(assignment => assignment.id === saved);

  return (
    <form className="mb-6 space-y-3 border-b border-border pb-6" aria-label={`Relayer link for ${nodeName}`}
      onSubmit={event => {
        event.preventDefault();
        if (!canWrite || error || pending || selected === saved) return;
        const target = selected;
        setMessage("");
        setFailure(null);
        startTransition(async () => {
          try {
            const result = await setNodeRelayer(nodeId, target || null);
            if (!result.ok) {
              setFailure(result.error ?? "The relay link could not be saved.");
              return;
            }
            setSaved(target);
            setMessage(target ? `Relayer linked to ${nodeName}.` : `Relayer unlinked from ${nodeName}.`);
            router.refresh();
          } catch {
            setFailure("The relay link could not be saved. Try again.");
          }
        });
      }}>
      <div className="rounded-lg border border-border bg-secondary/20 p-3">
        <div className="flex flex-wrap items-center justify-between gap-2"><strong className="break-words text-sm">{nodeName}</strong><span className="rounded-full border border-border px-2 py-1 text-xs tabular-nums">{error ? "Link unavailable" : `${saved ? 1 : 0} of 1 relay linked`}</span></div>
        <p className="mt-2 text-xs text-muted-foreground">Below Running: <strong className="text-foreground">{error ? "Unavailable" : savedAssignment?.relayer_name ?? (saved ? "Linked relay" : "No relay linked")}</strong></p>
        {savedAssignment && !error ? <Link href={`/dashboard?section=relayers&relayScope=server&node=${nodeId}`} className="mt-2 inline-block rounded-sm text-xs text-primary underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-primary">View linked relay</Link> : null}
      </div>
      <label htmlFor={id} className="block font-medium">Linked Highway relayer</label>
      <p id={`${id}-help`} className="text-sm text-muted-foreground">
        Choose the relayer running on {nodeName}. Its heartbeat and health appear below Running on this server&apos;s dashboard.
      </p>
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
        <select id={id} aria-describedby={`${id}-help`} value={selected}
          onChange={event => { setSelected(event.target.value); setMessage(""); setFailure(null); }}
          disabled={!canWrite || !!error || pending}
          className="min-w-0 flex-1 rounded-md border border-border bg-background px-3 py-2.5 text-sm focus-visible:outline-2 focus-visible:outline-primary disabled:opacity-60">
          <option value="">No relayer linked</option>
          {assignments.map(assignment => {
            const linked = links.find(link => link.assignment_id === assignment.id);
            const elsewhere = linked && linked.node_id !== nodeId;
            const serverName = elsewhere ? nodes.find(node => node.id === linked.node_id)?.name ?? "another server" : null;
            return <option key={assignment.id} value={assignment.id} disabled={!!elsewhere}>
              {assignment.relayer_name} (#{assignment.relayer_id}){serverName ? ` - linked to ${serverName}` : ""}
            </option>;
          })}
        </select>
        {canWrite ? <button type="submit" disabled={!!error || pending || selected === saved}
          className="rounded-md bg-primary px-4 py-2.5 text-sm font-medium text-primary-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:opacity-50">
          {pending ? "Saving..." : "Save relay link"}
        </button> : <span className="text-xs text-muted-foreground">Super admins manage relay links.</span>}
      </div>
      {!error && !assignments.length ? <p className="text-sm text-muted-foreground">Assign a relayer to this server&apos;s owner in Assignments, then link it here.</p> : null}
      {error || failure ? <p role="alert" className="text-sm text-destructive">{error ?? failure}</p> : null}
      <p role="status" className="text-sm text-primary">{message}</p>
    </form>
  );
}
