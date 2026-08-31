import { bytesPerSecToMbit, formatBytes, formatDuration } from "@/lib/dashboard-data";
import { readHighway, unitTone, type HighwayState, type UnitTone } from "@/lib/highway";
import type { Metric } from "@/lib/types";

// The Highway node section of the dashboard: the same thing `hyn` view 4 draws in
// the terminal, for someone who is not at the terminal. It sits above the
// processor section because on a relay box "are my services up" outranks "how
// busy is the CPU" — a node with a failed unit earns nothing while running cool.
//
// Everything is read out of the last pushed payload. Nothing is polled from the
// server and nothing here can change its state; the agent is read-only by
// design (see lib/highway.sh) and this panel has no write path to it at all.

const TONE: Record<UnitTone, { dot: string; text: string }> = {
  ok: { dot: "bg-primary", text: "text-primary" },
  warn: { dot: "bg-[#e8a400]", text: "text-[#e8a400]" },
  crit: { dot: "bg-destructive", text: "text-destructive" },
  idle: { dot: "bg-muted-foreground", text: "text-muted-foreground" },
};

function HealthPill({ hw }: { hw: HighwayState }) {
  const tone: UnitTone =
    hw.health === "ok" ? "ok" : hw.health === "crit" ? "crit" : hw.health === "absent" ? "idle" : "warn";
  const t = TONE[tone];
  return (
    <span
      className={`flex w-fit items-center gap-2 rounded-full border px-3.5 py-2 font-mono text-xs uppercase ${t.text} ${
        tone === "ok"
          ? "border-primary/40 bg-primary/10"
          : tone === "crit"
            ? "border-destructive/50 bg-destructive/10"
            : "border-current/40 bg-current/5"
      }`}
    >
      <span aria-hidden className={`size-1.5 rounded-full ${t.dot}`} />
      {hw.health === "unknown" ? "state unknown" : hw.health}
    </span>
  );
}

function Figure({
  label,
  value,
  hint,
  tone,
}: {
  label: string;
  value: string;
  hint?: string;
  tone?: UnitTone;
}) {
  return (
    <div className="border-b border-border/60 pb-2">
      <dt className="font-mono text-[0.6rem] uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd
        className={`mt-1 truncate font-mono text-sm ${tone ? TONE[tone].text : "text-card-foreground"}`}
        title={hint ? `${value} · ${hint}` : value}
      >
        {value}
        {hint ? <span className="ml-2 text-[0.65rem] text-muted-foreground">{hint}</span> : null}
      </dd>
    </div>
  );
}

function Frame({ children, note }: { children: React.ReactNode; note?: React.ReactNode }) {
  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 rounded-xl p-6 duration-500">
      {children}
      <p className="mt-6 border-t border-border/60 pt-4 font-mono text-[0.65rem] leading-6 text-muted-foreground">
        Read-only observation of{" "}
        <a
          href="https://highwayp2p.com"
          target="_blank"
          rel="noopener noreferrer nofollow"
          className="text-primary underline underline-offset-2"
        >
          highwayp2p.com
        </a>{" "}
        node software. hyn-view is an independent monitor, not affiliated with or endorsed by
        Highway P2P — it never starts, stops or reconfigures anything it reports on.
        {note ? <> {note}</> : null}
      </p>
    </div>
  );
}

export function HighwayPanel({ latest }: { latest: Metric }) {
  const hw = readHighway(latest.payload);

  // No highway key at all: the agent on that box is older than this dashboard.
  // Said as a fact about the agent, because claiming the node has no services
  // would be a claim about the server that we have no evidence for.
  if (!hw) {
    return (
      <Frame>
        <p className="section-kicker">// highway node</p>
        <p className="mt-2 font-sentient text-2xl text-card-foreground">No Highway telemetry in this push</p>
        <p className="mt-3 max-w-xl font-mono text-sm leading-7 text-muted-foreground">
          This node&apos;s agent did not send a Highway section. Upgrade it on the server and the
          services below fill in on the next push:
        </p>
        <pre className="mt-4 overflow-x-auto border border-border bg-foreground/[0.04] p-3 font-mono text-xs text-primary">
          sudo npm i -g hyn-view{"\n"}hyn push
        </pre>
      </Frame>
    );
  }

  if (!hw.tracked) {
    return (
      <Frame>
        <p className="section-kicker">// highway node</p>
        <p className="mt-2 font-sentient text-2xl text-card-foreground">Node tracking is switched off</p>
        <p className="mt-3 max-w-xl font-mono text-sm leading-7 text-muted-foreground">
          The agent is running with <code>highway_track=off</code>, so it collects nothing about the
          node. Re-enable it with <code>hyn config set highway_track on</code>.
        </p>
      </Frame>
    );
  }

  if (!hw.present) {
    return (
      <Frame>
        <p className="section-kicker">// highway node</p>
        <p className="mt-2 font-sentient text-2xl text-card-foreground">No Highway node on this machine</p>
        <p className="mt-3 max-w-xl font-mono text-sm leading-7 text-muted-foreground">
          Nothing at <code>{hw.binPath ?? "/usr/local/bin/highway"}</code>. This is a normal reading
          for a server that is not running a relay.
          {hw.latest ? ` The current published release is ${hw.latest}.` : ""}
        </p>
      </Frame>
    );
  }

  const version =
    hw.version === null
      ? "version could not be read"
      : `${hw.version}${hw.versionSrc ? ` (from ${hw.versionSrc})` : ""}`;

  const failed = hw.unitsFailed ?? 0;
  const active = hw.unitsActive ?? 0;

  // A pre-1.5 agent sent six summary fields and nothing else. Rendering the full
  // panel from that would print "process not running" and "no mesh tunnel" —
  // absence claims we have no evidence for. Show what it did send, and say why
  // the rest is missing.
  if (hw.legacyAgent) {
    return (
      <Frame>
        <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
          <div>
            <p className="section-kicker">// highway node</p>
            <p className="mt-2 font-sentient text-2xl text-card-foreground">
              {active} unit{active === 1 ? "" : "s"} active
              {failed > 0 ? `, ${failed} failed` : ""}
            </p>
            <p className="mt-2 font-mono text-xs leading-6 text-muted-foreground">
              {hw.healthWhy ?? "summary only"}
              {hw.journalErr !== null ? ` · ${hw.journalErr} journal error(s) in the last hour` : ""}
            </p>
          </div>
          <div className="flex flex-col items-start gap-2 md:items-end">
            <HealthPill hw={hw} />
            <p className="font-mono text-xs text-muted-foreground">{version}</p>
          </div>
        </div>
        <p className="mt-6 border border-[#e8a400]/40 bg-[#e8a400]/5 p-3 font-mono text-xs leading-6 text-[#e8a400]">
          This agent sends a summary only — per-service state, restart counts, the mesh tunnel and the
          journal are not in its payload. Upgrade the agent on the server for the full section:
          <code className="ml-2">sudo npm i -g hyn-view</code>
        </p>
      </Frame>
    );
  }

  return (
    <Frame>
      <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div>
          <p className="section-kicker">// highway node</p>
          <p className="mt-2 font-sentient text-2xl text-card-foreground">
            {active > 0 ? `${active} service${active === 1 ? "" : "s"} running` : "Services are not running"}
          </p>
          <p className="mt-2 font-mono text-xs leading-6 text-muted-foreground">
            {hw.healthWhy ?? `${hw.unitsTotal ?? 0} unit(s) tracked`}
            {failed > 0 ? ` · ${failed} failed` : ""}
          </p>
        </div>
        <div className="flex flex-col items-start gap-2 md:items-end">
          <HealthPill hw={hw} />
          <p className="font-mono text-xs text-muted-foreground">{version}</p>
          {hw.updateAvailable && hw.latest ? (
            <p className="font-mono text-xs text-[#e8a400]">update available: {hw.latest}</p>
          ) : hw.latest ? (
            <p className="font-mono text-xs text-muted-foreground">latest release {hw.latest}</p>
          ) : null}
        </div>
      </div>

      {hw.units.length > 0 ? (
        <div className="mt-6 overflow-x-auto">
          <table className="w-full min-w-[34rem] border-collapse text-left">
            <caption className="sr-only">
              Highway systemd units with their state, restart count, memory and time active
            </caption>
            <thead>
              <tr className="border-b border-border">
                {["Service", "State", "Restarts", "Memory", "Active for"].map((h) => (
                  <th
                    key={h}
                    scope="col"
                    className="pb-2 font-mono text-[0.6rem] font-normal uppercase tracking-wide text-muted-foreground"
                  >
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {hw.units.map((u) => {
                const tone = unitTone(u);
                const looping = u.restarts !== null && u.restarts >= 3;
                return (
                  <tr key={u.name} className="border-b border-border/40">
                    <td className="py-2.5 pr-4 font-mono text-sm text-card-foreground">
                      <span className="flex items-center gap-2">
                        <span aria-hidden className={`size-1.5 shrink-0 rounded-full ${TONE[tone].dot}`} />
                        <span className="truncate" title={u.name}>
                          {u.name}
                        </span>
                      </span>
                    </td>
                    <td className={`py-2.5 pr-4 font-mono text-sm ${TONE[tone].text}`}>
                      {u.state ?? "—"}
                      {u.sub && u.sub !== u.state ? (
                        <span className="text-muted-foreground">/{u.sub}</span>
                      ) : null}
                    </td>
                    <td
                      className={`py-2.5 pr-4 font-mono text-sm ${
                        looping ? "text-[#e8a400]" : "text-muted-foreground"
                      }`}
                      title={looping ? "restarting repeatedly — likely crash-looping" : undefined}
                    >
                      {u.restarts === null ? "—" : `${u.restarts}×`}
                    </td>
                    <td className="py-2.5 pr-4 font-mono text-sm text-muted-foreground">
                      {u.memory === null ? "—" : formatBytes(u.memory)}
                    </td>
                    <td className="py-2.5 font-mono text-sm text-muted-foreground">
                      {u.activeFor === null ? "—" : formatDuration(u.activeFor)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      ) : (
        <p className="mt-6 border border-[#e8a400]/40 bg-[#e8a400]/5 p-3 font-mono text-xs leading-6 text-[#e8a400]">
          The binary is installed but no matching systemd unit was found
          {hw.pid ? `, though a process is running as pid ${hw.pid}` : ""}. Unit name patterns come
          from <code>highway_units</code> in the agent config.
        </p>
      )}

      <dl className="mt-6 grid grid-cols-2 gap-x-6 gap-y-3 sm:grid-cols-3 lg:grid-cols-4">
        <Figure
          label="Process"
          value={hw.pid === null ? "not running" : `pid ${hw.pid}`}
          hint={hw.procUptime ? `up ${formatDuration(hw.procUptime)}` : undefined}
          tone={hw.pid === null ? "warn" : undefined}
        />
        <Figure
          label="Node CPU"
          value={hw.cpuPct === null ? "—" : `${hw.cpuPct.toFixed(1)}%`}
          hint="of one core"
        />
        <Figure label="Node memory" value={formatBytes(hw.rss)} hint={hw.threads ? `${hw.threads} threads` : undefined} />
        <Figure label="Open files" value={hw.fds === null ? "—" : String(hw.fds)} hint={hw.fds === null ? "not readable" : undefined} />
        <Figure
          label="Mesh tunnel"
          value={hw.meshIface ?? "not detected"}
          tone={hw.meshIface ? undefined : "warn"}
          hint={hw.meshDrops ? `${hw.meshDrops} drops/s` : undefined}
        />
        <Figure
          label="Mesh traffic"
          value={
            hw.meshRxBps === null && hw.meshTxBps === null
              ? "—"
              : `↓ ${bytesPerSecToMbit(hw.meshRxBps)} / ↑ ${bytesPerSecToMbit(hw.meshTxBps)} Mbit/s`
          }
          hint={
            hw.meshRxTotal !== null
              ? `${formatBytes(hw.meshRxTotal)} in / ${formatBytes(hw.meshTxTotal)} out`
              : undefined
          }
        />
        <Figure
          label="WAN qdisc"
          value={hw.qdisc ?? "—"}
          hint={
            [
              hw.qdiscDrops !== null ? `${hw.qdiscDrops} dropped` : null,
              hw.congestion ? `cc ${hw.congestion}` : null,
            ]
              .filter(Boolean)
              .join(" · ") || undefined
          }
        />
        <Figure
          label="Journal, last hour"
          value={
            hw.journalErr === null && hw.journalWarn === null
              ? "—"
              : `${hw.journalErr ?? 0} err · ${hw.journalWarn ?? 0} warn`
          }
          tone={hw.journalErr ? "crit" : hw.journalWarn ? "warn" : "ok"}
          hint={hw.nftTables !== null ? `${hw.nftTables} nft tables` : undefined}
        />
      </dl>

      {hw.journalTail.length > 0 ? (
        <div className="mt-6">
          <p className="font-mono text-[0.6rem] uppercase tracking-wide text-muted-foreground">
            Latest journal lines at warning or worse
          </p>
          <ul className="mt-2 space-y-1">
            {hw.journalTail.map((line, i) => (
              <li
                key={`${i}-${line.slice(0, 24)}`}
                className="truncate border-l-2 border-border pl-3 font-mono text-xs leading-6 text-muted-foreground"
                title={line}
              >
                {line}
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      {hw.binSize !== null ? (
        <p className="mt-4 font-mono text-[0.65rem] text-muted-foreground">
          Binary {hw.binPath ?? "/usr/local/bin/highway"} · {formatBytes(hw.binSize)}
          {hw.binMtime ? ` · installed ${new Date(hw.binMtime * 1000).toLocaleDateString()}` : ""}
        </p>
      ) : null}
    </Frame>
  );
}
