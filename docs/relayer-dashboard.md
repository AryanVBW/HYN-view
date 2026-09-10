# Highway relayer dashboard

The customer dashboard includes Highway relayers in both simple and advanced
views, including accounts without a linked HYN agent. A Super admin opens
**Admin → Clients → the client**, searches a Highway on-chain name or numeric ID,
selects the result and clicks **Assign relayer**. A client with several assignments
can search and switch between those relayers on their dashboard.

Monitors and Super admins can use **Dashboard → Request a relayer** to submit their exact
Highway name or numeric ID (including copied IDs such as `#457`). The server
checks the identity against Highway's feed and saves a pending request. The
customer can see its status or cancel it; a request never grants relayer access.
The dashboard continues to work for accounts without a linked HYN machine.

Super admins review these under **Admin → Clients → Relayer requests**. Verify
ownership, then choose **Approve relayer** or **Decline**. Approval checks the
current provider identity again and performs the assignment and request update
in one database transaction. Direct assignment from a client's view also closes
their matching pending request. Suspended clients cannot submit requests or be
approved. Pending requests appear as a badge on the Clients tab.

Client navigation, tab selection and browser history now use the URL consistently,
so opening a client reveals its assignment controls without a page reload.

## Install and run

1. Apply `../supabase/migrations/20260906143000_relayer_assignments.sql` to the
   existing Supabase project. Fresh projects can apply the updated
   `../supabase/schema.sql`. Prefer the focused migration for existing projects;
   the full schema also contains older, unrelated data migrations.
   Then apply `../supabase/migrations/20260909090000_relayer_requests.sql` to enable
   customer requests and the admin queue, followed by
   `../supabase/migrations/20260909120000_portal_roles.sql`. Apply these before
   deploying the portal. The role migration converts legacy admins to Super admins
   and legacy users to Monitors. Existing assignments are preserved; no relayers
   are automatically assigned. See [Portal roles](portal-roles.md). A missing request migration shows
   a setup notice while existing relayer readings remain available.
2. Run `pnpm install --frozen-lockfile` in `web-portal/`.
3. Run `pnpm dev` locally, or build/deploy the portal with `pnpm build`.
4. Sign in as an active Super admin and assign the correct IDs to clients.
   No assignment is seeded automatically, including the screenshot example #457.

Deployment smoke check: sign in as a customer with no assignment, request an
unassigned relayer, verify its pending state survives a refresh, then approve it
from a separate Super admin session after checking ownership. Refresh the
customer dashboard and confirm the assigned relayer appears. A normal customer
cannot approve requests or assign themselves from `/admin`.

The existing public Supabase URL and anon key remain the only required
configuration. No Highway password, session cookie, service-role key, or signing
key is needed by this integration. Outbound HTTPS to Highway and Mosaic must be
available on the portal server.

## Data sources and meaning

Verified against the provider on 6 September 2026:

- [Highway fleet feed](https://highwayp2p.com/api/fleet/relayers): names, IDs,
  registration, check-in/heartbeat timestamps, public device and package identity,
  location, relayer count and config version. This feed is currently public even
  though [the portal UI](https://highwayp2p.com/shop-v3/#/engine/network/relayers)
  requires login. The server forwards only the caller's assigned records.
- [Mosaic devnet registry](https://devnet-gw1.mosaicchain.io/MosaicNode2/chain):
  finalized registration, authorization, active set, delegated earning weight,
  public wallets/keys and account balances. This is the network used by the
  supplied Highway view; it is explicitly labeled **Mosaic devnet**. The reader
  uses chain metadata and makes no transactions. `HIGHWAY_MOSAIC_RPC_URL` can
  optionally point at another HTTPS gateway **on the same Mosaic devnet**.
- **Check-in age**: elapsed seconds since `lastCheckinAt`; fresh strictly below
  300 seconds. **Heartbeat age**: elapsed seconds since `lastHeartbeatAt`; fresh
  strictly below 660 seconds. Positive upstream flags cannot conceal overdue
  timestamps. Missing fields stay unknown.
- **Provider response latency**: the portal server's elapsed time to retrieve
  the provider response. It is not a relayer network ping. Existing HYN machine
  telemetry still reports machine latency independently.
- **Earning weight** is delegated weight, not currency per unit time. No hourly
  or daily earning rate is published by these sources, so that field says
  **Not published**. Token balances retain full precision internally; the compact
  display truncates to four decimal places and the full balance is in its title.
- A missing manager account is normal and distinct from an unavailable balance.
  LAN-only host data cannot be obtained from this public feed; HYN agent data
  remains in its own dashboard sections.

The UI refreshes every 30 seconds while visible. A shared in-process fleet cache
lasts 15 seconds; chain records last 45 seconds, with in-flight deduplication.
Only the selected assigned relayer triggers chain lookups on each refresh.
An observation older than two minutes becomes unverified. Errors keep the last
available snapshot with an explicit notice. Sign-out or suspended-account
responses clear the customer display. Caches are ephemeral and disappear on
server restart; the UI does not fabricate historical charts or earnings rates.

## Access boundaries

`relayer_assignments` links numeric provider IDs to portal owners. Each ID can
belong to only one account; removing it explicitly is required before a transfer.
The RLS policy permits reads by the active owner, staff, or accounts with an explicit dashboard share.
Authenticated users have no table write grants. Super-admin-only database functions
recheck roles and append assignment/removal events to the existing audit trail.

`GET /api/relayers` authenticates the session and loads owner-scoped assignments
through RLS before contacting providers. It never treats a customer-supplied
relayer ID as authorization. The optional `owner` parameter selects a shared dashboard or staff preview;
the database verifies access before any provider read. Responses are `private, no-store`.
`GET /api/admin/relayers?q=...` permits only active administrators to search the
provider directory and returns up to 30 small identity matches.

## Verification

```sh
pnpm test
pnpm exec tsc --noEmit
pnpm lint
pnpm build
# From the parent HYN-view repository:
bash supabase/run-tests.sh
HYN_TEST_MIGRATIONS=1 bash supabase/run-tests.sh
```

The relayer tests cover strict freshness thresholds, missing/stale data, false
flags, one-based registry bitmaps, integer precision, malformed feed responses,
owner isolation, suspended users, unauthorized writes/RPCs, duplicate assignments,
removal and audit attribution. Database tests use disposable local Postgres.
Request tests also cover customer isolation, cancellation, quotas, suspended
accounts, approval conflicts, direct assignment reconciliation and audit records.
Component tests reproduce client-tab navigation and request submission/cancellation;
route tests verify authentication, the public Heroku origin and provider-derived
identities. All database test identities are disposable local fixtures.

The portal is a separate Git repository under `web-portal/`; include its changes
and the parent repository's SQL migration when releasing this feature.
