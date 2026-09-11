"use client";

import { useEffect, useState, useTransition } from "react";
import { Check, Link2, Search, Unlink } from "lucide-react";
import { assignRelayer, removeRelayer } from "@/app/admin/relayer-actions";
import { RelayerDashboard } from "@/components/dashboard/relayer-dashboard";
import type { RelayerAssignment } from "@/lib/relayer";
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
}: {
  ownerId: string;
  ownerName: string;
  assignments: RelayerAssignment[];
  error: string | null;
  showReadings?: boolean;
}) {
  const [query, setQuery] = useState("");
  const [matches, setMatches] = useState<Match[]>([]);
  const [chosen, setChosen] = useState<Match | null>(null);
  const [searching, setSearching] = useState(false);
  const [searched, setSearched] = useState(false);
  const [searchError, setSearchError] = useState<string | null>(null);
  const [message, setMessage] = useState("");
  const [pending, startTransition] = useTransition();
  const [revision, setRevision] = useState(0);
  function changeQuery(value: string) {
    setQuery(value);
    setMatches([]);
    setChosen(null);
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
          <h3>Assign Highway relayers</h3>
        </div>
        <p>
          Search the Highway server name, username or numeric relayer ID, then
          assign it to <strong>{ownerName}</strong>. This account will see only
          its assigned relayers.
        </p>
        <p>Every assigned relay appears in this user&apos;s Relayers tab, whether or not it is linked to a server. A Highway Node shows only its one linked relay.</p>
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
            disabled={!chosen || pending || !!error}
            onClick={() => {
              if (!chosen) return;
              const target = chosen;
              startTransition(async () => {
                const result = await assignRelayer(ownerId, target.id);
                setMessage(
                  result.ok
                    ? `Assigned ${target.name} (#${target.id}) to ${ownerName}.`
                    : (result.error ?? "Could not assign relayer."),
                );
                if (result.ok) {
                  changeQuery("");
                  setRevision((n) => n + 1);
                }
              });
            }}
          >
            <Link2 size={15} aria-hidden />
            {pending ? "Saving" : "Assign relayer"}
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
                aria-pressed={chosen?.id === match.id}
                disabled={pending}
                onClick={() => setChosen(match)}
              >
                <div>
                  <strong>{match.name}</strong>
                  <span>
                    #{match.id} ·{" "}
                    {[match.tier, match.city].filter(Boolean).join(" · ")}
                  </span>
                </div>
                {chosen?.id === match.id ? (
                  <Check size={18} aria-hidden />
                ) : (
                  <span>Select</span>
                )}
              </button>
            ))}
          </div>
        ) : null}
        {chosen ? (
          <p className="relayer-selection">
            Selected{" "}
            <strong>
              {chosen.name} · #{chosen.id}
            </strong>{" "}
            for {ownerName}.
          </p>
        ) : null}
        <div className="relayer-assigned-list">
          {assignments.map((a) => (
            <div key={a.id}>
              <span>
                <strong>{a.relayer_name}</strong>
                <small>Relayer #{a.relayer_id}</small>
              </span>
              <button
                className="relayer-button"
                disabled={pending}
                aria-label={`Remove assignment for ${a.relayer_name}`}
                onClick={() =>
                  startTransition(async () => {
                    const result = await removeRelayer(a.id);
                    setMessage(
                      result.ok
                        ? `Removed ${a.relayer_name} from this account.`
                        : (result.error ?? "Could not remove assignment."),
                    );
                    if (result.ok) setRevision((n) => n + 1);
                  })
                }
              >
                <Unlink size={14} aria-hidden />
                Remove assignment
              </button>
            </div>
          ))}
        </div>
        <p className="relayer-assignment-message" role="status">
          {message}
        </p>
      </div>
      {showReadings ? <RelayerDashboard key={ownerId} ownerId={ownerId} revision={revision} /> : null}
    </div>
  );
}
