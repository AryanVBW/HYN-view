// Runs public/app.js against a fake DOM, fed by a live dashboard server (default http://127.0.0.1:8787).
// Catches rendering exceptions and checks that real data lands in the page. No browser needed.
//   node test/ui-smoke.mjs [baseUrl]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'public');
const ids = [...fs.readFileSync(path.join(root, 'index.html'), 'utf8').matchAll(/id="([^"]+)"/g)].map((m) => m[1]);

const noop = () => {};
const draws = { stroke: 0, fill: 0 };
const ctx = new Proxy({}, { get: (t, k) => (k === 'measureText' ? () => ({ width: 40 }) : k === 'stroke' || k === 'fill' || k === 'fillRect' ? () => { draws[k === 'fillRect' ? 'fill' : k]++; } : t[k] ?? noop), set: (t, k, v) => ((t[k] = v), true) });
class El {
  constructor(tag = 'div') { this.tag = tag; this.nodeType = 1; this.children = []; this.style = { cssText: '' }; this.dataset = {}; this.className = ''; this._text = ''; this.value = ''; this.checked = true;
    this.clientWidth = 640; this.clientHeight = 160; this.width = 0; this.height = 0; this.scrollTop = 0; this.scrollHeight = 0; this.tBodies = [tag === 'table' ? new El('tbody') : null];
    this.classList = { toggle: noop, add: noop, remove: noop }; }
  get options() { return this.children; }
  get firstChild() { return this.children[0] || new El('i'); }
  get textContent() { return this._text + this.children.map((c) => c.textContent ?? '').join(''); }
  set textContent(v) { this._text = String(v); this.children = []; }
  append(...k) { this.children.push(...k); }
  replaceChildren(...k) { this._text = ''; this.children = k; }
  setAttribute(k, v) { if (k === 'id') els[v] = this; } addEventListener() {} getBoundingClientRect() { return { left: 0 }; } getContext() { return ctx; }
  querySelector() { return this._q ??= new El('x'); }
}
var els = Object.fromEntries(ids.map((id) => [id, new El(id === 'svc' || id === 'timers' || id === 'procs' || id === 'collectors' ? 'table' : 'div')]));
const listeners = {};
globalThis.document = { getElementById: (id) => els[id], createElement: (t) => new El(t), createTextNode: (t) => ({ nodeType: 3, textContent: String(t) }), documentElement: {}, hidden: false, title: '' };
globalThis.window = { devicePixelRatio: 1 };
globalThis.addEventListener = noop;
globalThis.getComputedStyle = () => ({ getPropertyValue: () => '#888' });
globalThis.EventSource = class { constructor() { this.l = {}; globalThis.__es = this; } addEventListener(n, f) { this.l[n] = f; } close() {} };
const realFetch = globalThis.fetch;
globalThis.fetch = (u, o) => realFetch(new URL(u, BASE), o);

const errors = [];
process.on('uncaughtException', (e) => errors.push(e));
process.on('unhandledRejection', (e) => errors.push(e));

await import(path.join(root, 'app.js'));
const state = await (await realFetch(BASE + '/api/state')).json();
const fire = (name, data) => { try { globalThis.__es.l[name]({ data: JSON.stringify(data) }); } catch (e) { errors.push(e); } };
fire('full', state);
fire('fast', { f: state.fast, status: state.status, alerts: 0, ifaces: state.ifaces, ts: Date.now() });
await new Promise((r) => setTimeout(r, 2500));      // history + logs fetches

const checks = [
  ['no exceptions', () => errors.length === 0, () => errors.map((e) => e.stack || e).join('\n')],
  ['overall pill', () => /OK|WARNING|CRITICAL/.test(els.overall.textContent)],
  ['cpu kpi filled', () => /%/.test(els['k-cpu']?.textContent ?? '') || els['k-cpu'].querySelector('.v').textContent !== '–'],
  ['service rows', () => els.svc.tBodies[0].children.length > 5],
  ['timer rows', () => els.timers.tBodies[0].children.length > 3],
  ['process rows', () => els.procs.tBodies[0].children.length > 0],
  ['filesystem rows', () => els.fs.children.length > 0],
  ['alerts rendered', () => els.alerts.children.length > 0],
  ['deploy checks', () => els.deploy.children.length > 2],
  ['highway panel', () => els.highway.textContent.includes('Health')],
  ['charts drew lines', () => draws.stroke > 20, () => JSON.stringify(draws)],
  ['kpi values', () => els['k-mem'].querySelector('.v').textContent !== '–'],
  ['log lines', () => els.logs.children.length > 0],
  ['collectors table', () => els.collectors.tBodies[0].children.length >= 10],
];
let bad = 0;
for (const [name, fn, why] of checks) { let ok = false; try { ok = fn(); } catch (e) { errors.push(e); } console.log(ok ? 'PASS' : 'FAIL', name, ok ? '' : (why ? why() : '')); if (!ok) bad++; }
console.log(bad ? `${bad} failed` : 'all passed');
process.exit(bad ? 1 : 0);
