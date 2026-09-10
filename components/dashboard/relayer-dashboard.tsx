"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { ResourceSwitcher } from "./resource-switcher";
import {
  Activity,
  ArrowUpRight,
  Check,
  ChevronDown,
  CircleHelp,
  Clock3,
  Copy,
  Radio,
  RefreshCw,
  ShieldCheck,
  Wallet,
  X,
} from "lucide-react";
import {
  ageSeconds,
  CHECKIN_LIMIT_S,
  HEARTBEAT_LIMIT_S,
  relayerChecks,
  type RelayerDashboardData,
  type RelayerReading,
} from "@/lib/relayer";
import "./relayer.css";

const number = (value: string | number | null | undefined) => {
  if (value === null || value === undefined) return "—";
  if (typeof value === "number")
    return value.toLocaleString("en-US", { maximumFractionDigits: 2 });
  const [whole, fraction] = value.split(".");
  return `${whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",")}${fraction ? `.${fraction.slice(0, 4)}` : ""}`;
};
function duration(seconds: number | null) {
  if (seconds === null) return "—";
  if (seconds < 60) return `${Math.floor(seconds)}s`;
  if (seconds < 3600)
    return `${Math.floor(seconds / 60)}m ${Math.floor(seconds % 60)}s`;
  if (seconds < 86400)
    return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
  return `${Math.floor(seconds / 86400)}d ${Math.floor((seconds % 86400) / 3600)}h`;
}
function time(at: string | null | undefined) {
  return at
    ? `${new Date(at).toLocaleString("en-GB", { dateStyle: "medium", timeStyle: "medium", timeZone: "UTC" })} UTC`
    : "Not reported";
}

export function RelayerDashboard({
  ownerId,
  nodeId,
  revision = 0,
  compact = false,
}: {
  ownerId?: string;
  nodeId?: string;
  revision?: number;
  compact?: boolean;
}) {
  const [data, setData] = useState<RelayerDashboardData | null>(null);
  const [loading, setLoading] = useState(false);
  const [reload, setReload] = useState(0);
  const params = useSearchParams();
  const pathname = usePathname();
  const candidate = Number(params.get("relayer"));
  const selected = !nodeId && !compact && Number.isSafeInteger(candidate) && candidate > 0 ? candidate : null;
  const [now, setNow] = useState(() => Date.now());
  const refresh = useCallback(() => setReload((n) => n + 1), []);

  useEffect(() => {
    let alive = true;
    let busy = false;
    let controller: AbortController | null = null;
    async function load() {
      if (busy) return;
      busy = true;
      controller = new AbortController();
      setLoading(true);
      const timeout = setTimeout(() => controller?.abort(), 55_000);
      try {
        const params = new URLSearchParams();
        if (nodeId) params.set("node", nodeId);
        else {
          if (ownerId) params.set("owner", ownerId);
          if (selected) params.set("relayer", String(selected));
        }
        const response = await fetch(`/api/relayers?${params}`, {
          cache: "no-store",
          signal: controller.signal,
        });
        const body = (await response.json()) as RelayerDashboardData;
        if (response.status === 401 || response.status === 403 || response.status === 404) {
          if (alive)
            setData({
              readings: [],
              error: body.error ?? "Sign in again to view your relayers.",
            });
          return;
        }
        if (!response.ok)
          throw new Error(
            body.error ?? "Relayer readings could not be loaded.",
          );
        if (alive) setData(body);
      } catch (error) {
        if (alive)
          setData((previous) => ({
            ...previous,
            readings: (previous?.readings ?? []).map((r) => ({
              ...r,
              error: "Refresh failed. These are the last received readings.",
            })),
            error:
              error instanceof Error && error.name !== "AbortError"
                ? error.message
                : "The provider took too long to respond. Retrying automatically.",
          }));
      } finally {
        clearTimeout(timeout);
        busy = false;
        if (alive) setLoading(false);
      }
    }
    void load();
    const interval = setInterval(() => {
      if (document.visibilityState !== "hidden") void load();
    }, 30_000);
    const onVisible = () => {
      if (document.visibilityState === "visible") void load();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      alive = false;
      controller?.abort();
      clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [ownerId, nodeId, revision, reload, selected]);
  useEffect(() => {
    const clock = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(clock);
  }, []);

  const readings = data?.readings ?? [];
  const reading =
    selected ? readings.find((r) => r.assignment.relayer_id === selected) : readings[0];
  if (compact) return <RelayerSummary data={data} ownerId={ownerId} nodeId={nodeId} now={now} />;
  return (
    <section className="relayer-view" aria-label="Highway relayer dashboard">
      <div className="relayer-heading">
        <div>
          <div className="relayer-wordmark">
            <Radio size={17} aria-hidden /> Highway network
          </div>
          <h2>{nodeId ? "Server's Highway relayer" : ownerId === "all" ? "All Highway relayers" : "Highway relayers"}</h2>
          <p>Service health, check-ins and on-chain earnings in one place.</p>
        </div>
        <button
          className="relayer-button"
          onClick={refresh}
          disabled={loading}
          aria-label="Refresh relayer readings"
        >
          <RefreshCw
            size={15}
            className={loading ? "relayer-spin" : ""}
            aria-hidden
          />
          {loading ? "Refreshing" : "Refresh"}
        </button>
      </div>
      {data?.error ? (
        <p role="alert" className="relayer-notice">
          {data.error}
        </p>
      ) : null}
      {!data ? (
        <div className="relayer-empty" role="status">
          <Radio size={26} aria-hidden />
          <h3>Connecting to your relayers</h3>
          <p>Reading service status and the finalized registry.</p>
        </div>
      ) : null}
      {data && !readings.length && !data.error ? (
        <div className="relayer-empty">
          <Radio size={26} aria-hidden />
          <h3>{nodeId ? "No relayer linked to this server" : "No relayers linked yet"}</h3>
          <p>{nodeId ? "A Super admin can choose this server's relayer in its server settings." : "Your administrator can link a Highway relayer to your account. Its status and earnings will appear here."}</p>
        </div>
      ) : null}
      {selected && data && readings.length > 0 && !reading ? <p role="status" className="relayer-notice">The selected relayer is no longer available in this view. Choose a relayer below.</p> : null}
      {!nodeId && readings.length ? <div className="my-6">
        <ResourceSwitcher label="Relayers" current={reading ? String(reading.assignment.relayer_id) : undefined} items={readings.map(r => {
          const next = new URLSearchParams(params.toString());
          next.set("relayer",String(r.assignment.relayer_id));
          return {id: String(r.assignment.relayer_id), name: r.relayer?.name ?? r.assignment.relayer_name,
            detail: `#${r.assignment.relayer_id}`, href: `${pathname}?${next}`};
        })} />
      </div> : null}
      {reading ? (
        <RelayerPanel key={reading.assignment.id} reading={reading} now={now} />
      ) : null}
    </section>
  );
}

export function RelayerSummary({
  data,
  ownerId,
  nodeId,
  now,
}: {
  data: RelayerDashboardData | null;
  ownerId?: string;
  nodeId?: string;
  now: number;
}) {
  const readings = (data?.readings ?? []).filter(
    (reading) => !ownerId || reading.assignment.owner === ownerId,
  );

  return (
    <section className="mt-4 max-w-2xl border-t border-border/60 pt-4" aria-label="Assigned Highway relayers">
      <p className="font-mono text-xs text-muted-foreground">{nodeId ? "Admin-linked relayer" : "Admin-assigned relayers"}</p>
      <p className="mt-1 text-xs text-muted-foreground">{nodeId ? "Linked to this server." : "Assigned to this account."}</p>
      {!data ? <p className="mt-3 text-sm text-muted-foreground" role="status">Loading assigned relayers...</p> : null}
      {data?.error ? <p className="mt-3 text-sm text-[#e8a400]" role="alert">{data.error}</p> : null}
      {data && !data.error && !readings.length ? (
        <p className="mt-3 text-sm text-muted-foreground">{nodeId ? "No relayer linked to this server yet. A Super admin can choose one in server settings." : "No relayer assigned to this account yet."}</p>
      ) : null}
      <div className="mt-3 space-y-5">
        {readings.map((reading) => {
          const { assignment, relayer } = reading;
          const status = relayerChecks(reading, now);
          const details = new URLSearchParams(nodeId ? {
            section: "relayers",
            node: nodeId,
            relayScope: "server",
          } : {
            section: "relayers",
            owner: assignment.owner,
            relayer: String(assignment.relayer_id),
          });
          return (
            <article key={assignment.id} className="space-y-3" aria-label={`Relayer ${assignment.relayer_id}`}>
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="min-w-0">
                  <Link href={`/dashboard?${details}`} className="inline-flex max-w-full items-center gap-1.5 rounded-sm text-sm font-medium text-card-foreground hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-primary">
                    <span className="break-words [overflow-wrap:anywhere]">{relayer?.name ?? assignment.relayer_name}</span>
                    <ArrowUpRight className="size-3.5 shrink-0" aria-hidden />
                  </Link>
                  <p className="mt-0.5 font-mono text-xs text-muted-foreground">
                    #{assignment.relayer_id}{relayer?.tier ? ` / ${relayer.tier}` : ""}
                  </p>
                </div>
                <div className="flex flex-wrap items-center gap-2.5">
                  <span role="img" aria-label={`${status.passed} of ${status.checks.length} relay health checks passed`} className="inline-flex items-end gap-1">
                    {status.checks.map((check, index) => (
                      <span key={check.label} aria-hidden title={`${check.label}: ${check.value === true ? "Passed" : check.value === false ? "Needs attention" : "Not verified"}`}
                        className={`w-1.5 rounded-sm ${check.value === true ? "bg-primary" : check.value === false ? "bg-[#e8a400]" : "bg-muted-foreground/30"}`}
                        style={{ height: 8 + index * 4 }} />
                    ))}
                    <span aria-hidden className="ml-1 font-mono text-sm tabular-nums text-card-foreground">{status.passed}/{status.checks.length}</span>
                  </span>
                  <span className={`text-xs ${status.tone === "healthy" ? "text-primary" : status.tone === "warning" ? "text-[#e8a400]" : "text-muted-foreground"}`}>{status.label}</span>
                </div>
              </div>
              <dl className="grid grid-cols-1 gap-3 min-[360px]:grid-cols-2">
                {[
                  { label: "Last heartbeat", at: relayer?.lastHeartbeatAt ?? null },
                  { label: "Last check-in", at: relayer?.lastCheckinAt ?? null },
                ].map(({ label, at }) => {
                  const age = ageSeconds(at, now);
                  return (
                    <div key={label}>
                      <dt className="text-xs text-muted-foreground">{label}</dt>
                      <dd className="mt-1 font-mono text-sm tabular-nums text-card-foreground">
                        <time dateTime={at ?? undefined} title={time(at)}>{age === null ? "Not reported" : `${duration(age)} ago`}</time>
                      </dd>
                    </div>
                  );
                })}
              </dl>
              <ul className="flex flex-wrap gap-x-3 gap-y-1.5 text-xs" aria-label="Relay health checks">
                {status.checks.map((check) => {
                  const Icon = check.value === true ? Check : check.value === false ? X : CircleHelp;
                  return (
                    <li key={check.label} className={`inline-flex items-center gap-1 ${check.value === true ? "text-primary" : check.value === false ? "text-[#e8a400]" : "text-muted-foreground"}`}>
                      <Icon className="size-3" aria-hidden />
                      {check.label}<span className="sr-only">: {check.value === true ? "Passed" : check.value === false ? "Needs attention" : "Not verified"}</span>
                    </li>
                  );
                })}
              </ul>
              {reading.error ? <p className="text-xs leading-5 text-[#e8a400]">{reading.error}</p> : !status.sourceFresh && relayer ? (
                <p className="text-xs leading-5 text-muted-foreground">Last readings are stale. Waiting for a refresh.</p>
              ) : null}
            </article>
          );
        })}
      </div>
    </section>
  );
}

// The dashboard obtains readings from the protected, assignment-scoped API.
export function RelayerPanel({
  reading,
  now,
}: {
  reading: RelayerReading;
  now: number;
}) {
  const { relayer: r, chain: c, assignment } = reading;
  const status = relayerChecks(reading, now);
  const checkinAge = ageSeconds(r?.lastCheckinAt ?? null, now);
  const heartbeatAge = ageSeconds(r?.lastHeartbeatAt ?? null, now);
  return (
    <div className="relayer-panel" data-tone={status.tone}>
      <header className="relayer-identity-header">
        <div className="relayer-name">
          <div className="relayer-symbol" aria-hidden>
            <Radio size={25} />
          </div>
          <div>
            <h3>{r?.name ?? assignment.relayer_name}</h3>
            <div className="relayer-meta">
              <span>Relayer #{assignment.relayer_id}</span>
              {r?.tier ? <span>{r.tier}</span> : null}
              {r?.city ? (
                <span>
                  {r.city}, {r.country}
                </span>
              ) : null}
            </div>
          </div>
        </div>
        <span className="relayer-health-pill">
          <span />
          {status.label}
        </span>
      </header>
      {reading.error ? (
        <p className="relayer-notice" role="status">
          {reading.error}
        </p>
      ) : !status.sourceFresh ? (
        <p className="relayer-notice">
          The provider snapshot is delayed or has no valid timestamp. Live
          service status is unverified.
        </p>
      ) : null}
      {reading.chainError ? (
        <p className="relayer-notice">{reading.chainError}</p>
      ) : null}
      <div className="relayer-main-grid">
        <div className="relayer-health-section">
          <div className="relayer-section-title">
            <ShieldCheck size={17} aria-hidden />
            <h4>Service health</h4>
          </div>
          <div className="relayer-health-overview">
            <svg
              viewBox="0 0 144 144"
              role="img"
              aria-label={`${status.passed} of 5 service checks passing`}
            >
              <circle cx="72" cy="72" r="56" className="relayer-ring-track" />
              {status.checks.map((check, i) => (
                <circle
                  key={check.label}
                  cx="72"
                  cy="72"
                  r="56"
                  fill="none"
                  strokeWidth="9"
                  strokeLinecap="round"
                  strokeDasharray="58.3 293.6"
                  transform={`rotate(${-90 + i * 72} 72 72)`}
                  className={
                    check.value === true
                      ? "relayer-stroke-ok"
                      : check.value === false
                        ? "relayer-stroke-warn"
                        : "relayer-stroke-muted"
                  }
                />
              ))}
              <text x="72" y="73" className="relayer-score" textAnchor="middle">
                {status.passed}
                <tspan className="relayer-score-denominator">/5</tspan>
              </text>
              <text
                x="72"
                y="94"
                className="relayer-score-caption"
                textAnchor="middle"
              >
                checks passing
              </text>
            </svg>
            <div>
              <strong>
                {status.label === "Healthy"
                  ? "All systems ready"
                  : status.label}
              </strong>
              <p>
                {status.label === "Healthy"
                  ? "Registered, authorized and keeping in touch with the network."
                  : "Each check below shows exactly what needs a closer look."}
              </p>
            </div>
          </div>
          <ul className="relayer-checks">
            {status.checks.map((check, i) => (
              <li key={check.label}>
                <span>
                  {check.label}
                  {i === 1 ? (
                    <small>under 300s</small>
                  ) : i === 4 ? (
                    <small>under 660s</small>
                  ) : null}
                </span>
                <span
                  className={
                    check.value === true
                      ? "relayer-ok"
                      : check.value === false
                        ? "relayer-warn"
                        : "relayer-muted"
                  }
                >
                  {check.value === true ? (
                    <Check size={15} aria-hidden />
                  ) : check.value === false ? (
                    <X size={15} aria-hidden />
                  ) : (
                    <CircleHelp size={15} aria-hidden />
                  )}
                  {check.value === true
                    ? "Yes"
                    : check.value === false
                      ? "No"
                      : "Unknown"}
                </span>
              </li>
            ))}
          </ul>
        </div>
        <div className="relayer-liveness-section">
          <div className="relayer-section-title">
            <Activity size={17} aria-hidden />
            <h4>Keeping pace</h4>
            <span>Live freshness</span>
          </div>
          <div className="relayer-gauges">
            <FreshnessGauge
              label="Check-in age"
              age={checkinAge}
              limit={CHECKIN_LIMIT_S}
              verified={status.sourceFresh}
            />
            <FreshnessGauge
              label="Heartbeat age"
              age={heartbeatAge}
              limit={HEARTBEAT_LIMIT_S}
              verified={status.sourceFresh}
            />
          </div>
          <div className="relayer-times">
            <TimeRow label="Last check-in" at={r?.lastCheckinAt} />
            <TimeRow label="Last heartbeat" at={r?.lastHeartbeatAt} />
            <TimeRow label="Last provider check" at={reading.fetchedAt} />
          </div>
          <div className="relayer-latency">
            <span>
              <Activity size={14} aria-hidden /> Provider response latency
            </span>
            <strong>
              {number(reading.providerLatencyMs)}
              <small> ms</small>
            </strong>
          </div>
          <p className="relayer-footnote">
            Portal-to-provider response time. Check-in age is measured in
            seconds, not network ping.
          </p>
        </div>
        <div className="relayer-earnings-section">
          <div className="relayer-section-title">
            <Wallet size={17} aria-hidden />
            <h4>Earnings &amp; weight</h4>
          </div>
          <div className="relayer-rewards">
            <span>Rewards balance</span>
            <strong title={c?.rewardsBalance ?? undefined}>
              {number(c?.rewardsBalance)}
            </strong>
            <small>{c?.tokenSymbol ?? "TMOS"} · Mosaic devnet</small>
          </div>
          <div className="relayer-weight">
            <span>Earning weight</span>
            <strong>{number(c?.earningWeight)}</strong>
            <p>Total delegated to this relayer, across all delegators.</p>
          </div>
          <div className="relayer-rate">
            <span>Earning rate</span>
            <strong>Not published</strong>
          </div>
          <p className="relayer-footnote">
            Weight is a delegation measure. The provider does not publish an
            hourly or daily earning rate.
          </p>
          <div className="relayer-chain-state">
            <span
              className={status.chainFresh ? "relayer-ok" : "relayer-muted"}
            >
              <ShieldCheck size={14} aria-hidden />
              {status.chainFresh
                ? "Finalized chain data"
                : "Chain data unverified"}
            </span>
            <small>
              {c
                ? `Block ${number(c.block)} · epoch ${number(c.epoch)}`
                : "Waiting for the registry"}
            </small>
          </div>
        </div>
      </div>
      <details className="relayer-details">
        <summary>
          <span>Identity, wallets &amp; location</span>
          <span>
            View details <ChevronDown size={16} aria-hidden />
          </span>
        </summary>
        <div className="relayer-details-grid">
          <div>
            <h4>Relayer identity</h4>
            <Detail
              label="Chain relayer ID"
              value={String(assignment.relayer_id)}
            />
            <Detail label="Registration" value={r?.registration} />
            <Detail label="User package" value={r?.packageId} copy />
            <Detail label="Device ID" value={r?.deviceId} copy />
            <Detail label="Relayer count" value={r?.relayerCount?.toString()} />
            <Detail
              label="Config version"
              value={r?.configVersion?.toString()}
            />
            <Detail
              label="Country / city"
              value={r ? [r.country, r.city].filter(Boolean).join(" / ") : null}
            />
            <Detail
              label="Coordinates"
              value={
                r?.latitude != null && r.longitude != null
                  ? `${r.latitude.toFixed(4)}, ${r.longitude.toFixed(4)}`
                  : null
              }
            />
          </div>
          <div>
            <h4>Public wallets &amp; keys</h4>
            <Detail label="Rewards wallet" value={c?.rewardsWallet} copy />
            <Detail label="Manager wallet" value={c?.managerWallet} copy />
            <Detail
              label="Manager balance"
              value={
                c?.managerExists === false
                  ? "No account on chain — normal"
                  : c?.managerBalance != null
                    ? `${number(c.managerBalance)} ${c.tokenSymbol}`
                    : null
              }
            />
            {c?.managerExists === false ? (
              <p className="relayer-footnote">
                The manager entry is informational. Heartbeats and active-set
                membership do not require a funded manager account.
              </p>
            ) : null}
            {c?.operationalKeys.map((k) => (
              <Detail
                key={k.key}
                label={`${k.chain} public key${k.balance !== null ? ` · ${number(k.balance)} ${c.tokenSymbol}` : ""}`}
                value={k.key}
                copy
              />
            ))}
            <Detail label="BLS public key" value={c?.blsKey} copy />
            <Detail label="p2p public key" value={c?.p2pKey} copy />
          </div>
        </div>
        <p className="relayer-lan-note">
          Host uptime, jobs and hostname require access to the relayer’s local
          network. Machine telemetry from your linked HYN agent appears
          separately on this dashboard.
        </p>
      </details>
      <footer className="relayer-footer">
        <span>
          <Clock3 size={13} aria-hidden />
          Snapshot{" "}
          {reading.sourceAt
            ? `${duration(ageSeconds(reading.sourceAt, now))} ago`
            : "time unavailable"}{" "}
          · refreshes every 30s
        </span>
        <a
          href="https://highwayp2p.com/shop-v3/#/engine/network/relayers"
          target="_blank"
          rel="noreferrer"
        >
          Highway portal <ArrowUpRight size={14} aria-hidden />
        </a>
      </footer>
    </div>
  );
}
function FreshnessGauge({
  label,
  age,
  limit,
  verified,
}: {
  label: string;
  age: number | null;
  limit: number;
  verified: boolean;
}) {
  const pct = age === null ? 0 : Math.min(1, age / limit);
  const tone =
    !verified || age === null
      ? "relayer-stroke-muted"
      : pct >= 1
        ? "relayer-stroke-warn"
        : "relayer-stroke-ok";
  return (
    <div className="relayer-gauge">
      <svg
        viewBox="0 0 156 130"
        role="img"
        aria-label={`${label}: ${duration(age)}, threshold ${limit} seconds${verified ? "" : ", unverified"}`}
      >
        <circle
          cx="78"
          cy="72"
          r="55"
          fill="none"
          strokeWidth="7"
          strokeDasharray="259.2 86.4"
          transform="rotate(135 78 72)"
          className="relayer-stroke-track"
        />
        <circle
          cx="78"
          cy="72"
          r="55"
          fill="none"
          strokeWidth="7"
          strokeLinecap="round"
          strokeDasharray={`${259.2 * pct} 345.6`}
          transform="rotate(135 78 72)"
          className={tone}
        />
        <text x="78" y="76" textAnchor="middle" className="relayer-gauge-value">
          {duration(age)}
        </text>
        <text
          x="78"
          y="96"
          textAnchor="middle"
          className="relayer-score-caption"
        >
          {!verified
            ? "unverified"
            : age === null
              ? "not reported"
              : age >= limit
                ? "overdue"
                : "within limit"}
        </text>
        <text x="28" y="127" className="relayer-gauge-tick">
          0s
        </text>
        <text x="128" y="127" textAnchor="end" className="relayer-gauge-tick">
          {limit}s
        </text>
      </svg>
      <strong>{label}</strong>
    </div>
  );
}
function TimeRow({ label, at }: { label: string; at?: string | null }) {
  return (
    <div>
      <span>{label}</span>
      <time dateTime={at ?? undefined}>{time(at)}</time>
    </div>
  );
}
function Detail({
  label,
  value,
  copy = false,
}: {
  label: string;
  value?: string | null;
  copy?: boolean;
}) {
  const [message, setMessage] = useState("");
  return (
    <div className="relayer-detail-row">
      <span>{label}</span>
      <div>
        <span title={value ?? undefined}>{value || "—"}</span>
        {copy && value ? (
          <button
            aria-label={`Copy ${label}`}
            title={`Copy ${label}`}
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(value);
                setMessage("Copied");
              } catch {
                setMessage("Could not copy");
              }
            }}
          >
            {message === "Copied" ? (
              <Check size={13} aria-hidden />
            ) : (
              <Copy size={13} aria-hidden />
            )}
          </button>
        ) : null}
      </div>
      {message ? <small role="status">{message}</small> : null}
    </div>
  );
}
