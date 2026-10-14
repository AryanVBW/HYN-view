// Dashboard client. No libraries. All dynamic text goes through textContent (no innerHTML).
const $ = (id) => document.getElementById(id);
const h = (tag, props = {}, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) { if (k === 'class') e.className = v; else if (k === 'text') e.textContent = v; else if (k === 'style') e.style.cssText = v; else e.setAttribute(k, v); }
  for (const k of kids.flat()) if (k != null) e.append(k.nodeType ? k : document.createTextNode(String(k)));
  return e;
};
const fill = (el, ...kids) => el.replaceChildren(...kids.flat().filter((k) => k != null));

// ---- formatting
const bytes = (n) => { if (!isFinite(n)) return '–'; const u = ['B', 'KiB', 'MiB', 'GiB', 'TiB']; let i = 0; while (n >= 1024 && i < 4) { n /= 1024; i++; } return n.toFixed(n >= 100 || i === 0 ? 0 : 1) + ' ' + u[i]; };
const bits = (bps) => { let n = bps * 8; const u = ['bit/s', 'kbit/s', 'Mbit/s', 'Gbit/s']; let i = 0; while (n >= 1000 && i < 3) { n /= 1000; i++; } return n.toFixed(n >= 100 || i === 0 ? 0 : 1) + ' ' + u[i]; };
const pct = (n, d = 0) => (n == null || !isFinite(n) ? '–' : n.toFixed(d) + '%');
const dur = (s) => { s = Math.max(0, Math.round(s)); const d = Math.floor(s / 86400), hh = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60); return d ? `${d}d ${hh}h` : hh ? `${hh}h ${m}m` : m ? `${m}m ${s % 60}s` : `${s}s`; };
const ago = (ms) => dur((Date.now() - ms) / 1000) + ' ago';
const when = (ms) => new Date(ms).toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', second: '2-digit' });
const parseSd = (s) => { const t = Date.parse((s || '').replace(/^\w{3} /, '')); return isNaN(t) ? 0 : t; };
const lvl = (v, w, c) => (v >= c ? 'crit' : v >= w ? 'warn' : 'ok');

// ---- KPI cards
const KPI = [
  { id: 'cpu', label: 'CPU', val: (f) => pct(f.cpu), sub: (f) => `user ${f.user.toFixed(0)}% · sys ${f.sys.toFixed(0)}% · iowait ${f.iow.toFixed(0)}% · steal ${f.steal.toFixed(0)}%`, p: (f) => f.cpu, lvl: (f) => lvl(f.cpu, 70, 90) },
  { id: 'mem', label: 'Memory', val: (f) => pct(f.mem), sub: (f) => `${bytes(f.memUsed)} of ${bytes(f.memTotal)} · cache ${bytes(f.cache)}`, p: (f) => f.mem, lvl: (f) => lvl(f.mem, 85, 95) },
  { id: 'swap', label: 'Swap', val: (f) => pct(f.swap), sub: (f) => `${bytes(f.swapUsed)} of ${bytes(f.swapTotal)}`, p: (f) => f.swap, lvl: (f) => lvl(f.swap, 40, 70) },
  { id: 'disk', label: 'Disk /', val: (f) => pct(f.disk), sub: (f) => `read ${bytes(f.dioR)}/s · write ${bytes(f.dioW)}/s · util ${f.dioUtil.toFixed(0)}%`, p: (f) => f.disk, lvl: (f) => lvl(f.disk, 80, 92) },
  { id: 'load', label: 'Load (1/5/15)', val: (f) => f.load1.toFixed(2), sub: (f) => `${f.load1} · ${f.load5} · ${f.load15} on ${f.cores} cores`, p: (f) => (100 * f.load1) / f.cores, lvl: (f) => lvl(f.load5 / f.cores, 1, 2) },
  { id: 'net', label: 'Network', val: (f) => '↓ ' + bits(f.rx), sub: (f) => `↑ ${bits(f.tx)} · ${f.iface || '?'} · ${f.tcpInuse} tcp · ${f.retrans.toFixed(1)} retrans/s`, p: null },
  { id: 'up', label: 'Uptime', val: (f) => dur(f.uptime), sub: (f) => `${f.procsTotal} tasks, ${f.procsRun} running · fds ${f.fdOpen}`, p: null },
  { id: 'psi', label: 'Pressure (10 s)', val: (f) => (f.psiCpu == null ? 'n/a' : `${f.psiCpu}/${f.psiMem}/${f.psiIo}`), sub: () => 'cpu / memory / io stall %', p: (f) => Math.max(f.psiCpu || 0, f.psiMem || 0, f.psiIo || 0), lvl: (f) => lvl(Math.max(f.psiCpu || 0, f.psiMem || 0, f.psiIo || 0), 10, 30) },
];
for (const k of KPI) $('kpis').append(h('div', { class: 'card kpi', id: 'k-' + k.id }, h('div', { class: 'l', text: k.label }), h('div', { class: 'v', text: '–' }), h('div', { class: 's' }), k.p ? h('div', { class: 'meter' }, h('i')) : null));
function drawKpis(f) {
  for (const k of KPI) {
    const el = $('k-' + k.id); el.querySelector('.v').textContent = k.val(f); el.querySelector('.s').textContent = k.sub(f);
    if (k.p) { const m = el.querySelector('.meter'); m.className = 'meter ' + k.lvl(f); m.firstChild.style.width = Math.min(100, Math.max(1, k.p(f))) + '%'; }
  }
}

// ---- charts
const C = { blue: '#6366f1', green: '#22c55e', amber: '#f59e0b', red: '#ef4444', cyan: '#38bdf8', pink: '#ec4899', gray: '#94a3b8' };
const CHARTS = [
  { id: 'cpu', title: 'CPU %', fixedMax: 100, fmt: (v) => v.toFixed(0) + '%', series: [['cpu', 'total', C.blue, true], ['iow', 'iowait', C.amber], ['steal', 'steal', C.red]] },
  { id: 'mem', title: 'Memory & swap %', fixedMax: 100, fmt: (v) => v.toFixed(0) + '%', series: [['mem', 'memory', C.green, true], ['swap', 'swap', C.amber]] },
  { id: 'net', title: 'Network throughput', fmt: bits, series: [['rx', 'down', C.cyan, true], ['tx', 'up', C.pink]] },
  { id: 'load', title: 'Load average & pressure', fmt: (v) => v.toFixed(2), series: [['load1', 'load 1m', C.blue, true], ['psiCpu', 'cpu psi%', C.amber], ['psiMem', 'mem psi%', C.red]] },
  { id: 'dio', title: 'Disk I/O', fmt: (v) => bytes(v) + '/s', series: [['dioR', 'read', C.green, true], ['dioW', 'write', C.amber]] },
  { id: 'tcp', title: 'TCP & processes', fmt: (v) => v.toFixed(0), series: [['tcpInuse', 'tcp sockets', C.cyan, true], ['procsTotal', 'tasks', C.gray], ['retrans', 'retrans/s', C.red]] },
  { id: 'rmem', title: 'Relayer memory (cgroup)', fmt: bytes, series: [['relayerMem', 'hway-relayer', C.pink, true]] },
];
const charts = {};
for (const c of CHARTS) {
  const canvas = h('canvas', { class: 'chart' });
  const legend = h('div', { class: 'legend' }, c.series.map((s) => h('span', {}, h('i', { style: `background:${s[2]}` }), s[1])));
  $('charts').append(h('div', { class: 'card chartwrap' }, h('h2', {}, h('span', { text: c.title }), legend), canvas));
  charts[c.id] = { cfg: c, canvas, data: null, hover: null };
  canvas.addEventListener('mousemove', (e) => { const r = canvas.getBoundingClientRect(); charts[c.id].hover = e.clientX - r.left; drawChart(charts[c.id]); });
  canvas.addEventListener('mouseleave', () => { charts[c.id].hover = null; drawChart(charts[c.id]); });
}
function css(v) { return getComputedStyle(document.documentElement).getPropertyValue(v).trim(); }
function setupCanvas(canvas) {
  const dpr = window.devicePixelRatio || 1, w = canvas.clientWidth, hh = canvas.clientHeight;
  if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(hh * dpr)) { canvas.width = Math.round(w * dpr); canvas.height = Math.round(hh * dpr); }
  const ctx = canvas.getContext('2d'); ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, w, hh); return { ctx, w, h: hh };
}
function niceMax(v) { if (v <= 0) return 1; const e = Math.pow(10, Math.floor(Math.log10(v))), n = v / e; return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * e; }
function drawChart(ch) {
  const { cfg, canvas, data } = ch; if (!data || !data.t.length) return;
  const { ctx, w, h: H } = setupCanvas(canvas), L = 44, R = 8, T = 6, B = 18, pw = w - L - R, ph = H - T - B;
  const t0 = data.t[0], t1 = data.t[data.t.length - 1] || t0 + 1, span = Math.max(1, t1 - t0);
  let max = cfg.fixedMax || 0;
  if (!cfg.fixedMax) for (const s of cfg.series) for (const v of data.series[s[0]]) if (v != null && v > max) max = v;
  max = cfg.fixedMax || niceMax(max * 1.1);
  const X = (t) => L + ((t - t0) / span) * pw, Y = (v) => T + ph - (Math.min(v, max) / max) * ph;
  ctx.font = '10px system-ui'; ctx.fillStyle = css('--muted'); ctx.strokeStyle = css('--line'); ctx.lineWidth = 1;
  for (let i = 0; i <= 4; i++) {
    const y = T + (ph * i) / 4; ctx.beginPath(); ctx.moveTo(L, y); ctx.lineTo(w - R, y); ctx.stroke();
    ctx.textAlign = 'right'; ctx.fillText(cfg.fmt(max * (1 - i / 4)), L - 4, y + 3);
  }
  ctx.textAlign = 'center';
  for (let i = 0; i <= 4; i++) { const t = t0 + (span * i) / 4; ctx.fillText(new Date(t * 1000).toLocaleTimeString([], span > 172800 ? { month: 'short', day: 'numeric' } : { hour: '2-digit', minute: '2-digit' }), Math.min(w - 22, Math.max(L + 14, X(t))), H - 4); }
  for (const [key, , color, area] of cfg.series) {
    const vals = data.series[key]; let started = false, lastX = 0;
    ctx.beginPath();
    vals.forEach((v, i) => { if (v == null) { started = false; return; } const x = X(data.t[i]), y = Y(v); if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y); lastX = x; });
    ctx.strokeStyle = color; ctx.lineWidth = 1.6; ctx.stroke();
    if (area) { ctx.lineTo(lastX, T + ph); ctx.lineTo(L, T + ph); ctx.closePath(); ctx.globalAlpha = 0.12; ctx.fillStyle = color; ctx.fill(); ctx.globalAlpha = 1; }
  }
  if (ch.hover != null && ch.hover >= L && ch.hover <= w - R) {
    const t = t0 + ((ch.hover - L) / pw) * span; let idx = 0, best = Infinity;
    data.t.forEach((x, i) => { const d = Math.abs(x - t); if (d < best) { best = d; idx = i; } });
    const x = X(data.t[idx]); ctx.strokeStyle = css('--muted'); ctx.beginPath(); ctx.moveTo(x, T); ctx.lineTo(x, T + ph); ctx.stroke();
    const lines = [new Date(data.t[idx] * 1000).toLocaleString()].concat(cfg.series.map((s) => { const v = data.series[s[0]][idx]; return `${s[1]}: ${v == null ? '–' : cfg.fmt(v)}`; }));
    ctx.font = '11px system-ui'; const bw = Math.max(...lines.map((l) => ctx.measureText(l).width)) + 14, bh = lines.length * 15 + 8, bx = x + 10 + bw > w ? x - bw - 10 : x + 10;
    ctx.fillStyle = css('--card2'); ctx.strokeStyle = css('--line'); ctx.fillRect(bx, T + 4, bw, bh); ctx.strokeRect(bx, T + 4, bw, bh);
    ctx.fillStyle = css('--fg'); ctx.textAlign = 'left'; lines.forEach((l, i) => ctx.fillText(l, bx + 7, T + 18 + i * 15));
  }
}
async function loadHistory() {
  try {
    const r = await fetch('/api/history?range=' + $('range').value); if (!r.ok) return; const d = await r.json();
    for (const c of Object.values(charts)) { c.data = d; drawChart(c); }
  } catch { /* retried on next tick */ }
}
$('range').addEventListener('change', loadHistory);
setInterval(() => loadHistory(), 5000);
addEventListener('resize', () => { for (const c of Object.values(charts)) drawChart(c); drawJournal(); });

// ---- panels
let S = null, F = null, svcGroup = 'Highway', procKey = 'cpu', lastMsg = 0;
const sevPill = (sev) => h('span', { class: 'sev ' + sev, text: sev });
function drawAlerts() {
  const a = S.alerts.active; $('alertCount').textContent = a.length;
  const hynFire = (S.hyn.firing || []).filter((x) => !a.some((y) => y.id === x.rule));
  fill($('alerts'), a.length || hynFire.length ? [
    ...a.map((x) => h('div', { class: 'row' }, sevPill(x.sev), h('div', { class: 'grow' }, h('b', { text: x.title }), h('div', { class: 'muted small', text: x.detail })), h('span', { class: 't', text: 'since ' + when(x.since * 1000) }))),
    ...hynFire.map((x) => h('div', { class: 'row' }, sevPill('info'), h('div', { class: 'grow' }, h('b', { text: 'hyn-view: ' + x.rule })), h('span', { class: 't', text: 'since ' + when(x.since * 1000) }))),
  ] : [h('div', { class: 'ok-msg', text: '✓ No active alerts' })]);
  const ev = S.alerts.recent.slice(0, 12);
  fill($('events'), ev.length ? ev.map((e) => h('div', { class: 'row' }, h('span', { class: 's-' + (e.type === 'resolved' ? 'ok' : e.sev), text: e.type === 'resolved' ? '✓ resolved' : '● ' + e.sev }), h('div', { class: 'grow', text: e.title + (e.detail ? ' — ' + e.detail : '') }), h('span', { class: 't', text: when(e.t * 1000) }))) : [h('div', { class: 'muted', text: 'No alert changes recorded yet.' })]);
}
function drawDeploy() {
  const d = S.deploy || {}; const ch = d.checks || [];
  fill($('deploy'), ch.length ? ch.map((c) => h('div', { class: 'row' }, h('span', { class: c.ok ? 's-ok' : 's-' + c.sev, text: c.ok ? '✓' : c.sev === 'crit' ? '✗' : '!' }), h('div', { class: 'grow' }, h('b', { text: c.name }), h('div', { class: 'muted small', text: c.detail })))) : [h('div', { class: 'muted', text: 'collecting…' })]);
  fill($('files'), (d.files || []).map((f) => h('div', { class: 'row' }, h('div', { class: 'grow', text: f.label }), h('span', { class: 't', text: when(f.mtime) }))));
}
function stateCell(s) {
  const cls = s.active === 'failed' ? 'crit' : s.running ? 'ok' : s.oneshotDone || s.active === 'active' ? 'ok' : s.active === 'inactive' ? 'off' : 'warn';
  const label = s.active === 'failed' ? 'failed' : s.running ? 'running' : s.oneshotDone ? 'idle (ok)' : `${s.active}/${s.sub}`;
  return h('span', { class: 's-' + cls, text: '● ' + label });
}
function drawServices() {
  const groups = ['Highway', 'HYN-view', 'System', 'All'], q = $('svcFilter').value.toLowerCase();
  fill($('svcTabs'), groups.map((g) => { const n = g === 'All' ? S.services.length : S.services.filter((s) => s.group === g).length; const b = h('button', { class: g === svcGroup ? 'on' : '', text: `${g} ${n}` }); b.onclick = () => { svcGroup = g; drawServices(); }; return b; }));
  let rows = S.services.filter((s) => (svcGroup === 'All' || s.group === svcGroup) && (!q || s.name.includes(q) || (s.desc || '').toLowerCase().includes(q)));
  const rank = (s) => (s.active === 'failed' ? 0 : s.running ? 1 : 2);
  rows.sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name));
  const failed = S.services.filter((s) => s.active === 'failed').length;
  $('svcCount').textContent = `${S.services.filter((s) => s.running).length} running · ${failed} failed`;
  fill($('svc').tBodies[0], rows.map((s) => h('tr', {}, h('td', {}, s.name), h('td', {}, stateCell(s)),
    h('td', { class: 'n' }, s.mem ? bytes(s.mem) + (s.memMax && s.memMax < 1e15 ? ` / ${bytes(s.memMax)}` : '') : '–'), h('td', { class: 'n s-' + (s.restarts > 3 ? 'warn' : 'off'), text: String(s.restarts) }),
    h('td', {}, s.since ? ago(parseSd(s.since)) : '–'), h('td', { class: 'hide-sm muted', text: s.desc || '' }))));
  const sel = $('logUnit'), cur = sel.value, units = ['', ...S.services.filter((s) => s.group !== 'System' || s.running).map((s) => s.name).sort()];
  if (sel.options.length !== units.length) fill(sel, units.map((u) => h('option', { value: u, text: u || 'all units' }))), (sel.value = cur);
}
function drawTimers() {
  const rows = [...S.timers].sort((a, b) => a.group.localeCompare(b.group) || a.name.localeCompare(b.name)).filter((t) => t.group !== 'System' || t.active !== 'active' || true);
  fill($('timers').tBodies[0], rows.map((t) => { const nx = parseSd(t.next), ls = parseSd(t.last);
    return h('tr', {}, h('td', {}, t.name), h('td', {}, h('span', { class: 's-' + (t.active === 'active' ? 'ok' : 'warn'), text: '● ' + t.active })),
      h('td', { class: nx ? '' : 's-warn', text: nx ? 'in ' + dur((nx - Date.now()) / 1000) : 'not scheduled' }), h('td', { text: ls ? ago(ls) : '–' })); }));
}
const kv = (pairs) => h('div', { class: 'kv' }, pairs.flatMap(([k, v, cls]) => [h('div', { text: k }), h('div', { class: cls || '', text: v == null || v === '' ? '–' : String(v) })]));
function drawHighway() {
  const w = S.highway;
  fill($('highway'), w && w.present ? kv([['Health', `${w.health} — ${w.why}`, 's-' + (w.health === 'ok' ? 'ok' : 'crit')], ['Version', `${w.version} (latest ${w.latest || '?'})`, w.update_available ? 's-info' : ''],
    ['Relayer pid / RSS', `${w.pid} / ${bytes(w.rss)}`], ['Units active / failed', `${w.units_active} / ${w.units_failed}`, w.units_failed ? 's-crit' : ''], ['Tunnel', w.tunnel], ['Journal errors (1h)', w.journal_err_1h, w.journal_err_1h ? 's-warn' : ''],
    ['Nebula guard', S.nebula ? `${S.nebula.connected ? 'connected' : 'DISCONNECTED'} · blocklist v${S.nebula.version} (${S.nebula.blocklist} entries)` : '–', S.nebula && !S.nebula.connected ? 's-crit' : '']]) : h('div', { class: 'muted', text: S.highway === null ? 'waiting for first snapshot…' : 'Highway not detected' }));
  const y = S.hyn || {}, hb = y.heartbeat, pu = y.push;
  const st = (S.hyn.speedtests || []).slice(-1)[0];
  fill($('hyn'), kv([['Linked to portal', y.linked ? 'yes' : 'no'], ['Last heartbeat', hb ? `${hb.status} · ${ago(hb.ts * 1000)}${hb.msg ? ' · ' + hb.msg : ''}` : '–', hb && hb.status !== 'ok' ? 's-crit' : 's-ok'],
    ['Last push', pu ? `${pu.status} · ${ago(pu.ts * 1000)}${pu.msg ? ' · ' + pu.msg : ''}` : '–', pu && pu.status !== 'ok' ? 's-warn' : ''],
    ['Last speed test', st ? `↓ ${bits(st.down / 8)} ↑ ${bits(st.up / 8)} · ${st.lat.toFixed(0)} ms · ${ago(st.t * 1000)}` : '–'], ['Local metric rows', y.metricsRows]]));
}
function drawProcs() {
  const rows = [...S.procs].sort((a, b) => b[procKey] - a[procKey]).slice(0, 12);
  fill($('procs').tBodies[0], rows.map((p) => h('tr', {}, h('td', { text: String(p.pid) }), h('td', { text: p.comm }), h('td', { text: p.user }), h('td', { class: 'n', text: p.cpu.toFixed(1) + '%' }), h('td', { class: 'n', text: bytes(p.rss) }), h('td', { class: 'hide-sm muted', text: p.cmd }))));
}
function drawStorage() {
  fill($('fs'), S.fs.map((f) => h('div', { class: 'fsrow' }, h('div', { class: 'top' }, h('span', { text: `${f.mount}  (${f.type})` }), h('span', { text: `${bytes(f.used)} / ${bytes(f.total)} · ${f.pct.toFixed(0)}% · inodes ${f.inodePct.toFixed(0)}%` })), h('div', { class: 'meter ' + lvl(f.pct, 85, 93) }, h('i', { style: `width:${Math.max(1, f.pct)}%` })))));
  fill($('ifaces'), (S.ifaces || []).map((i) => h('div', { class: 'row' }, h('div', { class: 'grow', text: i.name }), h('span', { text: `↓ ${bits(i.rx)}  ↑ ${bits(i.tx)}` }), h('span', { class: 't', text: `Σ ↓${bytes(i.rxTotal)} ↑${bytes(i.txTotal)}` }))));
  fill($('ports'), (S.ports || []).map((p) => h('div', { class: 'row' }, h('span', { class: 'chip', text: p.proto }), h('div', { class: 'grow', text: `${p.addr}:${p.port}  ${p.proc}` }), h('span', { class: p.exposed ? 's-warn' : 's-off', text: p.exposed ? 'public' : 'local' }))));
}
function drawSecurity() {
  const s = S.security || {};
  fill($('security'), kv([['SSH port', s.sshPort], ['Root login', s.rootLogin, s.rootLogin === 'yes' ? 's-warn' : ''], ['Password auth', s.passwordAuth, s.passwordAuth === 'yes' ? 's-warn' : ''], ['Firewall', s.firewall, s.firewall && s.firewall.startsWith('none') ? 's-warn' : 's-ok'],
    ['Failed SSH logins 24h', s.sshFailures24h, s.sshFailures24h > 50 ? 's-warn' : ''], ['Accepted SSH logins 24h', s.sshAccepted24h], ['Auto security updates', s.unattendedUpgrades ? 'enabled' : 'off'], ['Reboot required', s.rebootRequired ? 'yes' : 'no', s.rebootRequired ? 's-info' : ''],
    ['Upgradable packages', S.sys && S.sys.upgradable]]));
  const ss = (S.snapshot && S.snapshot.sessions) || [];
  fill($('sessions'), ss.length ? ss.map((x) => h('div', { class: 'row' }, h('div', { class: 'grow', text: `${x.user} on ${x.tty}` }), h('span', { class: 't', text: 'from ' + x.from }))) : [h('div', { class: 'muted', text: 'no interactive sessions' })]);
}
function drawJournal() {
  const hours = (S && S.journal.hourly) || [], canvas = $('jchart'); if (!hours.length) return;
  const { ctx, w, h: H } = setupCanvas(canvas), max = Math.max(1, ...hours.map((x) => x.err + x.warn)), bw = (w - 8) / 24;
  hours.forEach((x, i) => { const hw = ((x.warn) / max) * (H - 16), he = (x.err / max) * (H - 16); ctx.fillStyle = C.amber; ctx.fillRect(4 + i * bw + 1, H - 12 - hw - he, bw - 2, hw); ctx.fillStyle = C.red; ctx.fillRect(4 + i * bw + 1, H - 12 - he, bw - 2, he); });
  ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui'; ctx.fillText('24 h ago', 4, H - 1); ctx.textAlign = 'right'; ctx.fillText('now', w - 4, H - 1);
  fill($('jbyunit'), S.journal.byUnit.map((u) => h('div', { class: 'row' }, h('div', { class: 'grow', text: u.unit }), h('span', { class: 's-crit', text: u.err + ' err' }), h('span', { class: 's-warn', text: u.warn + ' warn' }))));
}
function drawSys() {
  const y = S.sys || {};
  fill($('sys'), kv([['Host', y.host], ['OS', y.os], ['Kernel', `${y.kernel} ${y.arch || ''}`], ['CPU', `${y.cpuModel} × ${y.cores}`], ['Virtualization', y.virt], ['Timezone', y.tz], ['Node (dashboard)', y.node],
    ['Packages', (y.packages || []).map((p) => `${p[0]} ${p[1]}`).join(' · ')], ['Dashboard up', ago(S.startedAt)]]));
}
function drawCollectors() {
  fill($('collectors').tBodies[0], Object.entries(S.collectors).map(([k, c]) => { const age = c.lastOk ? Date.now() - c.lastOk : Infinity, stale = age > c.everyMs * 3 + 5000;
    return h('tr', {}, h('td', { text: k }), h('td', { text: dur(c.everyMs / 1000) }), h('td', { class: stale ? 's-crit' : 's-ok', text: c.lastOk ? ago(c.lastOk) : 'never' }), h('td', { class: c.errors ? 's-warn' : '', text: c.errors + (c.lastError ? ' · ' + c.lastError : '') })); }));
}
function drawHeader() {
  const o = $('overall'), st = S.status; o.className = 'pill ' + st; o.textContent = st === 'ok' ? 'ALL OK' : st === 'warn' ? 'WARNING' : 'CRITICAL';
  $('host').textContent = S.sys.host || 'VPS'; $('sub').textContent = `${S.sys.os || ''} · up ${dur(F ? F.uptime : 0)} · ${S.sys.virt || ''}`;
  document.title = (st === 'ok' ? '● ' : st === 'warn' ? '▲ ' : '✖ ') + (S.sys.host || 'VPS');
}
function drawAll() { drawHeader(); drawAlerts(); drawDeploy(); drawServices(); drawTimers(); drawHighway(); drawProcs(); drawStorage(); drawSecurity(); drawJournal(); drawSys(); drawCollectors(); }
$('svcFilter').addEventListener('input', () => S && drawServices());
$('procSort').addEventListener('click', (e) => { const k = e.target.dataset && e.target.dataset.k; if (!k) return; procKey = k; for (const b of $('procSort').children) b.classList.toggle('on', b.dataset.k === k); S && drawProcs(); });

// ---- logs
async function loadLogs() {
  const p = new URLSearchParams({ unit: $('logUnit').value, prio: $('logPrio').value, q: $('logQ').value, n: 150 });
  try {
    const r = await fetch('/api/logs?' + p); const d = await r.json(); const box = $('logs'), atEnd = box.scrollHeight - box.scrollTop - box.clientHeight < 40;
    const nodes = (d.rows || []).map((x) => { const l = h('div', { class: 'p' + x.p }); l.append(h('span', { class: 'muted', text: new Date(x.t).toLocaleTimeString() + ' ' }), h('span', { class: 'u', text: x.u + ' ' }), x.m); return l; });
    fill(box, nodes.length ? nodes : [h('span', { class: 'muted', text: 'no matching entries' })]); if (atEnd) box.scrollTop = box.scrollHeight;
  } catch { $('logs').textContent = 'log request failed'; }
}
for (const id of ['logUnit', 'logPrio']) $(id).addEventListener('change', loadLogs);
let qt; $('logQ').addEventListener('input', () => { clearTimeout(qt); qt = setTimeout(loadLogs, 350); });
setInterval(() => { if ($('logLive').checked && !document.hidden) loadLogs(); }, 5000);

// ---- live stream with reconnect
function connect() {
  const es = new EventSource('/api/stream');
  es.addEventListener('full', (e) => { S = JSON.parse(e.data); F = S.fast; lastMsg = Date.now(); drawKpis(F); drawAll(); });
  es.addEventListener('fast', (e) => { const d = JSON.parse(e.data); if (!S) return; F = d.f; S.fast = F; S.status = d.status; S.ifaces = d.ifaces; lastMsg = Date.now(); drawKpis(F); drawHeader(); drawStorage(); });
  es.onopen = () => { $('dot').className = 'dot'; };
  es.onerror = () => { $('dot').className = 'dot off'; $('age').textContent = 'reconnecting…'; es.close(); setTimeout(connect, 3000); };
}
setInterval(() => {
  if (!lastMsg) return; const a = Date.now() - lastMsg;
  $('age').textContent = a < 5000 ? 'live' : `no data for ${dur(a / 1000)}`;
  if (a > 8000) $('dot').className = 'dot crit'; else if (S) $('dot').className = 'dot' + (S.status === 'ok' ? '' : ' ' + S.status);
}, 1000);
connect(); loadHistory(); loadLogs();
