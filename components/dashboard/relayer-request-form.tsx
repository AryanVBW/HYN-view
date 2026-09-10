"use client";

import { useState, type FormEvent } from "react";
import type { RelayerRequest } from "@/lib/relayer";

export function RelayerRequestForm({
  requests,
  error,
  onChanged,
  manageHref,
}: {
  requests: RelayerRequest[];
  error: string | null;
  onChanged: () => void;
  manageHref?: string | null;
}) {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  async function send(
    body:
      | { action: "request"; query: string }
      | { action: "cancel"; requestId: string },
  ) {
    setBusy(true);
    setMessage(null);
    setFailed(false);
    try {
      const response = await fetch("/api/relayers/requests", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(20_000),
      });
      const result = await response.json();
      if (!response.ok)
        throw new Error(result.error ?? "Could not save your request.");
      setMessage(
        body.action === "request"
          ? "Request sent. An administrator will verify the relayer before connecting it to your account."
          : "Request cancelled.",
      );
      onChanged();
    } catch (error) {
      setFailed(true);
      setMessage(
        error instanceof Error
          ? error.message
          : "Could not save your request. Try again.",
      );
    } finally {
      setBusy(false);
    }
  }
  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const query = String(
      new FormData(event.currentTarget).get("query") ?? "",
    ).trim();
    void send({ action: "request", query });
  }
  const visible = requests.filter(
    (r) => r.status === "pending" || r.status === "rejected",
  );
  return (
    <div className="relayer-request-panel">
      <h3>Connect a Highway relayer</h3>
      <p>
        Enter the exact Highway username or relayer ID. An administrator will
        verify ownership and approve your request.
      </p>
      {manageHref ? (
        <a className="relayer-button" href={manageHref}>
          Assign a relayer as administrator
        </a>
      ) : null}
      {error ? (
        <p role="alert" className="relayer-notice">
          {error}
        </p>
      ) : null}
      <form onSubmit={submit}>
        <label className="relayer-search">
          <span className="sr-only">Highway username or relayer ID</span>
          <input
            name="query"
            placeholder="Highway username or relayer ID"
            maxLength={100}
            required
            disabled={busy || !!error}
          />
        </label>
        <button
          className="relayer-button"
          type="submit"
          disabled={busy || !!error}
        >
          {busy ? "Saving…" : "Request relayer"}
        </button>
      </form>
      {message ? (
        <p role={failed ? "alert" : "status"} className="relayer-notice">
          {message}
        </p>
      ) : null}
      {visible.length ? (
        <ul aria-label="Your relayer requests">
          {visible.map((r) => (
            <li key={r.id}>
              <span>
                <strong>
                  {r.relayer_name} · #{r.relayer_id}
                </strong>
                <small>
                  {r.status === "pending"
                    ? "Pending administrator approval"
                    : "Request declined. Check the ID with your administrator before trying again."}
                </small>
              </span>
              {r.status === "pending" ? (
                <button
                  className="relayer-button"
                  disabled={busy}
                  onClick={() =>
                    void send({ action: "cancel", requestId: r.id })
                  }
                >
                  Cancel request
                </button>
              ) : null}
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
