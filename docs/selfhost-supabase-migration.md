# HYN-view → self-hosted Supabase: migration status

**Date:** 2026-09-20 · **Target:** `server02` (192.168.0.105), public via `data.hyn-view.in`

## Real architecture (verified, not what the README implies)

| Concern | Source of truth |
| --- | --- |
| Auth (13 users) | Supabase cloud `iycjemnbfyuastnvagcj` |
| All application data | **Cloudflare D1** `hyn-view-production` (`6f77e7c9-…`) |
| Portal switch | Heroku `HYN_DATABASE_PROVIDER=d1` |

Self-hosted stack: LXD container `supabase` (10.211.210.5) running 11 Docker containers,
all healthy. Host proxy devices expose `5432`/`6543` on loopback and `8000` on all
interfaces. `cloudflared` fronts `data.hyn-view.in`.

## DONE — data migration complete and verified

The local Supabase had already been restored from a cloud-Supabase backup (Sep 15–17
window). D1 held a **later, disjoint** window (Sep 18–20), so this was a top-up merge,
not a reload. Both windows are now present.

| Table | Before | D1 added | **Now** |
| --- | --- | --- | --- |
| `alert_events` | 15,751 | 17,302 | **33,053** |
| `metrics` | 6,015 | 5,781 | **11,796** |
| `speedtests` | 33 | 32 | **65** |
| `bandwidth_daily` | 40 | 19 new | **59** |
| `node_commands` | 36 | 4 | **40** |
| `notification_log` | 474 | 474 (identical ids, deduped) | **474** |
| `profiles` / `nodes` | 13 / 8 | deduped | **13 / 8** |
| `auth.users` / `auth.identities` | 13 / 14 | — | **13 / 14** |

`id` ranges were disjoint between the two stores (D1 `alert_events` 72,441–95,674 vs local
43,675–59,428), so rows merged without collision — but the sequences were left stale and
**would have failed the next insert**. All sequences were reset to `max(id)`:

```
alert_events_id_seq  59,428 -> 95,674
metrics_id_seq       26,027 -> 48,283
speedtests_id_seq    24,367 -> 35,776
```
Proven functionally: a probe insert produced alert id `95675` and metric id `48284`
(max+1, no collision), then rolled back leaving 33,053 intact.

Production readiness: **RLS on 28/28 tables**, 22 policies, 102 functions,
`super_admin = hynview@gmail.com`. `admin_allowlist` has RLS on and **0 policies**, which
is the intended design — unreachable from any browser session.

Backup before the merge: `~/supabase-migration/pre-d1-merge-20260920-125517.sql` (60 MB).

## Tooling (in-repo, reusable)

```sh
# re-export D1 at any time
npx wrangler d1 export hyn-view-production --remote --output=migration-artifacts/d1-production.sql

# prove the conversion on a throwaway Postgres (no real project touched)
bash scripts/verify-d1-migration.sh migration-artifacts/d1-production.sql
# => verify: PASS — every D1 row reached Postgres   (23,720 rows, 28 tables)
```
`scripts/d1-to-postgres.py` converts D1 SQLite → Postgres, driven by live column
introspection (so a schema drift is reported, not silently skipped) and emits
`on conflict do nothing`, which is what made the merge idempotent.

## BLOCKER — Google OAuth redirect not registered

Server side is correct: `GOTRUE_EXTERNAL_GOOGLE_ENABLED=true`, same client
`360370652986-ogp44nr08esp1vobm2afmj106cgq4uuo`, and
`GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI=https://data.hyn-view.in/auth/v1/callback`.
`/auth/v1/authorize?provider=google` correctly 302s to Google.

But Google itself refuses:

```
Error 400: redirect_uri_mismatch
redirect_uri: https://data.hyn-view.in/auth/v1/callback
"register the redirect URI in the Google Cloud Console"
```

**Fix (only you can do this):** Google Cloud Console → APIs & Services → Credentials →
client `360370652986-…` → **Authorized redirect URIs** → add
`https://data.hyn-view.in/auth/v1/callback`. Keep the existing
`https://iycjemnbfyuastnvagcj.supabase.co/auth/v1/callback` during cutover as rollback.

**11 of 13 users are Google-only**, so this must be done before cutover or 85% of
accounts cannot sign in.

Note: the `401 Basic` on `https://data.hyn-view.in/` is only the Studio dashboard guard.
It does **not** affect OAuth — `/auth/v1/authorize` and `/auth/v1/callback` are public
(302/303 without an apikey), so it is not a blocker.

## Cutover — do NOT run until Google is fixed

Order matters. Cutting over first would break every Google login.

```sh
# 1. after registering the redirect URI, confirm the flow end to end in a browser
# 2. then flip the portal to Supabase
heroku config:set -a hyn-view \
  HYN_DATABASE_PROVIDER=supabase \
  NEXT_PUBLIC_SUPABASE_URL=https://data.hyn-view.in \
  NEXT_PUBLIC_SUPABASE_ANON_KEY="<ANON_KEY from ~/supabase-project/.env>" \
  SUPABASE_SERVICE_ROLE_KEY="<SERVICE_ROLE_KEY from ~/supabase-project/.env>"
```

Leave `HYN_D1_WORKER_URL`, `HYN_D1_PORTAL_SECRET`, `HYN_DATA_API_URL` and
`HYN_DATA_SERVICE_KEY` in place — they are the rollback.

**Rollback:** `heroku config:set -a hyn-view HYN_DATABASE_PROVIDER=d1` plus the cloud
Supabase URL/keys. One dyno restart.

Self-hosted `SITE_URL` and `ADDITIONAL_REDIRECT_URLS` already include
`www.hyn-view.in`, `hyn-view.in`, the Heroku app and localhost — no change needed.

**HYN CLI agents:** keep `cloud_api_url = https://www.hyn-view.in/api/agent/v1`
(hosted-gateway mode) and no agent needs reconfiguring.

## Residual risk

Auth and all data now live on one self-hosted box. If that server or its connectivity
drops, every HYN / vivek.n login and the dashboard stop — cloud Supabase + D1 were
managed, redundant infrastructure; this is not. Keep the cloud project and the D1
database intact until self-hosted has run clean for several days.
