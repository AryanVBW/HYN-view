# HYN data plane (Cloudflare D1)

Application data lives in D1. **Supabase is used only for authentication**
(Google sign-in, JWT, session cookies). Heartbeats, readings, pairing, roles,
bandwidth and dashboard queries never touch Postgres.

Production Worker: `https://hyn-view-data.hynview.workers.dev`  
Staging Worker: `https://hyn-view-data-staging.hynview.workers.dev`

```
Ubuntu agent  →  POST /api/agent/v1/<rpc>  →  Worker + D1
Browser login →  Supabase Auth (ES256 JWT / JWKS)
Dashboard     →  Worker /rpc/<name> with that JWT  →  D1
```

## Local

```bash
cd cloudflare
pnpm install
cp .dev.vars.example .dev.vars
pnpm migrate:local
pnpm test
pnpm dev                         # http://127.0.0.1:8787
```

Point the portal at the worker:

```
HYN_DATA_API_URL=http://127.0.0.1:8787
HYN_DATA_SERVICE_KEY=same-as-DATA_SERVICE_KEY
```

The CLI can keep `https://www.hyn-view.in/api/agent/v1`. The portal proxies
those routes to the worker when `HYN_DATA_API_URL` is set. After cutover, route
`/api/agent/v1*` on the zone directly to this Worker so Heroku never sees the
ingest firehose.

## Deploy

Production uses D1 `hyn-view-production`. Staging uses D1 `hynview`.

```bash
npx wrangler d1 migrations apply hyn-view-production --remote
npx wrangler d1 migrations apply hynview --remote --env staging
npx wrangler secret put PAIRING_PEPPER
npx wrangler secret put DATA_SERVICE_KEY
npx wrangler secret put PAIRING_PEPPER --env staging
npx wrangler secret put DATA_SERVICE_KEY --env staging
npx wrangler deploy
npx wrangler deploy --env staging
```

Auth JWTs are verified against Supabase JWKS (`ES256`). `SUPABASE_JWT_SECRET`
is only needed for local HS256 fixtures.

`BOOTSTRAP_EMAIL` becomes Super admin on first sign-in if the allowlist is empty.
Add further operators with `hyn_admin_promote_by_email` or `admin_allowlist`.

Existing Postgres rows are not copied automatically. After Auth still works,
link machines again (or import) so D1 holds the live fleet.
