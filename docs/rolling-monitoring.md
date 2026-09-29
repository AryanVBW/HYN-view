# Rolling monitoring and local backup — CLI 1.10

Linked servers upload a scheduled reading to the HYN portal every minute by
default. The portal authenticates the server token and stores a bounded snapshot
in Supabase for **48 hours**. Every scheduled upload is saved locally first;
network failures do not erase that secondary copy.

## Data and freshness

- Cloud snapshots contain CPU, memory, disks, sensors, network, service health,
  supported VPS/container observations, alerts and HYN operational summaries.
- Operational summaries are timestamped status codes and counters. They describe
  collection, heartbeat/upload outcomes, active alerts and service issues.
  They are not a copy of all host journal files or application log text. HYN's
  raw local diagnostics remain accessible with `hyn logs`.
- The resident agent sends a heartbeat every 24 seconds (`heartbeat_sec`). The
  portal calls a machine quiet after three missed beats and never sooner than
  three minutes, and delayed at half that; a node with a slower configured
  heartbeat gets a proportionally longer allowance. Heartbeats update a node
  record, not an append-only table. WAN cloud reports are coalesced while local
  counters continue.
- A fresh heartbeat does not prove telemetry is arriving: uploads come from a
  separate timer. The agent warns (`hyn cloud status`, `hyn doctor`) and
  re-arms the upload timer when no upload has been attempted for three upload
  intervals (at least 15 minutes).
- The browser checks a small freshness response every 15 seconds while visible
  and online. It reloads telemetry when the latest sample or configuration changes,
  and at least every five minutes to expire old readings.
  The heartbeat age advances every second locally. CPU/network samples are real
  observations at the upload interval (one minute by default), not simulated
  second-by-second measurements.
- Charts use at most 600 five-minute sample points across 48 hours. The latest
  full reading is fetched separately, so detail panels cannot select an old point
  merely because the history query reached its row limit.
- `hyn_metric_history` and `hyn_fleet_metric_history` check access once per call
  (`hyn_can_view_node`, `hyn_is_admin`) rather than through row level security on
  every reading. They return the same rows as before.

## Retention and cost limits

Cloud metrics, speed tests and alert events are hidden from user queries after
48 hours. Bounded cleanup removes expired rows in batches of 5,000 per table.
When enabled, `pg_cron` runs cleanup every five minutes even while the portal is
offline. The database creates its jobs with `public._hyn_schedule_jobs()`, which
creates or updates each job by name. Migrations that add a job run it again. If
you enable pg_cron on an existing database, run
`select public._hyn_schedule_jobs();` once yourself. A service-only portal
endpoint, `/api/cron/telemetry`, protected by
`CRON_SECRET`, is available as a fallback; scheduled email maintenance also
attempts cleanup. Schedule the fallback every five minutes if database Cron is
unavailable. Physical deletion may lag the exact 48-hour boundary by a scheduler
interval or while a backlog drains; the read cutoff is immediate.

This cutoff applies to monitoring history, not account settings, permissions,
bandwidth accounting totals/daily records, command receipts, delivery records or
administrative audit trails. Those retain their existing policies. The cloud copy
contains structured HYN operational summaries, not arbitrary application log text.

Local history defaults to 14 days with a shared 256 MiB disk cap; oldest history
rotates when either limit is reached. The delivery outbox has independent limits
of 48 hours, 2,880 readings and 32 MiB. It contains payloads and node identity,
never tokens. New readings are attempted before bounded replay. Acknowledgements
and original sample timestamps prevent duplicate chart points and history gaps
caused by a lost HTTP response. Relinking a server cannot send a previous node's
queued data under its new identity. The retry queue is a delivery mechanism;
longer local snapshots remain after queued items expire.

At one reading per minute, each server produces up to 2,880 retained sample rows.
Payloads and optional detail arrays are bounded. Actual storage includes indexes,
TOAST, WAL, other tables and PostgreSQL overhead. Free-tier capacity depends on
fleet size and measured payload sizes; this policy cannot guarantee an unlimited
fleet will fit. Use Supabase Usage and `hyn cloud usage` to monitor consumption.
Deleting rows makes space reusable and does not immediately shrink database files.

## VPS and container visibility

The agent infers AWS, Google Cloud, Azure, Oracle, DigitalOcean and Hetzner from
local DMI or device-tree evidence. Unknown providers remain unknown. No metadata
endpoint, instance credential, cloud account API or customer cloud secret is used.
Virtualization and cgroup v1/v2 CPU, memory and throttling limits are reported
separately from the existing system counters. This prevents a container quota
from being mislabeled as the host's total resources. Provider billing, credits,
VM scheduling and account-wide resource inventories are outside this collector.

## Existing installations and rollout

1. Apply the migrations in order. `20260913120000_five_minute_monitoring_cadence.sql`
   set a five-minute cadence for the Cloudflare D1 write cap; D1 was retired on
   2026-09-20 and `20260928130000_fast_cadence_policy.sql` returns every node
   still on that policy to the fast defaults (24-second heartbeat, one-minute
   check-in and upload). Explicit per-node values and an explicit
   `cloud_storage=local` privacy choice are preserved.
2. Verify `hyn_metric_history`, `hyn_fleet_metric_history`, `hyn_prune_telemetry`, the read cutoff, and the
   retention scheduler. Deploy the portal only after this database gate passes.
3. Publish/install CLI 1.10.0 and verify an actual server's running version,
   settings pull, local archive, heartbeat and new cloud sample. An old CLI that
   rejects the new managed storage setting still needs its package upgrade.

The default changes do not magically replace an already installed package. An
operator can activate cloud mode on a compatible existing CLI explicitly:

```sh
sudo hyn cloud optimize   # cloud history + local backup at the default cadence
sudo hyn push
```

Super admins manage cloud/local mode in server settings. On managed nodes this
setting follows the same portal-override precedence as alert thresholds; clear
or change the portal override before expecting a local-only setting to win.

CI runs CLI fixtures and release/package checks on Ubuntu 22.04/24.04 x64 and
Ubuntu 24.04 ARM, plus PostgreSQL fresh, upgrade and schema-reapply suites. These
checks validate portability and package contents; real Ubuntu/systemd upgrade,
power-loss behavior and production telemetry still require live acceptance.

Database Cron can be enabled through the [Supabase Cron installation guide](https://supabase.com/docs/guides/cron/install).
