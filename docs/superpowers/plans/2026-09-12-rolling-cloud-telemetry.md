# Rolling Cloud Telemetry Implementation Plan

> Execution scope updated by the user on 2026-09-12: use **48 hours**, cloud and
> local HYN operational summaries, bounded retry, VPS/container visibility and
> Ubuntu/ARM CI. See [current policy](../../rolling-monitoring.md). The earlier
> 72-hour plan below records the original proposal.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Supabase-backed 72-hour telemetry the primary dashboard source, with a durable local backup and bounded retry behavior.

**Architecture:** The CLI records every scheduled snapshot locally, sends dashboard-safe data through the hosted portal, and retains failures for bounded retry. Supabase stores idempotent samples for 72 hours and serves the dashboard; lightweight heartbeats update node liveness without appending heartbeat rows.

**Tech Stack:** Bash 4+, PostgreSQL/Supabase RLS and RPCs, Next.js 16 App Router, React 19, Node test runner

**Spec:** `docs/superpowers/specs/2026-09-12-rolling-cloud-telemetry-design.md`

## Global Constraints

- Supabase retains dashboard telemetry for exactly 72 rolling hours.
- Long-term history, logs, process details, diagnostics, reports, and backup material remain local.
- The local archive is written before cloud upload and survives network or portal failure.
- Managed linked installs default to cloud telemetry; an explicit root-owned local privacy choice remains respected.
- Heartbeats use the hosted portal and update one node row rather than appending history.
- Do not delete or overwrite existing local history during upgrade.
- Preserve compatibility with older agents and existing portal endpoints.

---

### Task 1: Enforce the 72-hour Supabase telemetry window

**Files:**
- Create: `supabase/migrations/20260912120000_rolling_telemetry_retention.sql`
- Modify: `supabase/schema.sql`
- Modify: `supabase/flow-test.sql`
- Modify: `supabase/migration-upgrade-test.sql`

**Interfaces:**
- Consumes: existing `public.hyn_ingest(jsonb)` node-token authorization and `(node_id, ts)` metric uniqueness.
- Produces: `public.hyn_prune_telemetry(p_before timestamptz default now() - interval '72 hours', p_batch integer default 5000) returns jsonb`; ingestion-time pruning for the authenticated node.

- [ ] **Step 1: Write failing SQL tests**

Add fixtures at 73 hours and 71 hours, ingest a duplicate timestamp, call the cleanup function as authorized and unauthorized roles, and assert that only expired `metrics`, `speedtests`, and dashboard `alert_events` are deleted while node/access/audit data remains.

- [ ] **Step 2: Run the SQL suite and confirm the new assertions fail**

Run: `npm run test:db`

Expected: failure because `hyn_prune_telemetry` and the 72-hour policy do not exist.

- [ ] **Step 3: Add the migration and canonical schema definitions**

Implement bounded deletes with indexed `ctid` selections, cap `p_batch` to `1..10000`, revoke execution from `public`, `anon`, and `authenticated`, and grant only `service_role`. Change `hyn_ingest` pruning from 30 days to 72 hours for the current node and cover metrics, speed tests, and alert events.

- [ ] **Step 4: Run SQL tests**

Run: `npm run test:db`

Expected: all database flow and migration-upgrade tests pass.

- [ ] **Step 5: Commit the retention boundary**

```bash
git add supabase/migrations/20260912120000_rolling_telemetry_retention.sql supabase/schema.sql supabase/flow-test.sql supabase/migration-upgrade-test.sql
git commit -m "feat(db): retain rolling telemetry for 72 hours"
```

### Task 2: Restore cloud-first managed defaults and safe payloads

**Files:**
- Modify: `lib/core.sh`
- Modify: `lib/setup.sh`
- Modify: `lib/cloud.sh`
- Modify: `bin/hyn`
- Modify: `test/selfcheck.sh`
- Modify: `test/cloud-integration.sh`
- Modify: `test/unattended.sh`

**Interfaces:**
- Consumes: `cloud_collect_full`, `local_store_snapshot`, `cloud_ingest_collected`, and root-owned configuration precedence.
- Produces: default `cloud_storage=cloud`, `cloud_push_min=1`, `heartbeat_sec=24`; `cloud_dashboard_payload_v()` that excludes process rows, logs, service output, and notification bodies.

- [ ] **Step 1: Write failing shell assertions**

Assert the three managed defaults, local-write-before-upload ordering, cloud payload exclusion of `processes.rows`, and preservation of an explicit local storage setting.

- [ ] **Step 2: Run focused tests and confirm failures**

Run: `bash test/selfcheck.sh && bash test/cloud-integration.sh && bash test/unattended.sh`

Expected: default and payload assertions fail against the local-first ten-minute configuration.

- [ ] **Step 3: Implement managed defaults and payload reduction**

Set cloud-first defaults, retain the local archive call in `cloud_collect_full`, and derive a dashboard-safe JSON object before `hyn_ingest`. Keep node token handling and the explicit local-mode transient route compatible.

- [ ] **Step 4: Run focused tests**

Run: `bash test/selfcheck.sh && bash test/cloud-integration.sh && bash test/unattended.sh`

Expected: all focused tests pass.

- [ ] **Step 5: Commit agent behavior**

```bash
git add lib/core.sh lib/setup.sh lib/cloud.sh bin/hyn test/selfcheck.sh test/cloud-integration.sh test/unattended.sh
git commit -m "feat(agent): make rolling cloud telemetry the managed default"
```

### Task 3: Add a bounded local delivery outbox

**Files:**
- Modify: `lib/local-store.sh`
- Modify: `lib/cloud.sh`
- Modify: `test/local-storage.sh`
- Modify: `test/cloud-integration.sh`

**Interfaces:**
- Produces: `local_outbox_enqueue(sample_id, payload)`, `local_outbox_peek(limit)`, and `local_outbox_ack(sample_id)` using root-only files under the existing local store.
- Consumes: stable sample timestamp as `sample_id`; `_cloud_rpc hyn_ingest` result classification.

- [ ] **Step 1: Write failing outbox tests**

Cover mode `0600`, FIFO order, duplicate sample replacement, acknowledgement, corrupt-line quarantine, maximum byte enforcement, retry batch cap, and retention of transient failures.

- [ ] **Step 2: Run focused tests and confirm failures**

Run: `bash test/local-storage.sh && bash test/cloud-integration.sh`

Expected: failures because the outbox functions are absent.

- [ ] **Step 3: Implement the outbox and retry loop**

Use the existing local-store lock, atomic replacement, and size accounting. Enqueue before upload, acknowledge on success, retry at most ten oldest items per check-in, stop on authorization failure, and continue later after retryable transport or server errors.

- [ ] **Step 4: Run focused tests**

Run: `bash test/local-storage.sh && bash test/cloud-integration.sh`

Expected: all outbox and cloud integration tests pass.

- [ ] **Step 5: Commit reliable delivery**

```bash
git add lib/local-store.sh lib/cloud.sh test/local-storage.sh test/cloud-integration.sh
git commit -m "feat(agent): retry cloud telemetry from local backup"
```

### Task 4: Make the portal cloud-first and visibly live

**Files:**
- Modify: `web-portal/app/dashboard/page.tsx`
- Modify: `web-portal/components/live-refresh.tsx`
- Modify: `web-portal/lib/live-refresh.ts`
- Modify: `web-portal/components/dashboard/heartbeat-indicator.tsx`
- Modify: `web-portal/tests/dashboard-page-api.test.ts`
- Modify: `web-portal/lib/live-refresh.test.ts`

**Interfaces:**
- Consumes: Supabase `metrics` rows and durable node heartbeat columns.
- Produces: visibility-aware 15-second data refresh and one-second client-side freshness labels without one-second server or database requests.

- [ ] **Step 1: Write failing portal tests**

Assert that cloud nodes without a reading show an honest first-report state, managed nodes never show the five-minute local-history warning, refresh defaults to 15 seconds, and heartbeat copy states that its elapsed clock updates every second.

- [ ] **Step 2: Run focused portal tests and confirm failures**

Run: `pnpm test -- lib/live-refresh.test.ts tests/dashboard-page-api.test.ts`

Working directory: `web-portal`

Expected: refresh cadence and cloud-first copy assertions fail.

- [ ] **Step 3: Implement live presentation behavior**

Change the refresh delay to 15 seconds, retain hidden/offline suppression, update heartbeat explanatory text to the 24-second cadence, and reserve the temporary snapshot message for explicit local-only nodes.

- [ ] **Step 4: Run portal tests and build**

Run: `pnpm test && pnpm build`

Working directory: `web-portal`

Expected: all tests and production build pass.

- [ ] **Step 5: Commit the nested portal repository**

```bash
git add app/dashboard/page.tsx components/live-refresh.tsx lib/live-refresh.ts components/dashboard/heartbeat-indicator.tsx tests/dashboard-page-api.test.ts lib/live-refresh.test.ts
git commit -m "feat(dashboard): show rolling cloud telemetry live"
```

### Task 5: Document, validate, publish, and verify production

**Files:**
- Modify: `README.md`
- Modify: `docs/local-storage-and-hosting.md`
- Modify: `docs/cli-release-readiness.md`
- Modify: parent gitlink for `web-portal`

**Interfaces:**
- Consumes: completed database, agent, and portal behavior.
- Produces: operator documentation and independently verified publication/deployment evidence.

- [ ] **Step 1: Update operator documentation**

Document the 72-hour cloud window, one-minute readings, 24-second heartbeat, local long-term backup, bounded retry behavior, and the fact that every-second freshness is client-side presentation rather than database ingestion.

- [ ] **Step 2: Run all local validation**

Run: `npm test`

Run: `pnpm test && pnpm build` in `web-portal`.

Expected: both complete suites pass.

- [ ] **Step 3: Commit documentation and parent gitlink**

```bash
git add README.md docs/local-storage-and-hosting.md docs/cli-release-readiness.md web-portal
git commit -m "docs: explain rolling cloud telemetry and local backup"
```

- [ ] **Step 4: Apply and verify Supabase migration**

Apply `20260912120000_rolling_telemetry_retention.sql` using the configured project workflow. Verify function privileges, authenticated ingestion, oldest retained timestamp, and rejection of unauthorized cleanup without exposing credentials.

- [ ] **Step 5: Publish and deploy**

Push the nested portal repository first, then the parent repository. Confirm remote SHAs. Verify the hosting deployment uses the pushed portal SHA and reaches a ready state.

- [ ] **Step 6: Perform a live node check**

Verify one real active node sends a fresh heartbeat and dashboard reading, the five-minute message is absent for the managed node, and its existing local archive remains readable. Report local, database, published, deployed, and live-node evidence separately.
