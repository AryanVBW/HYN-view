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
- The default heartbeat is 24 seconds through the web portal; existing explicit
  60-second settings remain valid. Heartbeats update a node record, not an
  append-only table. WAN cloud reports are coalesced while local counters continue.
- The browser checks a small freshness response every 15 seconds while visible
  and online. It reloads telemetry when the latest sample or configuration changes,
  and at least every five minutes to expire old readings.
  The heartbeat age advances every second locally. CPU/network samples are real
  one-minute observations, not simulated second-by-second measurements.
- Charts use at most 600 five-minute sample points across 48 hours. The latest
  full reading is fetched separately, so detail panels cannot select an old point
  merely because the history query reached its row limit.

## Retention and cost limits

Cloud metrics, speed tests and alert events are hidden from user queries after
48 hours. Bounded cleanup removes expired rows in batches of 5,000 per table.
When enabled, `pg_cron` runs cleanup every five minutes even while the portal is
offline. A service-only portal endpoint `/api/cron/telemetry`, protected by
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

1. Apply `20260912190000_rolling_cloud_telemetry.sql`. The one-time fleet policy
   sets `cloud_storage=cloud` and changes the old default ten-minute interval to
   one minute. Explicit non-default intervals remain. Later local-only choices
   survive migration reapplication.
2. Verify `hyn_metric_history`, `hyn_fleet_metric_history`, `hyn_prune_telemetry`, the read cutoff, and the
   retention scheduler. Deploy the portal only after this database gate passes.
3. Publish/install CLI 1.10.0 and verify an actual server's running version,
   settings pull, local archive, heartbeat and new cloud sample. An old CLI that
   rejects the new managed storage setting still needs its package upgrade.

The default changes do not magically replace an already installed package. An
operator can activate cloud mode on a compatible existing CLI explicitly:

```sh
sudo hyn config set cloud_storage cloud cloud_push_min 1
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
