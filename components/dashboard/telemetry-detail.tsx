import { bytesPerSecToMbit, formatBytes } from "@/lib/dashboard-data";
import {
  headroomLabel,
  readCpuClocks,
  readFilesystems,
  readLatencyHops,
  readNetworkDetail,
  readPower,
  readPressure,
  readProcesses,
  powerSourceLabel,
} from "@/lib/telemetry";
import type { Metric } from "@/lib/types";

// The detail an operator who is not at the terminal cannot otherwise get: every
// filesystem, what was actually using the box, the link's error and drop
// counters, the socket state distribution, kernel pressure, and per-core clocks.
//
// All of it is read out of the last pushed payload, which the agent has always
// sent. A missing value renders as "—" and a missing section says why it is
// missing, because a zero drawn in place of an unread sensor is a lie about a
// healthy machine.

const MUTED = "font-mono text-[0.6rem] uppercase tracking-wide text-muted-foreground";

function Panel({
  kicker,
  title,
  children,
}: {
  kicker: string;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 p-6 duration-500">
      <p className="section-kicker">{`// ${kicker}`}</p>
      <p className="mt-2 font-sentient text-2xl text-card-foreground">{title}</p>
      <div className="mt-6">{children}</div>
    </div>
  );
}

function Note({ children }: { children: React.ReactNode }) {
  return <p className="font-mono text-xs leading-6 text-muted-foreground">{children}</p>;
}

function Figure({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="border-b border-border/60 pb-2">
      <dt className={MUTED}>{label}</dt>
      <dd className="mt-1 truncate font-mono text-sm text-card-foreground" title={value}>
        {value}
        {hint ? <span className="ml-2 text-[0.65rem] text-muted-foreground">{hint}</span> : null}
      </dd>
    </div>
  );
}

function n(v: number | null, unit = "", digits = 0): string {
  if (v === null) return "—";
  return `${v.toFixed(digits)}${unit}`;
}

// One bar, coloured by how close the value is to being a problem. The thresholds
// match the agent's own defaults (alert_disk_pct 85 / crit 93) so a bar that
// looks alarming here is one that would have emailed you.
function Bar({ pct, warn = 85, crit = 93 }: { pct: number | null; warn?: number; crit?: number }) {
  if (pct === null) return <span className="font-mono text-xs text-muted-foreground">—</span>;
  const clamped = Math.max(0, Math.min(100, pct));
  const tone = clamped >= crit ? "bg-destructive" : clamped >= warn ? "bg-[#e8a400]" : "bg-primary";
  return (
    <span className="flex items-center gap-2">
      <span
        className="h-1.5 w-24 shrink-0 overflow-hidden rounded-full bg-muted/30"
        role="img"
        aria-label={`${clamped.toFixed(0)} percent`}
      >
        <span className={`block h-full rounded-full ${tone}`} style={{ width: `${clamped}%` }} />
      </span>
      <span className="font-mono text-xs text-card-foreground">{clamped.toFixed(0)}%</span>
    </span>
  );
}

export function FilesystemsPanel({ latest }: { latest: Metric }) {
  const rows = readFilesystems(latest.payload);
  return (
    <Panel kicker="storage" title="Every filesystem">
      {rows.length === 0 ? (
        <Note>
          This reading carries no per-filesystem detail. Snap mounts are excluded on purpose —
          they are read-only squashfs and therefore permanently 100% full.
        </Note>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-left">
            <thead>
              <tr className={MUTED}>
                <th className="pb-2 pr-4 font-normal">Mount</th>
                <th className="pb-2 pr-4 font-normal">Type</th>
                <th className="pb-2 pr-4 font-normal">Used</th>
                <th className="pb-2 pr-4 font-normal">Size</th>
                <th className="pb-2 font-normal">Usage</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((fs) => (
                <tr key={fs.mount} className="border-t border-border/60">
                  <td className="py-2 pr-4 font-mono text-sm text-card-foreground">{fs.mount}</td>
                  <td className="py-2 pr-4 font-mono text-xs text-muted-foreground">
                    {fs.fstype ?? "—"}
                  </td>
                  <td className="py-2 pr-4 font-mono text-xs text-card-foreground">
                    {formatBytes(fs.used)}
                  </td>
                  <td className="py-2 pr-4 font-mono text-xs text-card-foreground">
                    {formatBytes(fs.size)}
                    {headroomLabel(fs) ? (
                      <span className="ml-2 text-[0.65rem] text-muted-foreground">
                        {headroomLabel(fs)}
                      </span>
                    ) : null}
                  </td>
                  <td className="py-2">
                    <Bar pct={fs.pct} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Panel>
  );
}

export function ProcessesPanel({ latest }: { latest: Metric }) {
  const procs = readProcesses(latest.payload);
  return (
    <Panel kicker="processes" title="What is using the machine">
      {!procs ? (
        <Note>This reading carries no process detail.</Note>
      ) : (
        <>
          <dl className="grid grid-cols-2 gap-x-8 gap-y-3 sm:grid-cols-3">
            <Figure label="Processes" value={n(procs.count)} />
            <Figure label="Runnable" value={n(procs.running)} />
            <Figure label="Blocked on I/O" value={n(procs.blocked)} />
          </dl>
          {procs.top.length === 0 ? (
            <Note>No per-process rows in this reading.</Note>
          ) : (
            <div className="mt-6 overflow-x-auto">
              <table className="w-full border-collapse text-left">
                <thead>
                  <tr className={MUTED}>
                    <th className="pb-2 pr-4 font-normal">PID</th>
                    <th className="pb-2 pr-4 font-normal">Command</th>
                    <th className="pb-2 pr-4 font-normal">CPU</th>
                    <th className="pb-2 pr-4 font-normal">Memory</th>
                    <th className="pb-2 font-normal">Threads</th>
                  </tr>
                </thead>
                <tbody>
                  {procs.top.map((p) => (
                    <tr key={`${p.pid}-${p.name}`} className="border-t border-border/60">
                      <td className="py-2 pr-4 font-mono text-xs text-muted-foreground">
                        {n(p.pid)}
                      </td>
                      <td className="py-2 pr-4 font-mono text-sm text-card-foreground">{p.name}</td>
                      <td className="py-2 pr-4 font-mono text-xs text-card-foreground">
                        {n(p.cpuPct, "%", 1)}
                      </td>
                      <td className="py-2 pr-4 font-mono text-xs text-card-foreground">
                        {formatBytes(p.rss)}
                      </td>
                      <td className="py-2 font-mono text-xs text-muted-foreground">
                        {n(p.threads)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {/* The agent deliberately omits the process owner from what it sends;
              a username is identity-bearing and health monitoring does not need
              it. Said here so its absence reads as a decision, not a gap. */}
          <Note>
            <span className="mt-4 block">
              Process owners are not sent to the portal. Run <code>hyn proc</code> on the machine
              if you need them.
            </span>
          </Note>
        </>
      )}
    </Panel>
  );
}

export function NetworkDetailPanel({ latest }: { latest: Metric }) {
  const net = readNetworkDetail(latest.payload);
  const hops = readLatencyHops(latest.payload);
  if (!net) {
    return (
      <Panel kicker="link" title="The connection">
        <Note>This reading carries no network detail.</Note>
      </Panel>
    );
  }
  const identity = net.ssid ?? net.connection ?? net.iface ?? "—";
  return (
    <Panel kicker="link" title="The connection">
      <dl className="grid grid-cols-2 gap-x-8 gap-y-3 sm:grid-cols-3 lg:grid-cols-4">
        <Figure label="Connection" value={identity} hint={net.iface ?? undefined} />
        <Figure label="State" value={net.state ?? "—"} />
        <Figure
          label="Negotiated link"
          value={net.linkMbps === null ? "—" : `${net.linkMbps} Mb/s`}
          hint={net.duplex ?? undefined}
        />
        <Figure label="Driver" value={net.driver ?? "—"} hint={net.mtu ? `MTU ${net.mtu}` : undefined} />
        <Figure label="Local address" value={net.localIp ?? "—"} />
        <Figure label="Gateway" value={net.gateway ?? "—"} />
        <Figure label="DNS" value={net.dns ?? "—"} />
        <Figure
          label="Throughput"
          value={`${bytesPerSecToMbit(net.rxBps).toFixed(1)} / ${bytesPerSecToMbit(net.txBps).toFixed(1)} Mbps`}
          hint="down / up"
        />
        <Figure label="Transferred" value={`${formatBytes(net.rxTotal)} / ${formatBytes(net.txTotal)}`} hint="rx / tx" />
        <Figure label="Interface errors" value={`${n(net.rxErr)} / ${n(net.txErr)}`} hint="rx / tx" />
        <Figure label="Interface drops" value={`${n(net.rxDrop)} / ${n(net.txDrop)}`} hint="rx / tx" />
        <Figure
          label="TCP retransmits"
          value={net.retransPermille === null ? "—" : `${(net.retransPermille / 10).toFixed(2)}%`}
          hint="of segments sent"
        />
        <Figure label="Established sockets" value={n(net.tcpEstab)} />
        <Figure label="TIME_WAIT sockets" value={n(net.tcpTimeWait)} />
        <Figure label="Listen queue drops" value={n(net.listenDrops)} />
        <Figure label="Conntrack in use" value={n(net.conntrackPct, "%")} hint="of the table" />
      </dl>

      {/* First hop separately from the internet, because that is what says
          whether a latency problem is yours or your provider's. */}
      <div className="mt-6 border-t border-border/60 pt-4">
        <p className={MUTED}>Latency</p>
        {hops.length === 0 ? (
          <Note>No probe completed in this reading. ICMP is filtered on some networks.</Note>
        ) : (
          <ul className="mt-2 flex flex-wrap gap-x-8 gap-y-2">
            {hops.map((hop) => (
              <li key={hop.target} className="font-mono text-sm text-card-foreground">
                <span className="text-muted-foreground">
                  {hop.firstHop ? "first hop" : hop.target}
                </span>{" "}
                {hop.ms.toFixed(2)} ms
              </li>
            ))}
          </ul>
        )}
      </div>
    </Panel>
  );
}

export function PowerPanel({ latest }: { latest: Metric }) {
  const power = readPower(latest.payload);
  // Losing mains is an incident, not a measurement, so it is the one thing here
  // that gets colour and the top of the panel.
  const onBattery = power?.acOnline === 0;
  return (
    <Panel kicker="power" title="Power draw">
      {!power ? (
        <Note>
          This machine exposes no power measurement — no RAPL energy counters, no hwmon power rail
          and no battery. That is normal on a virtual machine, and it is shown as absent rather than
          as 0 W.
        </Note>
      ) : (
        <>
          {onBattery ? (
            <p className="mb-4 border border-destructive/50 bg-destructive/10 px-3 py-2 font-mono text-xs text-destructive">
              Running on battery
              {power.batteryPct === null ? "" : ` · ${power.batteryPct}% charge`}
              {power.batteryStatus ? ` · ${power.batteryStatus.toLowerCase()}` : ""}
            </p>
          ) : null}
          <dl className="grid grid-cols-2 gap-x-8 gap-y-3 sm:grid-cols-4">
            <Figure
              label="Input"
              value={n(power.inputW, " W", 1)}
              hint={powerSourceLabel(power.inputSrc) ?? undefined}
            />
            <Figure label="CPU package" value={n(power.cpuW, " W", 1)} />
            <Figure label="DRAM" value={n(power.dramW, " W", 1)} />
            <Figure
              label="Mains"
              value={power.acOnline === null ? "—" : power.acOnline === 1 ? "present" : "absent"}
              hint={power.batteryPct === null ? undefined : `battery ${power.batteryPct}%`}
            />
          </dl>
          {power.rails.length === 0 ? null : (
            <div className="mt-6 border-t border-border/60 pt-4">
              <p className={MUTED}>Every rail this platform exposes</p>
              <ul className="mt-2 grid grid-cols-1 gap-x-8 gap-y-1 sm:grid-cols-2">
                {power.rails.map((rail) => (
                  <li
                    key={rail.label}
                    className="flex items-baseline justify-between gap-4 border-b border-border/40 py-1 font-mono text-xs"
                  >
                    <span className="truncate text-muted-foreground" title={rail.label}>
                      {rail.label}
                    </span>
                    <span className="shrink-0 text-card-foreground">{rail.watts.toFixed(1)} W</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </>
      )}
    </Panel>
  );
}

export function PressurePanel({ latest }: { latest: Metric }) {
  const psi = readPressure(latest.payload);
  const clocks = readCpuClocks(latest.payload);
  return (
    <Panel kicker="contention" title="Pressure and clocks">
      {/* PSI sits next to the clocks rather than next to load average on
          purpose: load counts runnable tasks, PSI measures time actually lost
          to contention, and a busy machine that is losing no time is fine. */}
      {!psi ? (
        <Note>
          This kernel reports no pressure information (built without <code>CONFIG_PSI</code>), so
          nothing is shown rather than three zeroed bars.
        </Note>
      ) : (
        <dl className="grid grid-cols-1 gap-x-8 gap-y-3 sm:grid-cols-3">
          <div className="border-b border-border/60 pb-2">
            <dt className={MUTED}>CPU stalled</dt>
            <dd className="mt-1">
              <Bar pct={psi.cpu} warn={20} crit={50} />
            </dd>
          </div>
          <div className="border-b border-border/60 pb-2">
            <dt className={MUTED}>Memory stalled</dt>
            <dd className="mt-1">
              <Bar pct={psi.memory} warn={10} crit={30} />
            </dd>
          </div>
          <div className="border-b border-border/60 pb-2">
            <dt className={MUTED}>I/O stalled</dt>
            <dd className="mt-1">
              <Bar pct={psi.io} warn={20} crit={50} />
            </dd>
          </div>
        </dl>
      )}

      <div className="mt-6 border-t border-border/60 pt-4">
        <p className={MUTED}>Processor clocks</p>
        {!clocks ? (
          <Note>This platform exposes no per-core frequency.</Note>
        ) : (
          <>
            <dl className="mt-2 grid grid-cols-2 gap-x-8 gap-y-3 sm:grid-cols-4">
              <Figure label="Governor" value={clocks.governor ?? "—"} />
              <Figure label="Average" value={clocks.avgMhz === null ? "—" : `${clocks.avgMhz} MHz`} />
              <Figure label="Hardware floor" value={clocks.minMhz === null ? "—" : `${clocks.minMhz} MHz`} />
              <Figure label="Hardware ceiling" value={clocks.maxMhz === null ? "—" : `${clocks.maxMhz} MHz`} />
            </dl>
            {clocks.cores.length === 0 ? null : (
              <ul className="mt-4 flex flex-wrap gap-2">
                {clocks.cores.map((mhz, i) => (
                  <li
                    key={`${i}-${mhz}`}
                    className="border border-border/60 px-2 py-1 font-mono text-[0.65rem] text-card-foreground"
                  >
                    <span className="text-muted-foreground">c{i}</span> {mhz}
                  </li>
                ))}
              </ul>
            )}
          </>
        )}
      </div>
    </Panel>
  );
}
