// HTTP + SSE server for the VPS dashboard. Zero dependencies, read-only API.
import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { state, start, history, logs, overall } from './collector.mjs';

const HOST = process.env.DASH_HOST || '127.0.0.1';
const PORT = Number(process.env.DASH_PORT || 8787);
const TLS_CERT = process.env.DASH_TLS_CERT || '', TLS_KEY = process.env.DASH_TLS_KEY || '';
if (!Number.isInteger(PORT) || PORT < 1 || PORT > 65535) { console.error(`invalid DASH_PORT: ${process.env.DASH_PORT}`); process.exit(1); }
const TOKEN = process.env.DASH_TOKEN || '';
const PUB = path.join(path.dirname(fileURLToPath(import.meta.url)), 'public');
const loopback = ['127.0.0.1', '::1', 'localhost'].includes(HOST);

if (!loopback && !TOKEN) {
  console.error('refusing to listen on a non-loopback address without DASH_TOKEN');
  process.exit(1);
}
// A token over plain HTTP can be sniffed. Off-loopback needs TLS here, or a TLS proxy plus an explicit opt-in.
if (!loopback && !(TLS_CERT && TLS_KEY) && process.env.DASH_ALLOW_PLAINTEXT !== '1') {
  console.error('refusing plain HTTP on a non-loopback address: set DASH_TLS_CERT and DASH_TLS_KEY, or put a TLS proxy in front and set DASH_ALLOW_PLAINTEXT=1 (bind the dashboard to loopback behind it)');
  process.exit(1);
}
const useTls = !!(TLS_CERT && TLS_KEY);

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' };
const SEC = {
  'Content-Security-Policy': "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'",
  'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'X-Frame-Options': 'DENY', 'Cache-Control': 'no-store',
};
const eq = (a, b) => { const x = Buffer.from(a), y = Buffer.from(b); return x.length === y.length && crypto.timingSafeEqual(x, y); };

function authed(req, url) {
  if (!TOKEN) return true;
  const h = req.headers.authorization || '';
  if (h.startsWith('Bearer ') && eq(h.slice(7), TOKEN)) return true;
  const ck = (req.headers.cookie || '').split(/;\s*/).find((c) => c.startsWith('dash='));
  return !!ck && eq(decodeURIComponent(ck.slice(5)), TOKEN);
}
function hostOk(req) {
  if (!loopback) return true;                                     // token protects non-loopback binds
  const h = (req.headers.host || '').replace(/:\d+$/, '').replace(/^\[|\]$/g, '');
  return ['127.0.0.1', 'localhost', '::1'].includes(h);          // blocks DNS-rebinding against the local port
}
const json = (res, code, body) => { res.writeHead(code, { 'Content-Type': 'application/json', ...SEC }); res.end(JSON.stringify(body)); };

function fastPayload() {
  const f = state.fast;
  return { f, status: overall(), alerts: state.alerts.active.length, ifaces: state.ifaces, ts: Date.now() };
}
function fullPayload() {
  const { fast, ...rest } = state;
  return { ...rest, fast, status: overall(), ts: Date.now(), startedAt: state.startedAt };
}

const clients = new Set();
const MAX_BUFFERED = 512 * 1024;   // a client that stops reading is dropped instead of buffered without limit
function broadcast(data) {
  for (const c of clients) {
    if (c.destroyed || c.writableLength > MAX_BUFFERED) { clients.delete(c); c.destroy(); continue; }
    c.write(data);
  }
}
setInterval(() => { if (clients.size) broadcast(`event: fast\ndata: ${JSON.stringify(fastPayload())}\n\n`); }, 2000);
setInterval(() => { if (clients.size) broadcast(`event: full\ndata: ${JSON.stringify(fullPayload())}\n\n`); }, 10000);
setInterval(() => broadcast(': keepalive\n\n'), 25000);

const handler = async (req, res) => {
  try {
    const url = new URL(req.url, 'http://x');
    if (!hostOk(req)) { res.writeHead(403, SEC); return res.end('forbidden host'); }
    if (url.pathname === '/healthz') {
      const age = Date.now() - (state.fast.t || 0);
      return json(res, age < 15000 ? 200 : 503, { ok: age < 15000, sampleAgeMs: age, uptimeS: Math.round((Date.now() - state.startedAt) / 1000) });
    }
    if (TOKEN && url.searchParams.get('token') && eq(url.searchParams.get('token'), TOKEN)) {
      res.writeHead(302, { 'Set-Cookie': `dash=${encodeURIComponent(TOKEN)}; HttpOnly; SameSite=Strict; Path=/; Max-Age=2592000${useTls ? '; Secure' : ''}`, Location: '/', ...SEC });
      return res.end();
    }
    if (!authed(req, url)) { res.writeHead(401, { 'WWW-Authenticate': 'Bearer', ...SEC }); return res.end('token required: open /?token=...'); }
    if (req.method !== 'GET') { res.writeHead(405, SEC); return res.end(); }

    if (url.pathname === '/api/state') return json(res, 200, fullPayload());
    if (url.pathname === '/api/history') return json(res, 200, history(url.searchParams.get('range') || '30m'));
    if (url.pathname === '/api/logs') {
      return json(res, 200, await logs({ unit: url.searchParams.get('unit') || '', prio: url.searchParams.get('prio') || '6',
        n: url.searchParams.get('n') || '100', q: url.searchParams.get('q') || '' }));
    }
    if (url.pathname === '/api/stream') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', Connection: 'keep-alive', 'X-Accel-Buffering': 'no', ...SEC });
      res.write(`retry: 3000\nevent: full\ndata: ${JSON.stringify(fullPayload())}\n\n`);
      clients.add(res); req.on('close', () => clients.delete(res));
      return;
    }
    // static files
    let rel = url.pathname === '/' ? '/index.html' : url.pathname;
    const file = path.normalize(path.join(PUB, rel));
    if (!file.startsWith(PUB + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404, SEC); return res.end('not found'); }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', ...SEC });
    fs.createReadStream(file).pipe(res);
  } catch (e) {
    console.error('request error', e);
    if (!res.headersSent) json(res, 500, { error: 'internal' }); else res.end();
  }
};
const server = useTls
  ? https.createServer({ cert: fs.readFileSync(TLS_CERT), key: fs.readFileSync(TLS_KEY), minVersion: 'TLSv1.2' }, handler)
  : http.createServer(handler);

// A fatal error must end the process so systemd (Restart=always) brings back a clean one.
const die = (label) => (e) => { console.error(label, e); process.exit(1); };
process.on('uncaughtException', die('uncaught'));
process.on('unhandledRejection', die('unhandled'));
server.on('error', die('listen error'));
const stop = await start();
server.listen(PORT, HOST, () => console.log(`hyn-dashboard listening on ${useTls ? 'https' : 'http'}://${HOST}:${PORT} (auth ${TOKEN ? 'token' : 'none, loopback only'})`));
for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, () => { stop(); server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 2000).unref(); });
