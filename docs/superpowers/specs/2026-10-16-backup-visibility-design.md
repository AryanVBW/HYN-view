# Backup and security visibility by role — design

Date: 2026-10-16
Status: draft for review (nothing implemented yet)

## 1. Intent

Operators of the platform want the people who own servers (the *owner tier*) to
feel that the platform is calm and well looked after, and want serious
backup and security problems to reach the people who can act on them (the
*admin tier*) first, in full detail.

What was said:

- Backup creation and the automatic backups must be reported properly and kept
  up to date.
- A backup problem must not be shown to the owner as an alarm; it goes to
  admins in the web portal.
- The Highway **running state** is shown for real, to everyone.
- Do not change the colours or wording of the backup display when it is healthy.

What this design adds as assumptions (please correct):

- **Owner tier** = portal roles `viewer` and `monitor`. **Admin tier** = roles
  `maintainer`, `admin`, `super_admin` (the people for whom
  `hyn_can_view_fleet()` is true).
- The owner is never told a backup is protected when it is not. When anything
  is wrong the owner sees a neutral, non-alarming line, never a green
  "protected" state and never a made-up time.
- Because only the person on the machine can run `CREATE BACKUP` for the
  Highway recovery bundle, admin visibility has to be hard to miss: an
  immediate email and a repeat reminder every 3 days while the issue stays
  open.

Out of scope: the CLI running on a user's own machine (it is theirs and keeps
showing their own state), the Highway account-side copy of the bundle (not
checkable from the server), billing, and any colour or layout change to the
healthy backup display.

## 2. Why the boundary must be in the database

Today the `metrics_select_own` policy lets anyone with dashboard access read the
whole `metrics.payload` jsonb, and `alert_events_select_own` lets them read
every alert row. Hiding something only in the React components would leave it
readable through the API. So the split is enforced in Postgres, and the UI is
built on top of it.

## 3. Architecture

Four units, each with one job.

### 3.1 CLI payload (`lib/cloud.sh`, `lib/highway.sh`)

Already sent: `backup_present`, `backup_age_s`, `backup_size`, `backup_stale`,
`backup_perms_ok`, `backup_magic_ok` (inside the `highway` object).

Add a top-level `backups` object, scalars only, from the collector built for
the simple view (`bk_local_sample`):

```
"backups": {
  "sys_present": true,  "sys_ts": 1792110000, "sys_size": 3145728, "sys_count": 7,
  "sys_offsite_ts": 1792110120,
  "loc_present": true,  "loc_ts": 1792150000, "loc_count": 24
}
```

Add alert rules, same pattern as `hw_no_backup` in `lib/alerts.sh`:
`bk_sys_late` (warn after 36h, crit after 72h) and `bk_offsite_late` (same
thresholds, only when an off-site stamp exists).

### 3.2 Database (`supabase/migrations/20261016120000_backup_visibility.sql`)

Additive and idempotent, like the previous migrations.

1. **`node_backup_status`** — one row per node: `node_id` (PK, FK to `nodes`),
   `updated_at`, `detail jsonb`. RLS: `select` only where
   `public.hyn_can_view_fleet()`. No owner-tier grant.
2. **Split trigger on `metrics`** — `before insert`, security definer. Moves
   `payload->'backups'` and `payload->'highway'->backup_*` into
   `node_backup_status` (upsert) and removes them from `NEW.payload`, so the
   row owners can read never contains them. A one-time statement in the same
   migration scrubs the existing rows (the fields have only existed since
   `20261014140000_highway_operations.sql`).
3. **Alert audience** — add `alert_events.audience text not null default
   'owner' check (audience in ('owner','admin'))` and a small table
   `alert_rule_audience(rule text primary key, audience text)`; a `before
   insert` trigger on `alert_events` sets the audience from it. Initial
   admin-only rules: `hw_no_backup`, `hw_backup_stale`, `hw_backup_unsafe`,
   `bk_sys_late`, `bk_offsite_late`, `hw_killswitch`, `hw_api_cert`. Rules that
   describe the running state (`hw_failed`, `hw_inactive`, `hw_not_running`,
   `hw_tunnel_down`, `hw_restarts`, `hw_journal_err`, …) stay `owner` and are
   shown for real. Replace `alert_events_select_own` with
   `using (hyn_can_view_node(node_id) and (audience = 'owner' or
   hyn_can_view_fleet()))`.
4. **Counts and summaries** — every function or view that counts or lists
   `alert_events` for an owner (the `alerts_open` counters and the 7-day alert
   lists) filters `audience = 'owner'` unless the caller is admin-tier.
   Implementation plan must enumerate each one; none may be left behind.
5. **`hyn_backup_card(p_node uuid) returns jsonb`** — security definer, checks
   `hyn_can_view_node(p_node)`. Returns only:
   `{"state":"protected","taken":{...times...}}`,
   `{"state":"refreshing"}`, or `{"state":"none"}` (no backup source exists on
   this node at all, so the card is hidden). Times are returned **only** for
   `protected`, because the time of a stale backup is itself the problem.
   `protected` means every source that exists is healthy by the rules in 3.3.

### 3.3 Status rules (`web-portal/lib/backup-status.ts`)

Pure functions, no I/O, mirrored by the SQL function in 3.2.5 and tested against
the same table of cases so the two cannot drift.

| Source | Healthy when |
|---|---|
| Recovery bundle (Highway nodes only) | present, header valid, owner-only permissions, not stale (keys changed within a 6h grace) |
| System backup | newest stamp not older than 36h |
| Off-site copy | stamp present and not older than 36h (only judged when an off-site stamp exists) |
| Local snapshot | newest not older than 24h |

`backupIssues(detail, now)` returns the admin list (plain-language reason,
severity, how long it has been open). `ownerCard(detail, now)` returns one of
`protected`, `refreshing`, `none`. Invariants, each with a test:

- `protected` is returned if and only if `backupIssues` is empty and at least
  one source exists.
- The owner card contains no issue text, no severity and no times unless
  `protected`.
- A value that cannot be read is an issue, never healthy.

### 3.4 Portal UI

- **Owner**: a `Backup` card (`components/dashboard/backup-card.tsx`). Healthy:
  the existing green styling and wording, listing each source's real time.
  Refreshing: neutral grey, "Backup is being refreshed by our team. No action
  needed." No red, no detail.
- **Admin**: backup and security issues appear in the fleet "needs attention"
  panel (extend `concernsFor` in `lib/fleet-monitor.ts` with the backup issues)
  and in a per-server backup section on the admin page, with times, sizes,
  counts, and the exact reason.
- **Running state**: `HighwayState`, `servicesVerdict` and the existing unit
  display are untouched and identical for every role.
- **Parsing**: `lib/highway.ts` stays as it is. The backup detail is read by
  `backup-status.ts` from `node_backup_status`, not from the metrics payload.

### 3.5 Emails and reminders

- Incident email for an `admin`-audience alert goes to admin-tier recipients
  only, not the node owner. The existing owner delivery path
  (`lib/scheduled-email.ts`, `incident` kind) skips those rules; an admin
  fan-out is added with the same delivery controls and templates. The plan
  must confirm which recipients the current admin delivery settings produce.
- The existing outage sweep job gains a reminder: while an admin-audience
  backup alert for a node is still open, email admins at most once every 3
  days, and show "open for N days" in the portal.

## 4. Error handling

- Unreadable or absent backup detail for a node that reports a Highway process:
  treated as an issue for admins ("no backup information received") and
  `refreshing` for the owner. Never `protected`.
- Older agents that do not send `backups` still send the `backup_*` fields;
  the recovery rule works from those alone and the other sources are simply
  absent, not failing.
- The split trigger must never reject a metrics insert. On any parse failure it
  still inserts the row, with the backup fields removed on a best-effort basis
  (never left in), and records the problem through the existing ingest warning
  path, so telemetry keeps flowing and nothing admin-only leaks.

## 5. Testing

- `web-portal/lib/backup-status.test.ts`: the rule table, the three
  invariants, boundary ages, unreadable values, a Highway node with no backup,
  a non-Highway node with only a system backup.
- `supabase/backup-visibility-test.sql` (run by `supabase/run-tests.sh`):
  an owner-tier user cannot select `node_backup_status`; cannot see
  `backups` or `backup_*` in `metrics.payload`; cannot see admin-audience
  alert rows or counts; can call `hyn_backup_card` and gets no detail while
  `refreshing`; an admin-tier user sees everything; running-state alerts remain
  visible to owners.
- `test/selfcheck.sh` and `test/cloud-integration.sh`: the new `backups`
  payload fields and the two new alert rules.
- Existing portal and CLI suites must stay green.

## 6. Open points for review

1. The admin-only rule list in 3.2.3 (backup rules, `hw_killswitch`,
   `hw_api_cert`). Anything else that should be admin-only, or any of these that
   owners should see?
2. Thresholds: 36h system, 24h local, 6h stale-key grace, 3-day reminder.
3. Whether a `refreshing` state that lasts a long time (for example 14 days)
   should eventually show the owner the one-step note, since only they can run
   `CREATE BACKUP`. This design says no; admins are expected to act.
4. Which roles receive admin incident emails.
