# Heartbeat, Web Alerts, Sync, and Admin Control Design

## Purpose

HYN-view must make a linked machine feel continuously connected without turning
every install into a high-frequency request generator. Users need an immediate
full synchronization control and an observable update flow. Administrators need
audited controls to send a current report to one client and update that client's
machines. All managed email must use the portal's Resend environment, share the
site's visual identity, and be active by default after linking.

## Decisions

- A machine performs one real portal heartbeat per minute. The dashboard updates
  the displayed elapsed time every second from the last durable heartbeat.
- Full telemetry remains controlled by `cloud_push_min` and is never collected
  every second. A `sync` command bypasses that interval exactly once.
- The existing owner-scoped command queue supports both `update` and `sync`.
- A link with no explicit local notification channel enables the `web` channel.
  Existing operator-selected local channels are preserved.
- The portal owns managed delivery credentials. The CLI never receives a Resend
  key, sender address, service-role key, or user email address.
- Administrator policy supplies defaults. Users retain control of recurring
  incident, daily-health, and system-information schedules.
- One-time administrator report and update actions are authoritative, scoped to
  the selected client/machine, idempotent, and recorded in `admin_audit`.
- `hyn-view@1.7.0` remains unpublished until the operator performs the npm release.

## Liveness Model

`hyn_fetch_config()` already runs from `hyn-push.timer` every minute. It becomes
the canonical heartbeat by updating `nodes.last_heartbeat_at`, independently of
the more expensive telemetry `last_seen_at`. Fleet freshness and quiet-machine
warnings use `last_heartbeat_at`; charts continue to use `last_seen_at`.

The dashboard receives the last heartbeat as an ISO string. A small client
component renders `Connected · 18s ago`, `Delayed · 2m 12s`, or `Gone quiet`
and recalculates only the text once per second. It does not fetch once per second.
The existing once-per-minute page refresh obtains the next durable heartbeat.

A durable Vercel Workflow watchdog is started once per real node. It sleeps for
one minute, checks the heartbeat, and records transitions after three missed
intervals. It sends one offline message and one recovery message, not repeated
mail for every check. The workflow exits for revoked/demo nodes and otherwise
continues. Database claims prevent duplicate watchdogs.

## Command Protocol

`node_commands.command` accepts `update` and `sync`. Shared states are `queued`,
`running`, `succeeded`, `failed`, and `expired`.

Update stages remain:

1. queued
2. accepted
3. checking
4. installing
5. restarting
6. verifying
7. completed

Sync stages are:

1. queued
2. accepted
3. collecting
4. uploading
5. verifying
6. completed

The one-minute heartbeat claims at most one command. Update reinstalls the latest
package even when already current, reapplies setup, restarts every enabled HYN
timer, verifies units and the installed version, and immediately sends a complete
snapshot. Sync collects all system/network/process/temperature/speed/service data,
uploads it regardless of `cloud_push_min`, verifies ingest, and updates the
command with the received telemetry time.

Commands use leases and can be safely reclaimed after a crash. Owner and admin
request RPCs are idempotent. Admin requests additionally write the actor, client,
node, action, and requested version to `admin_audit`.

## Web Alert Channel

The CLI gains `web` as a notification channel. It serializes a bounded event
containing category, severity, subject, plain text, safe generated HTML, and a
stable event fingerprint. It submits through the existing agent gateway using
the node token. The portal stores an idempotent delivery job and dispatches it
through Resend after the response. A failed after-task remains queued and is
retried on the next heartbeat.

The web event cannot set a recipient or sender. The portal resolves the node's
owner and `email_preferences`, applies the relevant administrator template, and
uses `RESEND_API_KEY` and `EMAIL_FROM` from Vercel. Delivery success or failure is
written to `notification_log`.

## Email System

A single email-shell renderer provides the HYN-view identity for every managed
message: near-black terminal canvas, cyan status rail, amber warning state,
monospace telemetry labels, Sentient-like serif fallback headings, inline styles,
table layout, no remote images, and readable plain structure when CSS is stripped.

It wraps:

- welcome/sign-in security notices;
- device-linked confirmation;
- first full system report;
- immediate web alerts and recovery notices;
- daily health and daily system inventory;
- manual synchronization completion;
- CLI update completion/failure;
- administrator-triggered current reports.

The admin template editor continues to control alert, report, and system bodies.
The common shell is always applied, so a malformed/custom wrapper cannot remove
brand, sender identity, or required incident content. Subjects, hostnames, IPs,
and all telemetry values are escaped. Resend calls use durable idempotency keys.

## User Dashboard

The machine header adds a compact connection pulse based on heartbeat time. A
machine-control panel offers `Sync now` and `Update CLI`. Either opens one proper
modal rather than expanding an inline panel. The modal contains:

- requested action and machine name;
- installed and available versions when applicable;
- ordered stage list with one active stage;
- latest server message and last progress time;
- a visible failure recovery instruction;
- close only after a terminal state, plus a background-safe close affordance;
- automatic dashboard refresh after successful sync/update.

Reduced-motion users receive a static pulse and stage icon. The modal traps focus,
closes with Escape only when safe, restores focus to the triggering button, and
uses `aria-live` for progress.

## Administrator Dashboard

The fleet keeps its per-version counts and adds registry-latest comparison.
Each machine row can open the same update modal through an admin-scoped request.
The selected client control room adds:

- `Send report now`: sends one current themed report to the client's configured
  recipient. The report contains every active machine, current metrics, open
  alerts, heartbeat age, installed/latest versions, network, temperature,
  storage, speed-test, process, and managed-service information.
- `Sync selected machine`: queues a full current snapshot.
- `Update selected machine`: repairs/updates one machine.
- `Update outdated machines`: queues one update per outdated active machine for
  the selected client after confirmation.

Report generation is a server action backed by an admin-only RPC/service query.
It returns a delivery result to the UI and logs the exact audit and notification
records. Empty telemetry, unavailable sensors, inactive nodes, missing recipients,
Resend failures, and partially queued bulk updates are reported explicitly.

## Error Handling and Recovery

- Every mutation validates authentication, ownership/admin role, active node,
  UUIDs, command kind, stage transitions, body size, and message length.
- Database unique keys deduplicate active commands, watchdogs, alert jobs, manual
  reports, and email sends.
- Agent HTTP calls keep bounded curl timeouts and retries. Systemd invokes the
  agent again after one minute, so a crash is self-recovering.
- Update failure preserves the installed package and reports the first failing
  setup, timer, or verification step. A later update request is also a repair.
- Sync failure never replaces the last good chart value and states whether
  collection or upload failed.
- Offline status is based on heartbeat, not assumed power state.
- No admin action exposes node tokens or email-provider credentials.

## Migration and Compatibility

The migration backfills `last_heartbeat_at` from `last_config_pull_at` or
`last_seen_at`, expands command constraints, creates web-delivery/watchdog state,
and installs owner/admin RPCs. Existing 1.6/1.7 agents continue to ingest and pull
configuration; they simply do not claim `sync` or send web-channel events until
updated. The portal labels such machines as requiring the new agent.

The deployment order is migration, portal deployment, then later npm publication.
The portal must tolerate legacy payloads and unknown versions throughout rollout.

## Verification

- SQL flow tests cover heartbeat ownership, stale transitions, command isolation,
  admin auditing, idempotent report jobs, and web-alert tenant isolation.
- Shell tests cover linked default `web`, heartbeat/check-in, sync stage order,
  update repair, retry behavior, and bounded payloads.
- Portal unit tests cover heartbeat states, modal stage models, themed/escaped
  emails, report aggregation, admin authorization, and retry/idempotency helpers.
- Full CLI, migration-chain, schema, portal test, lint, and production build gates
  run before commits and again after merges.
- Production is checked with the current Vercel CLI: READY deployment, aliases,
  public pages, auth boundaries, Workflow routes, API errors, and runtime error
  logs. Supabase local/remote migration lists must match.
- npm registry must still report `1.6.0` at handoff.
