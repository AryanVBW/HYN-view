# Rolling Cloud Telemetry With Local Backup

> Superseded by the user's 2026-09-12 correction: cloud retention is **48 hours**,
> and bounded HYN operational summaries plus dashboard details are copied to
> cloud and local storage. See [implemented policy](../../rolling-monitoring.md).
> The 72-hour proposal below is retained as design history, not the active policy.

## Goal

Make the hosted dashboard the primary, dependable view of every linked server while keeping long-term and sensitive history on the server itself. Supabase retains only the most recent 72 hours of dashboard-safe telemetry. The existing local archive remains an independent, longer-lived backup and supplies a bounded retry queue when cloud delivery fails.

## Product behavior

- Every linked, active server sends lightweight liveness beats through the hosted web portal.
- The portal dashboard updates the visible heartbeat age every second and refreshes immediately enough to show newly delivered readings without manual action.
- Full dashboard readings are sampled and uploaded at a resource-conscious interval, initially one minute. A one-second UI clock must not create one-second database writes.
- Supabase contains a rolling 72-hour telemetry window. Readings older than 72 hours are deleted automatically.
- Full local history continues for the configured local retention period and size cap. Logs, process details, service diagnostics, report artifacts, and backup material remain local only.
- Local-mode temporary snapshot messaging is removed from normal linked-server dashboards because cloud telemetry becomes the managed default.
- Existing local history is never deleted during upgrade or mode migration.

## Architecture

### Agent and portal contract

The resident agent keeps the stable unattended loop introduced in CLI 1.8.0. It sends a small heartbeat to the web portal every 24 seconds. The portal authenticates the node token and writes only node status, agent version, and heartbeat time through the existing Supabase RPC. The browser never talks directly to a server.

The agent records each scheduled dashboard snapshot locally before attempting upload. The cloud payload is reduced to fields required by the dashboard: CPU, memory, disk, temperature sensors, network rates and link state, uptime, pressure, connection counters, and aggregate health. It excludes process rows, service output, logs, notification bodies, credentials, and local report contents.

### Local backup and recovery

The existing bounded JSONL archive remains the long-term local record. A separate bounded outbox tracks dashboard snapshots whose upload failed. Successful upload acknowledges the corresponding outbox item. On later check-ins, the agent retries oldest-first with a strict batch limit so reconnection cannot overload the server or Supabase. Duplicate delivery is safe through a stable node-and-sample timestamp identity.

The outbox obeys the same local size protections and never blocks fresh heartbeat delivery. Permanent authorization failures stop retries and surface an actionable local status; transient network and 5xx failures remain queued.

### Supabase retention

Metrics use a unique node/sample identity to make retries idempotent. Ingestion upserts that identity and opportunistically removes rows older than 72 hours for the authenticated node. A database cleanup function removes expired metrics fleet-wide and is callable only by the service role. The existing hosted scheduled job calls it at the platform-supported cadence. This combination prevents unbounded growth even if a scheduled cleanup is delayed.

Associated high-volume dashboard samples, including speed-test rows where applicable, follow the same 72-hour policy. Account, node, access-control, billing, audit, notification, and assignment records are not telemetry and are outside this deletion policy.

### Dashboard freshness

The dashboard reads rolling metrics from Supabase for cloud-managed nodes. The heartbeat indicator already advances locally every second. The page refresh controller uses a visibility-aware interval and avoids requests in hidden/offline tabs. New telemetry replaces stale panels as soon as the next refresh completes. “History stays on … Request a reading …” is reserved only for an explicit privacy/local-only override, not the managed default.

## Defaults and compatibility

- Managed linked installations default to `cloud_storage=cloud`.
- Heartbeat cadence defaults to 24 seconds, preserving the stable 1.8.0 behavior.
- Dashboard snapshot cadence defaults to one minute and remains configurable upward.
- Existing nodes in local mode are migrated to cloud mode through the normal portal configuration pull unless an explicit root-owned privacy override is present.
- Older agents continue to work with existing endpoints. New database functions and columns are additive, and the portal tolerates agents that do not yet support outbox replay.

## Resource controls

For each server, one-minute telemetry creates at most 4,320 retained metric rows. Heartbeats update the node record rather than appending rows. The portal queries indexed `(node_id, ts)` ranges with fixed limits. Cleanup deletes in bounded batches, payload size stays capped, retries are rate-limited, and hidden browser tabs do not poll.

These controls target Supabase's free tier without making a contractual claim about a particular account's quota. Fleet usage remains visible through the existing cloud-usage diagnostics.

## Failure behavior

- Portal or network unavailable: heartbeat reports degraded locally; snapshots remain in the bounded outbox.
- Supabase ingestion unavailable: the portal returns a retryable failure and stores no process-local substitute.
- Agent restarts: local archive and outbox survive.
- Duplicate retry: the database upsert prevents duplicate chart points.
- Retention cleanup delayed: per-node opportunistic pruning limits growth until fleet cleanup resumes.
- Node paused, suspended, or revoked: ingestion and retry stop according to the current authorization state.

## Security and privacy

The node token remains the ingestion credential. RLS and RPC authorization remain the data boundary. Users see only nodes granted through existing ownership and server-access policies. Supabase never receives secrets, command output, raw logs, process listings, notification content, or long-term backups. Retention deletion is enforced server-side rather than trusted to browsers or agents.

## Verification

- Shell tests cover defaults, heartbeat scheduling, archive-before-upload ordering, outbox retry limits, idempotency, and permanent versus transient failures.
- SQL tests cover authorization, payload reduction, upsert behavior, 72-hour boundaries, bounded cleanup, and RLS isolation.
- Portal tests cover cloud-first empty states, second-by-second heartbeat presentation, visibility-aware refresh, and retained access boundaries.
- Migration-upgrade tests cover an older schema and existing local-mode nodes without deleting local data.
- A production verification checks the applied migration, authenticated ingestion, row counts and age bounds, portal rendering, and remote deployment revision separately.

## Delivery boundary

Implementation is complete only after local tests pass, the Supabase migration is applied and verified, the CLI and portal revisions are published, the portal deployment is live, and at least one real node produces a fresh dashboard reading while retaining its local archive. Each boundary is reported independently.
