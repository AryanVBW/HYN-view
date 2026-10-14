// Collector: reads the real server (/proc, systemd, journald, hyn-view state files)
// and keeps the latest state plus history in memory and on disk.
// Zero dependencies. Read-only: nothing here changes the machine.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFile } from 'node:child_process';

const CFG = {
  stateDir: process.env.DASH_STATE_DIR || '/var/lib/hyn-dashboard',
  hynState: process.env.HYN_VAR || '/var/lib/hyn-view',
  installDir: process.env.HYN_INSTALL_DIR || '/usr/local/lib/node_modules/hyn-view',
  hynBin: process.env.HYN_BIN || '/usr/local/bin/hyn',
  repoDir: process.env.HYN_REPO || '',
  webhook: process.env.DASH_WEBHOOK_URL || '',
  unitGlobs: (process.env.DASH_UNIT_PREFIXES || 'hway,hyn,nebula,highway,mosaic').split(','),
};
const RING_MAX = 900;           // 30 min at 2 s
const HIST_MAX = 10080;         // 7 days at 1 min
const HIST_FILE = path.join(CFG.stateDir, 'history.jsonl');
const EVENT_FILE = path.join(CFG.stateDir, 'events.jsonl');

const rd = (p) => { try { return fs.readFileSync(p, 'utf8'); } catch { return ''; } };
const num = (x) => { const n = Number(x); return Number.isFinite(n) ? n : 0; };
const now = () => Date.now();
function run(cmd, args, timeout = 10000) {
  return new Promise((res) => {
    execFile(cmd, args, { timeout, maxBuffer: 32 << 20, env: { ...process.env, LC_ALL: 'C', SYSTEMD_COLORS: '0' } },
      (e, stdout) => res({ ok: !e, out: stdout || '' }));
  });
}

export const state = {
  startedAt: now(),
  nebula: null, sys: {}, fast: {}, procs: [], services: [], timers: [], fs: [], ifaces: [], ports: [],
  highway: null, hyn: {}, deploy: {}, security: {}, journal: { hourly: [], byUnit: [], total24h: 0 },
  alerts: { active: [], recent: [] }, collectors: {},
};
const ring = [];
let hist = [];
let acc = { n: 0, sum: {}, t0: now() };

// ---------------------------------------------------------------- fast metrics
let prevCpu = null, prevNet = null, prevDisk = null, prevSnmp = null, prevT = 0;
const WHOLE_DISK = /^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme\d+n\d+|mmcblk\d+)$/;

function readCpu() {
  const l = rd('/proc/stat').split('\n')[0].trim().split(/\s+/).slice(1).map(Number);
  const [user, nice, sys, idle, iow, irq, sirq, steal] = l;
  return { user: user + nice, sys: sys + irq + sirq, idle, iow, steal: steal || 0, total: l.slice(0, 8).reduce((a, b) => a + b, 0) };
}
function defaultIface() {
  for (const line of rd('/proc/net/route').split('\n').slice(1)) {
    const f = line.split('\t');
    if (f[1] === '00000000') return f[0];
  }
  return '';
}
function readNet() {
  const o = {};
  for (const line of rd('/proc/net/dev').split('\n').slice(2)) {
    const [name, rest] = line.split(':');
    if (!rest) continue;
    const f = rest.trim().split(/\s+/).map(Number);
    o[name.trim()] = { rx: f[0], rxPk: f[1], rxErr: f[2], rxDrop: f[3], tx: f[8], txPk: f[9], txErr: f[10], txDrop: f[11] };
  }
  return o;
}
function readDisk() {
  const o = {};
  for (const line of rd('/proc/diskstats').split('\n')) {
    const f = line.trim().split(/\s+/);
    if (f.length < 14 || !WHOLE_DISK.test(f[2])) continue;
    o[f[2]] = { r: num(f[5]) * 512, w: num(f[9]) * 512, ticks: num(f[12]) };
  }
  return o;
}
function readSnmpTcp() {
  const lines = rd('/proc/net/snmp').split('\n').filter((l) => l.startsWith('Tcp:'));
  if (lines.length < 2) return { out: 0, retr: 0 };
  const h = lines[0].split(/\s+/), v = lines[1].split(/\s+/);
  return { out: num(v[h.indexOf('OutSegs')]), retr: num(v[h.indexOf('RetransSegs')]) };
}
function psi(kind) {
  const m = rd(`/proc/pressure/${kind}`).match(/some avg10=([\d.]+)/);
  return m ? Number(m[1]) : null;
}

function sampleFast() {
  const t = now(), dt = prevT ? (t - prevT) / 1000 : 0;
  const cpu = readCpu(), net = readNet(), disk = readDisk(), tcp = readSnmpTcp();
  const f = {};
  f.t = t;
  if (prevCpu) {
    const d = cpu.total - prevCpu.total || 1;
    f.user = (100 * (cpu.user - prevCpu.user)) / d;
    f.sys = (100 * (cpu.sys - prevCpu.sys)) / d;
    f.iow = (100 * (cpu.iow - prevCpu.iow)) / d;
    f.steal = (100 * (cpu.steal - prevCpu.steal)) / d;
    f.cpu = 100 - (100 * (cpu.idle + cpu.iow - prevCpu.idle - prevCpu.iow)) / d;
  } else { f.user = f.sys = f.iow = f.steal = f.cpu = 0; }
  const mi = {};
  for (const l of rd('/proc/meminfo').split('\n')) { const m = l.match(/^(\w+):\s+(\d+)/); if (m) mi[m[1]] = Number(m[2]) * 1024; }
  f.memTotal = mi.MemTotal || 0; f.memAvail = mi.MemAvailable || 0;
  f.memUsed = f.memTotal - f.memAvail;
  f.mem = f.memTotal ? (100 * f.memUsed) / f.memTotal : 0;
  f.cache = (mi.Cached || 0) + (mi.Buffers || 0);
  f.swapTotal = mi.SwapTotal || 0; f.swapUsed = (mi.SwapTotal || 0) - (mi.SwapFree || 0);
  f.swap = f.swapTotal ? (100 * f.swapUsed) / f.swapTotal : 0;
  const la = rd('/proc/loadavg').split(' ');
  f.load1 = num(la[0]); f.load5 = num(la[1]); f.load15 = num(la[2]);
  f.procsRun = num((la[3] || '').split('/')[0]); f.procsTotal = num((la[3] || '').split('/')[1]);
  f.uptime = num(rd('/proc/uptime').split(' ')[0]);
  f.cores = os.cpus().length;
  f.psiCpu = psi('cpu'); f.psiMem = psi('memory'); f.psiIo = psi('io');
  const ss = rd('/proc/net/sockstat').match(/TCP: inuse (\d+) orphan (\d+) tw (\d+) alloc (\d+)/);
  f.tcpInuse = ss ? num(ss[1]) : 0; f.tcpTw = ss ? num(ss[3]) : 0;
  const fn = rd('/proc/sys/fs/file-nr').split(/\s+/);
  f.fdOpen = num(fn[0]); f.fdMax = num(fn[2]);
  const ifc = defaultIface(); f.iface = ifc;
  f.rx = f.tx = f.rxErr = f.txErr = 0; f.dioR = f.dioW = f.dioUtil = 0; f.retrans = 0;
  const ifRates = [];
  if (prevNet && dt > 0) {
    for (const [n, c] of Object.entries(net)) {
      const p = prevNet[n]; if (!p || n === 'lo') continue;
      const r = { name: n, rx: Math.max(0, (c.rx - p.rx) / dt), tx: Math.max(0, (c.tx - p.tx) / dt),
        rxErr: c.rxErr + c.txErr, drop: c.rxDrop + c.txDrop, rxTotal: c.rx, txTotal: c.tx };
      ifRates.push(r);
      if (n === ifc) { f.rx = r.rx; f.tx = r.tx; f.rxErr = c.rxErr; f.txErr = c.txErr; f.rxTotal = c.rx; f.txTotal = c.tx; }
    }
    let ticks = 0, devs = 0;
    for (const [n, c] of Object.entries(disk)) {
      const p = prevDisk && prevDisk[n]; if (!p) continue;
      f.dioR += Math.max(0, (c.r - p.r) / dt); f.dioW += Math.max(0, (c.w - p.w) / dt);
      ticks += Math.max(0, (c.ticks - p.ticks) / (dt * 10)); devs++;
    }
    f.dioUtil = devs ? Math.min(100, ticks / devs) : 0;
    if (prevSnmp) f.retrans = Math.max(0, (tcp.retr - prevSnmp.retr) / dt);
  }
  state.ifaces = ifRates;
  prevCpu = cpu; prevNet = net; prevDisk = disk; prevSnmp = tcp; prevT = t;

  // root filesystem usage comes from the slow filesystem list; keep last known value
  f.disk = state.fast.disk ?? 0;
  const rel = state.services.find((s) => s.name === 'hway-relayer.service');
  f.relayerMem = rel ? rel.mem : 0;
  state.fast = f;
  ring.push(f); if (ring.length > RING_MAX) ring.shift();
  accumulate(f);
}

const HIST_KEYS = ['cpu', 'user', 'sys', 'iow', 'steal', 'mem', 'swap', 'load1', 'rx', 'tx', 'disk', 'dioR', 'dioW', 'dioUtil',
  'tcpInuse', 'retrans', 'psiCpu', 'psiMem', 'psiIo', 'relayerMem', 'procsTotal'];
function accumulate(f) {
  for (const k of HIST_KEYS) { if (typeof f[k] === 'number') acc.sum[k] = (acc.sum[k] || 0) + f[k]; }
  acc.n++;
  if (now() - acc.t0 >= 60000 && acc.n > 0) {
    const p = { t: Math.round(now() / 1000) };
    for (const k of HIST_KEYS) p[k] = acc.sum[k] === undefined ? null : Math.round((acc.sum[k] / acc.n) * 100) / 100;
    hist.push(p);
    try { fs.appendFileSync(HIST_FILE, JSON.stringify(p) + '\n', { mode: 0o600 }); } catch { /* disk full etc: keep running */ }
    if (hist.length > HIST_MAX + 500) hist = hist.slice(-HIST_MAX);
    acc = { n: 0, sum: {}, t0: now() };
  }
}
function loadHistory() {
  fs.mkdirSync(CFG.stateDir, { recursive: true, mode: 0o700 });
  const lines = rd(HIST_FILE).split('\n').filter(Boolean);
  const keep = lines.slice(-HIST_MAX);
  hist = keep.map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
  if (lines.length > HIST_MAX + 1000) {
    try { fs.writeFileSync(HIST_FILE + '.tmp', keep.join('\n') + '\n', { mode: 0o600 }); fs.renameSync(HIST_FILE + '.tmp', HIST_FILE); } catch { /* ignore */ }
  }
}
const RANGES = { '30m': 1800, '1h': 3600, '6h': 21600, '24h': 86400, '7d': 604800 };
export function history(range = '30m') {
  const secs = RANGES[range] || 1800;
  const from = Date.now() / 1000 - secs;
  let pts;
  if (range === '30m') pts = ring.map((f) => { const p = { t: f.t / 1000 }; for (const k of HIST_KEYS) p[k] = f[k] ?? null; return p; });
  else pts = hist.filter((p) => p.t >= from);
  const max = 360;
  if (pts.length > max) {
    const size = pts.length / max, out = [];
    for (let i = 0; i < max; i++) {
      const slice = pts.slice(Math.floor(i * size), Math.floor((i + 1) * size)); if (!slice.length) continue;
      const m = { t: slice[slice.length - 1].t };
      for (const k of HIST_KEYS) {
        const vals = slice.map((s) => s[k]).filter((v) => typeof v === 'number');
        m[k] = vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : null;
      }
      out.push(m);
    }
    pts = out;
  }
  const res = { range, t: pts.map((p) => p.t), series: {} };
  for (const k of HIST_KEYS) res.series[k] = pts.map((p) => p[k]);
  return res;
}

// ---------------------------------------------------------------- processes
let prevProc = new Map(), prevProcT = 0;
const uidName = {};
function userName(uid) {
  if (uidName[uid] !== undefined) return uidName[uid];
  for (const l of rd('/etc/passwd').split('\n')) { const f = l.split(':'); if (f[2] !== undefined) uidName[f[2]] = f[0]; }
  return (uidName[uid] = uidName[uid] || String(uid));
}
function sampleProcs() {
  const t = now(), dt = prevProcT ? (t - prevProcT) / 1000 : 0, cur = new Map(), list = [];
  const page = 4096, hz = 100;
  for (const d of fs.readdirSync('/proc')) {
    if (!/^\d+$/.test(d)) continue;
    const raw = rd(`/proc/${d}/stat`); if (!raw) continue;
    const i = raw.lastIndexOf(')'), comm = raw.slice(raw.indexOf('(') + 1, i), f = raw.slice(i + 2).split(' ');
    const ticks = num(f[11]) + num(f[12]); cur.set(d, ticks);
    const p = prevProc.get(d);
    list.push({ pid: Number(d), comm, state: f[0], threads: num(f[17]), rss: num(f[21]) * page,
      cpu: dt && p !== undefined ? Math.max(0, (ticks - p) / hz / dt * 100) : 0 });
  }
  prevProc = cur; prevProcT = t;
  const top = new Map();
  for (const p of [...list].sort((a, b) => b.cpu - a.cpu).slice(0, 10)) top.set(p.pid, p);
  for (const p of [...list].sort((a, b) => b.rss - a.rss).slice(0, 10)) top.set(p.pid, p);
  state.procs = [...top.values()].map((p) => {
    let user = '', cmd = p.comm;
    try { user = userName(fs.statSync(`/proc/${p.pid}`).uid); } catch { /* gone */ }
    const c = rd(`/proc/${p.pid}/cmdline`).replace(/\0/g, ' ').trim(); if (c) cmd = c.slice(0, 120);
    return { ...p, user, cmd };
  });
  state.procCounts = { total: list.length, zombie: list.filter((p) => p.state === 'Z').length };
}

// ---------------------------------------------------------------- filesystems
function sampleFs() {
  const seen = new Set(), out = [];
  for (const l of rd('/proc/mounts').split('\n')) {
    const [dev, mp, type] = l.split(' ');
    if (!dev || !dev.startsWith('/dev/') || seen.has(dev) || /\/(snap|docker|containers)/.test(mp)) continue;
    if (!['ext4', 'ext3', 'xfs', 'btrfs', 'vfat', 'zfs', 'f2fs'].includes(type)) continue;
    seen.add(dev);
    try {
      const s = fs.statfsSync(mp), total = s.blocks * s.bsize, free = s.bavail * s.bsize;
      const itot = s.files, ifree = s.ffree;
      out.push({ dev, mount: mp, type, total, used: total - s.bfree * s.bsize, free, pct: total ? (100 * (total - free)) / total : 0,
        inodePct: itot ? (100 * (itot - ifree)) / itot : 0 });
    } catch { /* unreadable mount */ }
  }
  state.fs = out;
  const root = out.find((x) => x.mount === '/') || out[0];
  state.fast.disk = root ? root.pct : 0;
}

// ---------------------------------------------------------------- services
const isOurs = (n) => CFG.unitGlobs.some((p) => n.startsWith(p));
const GROUP = (n) => (/^(hway|highway|nebula|mosaic)/.test(n) ? 'Highway' : n.startsWith('hyn') ? 'HYN-view' : 'System');
async function sampleServices() {
  const lu = await run('systemctl', ['list-units', '--type=service,timer', '--all', '--plain', '--no-legend', '--no-pager']);
  if (!lu.ok) throw new Error('systemctl list-units failed');
  const names = [];
  for (const l of lu.out.split('\n')) {
    const f = l.trim().split(/\s+/); if (f.length < 4) continue;
    const [name, load, active, sub] = f; if (load === 'not-found') continue;
    if (isOurs(name) || active === 'active' || active === 'failed') names.push({ name, active, sub });
  }
  const props = 'Id,ActiveState,SubState,MainPID,MemoryCurrent,MemoryMax,NRestarts,ActiveEnterTimestamp,Result,NextElapseUSecRealtime,LastTriggerUSec,Description,UnitFileState,NeedDaemonReload,Type';
  const sh = await run('systemctl', ['show', '-p', props, '--', ...names.map((n) => n.name)]);
  const blocks = sh.out.split('\n\n').filter((b) => b.trim());
  const services = [], timers = [];
  for (const b of blocks) {
    const o = {}; for (const l of b.split('\n')) { const i = l.indexOf('='); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1); }
    if (!o.Id) continue;
    const mem = o.MemoryCurrent && o.MemoryCurrent !== '[not set]' && /^\d+$/.test(o.MemoryCurrent) ? Number(o.MemoryCurrent) : 0;
    const memMax = /^\d+$/.test(o.MemoryMax || '') ? Number(o.MemoryMax) : 0;
    if (o.Id.endsWith('.timer')) {
      timers.push({ name: o.Id, active: o.ActiveState, next: o.NextElapseUSecRealtime || '', last: o.LastTriggerUSec || '', desc: o.Description, enabled: o.UnitFileState, group: GROUP(o.Id) });
    } else {
      const running = o.ActiveState === 'active' && o.SubState === 'running';
      const oneshotDone = o.ActiveState === 'inactive' && (o.Result === 'success');
      services.push({ name: o.Id, desc: o.Description, active: o.ActiveState, sub: o.SubState, result: o.Result,
        pid: Number(o.MainPID) || 0, mem, memMax, restarts: Number(o.NRestarts) || 0, since: o.ActiveEnterTimestamp,
        enabled: o.UnitFileState, group: GROUP(o.Id), running, oneshotDone, reloadNeeded: o.NeedDaemonReload === 'yes' });
    }
  }
  state.services = services; state.timers = timers;
}

// ---------------------------------------------------------------- ports, hyn, highway
async function samplePorts() {
  const r = await run('ss', ['-H', '-tulnp']); if (!r.ok) throw new Error('ss failed');
  state.ports = r.out.split('\n').filter(Boolean).map((l) => {
    const f = l.trim().split(/\s+/); const local = f[4] || ''; const i = local.lastIndexOf(':');
    const addr = local.slice(0, i), port = Number(local.slice(i + 1));
    const proc = (l.match(/\(\("([^"]+)"/) || [])[1] || '';
    const exposed = !/^(127\.|\[?::1\]?$|10\.66\.)/.test(addr.replace('%lo', '')) && !addr.startsWith('127.');
    return { proto: f[0], addr, port, proc, exposed };
  }).filter((p) => !(p.addr.startsWith('127.0.0.5') ));
}
function parseTsvLine(l) { return l.split('\t'); }
function sampleHyn() {
  const h = {}, v = CFG.hynState;
  const hb = parseTsvLine(rd(path.join(v, 'cloud-last-heartbeat')).trim());
  h.heartbeat = hb[0] ? { ts: num(hb[0]), status: hb[1], msg: hb[2] || '' } : null;
  const pu = parseTsvLine(rd(path.join(v, 'cloud-last-push')).trim());
  h.push = pu[0] ? { ts: num(pu[0]), status: pu[1], msg: pu[2] || '' } : null;
  h.linked = /linked=yes/.test(rd(path.join(v, 'applied-schedule')));
  h.firing = rd(path.join(v, 'alert-state')).split('\n').filter(Boolean).map((l) => {
    const f = l.split('\t'); return { rule: f[0], state: f[1], since: num(f[2]) };
  }).filter((x) => x.state === 'firing');
  h.log = rd(path.join(v, 'alert-log')).split('\n').filter(Boolean).slice(-40).reverse().map((l) => {
    const f = l.split('\t'); return { ts: num(f[0]), sev: f[1], rule: f[2], msg: (f[3] || '').slice(0, 200) };
  });
  const hw = rd(path.join(v, 'hw-latest')).trim().split('\t'); h.hwLatest = hw[1] || '';
  const st = rd(path.join(v, 'speedtest.tsv')).trim().split('\n').filter(Boolean).slice(-30).map((l) => {
    const f = l.split('\t'); return { t: num(f[0]), down: num(f[1]), up: num(f[2]), lat: num(f[3]) / 1000, note: f[7] };
  });
  h.speedtests = st;
  h.metricsRows = rd(path.join(v, 'metrics.tsv')).split('\n').length - 1;
  state.hyn = h;
  patchHw();
}
function patchHw() {
  const w = state.highway, latest = state.hyn && state.hyn.hwLatest;
  if (!w || !w.present || !latest) return;
  w.latest = latest; w.update_available = w.version && w.version !== latest ? 1 : 0;
}
async function sampleSnapshot() {
  const r = await run('nice', ['-n', '10', CFG.hynBin, 'snapshot', '--json'], 40000);
  if (!r.ok) throw new Error('hyn snapshot failed');
  const j = JSON.parse(r.out);
  state.highway = j.highway || null;
  patchHw();
  state.snapshot = { sessions: j.sessions || [], speedtest: j.speedtest || null, power: j.power || null, takenAt: now() };
}

async function sampleNebula() {
  const r = await fetch(process.env.NEBULA_METRICS || 'http://127.0.0.1:9101/metrics', { signal: AbortSignal.timeout(4000) });
  const txt = await r.text(), g = (k) => { const m = txt.match(new RegExp('^' + k + ' ([0-9.e+-]+)', 'm')); return m ? Number(m[1]) : null; };
  state.nebula = { connected: g('nebula_guard_connected'), blocklist: g('nebula_guard_blocklist_entries'), version: g('nebula_guard_blocklist_version'), lastUpdate: g('nebula_guard_last_update_timestamp'), takenAt: now() };
}

// ---------------------------------------------------------------- journal
async function sampleJournal() {
  const r = await run('journalctl', ['-p', 'warning', '--since', '24 hours ago', '-o', 'json', '--output-fields=SYSLOG_IDENTIFIER,_SYSTEMD_UNIT,UNIT,PRIORITY', '-q', '--no-pager'], 40000);
  if (!r.ok && !r.out) throw new Error('journalctl failed');
  const hours = new Array(24).fill(0).map(() => ({ warn: 0, err: 0 })), by = new Map(), nowS = Date.now() / 1000;
  let total = 0;
  for (const l of r.out.split('\n')) {
    if (!l) continue;
    let j; try { j = JSON.parse(l); } catch { continue; }
    const age = nowS - Number(j.__REALTIME_TIMESTAMP) / 1e6, idx = 23 - Math.min(23, Math.floor(age / 3600));
    const pr = Number(j.PRIORITY), k = j.UNIT || j._SYSTEMD_UNIT || j.SYSLOG_IDENTIFIER || 'unknown';
    if (pr <= 3) hours[idx].err++; else hours[idx].warn++;
    const e = by.get(k) || { unit: k, warn: 0, err: 0 }; if (pr <= 3) e.err++; else e.warn++; by.set(k, e); total++;
  }
  state.journal = { hourly: hours, byUnit: [...by.values()].sort((a, b) => b.err * 5 + b.warn - (a.err * 5 + a.warn)).slice(0, 12), total24h: total };
}
const SAFE_UNIT = /^[A-Za-z0-9@:._][A-Za-z0-9@:._\\-]{0,99}$/;
export async function logs({ unit = '', prio = '6', n = 100, q = '' } = {}) {
  const args = ['-o', 'json', '-n', String(Math.min(300, Math.max(10, Number(n) || 100))), '--no-pager', '-q', '-p', String(Math.min(7, Math.max(0, Number(prio) || 6)))];
  if (unit) { if (!SAFE_UNIT.test(unit)) return { error: 'bad unit' }; args.push('-u', unit); }
  const r = await run('journalctl', args, 15000);
  const needle = String(q).toLowerCase().slice(0, 100);
  const rows = [];
  for (const l of r.out.split('\n')) {
    if (!l) continue; let j; try { j = JSON.parse(l); } catch { continue; }
    let msg = j.MESSAGE; if (Array.isArray(msg)) msg = Buffer.from(msg).toString('utf8'); msg = String(msg ?? '');
    if (needle && !msg.toLowerCase().includes(needle)) continue;
    rows.push({ t: Number(j.__REALTIME_TIMESTAMP) / 1000, p: Number(j.PRIORITY), u: j._SYSTEMD_UNIT || j.SYSLOG_IDENTIFIER || '', m: msg.slice(0, 500) });
  }
  return { rows: rows.reverse() };
}

// ---------------------------------------------------------------- security / sys / deploy
async function sampleSecurity() {
  const s = {};
  const sshd = await run('sshd', ['-T']);
  const g = (k) => (sshd.out.match(new RegExp('^' + k + ' (.+)$', 'm')) || [])[1] || '';
  s.sshPort = g('port'); s.rootLogin = g('permitrootlogin'); s.passwordAuth = g('passwordauthentication');
  const ipt = await run('iptables', ['-S']);
  const ufw = await run('ufw', ['status']);
  s.firewall = /Status: active/.test(ufw.out) ? 'ufw active' : (ipt.out.split('\n').filter((l) => l.startsWith('-A')).length ? 'iptables rules' : 'none (all ports open to host rules)');
  const j = await run('journalctl', ['-u', 'ssh', '--since', '24 hours ago', '-o', 'cat', '-q', '--no-pager'], 20000);
  s.sshFailures24h = j.out.split('\n').filter((l) => /Failed password|Invalid user|authentication failure|Connection closed by invalid user/.test(l)).length;
  s.sshAccepted24h = j.out.split('\n').filter((l) => /^Accepted /.test(l)).length;
  s.rebootRequired = fs.existsSync('/var/run/reboot-required');
  s.unattendedUpgrades = fs.existsSync('/etc/apt/apt.conf.d/20auto-upgrades');
  state.security = s;
}
async function sampleSys() {
  const rel = Object.fromEntries(rd('/etc/os-release').split('\n').filter((l) => l.includes('=')).map((l) => { const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1).replace(/^"|"$/g, '')]; }));
  const cpuModel = (rd('/proc/cpuinfo').match(/model name\s*:\s*(.+)/) || [])[1] || '';
  const virt = (await run('systemd-detect-virt', [])).out.trim();
  const pk = await run('dpkg-query', ['-W', '-f', '${Package} ${Version}\n', 'systemd', 'openssh-server', 'bash', 'curl', 'python3', 'unattended-upgrades', 'sysstat']);
  const up = await run('sh', ['-c', 'apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | grep -c "^Inst"']);
  state.sys = { host: os.hostname(), os: rel.PRETTY_NAME || '', kernel: os.release(), arch: os.arch(), cpuModel, cores: os.cpus().length,
    virt, node: process.version, packages: pk.out.trim().split('\n').filter(Boolean).map((l) => l.split(' ')),
    upgradable: num(up.out.trim()), tz: Intl.DateTimeFormat().resolvedOptions().timeZone };
}
async function sampleDeploy() {
  const d = { checks: [], files: [] };
  const ver = (p) => { try { return JSON.parse(rd(p)).version; } catch { return ''; } };
  d.installed = ver(path.join(CFG.installDir, 'package.json'));
  if (CFG.repoDir) {
    d.repoVersion = ver(path.join(CFG.repoDir, 'package.json'));
    const b = await run('git', ['-C', CFG.repoDir, 'rev-parse', '--abbrev-ref', 'HEAD']);
    const c = await run('git', ['-C', CFG.repoDir, 'log', '-1', '--format=%h %s']);
    const ah = await run('git', ['-C', CFG.repoDir, 'rev-list', '--count', 'main..HEAD']);
    d.branch = b.out.trim(); d.commit = c.out.trim(); d.aheadOfMain = num(ah.out.trim());
  }
  const add = (name, ok, detail, sev = 'warn') => d.checks.push({ name, ok, detail, sev });
  if (d.installed) add('Deployed CLI matches repo', !d.repoVersion || d.installed === d.repoVersion, `running ${d.installed}` + (d.repoVersion ? `, repo ${d.repoVersion}${d.branch ? ' @ ' + d.branch : ''}` : ''));
  if (d.repoVersion && d.aheadOfMain > 0) add('Repo branch merged to main', false, `${d.branch} is ${d.aheadOfMain} commit(s) ahead of main and not deployed`, 'info');
  // unit files must point at the installed copy, not at a working tree
  const bad = [];
  try {
    for (const f of fs.readdirSync('/etc/systemd/system').filter((x) => x.startsWith('hyn-') && x.endsWith('.service'))) {
      const m = rd('/etc/systemd/system/' + f).match(/^ExecStart=(\S+)/m);
      if (m && m[1].includes('/') && !m[1].startsWith(CFG.installDir) && !m[1].startsWith('/usr/')) bad.push(f);
    }
  } catch { /* none */ }
  add('hyn units run the installed copy', bad.length === 0, bad.length ? `outside ${CFG.installDir}: ${bad.join(', ')}` : `all point at ${CFG.installDir}`, 'crit');
  add('systemd is up to date with unit files', !state.services.some((s) => s.reloadNeeded), 'daemon-reload ' + (state.services.some((s) => s.reloadNeeded) ? 'needed' : 'not needed'));
  const hw = state.highway;
  if (hw && hw.present) add('Highway on latest release', !hw.update_available, `${hw.version || '?'} installed, ${hw.latest || '?'} available`, 'info');
  // Backups: Highway's sealed recovery file (relayer keys) and the daily system backup.
  try {
    const hrb = fs.readdirSync('/root').filter((n) => /^highway-recovery-.*\.hrb$/.test(n)).map((n) => '/root/' + n);
    if (!hrb.length) add('Highway recovery backup exists', false, 'no /root/highway-recovery-*.hrb — run `sudo highway` → CREATE BACKUP', 'crit');
    else {
      const f = hrb[0], m = fs.statSync(f).mtimeMs, head = Buffer.alloc(4), fd = fs.openSync(f, 'r'); fs.readSync(fd, head, 0, 4, 0); fs.closeSync(fd);
      const keys = fs.readdirSync('/etc/hway-relayer/relayers').flatMap((r) => ['p2p_key', '.env'].map((k) => `/etc/hway-relayer/relayers/${r}/config/${k}`)).filter(fs.existsSync);
      const stale = keys.some((k) => fs.statSync(k).mtimeMs > m);
      add('Highway recovery backup is current', head.toString() === 'HWRB' && !stale, head.toString() !== 'HWRB' ? 'bad header' : stale ? 'a relayer key changed after it was sealed — run CREATE BACKUP again' : `sealed ${new Date(m).toISOString().slice(0, 10)}, keys unchanged since (local file only; same disk)`, 'crit');
    }
  } catch { /* no relayer on this host */ }
  const bdir = '/var/backups/hyn-system', ls = Number(rd(path.join(bdir, 'last-success')).trim()) || 0, lo = Number(rd(path.join(bdir, 'last-offsite')).trim()) || 0;
  if (fs.existsSync('/etc/systemd/system/hyn-sysbackup.timer')) {
    add('System backup ran in the last 36 h', ls > 0 && Date.now() / 1000 - ls < 36 * 3600, ls ? `last success ${new Date(ls * 1000).toISOString().replace('T', ' ').slice(0, 16)} UTC` : 'never succeeded', 'crit');
    const prov = process.env.DASH_OFFSITE_PROVIDER === '1';
    add('Backup copied off this machine', prov || (lo > 0 && Date.now() / 1000 - lo < 36 * 3600), prov ? 'relying on VPS provider snapshots (owner-confirmed, not verifiable from the server)' : lo ? 'offsite copy is fresh' : 'only on this disk — a lost VPS loses the backup too (set HYN_BACKUP_REMOTE)', 'warn');
  }
  const hb = state.hyn.heartbeat;
  add('Portal accepts heartbeats', !!hb && hb.status === 'ok', hb ? `${hb.status}${hb.msg ? ': ' + hb.msg : ''}` : 'no heartbeat recorded', 'crit');
  add('Reboot not pending', !fs.existsSync('/var/run/reboot-required'), fs.existsSync('/var/run/reboot-required') ? 'reboot required' : 'none', 'info');
  for (const [label, p] of [['hyn-view installed', CFG.installDir], ['highway binary', '/usr/local/bin/highway'], ['relayer binary', '/usr/local/bin/hway-relayer'], ['nebula binary', '/usr/local/bin/nebula'], ['hyn-view config', '/etc/hyn-view/config']]) {
    try { d.files.push({ label, path: p, mtime: fs.statSync(p).mtimeMs }); } catch { /* absent */ }
  }
  d.dashboardStarted = state.startedAt;
  state.deploy = d;
}

// ---------------------------------------------------------------- alerts
const sustained = new Map();   // rule id -> consecutive hits
const activeAlerts = new Map();
const SEV = { crit: 3, warn: 2, info: 1 };
function evalAlerts() {
  const f = state.fast, rules = [];
  const R = (id, sev, cond, title, detail, need = 3) => rules.push({ id, sev, cond: !!cond, title, detail, need });
  R('cpu', 'warn', f.cpu > 85, 'High CPU', `CPU at ${f.cpu?.toFixed(0)}%`, 6);
  R('steal', 'warn', f.steal > 15, 'CPU steal', `Hypervisor steal ${f.steal?.toFixed(0)}% — the host is not giving the CPU you pay for`, 6);
  R('iowait', 'warn', f.iow > 35, 'High IO wait', `iowait ${f.iow?.toFixed(0)}%`, 6);
  R('mem_warn', 'warn', f.mem > 90 && f.mem <= 96, 'Memory high', `Memory ${f.mem?.toFixed(0)}%`);
  R('mem_crit', 'crit', f.mem > 96, 'Memory critical', `Memory ${f.mem?.toFixed(0)}% — OOM kills likely`);
  R('swap', 'warn', f.swap > 60, 'Swap in use', `Swap ${f.swap?.toFixed(0)}%`);
  R('load', 'warn', f.cores && f.load5 / f.cores > 2, 'Load high', `5-min load ${f.load5} on ${f.cores} cores`, 6);
  R('psi_mem', 'warn', f.psiMem > 20, 'Memory pressure', `PSI memory ${f.psiMem}% stalled over 10 s`);
  for (const x of state.fs) {
    R('disk:' + x.mount, x.pct > 93 ? 'crit' : 'warn', x.pct > 85, `Disk ${x.mount} filling`, `${x.mount} ${x.pct.toFixed(0)}% used`, 1);
    R('inode:' + x.mount, 'warn', x.inodePct > 85, `Inodes ${x.mount}`, `${x.inodePct.toFixed(0)}% inodes used`, 1);
  }
  const failed = state.services.filter((s) => s.active === 'failed');
  R('failed_units', 'crit', failed.length, 'Failed systemd units', failed.map((s) => s.name).join(', '), 1);
  for (const n of ['hway-relayer.service', 'nebula-hway.service', 'hyn-agent.service']) {
    const s = state.services.find((x) => x.name === n);
    if (s) R('down:' + n, 'crit', !s.running, `${n} not running`, `state ${s.active}/${s.sub}`, 1);
    if (s && s.memMax && s.memMax < 1e15) R('memcap:' + n, 'warn', s.mem / s.memMax > 0.9, `${n} near memory cap`, `${(s.mem / 1048576).toFixed(0)} of ${(s.memMax / 1048576).toFixed(0)} MiB — cgroup OOM-kill risk`, 3);
  }
  const hb = state.hyn.heartbeat;
  R('portal_sync', 'crit', state.hyn.linked && hb && hb.status !== 'ok', 'Portal sync failing', hb ? `${hb.status}: ${hb.msg} — fleet portal sees this node as silent` : '', 1);
  const hw = state.highway;
  if (hw && hw.present) {
    R('hw_health', hw.health === 'ok' ? 'info' : 'crit', hw.health && hw.health !== 'ok', 'Highway node unhealthy', hw.why || hw.health, 1);
    R('hw_update', 'info', hw.update_available, 'Highway update available', `${hw.version} → ${hw.latest}`, 1);
  }
  const ng = state.nebula;
  if (ng) R('nebula_down', 'crit', ng.connected === 0, 'Nebula guard disconnected', 'nebula-guard reports no connection to the platform', 3);
  const sec = state.security;
  R('reboot', 'info', sec.rebootRequired, 'Reboot required', 'Pending kernel/library updates need a reboot', 1);
  R('ssh_pw', 'warn', sec.passwordAuth === 'yes' && sec.rootLogin === 'yes' && sec.firewall && sec.firewall.startsWith('none'), 'SSH exposed', 'root login + password auth enabled and no firewall', 1);
  R('ssh_bf', 'warn', sec.sshFailures24h > 50, 'SSH brute force', `${sec.sshFailures24h} failed logins in 24 h`, 1);
  for (const c of state.deploy.checks || []) if (!c.ok && c.sev !== 'info' && c.name !== 'Portal accepts heartbeats') R('deploy:' + c.name, c.sev, true, c.name, c.detail, 1);

  const t = Math.round(now() / 1000), seen = new Set();
  for (const r of rules) {
    const hits = r.cond ? (sustained.get(r.id) || 0) + 1 : 0; sustained.set(r.id, hits);
    if (hits >= r.need) {
      seen.add(r.id);
      const prev = activeAlerts.get(r.id);
      if (!prev) { activeAlerts.set(r.id, { id: r.id, sev: r.sev, title: r.title, detail: r.detail, since: t }); recordEvent({ t, type: 'fired', id: r.id, sev: r.sev, title: r.title, detail: r.detail }); }
      else { prev.detail = r.detail; prev.sev = r.sev; }
    }
  }
  for (const [id, a] of [...activeAlerts]) if (!seen.has(id)) { activeAlerts.delete(id); recordEvent({ t, type: 'resolved', id, sev: a.sev, title: a.title, detail: '' }); }
  state.alerts.active = [...activeAlerts.values()].sort((a, b) => SEV[b.sev] - SEV[a.sev] || a.since - b.since);
}
function recordEvent(e) {
  state.alerts.recent.unshift(e); state.alerts.recent = state.alerts.recent.slice(0, 100);
  try { fs.appendFileSync(EVENT_FILE, JSON.stringify(e) + '\n', { mode: 0o600 }); } catch { /* ignore */ }
  if (CFG.webhook && e.sev === 'crit') {
    fetch(CFG.webhook, { method: 'POST', headers: { 'content-type': 'application/json' }, signal: AbortSignal.timeout(8000),
      body: JSON.stringify({ text: `[${state.sys.host || 'vps'}] ${e.type.toUpperCase()} ${e.sev}: ${e.title} ${e.detail}` }) }).catch(() => {});
  }
}

// ---------------------------------------------------------------- scheduler
function job(name, everyMs, fn, { immediate = true } = {}) {
  const c = (state.collectors[name] = { everyMs, runs: 0, errors: 0, lastOk: 0, lastMs: 0, lastError: '' });
  let busy = false;
  const tick = async () => {
    if (busy) return; busy = true; const t0 = now();
    try { await fn(); c.lastOk = now(); c.lastError = ''; } catch (e) { c.errors++; c.lastError = String(e.message || e).slice(0, 200); }
    c.runs++; c.lastMs = now() - t0; busy = false;
  };
  if (immediate) tick();
  return setInterval(tick, everyMs);
}
export async function start() {
  loadHistory();
  state.alerts.recent = rd(EVENT_FILE).split('\n').filter(Boolean).slice(-100).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean).reverse();
  sampleFast(); sampleFs();
  await Promise.allSettled([sampleServices(), sampleSys(), sampleSecurity(), samplePorts()]);
  sampleHyn();
  const timers = [
    job('fast', 2000, sampleFast, { immediate: false }),
    job('processes', 5000, sampleProcs),
    job('filesystems', 15000, sampleFs),
    job('services', 10000, sampleServices, { immediate: false }),
    job('ports', 30000, samplePorts, { immediate: false }),
    job('hyn-state', 10000, sampleHyn, { immediate: false }),
    job('hyn-snapshot', 60000, sampleSnapshot),
    job('nebula-guard', 30000, sampleNebula),
    job('journal', 120000, sampleJournal),
    job('security', 600000, sampleSecurity, { immediate: false }),
    job('system', 6 * 3600000, sampleSys, { immediate: false }),
  ];
  setTimeout(() => timers.push(job('deploy', 300000, sampleDeploy)), 4000);
  timers.push(job('alerts', 10000, evalAlerts, { immediate: false }));
  return () => timers.forEach(clearInterval);
}
export const overall = () => {
  const a = state.alerts.active;
  return a.some((x) => x.sev === 'crit') ? 'crit' : a.some((x) => x.sev === 'warn') ? 'warn' : 'ok';
};
