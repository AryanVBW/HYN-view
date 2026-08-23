# Heartbeat, Web Alerts, Sync, and Admin Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe one-minute liveness, immediate full synchronization, portal-managed web alerts, themed lifecycle email, and audited administrator report/update controls.

**Architecture:** Extend the existing token-authenticated Supabase RPC contract and command queue; keep the CLI as the only collector and the portal as the only managed email sender. Use Vercel Workflow for durable command/watchdog timing, Server Components for initial reads, authenticated route handlers/server actions for mutations, and focused client components for the one-second freshness display and accessible progress modal.

**Tech Stack:** Bash 5, systemd timers, PostgreSQL/Supabase RLS and SECURITY DEFINER RPCs, Next.js 16 App Router, React 19, TypeScript, Vercel Workflow 4.8, Resend, pnpm/node:test.

**Spec:** `docs/superpowers/specs/2026-08-24-heartbeat-alert-admin-control-design.md`

## Global Constraints

- Real heartbeat interval is exactly one minute; the browser alone updates elapsed text every second.
- Full telemetry is never collected every second.
- Existing local notification channels are preserved; `web` is added only when a linked install has none.
- Resend credentials and recipients never reach the CLI.
- Every owner/admin mutation is tenant-scoped, idempotent, and admin actions are audited.
- Existing agents remain compatible with ingest and configuration pull.
- `hyn-view@1.7.0` is not published to npm in this execution.

---

### Task 1: Heartbeat and generalized command schema

**Files:**
- Create: `supabase/migrations/20260824023000_heartbeat_sync_web_alerts.sql`
- Modify: `supabase/schema.sql`
- Modify: `supabase/flow-test.sql`
- Modify: `supabase/migration-upgrade-test.sql`

**Interfaces:**
- Produces: `nodes.last_heartbeat_at timestamptz`, generalized `node_commands.command`, `hyn_request_node_command(uuid,text)`, `hyn_admin_request_node_command(uuid,text)`, heartbeat/watchdog claim RPCs, web-notification queue RPCs, and admin report claim/audit RPCs.

- [ ] **Step 1: Write failing SQL flow assertions**

Add checks that config pull changes `last_heartbeat_at`, Alice cannot request Bob's command, an admin can request `sync`/`update` with an audit row, active commands deduplicate per kind, and web alerts cannot select a recipient.

- [ ] **Step 2: Verify the migration-chain test fails**

Run: `HYN_TEST_MIGRATIONS=1 npm run test:db`

Expected: FAIL because `last_heartbeat_at` and the generalized RPCs do not exist.

- [ ] **Step 3: Implement the migration and canonical schema**

Use explicit check constraints:

```sql
check (command in ('update', 'sync'))
check (stage in ('queued','accepted','checking','installing','restarting',
                 'collecting','uploading','verifying','completed','failed','expired'))
```

Backfill heartbeat with `coalesce(last_config_pull_at,last_seen_at,created_at)`. Keep
one partial unique active command per `(node_id, command)`. Security-definer RPCs
must verify owner/admin/node token internally and expose no token hash.

- [ ] **Step 4: Run schema and migration tests**

Run: `npm run test:db && HYN_TEST_MIGRATIONS=1 npm run test:db`

Expected: both modes report all checks passed.

- [ ] **Step 5: Commit the database contract**

Stage only the four listed paths and commit `feat(cloud): add heartbeat and sync contract`.

### Task 2: CLI heartbeat, web default, and sync execution

**Files:**
- Modify: `lib/core.sh`
- Modify: `lib/cloud.sh`
- Modify: `lib/notify.sh`
- Modify: `bin/hyn`
- Modify: `test/cloud-integration.sh`
- Modify: `test/cloud-mock.py`
- Modify: `test/selfcheck.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: generalized claim/report RPCs from Task 1.
- Produces: `cloud_command_sync`, `ch_web`, `cloud_web_notify`, immediate full ingest and sync progress.

- [ ] **Step 1: Add failing shell tests**

Test that linking with empty channels writes `notify_channels=web`, an existing
`smtp` setting remains unchanged, `sync` reports collecting/uploading/verifying,
an update still reports its original stage order, and a successful command causes
ingest even when the normal interval is not due.

- [ ] **Step 2: Verify the tests fail for missing behavior**

Run: `npm test`

Expected: FAIL at the new web-default/sync assertions.

- [ ] **Step 3: Generalize command dispatch**

Parse `action` as `update|sync`. For sync:

```bash
cloud_command_report running collecting 'Collecting a complete system snapshot'
alerts_collect && alerts_evaluate
cloud_command_report running uploading 'Uploading current telemetry to HYN-view'
# build and ingest the same bounded payload used by cloud_push
cloud_command_report running verifying 'Confirming the new reading reached the portal'
```

Refactor collection/ingest into reusable functions so normal push, sync, and
post-update refresh share one implementation.

- [ ] **Step 4: Add the web notification channel**

`ch_web` calls the agent gateway with a bounded JSON event and returns success only
after the portal accepts the durable job. It never sends `notify_to` or a provider
secret. `cloud_link` sets web only when `notify_channels` is empty.

- [ ] **Step 5: Run shell and cloud suites**

Run: `bash -n bin/hyn lib/*.sh test/*.sh && npm test`

Expected: syntax clean; all selfcheck and cloud integration checks pass.

- [ ] **Step 6: Commit the agent behavior**

Commit `feat(agent): add heartbeat sync and web alerts`.

### Task 3: Portal domain models and API contract

**Files:**
- Modify: `web-portal/lib/agent-api.ts`
- Modify: `web-portal/lib/agent-api.test.ts`
- Replace: `web-portal/lib/node-update.ts` with generalized `node-command.ts`
- Replace: `web-portal/lib/node-update.test.ts` with `node-command.test.ts`
- Modify: `web-portal/app/api/nodes/update/route.ts`
- Create: `web-portal/app/api/nodes/sync/route.ts`
- Create: `web-portal/app/api/admin/nodes/command/route.ts`

**Interfaces:**
- Produces: `NodeCommand`, `CommandKind`, `COMMAND_STEPS`, `normalizeNodeCommand`, `commandIsActive`, owner/admin command route responses.

- [ ] **Step 1: Write failing TypeScript model tests**

```ts
assert.deepEqual(commandSteps("sync").map((step) => step.key),
  ["queued", "collecting", "uploading", "verifying", "completed"]);
assert.equal(normalizeNodeCommand({ command: "erase", ...valid }), null);
```

- [ ] **Step 2: Run focused tests and observe RED**

Run: `pnpm test`

Expected: FAIL because sync/admin command helpers and routes are absent.

- [ ] **Step 3: Implement the generalized model and routes**

Owner routes call `hyn_request_node_command`; admin route calls
`hyn_admin_request_node_command`. Return 202 with `Cache-Control: no-store` and
normalize only known kinds/statuses/stages. Keep Node.js runtime.

- [ ] **Step 4: Verify GREEN**

Run: `pnpm test && pnpm lint`

Expected: all tests pass and lint exits zero.

- [ ] **Step 5: Commit the portal command API**

Commit `feat(api): generalize machine commands` in the portal repository.

### Task 4: Heartbeat indicator and accessible command modal

**Files:**
- Create: `web-portal/lib/heartbeat.ts`
- Create: `web-portal/lib/heartbeat.test.ts`
- Create: `web-portal/components/dashboard/heartbeat-indicator.tsx`
- Create: `web-portal/components/dashboard/machine-command-modal.tsx`
- Modify: `web-portal/components/dashboard/agent-update-control.tsx`
- Modify: `web-portal/app/dashboard/page.tsx`
- Modify: `web-portal/app/globals.css`

**Interfaces:**
- Produces: `heartbeatState(iso,now)`, `HeartbeatIndicator`, `MachineCommandModal`, Sync/Update triggers.

- [ ] **Step 1: Write failing heartbeat state tests**

Assert connected below 90 seconds, delayed below 180 seconds, and quiet at/above
180 seconds, with invalid/missing timestamps reported as unknown.

- [ ] **Step 2: Verify RED**

Run: `pnpm test`

Expected: FAIL because `heartbeatState` is missing.

- [ ] **Step 3: Implement the state helper and indicator**

The component receives an ISO string, uses a one-second local interval only for
text, and never fetches. Respect `prefers-reduced-motion` in CSS.

- [ ] **Step 4: Implement the modal and controls**

Use the existing Dialog primitive if present; otherwise use a fixed accessible
dialog with focus management. Poll the command API every two seconds only while
active. Show action-specific stages, last progress time, close/background rules,
and exact recovery commands on failure.

- [ ] **Step 5: Verify UI code**

Run: `pnpm test && pnpm lint && pnpm build`

Expected: tests/lint/build exit zero and all Workflow routes remain present.

- [ ] **Step 6: Commit user controls**

Commit `feat(dashboard): add heartbeat and sync modal`.

### Task 5: Durable web email delivery and themed shell

**Files:**
- Modify: `web-portal/lib/cloud-email.ts`
- Modify: `web-portal/lib/cloud-email.test.ts`
- Modify: `web-portal/app/api/agent/v1/[action]/route.ts`
- Modify: `web-portal/app/auth/callback/route.ts`
- Modify: `web-portal/app/api/email/device-linked/route.ts`
- Modify: `web-portal/app/api/cron/email/route.ts`
- Create: `web-portal/workflows/heartbeat-watchdog.ts`
- Create: `web-portal/lib/web-notification.ts`
- Create: `web-portal/lib/web-notification.test.ts`

**Interfaces:**
- Produces: `renderHynEmailShell`, `dispatchQueuedWebNotification`, heartbeat watchdog and offline/recovery delivery.

- [ ] **Step 1: Add failing email tests**

Assert every lifecycle builder renders the same terminal shell, escapes hostile
hostname/subject values, contains no remote images/scripts/forms, and preserves
Unavailable for absent sensors. Assert one alert fingerprint sends once.

- [ ] **Step 2: Verify RED**

Run: `pnpm test`

Expected: FAIL because the shared shell and durable dispatcher are absent.

- [ ] **Step 3: Implement the shared renderer**

Use inline tables and the palette from the spec. Apply the administrator body
template first and the immutable shell second. Migrate sign-in, link, first,
cron, command, and incident emails to the renderer.

- [ ] **Step 4: Implement queued web dispatch**

After accepted agent web events, claim a job, resolve recipient server-side,
send with Resend, and complete/release it. Include `Idempotency-Key` using the
database job id. Retry one queued job on each heartbeat.

- [ ] **Step 5: Implement the durable heartbeat watchdog**

Start once per node, sleep one minute, query the durable heartbeat in a step,
send only state transitions after three misses, and end for revoked/demo nodes.

- [ ] **Step 6: Verify email/workflow behavior**

Run: `pnpm test && pnpm lint && pnpm build`

Expected: tests clean; build reports both node-update and heartbeat workflows.

- [ ] **Step 7: Commit managed email behavior**

Commit `feat(email): route alerts through themed web delivery`.

### Task 6: Audited administrator reports and machine controls

**Files:**
- Create: `web-portal/lib/admin-report.ts`
- Create: `web-portal/lib/admin-report.test.ts`
- Modify: `web-portal/app/admin/actions.ts`
- Create: `web-portal/components/admin/client-actions.tsx`
- Modify: `web-portal/components/admin/client-dashboard.tsx`
- Modify: `web-portal/components/admin/tables.tsx`
- Modify: `web-portal/components/admin/agent-versions.tsx`
- Modify: `web-portal/app/admin/page.tsx`

**Interfaces:**
- Produces: `buildAdminClientReport`, `sendAdminClientReport`, admin Sync/Update/Update outdated UI.

- [ ] **Step 1: Write failing aggregation tests**

Build a two-machine fixture and assert one report includes each machine's
heartbeat, version, alerts, CPU/memory/disk/temp, network, speed, services, and
explicit unavailable fields.

- [ ] **Step 2: Verify RED**

Run: `pnpm test`

Expected: FAIL because `buildAdminClientReport` is missing.

- [ ] **Step 3: Implement the pure report builder**

Return escaped HTML content for the common email shell and a deterministic
subject. Keep database queries and Resend outside the pure function.

- [ ] **Step 4: Implement audited server actions**

`sendAdminClientReport(clientId)` rechecks admin, loads all active real nodes and
their latest metrics/open alerts/preferences, claims an idempotency key, sends,
logs delivery, and audits success/failure. Bulk update returns queued/skipped/
failed node arrays rather than hiding partial failure.

- [ ] **Step 5: Add client-control UI**

Add Send report now, Sync selected, Update selected, and Update outdated controls
to the selected client room. Reuse the command modal for progress; confirm bulk
updates with the exact machine count.

- [ ] **Step 6: Verify admin behavior**

Run: `pnpm test && pnpm lint && pnpm build`

Expected: all checks pass.

- [ ] **Step 7: Commit administrator controls**

Commit `feat(admin): add reports and machine updates`.

### Task 7: Deep local verification and migration dry run

**Files:**
- Modify only if a verification failure identifies a scoped defect.

- [ ] Run `bash -n bin/hyn lib/*.sh test/*.sh`.
- [ ] Run `npm test` and confirm all CLI/cloud checks pass.
- [ ] Run `npm run test:db` and migration-chain mode.
- [ ] Run `pnpm test`, `pnpm lint`, and `pnpm build` in `web-portal`.
- [ ] Run `git diff --check` in both repositories.
- [ ] Run `supabase db push --dry-run --linked`; confirm only the new migration.
- [ ] Run `npm pack --dry-run --json`; inspect package version/content but do not publish.
- [ ] Verify `npm view hyn-view version` still equals `1.6.0`.

### Task 8: Commit, PR, migrate, and deploy without npm

**Files:**
- No additional source files unless verification requires a fix.

- [ ] Push both `codex/heartbeat-admin-control` branches.
- [ ] Create ready GitHub PRs with exact verification evidence.
- [ ] Wait for required checks, inspect review findings, and merge both PRs.
- [ ] Run `supabase db push --linked`, then confirm local/remote migration parity.
- [ ] Deploy the merged portal with Vercel CLI 59.5.0 or newer.
- [ ] Do not run `npm publish`.

### Task 9: Post-deploy production re-verification

- [ ] Inspect the production deployment and aliases with Vercel CLI.
- [ ] Verify `/`, `/signin`, and auth boundaries with `vercel curl`.
- [ ] Verify Workflow flow/step routes are deployed.
- [ ] Verify unauthenticated owner/admin command routes return 401 and malformed requests return 400.
- [ ] Scan deployment runtime logs for errors and warnings since deployment.
- [ ] Verify the remote migration list includes the new migration exactly once.
- [ ] Verify both GitHub PRs are merged and repository heads contain expected commits.
- [ ] Verify npm remains at `hyn-view@1.6.0` and report the exact morning publish command without running it.
