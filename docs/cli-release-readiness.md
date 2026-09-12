# HYN CLI 1.10.0 release verification

## September 12 monitoring update

CLI **1.10.0** is the chosen next release after npm latest **1.9.0**.
The current work adds [rolling 48-hour cloud monitoring](rolling-monitoring.md),
continuous bounded secondary local backups, offline delivery replay, VPS/cgroup
observations and Ubuntu x64/ARM CI. The portal now has compact history queries,
small freshness polling, current-reading age and a protected retention endpoint.
This supersedes the September 11 local-only behavior described below.

The complete CLI gate passed 1,507 checks with CI's `HYN_NO_POSTINSTALL=1`:
1,009 selfchecks, 149 cloud integration, 83 updater, 119 local storage/replay,
38 unattended, 7 bandwidth, 27 release, 29 report and 46 platform checks.
Shell syntax, warning-level ShellCheck, whitespace checks and npm package-content
validation passed. Package metadata and the executable both report 1.10.0.

Portal verification passed: 135 helper/release checks, 26 UI checks, 32 route
checks, full typecheck and production build. Lint has no errors and one existing
image-optimization warning. The PostgreSQL migration chain plus schema reapply
passed 307 checks, including the new retention suite twice.

Supabase access was restored and migration `20260912190000` was applied to HYN
project `iycjemnbfyuastnvagcj`. Database Cron is enabled, its five-minute retention
job succeeded, and expired metrics were confirmed absent after cleanup. Pruning
is denied to anonymous/ordinary authenticated roles and permitted to service-role
maintenance. Portal commit `d1de3ef` is pushed and deployed to Heroku;
[production run 34709931660](https://github.com/V1vekW/HYN-view-web/actions/runs/34709931660)
passed validation, the production database gate, deployment and smoke checks.

npm publish authentication was restored using the existing publishing account.
Observed live installation
metadata showed three 1.8.0 nodes using cloud mode and four 1.9.0 nodes still
using local mode despite the new managed cloud policy. Those local-mode agents
require the 1.10.0 package before this setting can take effect. This is not proof
of a new CLI install, its local backup, or a new-agent round trip.
The npm latest version was rechecked as **1.9.0** on September 12; the older
observations below are historical, not present registry or deployment claims.

## September 11 baseline

Status on 2026-09-11: **local release candidate; not published or certified for production**.
The target is Ubuntu with Bash 5+, GNU coreutils and util-linux `flock`, supervised
by systemd. Verification ran on a macOS development workstation with Bash 5.3.
The workstation has no installed `hyn` command or resident Ubuntu agent.

## Versions and live observations

| Source | Observed version or result |
| --- | --- |
| npm `hyn-view` dist-tag `latest` | 1.8.0; last published 2026-08-30 |
| Checkout before this work | 1.11.0 |
| Prepared checkout and npm package | 1.12.0 |
| Latest GitHub release metadata | v1.4.0; npm is the CLI update channel |
| User's running Ubuntu installation | Not inspected; no host connection supplied |
| `https://www.hyn-view.in/api/agent/v1/health` | Returned `hyn-agent-v1` and transient-snapshot support |
| Apex `https://hyn-view.in/api/agent/v1/health` | Connection timed out after 15 seconds |

The configured live database responded to local-config, command-claim and WAN
accounting RPCs with application-level rejection of a deliberately invalid node
token. This confirms those endpoints exist; it does not prove an authenticated
update, settings change or telemetry round trip. The complete deployment-schema
check could not run because the local portal environment has no service-role key.
No inference is made about whether that key exists on Heroku.

## Changes

- Updates bind npm's install prefix and registry to the installation being
  checked. They use a kernel lock, reject downgrades, validate the new executable
  before setup, and restore the prior package/command links after ordinary npm
  failures. Setup/restart failures also attempt service recovery.
- `hyn --version` is a single line and performs no startup checks. This is needed
  for the parser already shipped in 1.8.0; copyright remains in `hyn about`.
- Candidate-driven portal updates verify telemetry in a fresh process running
  the installed collectors. Success requires both an accepted reading and a
  completed command receipt. Invalid/truncated settings retain previous valid
  settings; formatted JSON works; replacements are flushed before publication.
- Missing first-tick stamps receive a startup grace period and then recovery.
  Updates during agent startup and backwards clock corrections no longer leave
  stale code or delayed maintenance running indefinitely.
- Samples use elapsed uptime rather than assuming `sleep 1` took exactly one
  second. Fresh SNMP and Highway CPU measurements receive baseline samples.
- Local bandwidth calculations use decimal integer arithmetic for raw counters,
  deltas and accumulated totals, including values beyond JavaScript's exact
  integer range and Bash's signed integer range. Counter/interface changes,
  reboots, overlapping samples and clock changes have explicit handling.
- Compact report writes are serialized and atomic. Reports exclude malformed,
  future and stale rows, and show observation gaps. Energy and busy duration are
  explicitly sampled estimates, integrated only across covered intervals.

## Local data and accuracy

| Path under `/var/lib/hyn-view/` | Contents |
| --- | --- |
| `local/snapshots/` | Recorded telemetry and generated daily text reports |
| `local/bandwidth/` | Immutable prior calculation records: raw counters, baseline, deltas, totals, timestamps, boot/interface identity and gap reasons |
| `local/bandwidth-state` | Two-line checkpoint: validated tab-separated baseline, followed by the latest complete JSON calculation |
| `local/usage/` | CLI HTTP request status and exact body-byte accounting; no tokens or response bodies |
| `metrics.tsv` | Compact report inputs including boot, interface index and monotonic capture time |

The cumulative checkpoint is **not rotated**. Detailed history retains the
existing default limit of 14 days / 256 MiB; compact metrics have their separate
retention. This is bounded local storage, not an unlimited backup. Back up the
state directory if every historical record must be retained indefinitely.

Linux commits use private temporary files, per-file `fsync`, atomic rename and
directory `fsync`. They rely on the filesystem and storage device honoring flushes.
The implementation uses GNU `sync` with a file operand, not a global or whole
filesystem flush. See [GNU sync documentation](https://www.gnu.org/software/coreutils/manual/html_node/sync-invocation.html).

Exact byte arithmetic does not recover traffic before the first sample or
between the final sample and a reboot/counter reset. Such discontinuities are
recorded; previously observed totals are retained. Sensor precision, sampled CPU
averages, energy estimates and projections are not exact continuous measurements.
The interactive display does not archive every render frame. Periodic recording
and explicit synchronization retain samples independently of cloud upload success.
Counters come from the [Linux proc interface](https://docs.kernel.org/filesystems/proc.html).

## Local verification

Run the complete CLI gate with `npm test`. It includes collector/selfchecks,
mock HTTP cloud integration, updater faults and locking, local persistence,
unattended recovery, bandwidth, release compatibility and report accuracy tests.
The new arithmetic tests compare 129 deterministic cases with Python integers.
Shell syntax, warning-level ShellCheck and `git diff --check` are separate gates.

Fresh-schema and full migration-chain PostgreSQL suites passed in disposable
local clusters. The portal's 15 focused agent API, command-status and transient
snapshot tests passed under Node 24. No portal source changes were needed.

Performance measurements are workstation microbenchmarks, not Ubuntu load tests:
normal network-counter handling added approximately 0.27 ms per interface per
tick. The new envelope scanner validates a 100 KB string in about 5 ms; the
previous draft needed seconds. The regression suite includes a large-response
budget and does not add persistence to the interactive render loop.

## Required Ubuntu acceptance before publication

1. Identify the actual installed executable, npm prefix, loaded agent version,
   enabled units and recent service failures. Useful existing commands are
   `hyn --version`, `hyn autostart status` and `sudo hyn doctor`.
2. On a disposable Ubuntu/systemd host, upgrade an original npm 1.8.0 installation
   to the candidate using real npm and the original updater. Preserve config,
   pairing token, compact history and local snapshots. The original updater's
   first completion reading still uses its old collectors; separately verify
   the new resident service and a subsequent candidate-driven portal update.
3. Confirm an authenticated portal setting change alters the effective local
   setting and timer schedule. Confirm Update CLI reaches completed only after
   fresh telemetry and the correct installed/running version are observed.
4. Reboot the Ubuntu test host; verify startup without login and retention of
   counters/configuration. Test process-crash recovery and a missing/stale stamp.
   Test offline/reconnect, registry failure, low disk space and interrupted writes.
5. Measure agent RSS/CPU, collection duration, record I/O and portal-check latency
   on the intended hardware under normal load and a busy disk/network.
6. Resolve and recheck the apex endpoint, and run the full deployed database and
   authenticated portal checks. Publish/advance npm `latest` only after acceptance.

**Remaining installer limitation:** npm replaces its package tree in place.
If power loss or SIGKILL occurs while that executable tree is absent, the updater
cannot execute its rollback and the service executable can remain unavailable.
Recovery copies remain in `.hyn-update.*` beside the npm package directory, but
automatic boot recovery for this case requires a recovery installer outside the
package being replaced. Ordinary failing-command rollback tests do not certify
this scenario. The candidate must not be advertised as crash-proof.

Firmware power recovery, disk-unlock requirements, filesystem corruption and
physical storage failure are outside the CLI's restart policy. The workstation
was not rebooted and no installed production agent, portal deployment or npm
release was changed by this verification.
