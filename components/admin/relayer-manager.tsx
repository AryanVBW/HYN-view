"use client";

import { useEffect, useState, useTransition } from "react";
import Link from "next/link";
import { ArrowUpRight, Check, Link2, Radio, Search, Server, Unlink, Users, X } from "lucide-react";
import { assignRelayer, removeRelayer } from "@/app/admin/relayer-actions";
import { RelayerDashboard } from "@/components/dashboard/relayer-dashboard";
import type { NodeRelayerLink, RelayerAssignment } from "@/lib/relayer";
import "./relayer-manager.css";

type Match = {
  id: number;
  name: string;
  tier: string | null;
  city: string | null;
};
export function RelayerManager({
  ownerId,
  ownerName,
  assignments,
  error,
  showReadings = true,
  links,
  nodes = [],
}: {
  ownerId: string;
  ownerName: string;
  assignments: RelayerAssignment[];
  error: string | null;
  showReadings?: boolean;
  links?: NodeRelayerLink[];
  nodes?: { id: string; name: string }[];
}) {
  const [query, setQuery] = useState("");
  const [matches, setMatches] = useState<Match[]>([]);
  const [chosen, setChosen] = useState<Match[]>([]);
  const [failures, setFailures] = useState<string[]>([]);
  const [confirmRemoval, setConfirmRemoval] = useState<string | null>(null);
  const [searching, setSearching] = useState(false);
  const [searched, setSearched] = useState(false);
  const [searchError, setSearchError] = useState<string | null>(null);
  const [message, setMessage] = useState("");
  const [pending, startTransition] = useTransition();
  const [revision, setRevision] = useState(0);
  const assignedIds = new Set(assignments.map(assignment => assignment.relayer_id));
  const selectedRelays = chosen.filter(match => !assignedIds.has(match.id));
  const linkedCount = links === undefined ? null : assignments.filter(assignment =>
    links.some(link => link.assignment_id === assignment.id)).length;

  function toggle(match: Match) {
    setChosen(current => current.some(item => item.id === match.id)
      ? current.filter(item => item.id !== match.id) : [...current, match]);
  }

  function assignSelected() {
    const targets = [...selectedRelays];
    if (!targets.length || pending || error) return;
    setMessage("");
    setFailures([]);
    startTransition(async () => {
      const failed: Match[] = [];
      const errors: string[] = [];
      for (const target of targets) {
        try {
          const result = await assignRelayer(ownerId, target.id);
          if (!result.ok) {
            failed.push(target);
            errors.push(`${target.name}: ${result.error ?? "Could not assign relay."}`);
          }
        } catch {
          failed.push(target);
          errors.push(`${target.name}: Could not confirm the assignment. Retry to confirm it without creating a duplicate.`);
        }
      }
      const saved = targets.length - failed.length;
      setChosen(failed);
      setFailures(errors);
      setMessage(`${saved} relay${saved === 1 ? "" : "s"} assigned to ${ownerName}.${failed.length ? ` ${failed.length} not confirmed; those relays remain selected for retry.` : " They are available in this user's Relayers tab."}`);
      if (saved) setRevision(value => value + 1);
      if (!failed.length) changeQuery("");
    });
  }

  function remove(assignment: RelayerAssignment) {
    setMessage("");
    setFailures([]);
    startTransition(async () => {
      try {
        const result = await removeRelayer(assignment.id);
        if (!result.ok) {
          setFailures([result.error ?? "Could not remove assignment."]);
          return;
        }
        setMessage(`Removed ${assignment.relayer_name} from ${ownerName}. Other users' assignments have not changed.`);
        setConfirmRemoval(null);
        setRevision(value => value + 1);
      } catch {
        setFailures(["Could not confirm removal. Refresh before trying again."]);
      }
    });
  }

  function changeQuery(value: string) {
    setQuery(value);
    setMatches([]);
    setSearched(false);
    setSearchError(null);
    setSearching(!!value.trim());
  }
  useEffect(() => {
    const controller = new AbortController();
    if (!query.trim()) return () => controller.abort();
    const timer = setTimeout(async () => {
      try {
        const response = await fetch(
          `/api/admin/relayers?q=${encodeURIComponent(query.trim())}`,
          { signal: controller.signal, cache: "no-store" },
        );
        const data = await response.json();
        if (!response.ok) throw new Error(data.error ?? "Search failed.");
        if (!controller.signal.aborted) {
          setMatches(data.relayers);
          setSearched(true);
        }
      } catch (error) {
        if (!controller.signal.aborted)
          setSearchError(
            error instanceof Error ? error.message : "Search failed.",
          );
      } finally {
        if (!controller.signal.aborted) setSearching(false);
      }
    }, 300);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [query]);

  return (
    <div className="relayer-view relayer-management">
      <div className="relayer-assignment-panel">
        <div className="relayer-section-title">
          <Link2 size={18} aria-hidden />
          <h3>Assign relays to {ownerName}</h3>
        </div>
        <p>
          Select one or more relays, then assign them together. Search again to
          add more to your selection without losing the relays already selected.
        </p>
        <div className="relay-relationship" aria-label={`Relay access for ${ownerName}`}>
          <span className="relay-relationship-person"><Users size={18} aria-hidden /><strong>{ownerName}</strong></span>
          <span className="relay-relationship-verb">can view</span>
          <span className="relay-relationship-destination"><Radio size={18} aria-hidden /><strong>{error ? "Unavailable" : `${assignments.length} assigned relay${assignments.length === 1 ? "" : "s"}`}</strong><small>All appear in the Relayers tab</small></span>
        </div>
        <dl className="relay-assignment-totals">
          <div><dt>Assigned to user</dt><dd>{error ? "Unavailable" : assignments.length}</dd></div>
          <div><dt>Also linked to a server</dt><dd>{error || linkedCount === null ? "Unknown" : linkedCount}</dd></div>
          <div><dt>Relayers tab only</dt><dd>{error || linkedCount === null ? "Unknown" : assignments.length - linkedCount}</dd></div>
        </dl>
        <p>One user can have many relays. Linking a relay to a server is separate: each Highway Node shows only its one linked relay below Running.</p>
        {error ? (
          <p role="alert" className="relayer-notice">
            {error}
          </p>
        ) : null}
        <div className="relayer-assign-controls">
          <label className="relayer-search">
            <Search size={16} aria-hidden />
            <input
              aria-label="Search Highway relayers"
              placeholder="Search name or ID, e.g. praveen256 or 457"
              maxLength={100}
              value={query}
              onChange={(e) => changeQuery(e.target.value)}
              disabled={pending || !!error}
            />
          </label>
          <button
            className="relayer-button"
            type="button"
            disabled={!selectedRelays.length || pending || !!error}
            onClick={assignSelected}
          >
            <Link2 size={15} aria-hidden />
            {pending ? "Saving..." : selectedRelays.length ? `Assign ${selectedRelays.length} relay${selectedRelays.length === 1 ? "" : "s"}` : "Assign selected"}
          </button>
        </div>
        {searching ? (
          <p className="relayer-search-status" role="status">
            Searching Highway…
          </p>
        ) : null}
        {searchError ? (
          <p role="alert" className="relayer-notice">
            {searchError}
          </p>
        ) : null}
        {searched && !matches.length ? (
          <p className="relayer-search-status">
            No relayer found. Try the on-chain name or exact numeric ID.
          </p>
        ) : null}
        {matches.length ? (
          <div
            className="relayer-search-results"
            aria-label="Highway search results"
          >
            {matches.map((match) => (
              <button
                key={match.id}
                type="button"
                aria-pressed={assignedIds.has(match.id) || selectedRelays.some(item => item.id === match.id)}
                aria-label={`${assignedIds.has(match.id) ? "Already assigned" : "Select relay"}: ${match.name}`}
                disabled={pending || !!error || assignedIds.has(match.id)}
                onClick={() => toggle(match)}
              >
                <div>
                  <strong>{match.name}</strong>
                  <span>
                    {[match.city, match.tier].filter(Boolean).join(" / ") || "Highway relay"}
                  </span>
                </div>
                {assignedIds.has(match.id) ? <span>Already assigned</span> : selectedRelays.some(item => item.id === match.id) ? (
                  <span className="relay-match-selected"><Check size={18} aria-hidden />Selected</span>
                ) : (
                  <span>Select</span>
                )}
              </button>
            ))}
          </div>
        ) : null}
        {selectedRelays.length ? (
          <div className="relay-selection-tray" aria-label="Relays selected to assign">
            <div className="relay-selection-heading"><strong>{selectedRelays.length} selected, not yet assigned</strong><button type="button" disabled={pending} onClick={() => setChosen([])}>Clear selection</button></div>
            <ul>{selectedRelays.map(match => <li key={match.id}><span>{match.name}</span><button type="button" disabled={pending} onClick={() => toggle(match)} aria-label={`Deselect ${match.name}`}><X size={14} aria-hidden /></button></li>)}</ul>
          </div>
        ) : null}
        <div className="relay-access-list" aria-label={`Saved relay assignments for ${ownerName}`}>
          <h4>Assigned relays <span>{error ? "Unavailable" : assignments.length}</span></h4>
          {!assignments.length && !error ? <p className="relay-access-empty">No relays assigned yet. Search above, select relays, then choose Assign selected. A server link is not required.</p> : null}
          {assignments.map(assignment => {
            const link = links?.find(item => item.assignment_id === assignment.id);
            const serverName = link ? nodes.find(node => node.id === link.node_id)?.name ?? "Linked server" : null;
            return <article key={assignment.id} className="relay-access-row">
              <div className="relay-access-description"><strong>{assignment.relayer_name}</strong>
                <span className="relay-access-location"><Radio size={14} aria-hidden />Relayers tab</span>
                {link ? <span className="relay-access-location"><Server size={14} aria-hidden />Also below Running on <strong>{serverName}</strong></span> : <span className="relay-access-note">{links === undefined ? "Server link information is unavailable." : "Not linked to a server. Visible in the Relayers tab only."}</span>}
              </div>
              <div className="relay-access-actions">
                <Link className="relayer-button" href={`/admin?tab=relayers&relayer=${assignment.relayer_id}`}>View relay<ArrowUpRight size={14} aria-hidden /><span className="sr-only"> {assignment.relayer_name}</span></Link>
                <button className="relay-remove-button" type="button" disabled={pending || !!error} aria-label={`Remove assignment for ${assignment.relayer_name}`} onClick={() => setConfirmRemoval(assignment.id)}><Unlink size={14} aria-hidden />Remove</button>
              </div>
              {confirmRemoval === assignment.id ? <div className="relay-removal-confirmation" role="group" aria-label={`Confirm removal of ${assignment.relayer_name}`}>
                <p>Remove <strong>{assignment.relayer_name}</strong> from {ownerName}? {link ? `This also removes its link below Running on ${serverName}.` : links === undefined ? "Any server link using this assignment will also be removed." : "It will no longer appear in this user's Relayers tab."} Other users&apos; assignments stay unchanged.</p>
                <div><button className="relayer-button" type="button" disabled={pending} onClick={() => remove(assignment)}>Confirm removal</button><button className="relayer-button" type="button" disabled={pending} onClick={() => setConfirmRemoval(null)}>Cancel</button></div>
              </div> : null}
            </article>;
          })}
        </div>
        {failures.length ? <ul role="alert" className="relayer-notice">{failures.map((failure, index) => <li key={index}>{failure}</li>)}</ul> : null}
        <p className="relayer-assignment-message" role="status">
          {message}
        </p>
      </div>
      {showReadings ? <RelayerDashboard key={ownerId} ownerId={ownerId} revision={revision} /> : null}
    </div>
  );
}
