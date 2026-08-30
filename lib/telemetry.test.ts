import assert from "node:assert/strict";
import test from "node:test";
import {
  headroomLabel,
  readCpuClocks,
  readFilesystems,
  readLatencyHops,
  readNetworkDetail,
  readPressure,
  readProcesses,
} from "./telemetry.ts";

// One payload in the shape cloud_payload_v actually emits, including the awkward
// parts: numerics arriving as strings, unreadable sensors arriving as null, and
// the agent's integer-only "tenths of a percent" CPU encoding.
const payload = {
  disk: {
    pct: 58.4,
    mounts: [
      { mount: "/", pct: "58.4", used: 100, size: 200, avail: 100, fstype: "ext4" },
      { mount: "/data", pct: 91, used: 910, size: 1000, avail: 90, fstype: "xfs" },
      { pct: 3, size: 10 },
    ],
  },
  processes: {
    count: 42,
    running: 2,
    blocked: 0,
    top: [
      { pid: 4242, name: "queue-worker", cpu_tenths: 1234, rss: 8388608, threads: 4 },
      { pid: 7, name: "kworker", cpu_tenths: 0, rss: 0, threads: 1 },
      { pid: 9, cpu_tenths: 10 },
    ],
  },
  network: {
    iface: "eth0", state: "up", local_ip: "10.0.0.5", gateway: "10.0.0.1",
    dns: "1.1.1.1", ssid: "", connection: "Wired connection 1",
    link_mbps: 1000, duplex: "full", mtu: 1500, driver: "e1000e",
    rx_bps: 81250000, tx_bps: 22500000, rx_total: 999, tx_total: 888,
    rx_err: 0, tx_err: 2, rx_drop: 0, tx_drop: 0,
    retrans_permille: "3.1", conntrack_pct: 4,
    tcp_estab: 61, tcp_timewait: 12, listen_drops: 0,
  },
  psi: { cpu: 4, memory: null, io: "11" },
  cpu: { governor: "performance", mhz_avg: 3400, mhz_min: 1500, mhz_max: 3700, cores_mhz: [3400, 3390, 0, 3401] },
  latency_us: { "1.1.1.1": 8620, "8.8.8.8": 0, gateway: 1200 },
};

test("every filesystem the agent sent is readable, and a nameless row is dropped", () => {
  const rows = readFilesystems(payload);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0], {
    mount: "/", fstype: "ext4", pct: 58.4, used: 100, size: 200, avail: 100,
  });
  assert.equal(rows[1].mount, "/data");
  assert.equal(headroomLabel(rows[1]), "9% free");
  // Nothing to divide by must not become "Infinity% free".
  assert.equal(headroomLabel({ ...rows[1], size: 0 }), null);
  assert.equal(headroomLabel({ ...rows[1], avail: null }), null);
});

test("a payload without the key yields nothing rather than an invented row", () => {
  assert.deepEqual(readFilesystems({}), []);
  assert.deepEqual(readFilesystems(null), []);
  assert.equal(readProcesses({}), null);
  assert.equal(readNetworkDetail({}), null);
  assert.equal(readPressure({}), null);
  assert.equal(readCpuClocks({}), null);
  assert.deepEqual(readLatencyHops({}), []);
});

test("process CPU is converted out of the agent's integer tenths", () => {
  const procs = readProcesses(payload);
  assert.ok(procs);
  assert.deepEqual(procs.top[0], {
    pid: 4242, name: "queue-worker", cpuPct: 123.4, rss: 8388608, threads: 4,
  });
  // An idle process is a real reading of 0, not a missing one.
  assert.equal(procs.top[1].cpuPct, 0);
  // A row with no comm cannot be labelled, so it is not shown.
  assert.equal(procs.top.length, 2);
  assert.equal(procs.count, 42);
});

test("network detail keeps numeric strings numeric", () => {
  const net = readNetworkDetail(payload);
  assert.ok(net);
  assert.equal(net.retransPermille, 3.1);
  assert.equal(net.linkMbps, 1000);
  assert.equal(net.txErr, 2);
  // An empty SSID on a wired link is absent, not the empty string.
  assert.equal(net.ssid, null);
  assert.equal(net.connection, "Wired connection 1");
});

test("pressure survives one unreadable axis but not a kernel without PSI", () => {
  assert.deepEqual(readPressure(payload), { cpu: 4, memory: null, io: 11 });
  assert.equal(readPressure({ psi: { cpu: null, memory: null, io: null } }), null);
});

test("per-core clocks drop cores that could not be read", () => {
  const clocks = readCpuClocks(payload);
  assert.ok(clocks);
  assert.deepEqual(clocks.cores, [3400, 3390, 3401]);
  assert.equal(clocks.governor, "performance");
  assert.equal(clocks.minMhz, 1500);
});

test("the first hop is separated from the internet, and a failed probe is not 0ms", () => {
  const hops = readLatencyHops(payload);
  assert.deepEqual(hops, [
    { target: "gateway", ms: 1.2, firstHop: true },
    { target: "1.1.1.1", ms: 8.62, firstHop: false },
  ]);
});
