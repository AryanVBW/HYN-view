# HYN Customer Monitoring, Hardware Health, and Scheduled Reporting

Date: 2026-08-21

Status: Proposed direction; awaiting stakeholder review before implementation

Owners: Highway Networks / NexusV

Repositories in scope:

- /Volumes/DATA_vivek/GITHUB/HYN-view — Bash agent, Supabase schema, tests, signed agent artifact
- /Volumes/DATA_vivek/GITHUB/HYN-view/web-portal — Next.js customer and administrator portal
- Project-Highway installer repository — integration contract only; its source is not present in this workspace

## 1. Executive decision

HYN will remain a read-only, low-overhead Bash agent. It will not become a
permanently running Node.js service and it will never expose an inbound port.
The npm package remains supported, but the Highway bootstrap will install the
same agent sources from a separately signed archive so a customer machine does
not need Node.js or npm.

Urgent incident alerts continue to leave directly from the monitored machine
using locally stored provider credentials. Daily, weekly, and monthly summary
reports move to the Highway Networks cloud. Cloud reporting is required because
it must use the customer's timezone, continue when a node is offline, retry
transient failures, and maintain an auditable delivery ledger.

The agent will send telemetry to a branded, versioned HTTPS API rather than
exposing Supabase details as the customer-facing contract. The API validates,
limits, authenticates, and ingests idempotent batches. Failed uploads remain in
a bounded local spool and are retried with backoff.

The product will distinguish:

- current machine state;
- high-frequency numeric history;
- a current process inventory;
- bounded top-process history;
- hardware capabilities and unavailable reasons;
- install and software provenance;
- deterministic maintenance findings.

No screen or report may present an absent sensor as zero.

## 2. Why this design is necessary

The current repositories already contain useful telemetry, pairing, RLS,
administrator controls, local alerts, and a rich Highway service panel. The
following are release blockers or material gaps:

- npm currently serves hyn-view 1.4.0, while cloud pairing and telemetry exist
  only in the unpublished 1.5.0 tree.
- The public Highway installer installs only /usr/local/bin/highway. It does not
  install HYN, Node.js, npm, pairing, or monitoring timers.
- Account changes to report_at and cloud_push_min update a pulled config file
  but do not regenerate the installed systemd timer units.
- The current local report timer deliberately adds up to five minutes of
  random delay and 30 seconds of timer accuracy. It cannot meet a selected
  customer time.
- Failed telemetry pushes are discarded rather than queued and backfilled.
- General process telemetry contains only a top-ten snapshot. Highway telemetry
  describes matching units but only one selected main PID.
- Many values already sent in the payload are not rendered by either dashboard.
- Power, PSU, fan, voltage, current, SMART, NVMe health, RAID, ECC, DIMM,
  throttling, UPS, and BMC/IPMI signals are not collected.
- The user and administrator dashboards do not have a process explorer,
  capability view, hardware-health view, or maintenance findings.
- Reporting is daily-only, server-local, dependent on the node being online,
  and backed by only eight days of local history.
- Direct agent-to-Supabase ingestion has no versioned payload contract,
  payload-size limit, sequence number, batch idempotency, timestamp-skew check,
  or per-node rate limit.
- Metric cleanup happens only when the same node ingests again. Dormant nodes
  can retain data past the stated period.

## 3. Goals

### 3.1 Customer outcomes

A signed-in customer can:

- see every linked node from anywhere;
- see when each displayed value was observed and received;
- see Highway units and every current process belonging to their cgroups;
- see a sanitized current inventory of all machine processes;
- see top process history without storing an unlimited process table per sample;
- inspect every temperature, fan, voltage, current, power, disk-health, ECC,
  RAID, battery/UPS, and platform signal the host actually exposes;
- understand why a category is unavailable;
- see open and resolved maintenance findings with evidence and recommended
  action;
- configure daily, weekly, and monthly reports in an IANA timezone;
- choose node or fleet scope, report detail, sections, and email recipients;
- receive reports even when a monitored node is offline;
- see report generation and delivery history.

### 3.2 Operator outcomes

An administrator can:

- use the same complete node detail view as a customer, subject to tenant audit;
- filter the fleet by stale state, Highway health, hardware health, maintenance
  urgency, agent version, and missing capabilities;
- inspect ingest failures, spool age, dropped samples, report failures, and
  workflow run identifiers;
- roll out agent and schema versions gradually;
- revoke a node without giving it any ability to revoke itself.

### 3.3 Non-interference outcomes

The unattended agent:

- has no inbound listener;
- performs no Highway start, stop, restart, reload, enable, disable, firewall,
  traffic-control, sysctl, package, firmware, SMART-test, RAID-rebuild, or BMC
  mutation;
- uses explicit non-overlap locks for collection, shipping, and queue handoff;
- has explicit CPU, memory, task, I/O, and execution-time bounds;
- uses fast, slow, and inventory collection tiers;
- never reads process environments or uploads command-line arguments by
  default;
- does not upload raw journal messages;
- does not auto-install optional hardware tools;
- never grows its disk spool without a hard quota.

## 4. Non-goals

This release will not:

- remotely execute commands or remediate a customer server;
- restart Highway or any other service;
- capture every short-lived exec event between samples;
- add eBPF, auditd, kernel modules, or continuous packet capture;
- collect process environments, secrets, or raw command lines;
- upload raw system journals;
- promise PSU, BMC, or physical sensor values from a VM that does not expose
  them;
- promise email arrival at an exact second. The system schedules work at the
  selected minute; recipient and provider latency remain external;
- infer that high Linux memory use alone means RAM must be replaced or added;
- replace the Highway activation flow.

## 5. Architecture options considered

### Option A — extend direct Supabase pushes and local systemd reports

This is the smallest code change. It keeps the existing RPC surface and adds
more JSON fields and timer variants.

It is rejected because local reporting fails when a node is offline, timezone
changes remain coupled to systemd, direct public ingestion lacks a branded
contract and traffic controls, and full process inventories would bloat every
metric row.

### Option B — Bash agent, branded gateway, bounded spool, cloud reports

This preserves the tested collector investment, adds transport reliability,
separates high-cardinality state from time series, and uses durable cloud
delivery for scheduled reports. npm and a signed archive deliver identical
sources.

This is the selected design. It provides the requested behavior without putting
a new permanent runtime on 512 MB customer nodes.

### Option C — replace the agent with a compiled Rust or Go daemon

A compiled daemon could provide strong typing, richer concurrency, and a more
advanced local database. It would also be a full collector rewrite, require a
long compatibility migration, introduce a new persistent process, and expand
the privileged attack surface.

It is deferred. The versioned API and payload schema in Option B allow a future
compiled agent without changing the portal contract.

## 6. End-to-end data flow

    Highway installer
        |
        | installs verified Highway binary and signed HYN archive
        v
    hyn bootstrap / hyn link
        |
        | device-code pairing; no telemetry before approval
        v
    root one-shot collectors (network denied)
        |
        +---- sanitized alert queue ---- unprivileged local sender
        |                                      |
        |                                      +---- customer provider
        |
        +---- sanitized bounded spool ---- unprivileged cloud shipper
                                               |
                                               | HTTPS batches with node token
                                               v
    api.highwaynetworks.io/api/agent/v2
        |
        | validation, rate limit, idempotent transaction
        v
    Supabase raw state, time series, rollups, findings
        |
        +---- customer dashboard
        +---- administrator dashboard
        |
        v
    minute scheduler ---- Vercel Workflow ---- Resend ---- verified recipients

The portal remains a Next.js 16 App Router project. Initial page data is fetched
in Server Components. Focused client components provide search, sorting,
filters, forms, and refresh behavior.

## 7. Distribution and installation

### 7.1 Package identity

The existing npm name hyn-view and commands hyn and hyn-view remain for backward
compatibility. Customer-facing product text becomes Highway Networks Monitor,
powered by HYN. A package rename is not required for this release.

package.json and lib/core.sh must obtain the version from one release source of
truth. CI fails when package metadata, HYN_VERSION, the archive manifest, and
the Git tag disagree.

### 7.2 Two delivery channels, one source

Each release produces:

- the npm package;
- a deterministic tar archive containing bin, lib, themes, license, and
  manifest;
- SHA-256 checksums;
- a keyless cosign bundle bound to the exact release tag;
- an npm provenance statement;
- a software bill of materials;
- release notes and rollback instructions.

The archive installer verifies the pointer and archive with the same
exact-version identity principle used by the Highway bootstrap. It installs
under /opt/hyn-view/releases/VERSION and atomically switches
/opt/hyn-view/current. /usr/local/bin/hyn points to the current release.
The previous release remains available for one-command rollback.

No npm lifecycle script performs privileged setup.

### 7.3 Highway bootstrap integration

The public installer repository must add an explicit monitoring step. Its
contract is:

1. Verify and install Highway.
2. Write /var/lib/highway/install-manifest.json with version, binary SHA-256,
   install time, source channel, architecture, verification issuer, workflow
   identity, and installer version.
3. Verify and install the signed HYN archive.
4. Install the HYN privilege-separated one-shot services and timers in an
   unlinked state.
5. Continue to the existing Highway activation TUI.
6. Offer portal linking in the TUI or print sudo hyn link after activation.

No server telemetry leaves the machine before a human approves the pairing
code. A non-interactive operator may opt in explicitly with a documented
environment flag. Absence of the flag never silently links an account.

Because the installer repository is not present in this workspace, this
workspace will provide the signed artifact, bootstrap command, manifest schema,
and an exact integration document. Publishing the changed public installer is a
separate repository deployment gate.

### 7.4 Branded defaults

New archive and npm installs default to:

- portal URL: https://highwaynetworks.io
- API URL: https://api.highwaynetworks.io

The API URL may be overridden only in a root-owned local config. A portal-pulled
configuration cannot change an endpoint, credential, recipient, local privacy
setting, or collection privilege.

## 8. Agent runtime

### 8.1 Minimal privilege-separated schedulers

The five overlapping alert, record, report, push, and general sampling timers
are replaced by two fixed-frequency timers plus the separately guarded
speed-test timer:

- hyn-collect.timer starts a root, network-denied one-shot collector;
- hyn-ship.timer starts a dedicated unprivileged, network-enabled one-shot
  shipper.

Collection and upload remain separately schedulable so a failed collector never
prevents old spooled data from shipping. Portal interval changes affect due-time
logic in the agent state and do not require rewriting systemd timer units.

Default behavior:

- lightweight sample: every 60 seconds;
- upload: every 5 minutes, containing accumulated samples;
- full current process inventory: every 5 minutes;
- slow hardware health: every 30 minutes;
- static inventory and install provenance: at boot, agent upgrade, detected
  fingerprint change, and once daily;
- local alert evaluation: every lightweight sample;
- speed test: existing configurable cadence with busy-link guard.

The lightweight interval is constrained to 60 through 900 seconds. The upload
interval is constrained to 1 through 60 minutes and cannot be shorter than the
sample interval.

CPU and per-process rates use baselines persisted between one-shot executions.
The unattended path no longer sleeps for one or two seconds to create a second
sample.

### 8.2 Locking and resource controls

Every collection command takes a non-blocking flock on
/run/hyn-view/agent.lock. A busy lock records a skipped-overlap counter and
exits successfully. A separate non-blocking shipper lock guarantees one upload
attempt at a time. The notification queue, telemetry spool, update path, and
speed-test path use their own atomic locks where required.

The systemd unit applies:

- Nice=15;
- IOSchedulingClass=idle;
- CPUSchedulingPolicy=batch;
- CPUQuota=10%;
- MemoryMax=96M;
- TasksMax=32;
- TimeoutStartSec=45s;
- RuntimeMaxSec=45s;
- UMask=0077;
- NoNewPrivileges=true;
- ProtectSystem=strict;
- ProtectHome=read-only;
- PrivateTmp=true;
- PrivateDevices=true for the fast collector;
- ProtectKernelTunables=true;
- ProtectKernelModules=true;
- ProtectControlGroups=true;
- RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6;
- ReadWritePaths limited to /var/lib/hyn-view and /run/hyn-view.

The root collector has IPAddressDeny=any and no outbound-network capability.
The shipper runs as the dedicated hyn-agent user, uses ProtectProc=invisible and
ProcSubset=pid, has no device visibility, reads only sanitized spool entries,
and obtains the cloud token from a root-provisioned systemd credential. Local
urgent-alert credentials remain available only to the separately scoped local
notification sender.

Optional device-health probes run in a separate unit because SMART, NVMe, and
BMC access may require device visibility or extra capabilities. The ordinary
collector must not inherit those permissions.

The exact capability set is proven on Ubuntu 22.04 and 24.04. It starts empty
and adds only capabilities required by a tested collector. Documentation may
not claim an empty capability set unless the generated unit actually has one.

### 8.3 Store and forward

Root-only state and secret directories are mode 0700. The dedicated outbound
spool is mode 0700 and owned by hyn-agent; the root collector atomically hands
off only sanitized mode-0600 event files to that owner. A temporary file is
fsynced where available and renamed into the ready queue. A successful server
acknowledgement removes only acknowledged sequence numbers.

Secret loading fails closed if a file is not root-owned or is more permissive
than mode 0600. A warning followed by continued use is not acceptable.

Defaults:

- 64 MiB total spool quota;
- seven-day age limit;
- at most 25 samples per request;
- exponential retry backoff with bounded jitter;
- no more than one upload attempt per scheduled run;
- most recent health state is preserved when quota pressure forces eviction;
- evicted sample count, first lost sequence, and last lost sequence are sent in
  the next successful batch.

The system cannot truthfully promise zero loss during an outage longer than the
configured quota, a full filesystem, or hardware failure. It must surface loss
explicitly instead of silently consuming the server disk.

### 8.4 Agent self-observability

Every batch includes:

- agent version and telemetry schema version;
- boot ID and monotonic sequence range;
- collector duration;
- peak resident memory when available;
- skipped overlap count;
- spool bytes, oldest sample age, and dropped sample count;
- last upload status and HTTP class;
- capability changes;
- local clock skew against the API response time.

## 9. Telemetry protocol

### 9.1 Endpoints

Version 2 exposes:

- POST /api/agent/v2/pairings
- POST /api/agent/v2/pairings/poll
- GET /api/agent/v2/config
- POST /api/agent/v2/telemetry/batches
- POST /api/agent/v2/delivery-events
- GET /api/agent/v2/health

The custom API uses the existing database device-code and node-token model
behind a stable branded contract. Node tokens use the Authorization bearer
header. The Bash client provides the header through curl configuration on
standard input so the token never appears in process arguments.

Version 1 direct RPCs remain available during a measured migration window and
are removed only after the administrator fleet page shows no supported node
using them.

### 9.2 Batch envelope

Every request contains:

- schema_version;
- batch_id;
- node boot_id;
- first_sequence and last_sequence;
- observed sample list;
- optional process snapshot;
- optional service-process snapshot;
- optional hardware-health snapshot;
- optional inventory snapshot;
- optional capability snapshot;
- optional local delivery events;
- optional loss disclosure.

Each sample has both observed_at and a monotonic sequence. Server received_at is
always recorded. A clock-skewed observed_at is retained as evidence but cannot
control retention, ordering, authentication, or report scheduling.

Limits:

- 1 MiB compressed request;
- 4 MiB uncompressed request;
- 25 metric samples;
- 2,000 current processes;
- 256 tracked service processes;
- 256 sensor channels;
- 100 delivery events;
- bounded strings and arrays at every nesting level.

The agent chunks a larger process snapshot. The API rejects unknown major schema
versions, ignores documented forward-compatible fields, and returns an
actionable upgrade response.

The response contains:

- acknowledged last sequence;
- accepted batch ID;
- server time;
- current config revision;
- administrative node state;
- minimum supported agent and schema versions;
- retry-after guidance when throttled.

### 9.3 Validation and idempotency

The route validates shape and limits before the database call. A narrow
SECURITY DEFINER ingest function repeats security-critical validation,
authenticates the node token, and writes one transaction.

Uniqueness:

- telemetry batch: node ID plus batch ID;
- metric sample: node ID plus boot ID plus sequence;
- delivery event: node ID plus event ID;
- alert transition: node ID plus rule plus state version;
- process snapshot: node ID plus snapshot ID;
- report occurrence: report preference ID plus scheduled_for.

Retries return the prior acknowledgement and do not duplicate metrics, alerts,
events, or reports.

Per-node and per-IP rate limits return 429 with Retry-After. Repeated malformed
payloads, token failures, and clock anomalies are counted without logging raw
tokens or entire bodies.

## 10. Collection model

### 10.1 Existing fast signals retained

- CPU total, user, system, IRQ, iowait, steal, per-core utilization;
- load, context switches, interrupts, process starts;
- per-core clock, governor, hardware min/max;
- memory, swap, cache, dirty pages, commit, memory PSI;
- filesystem bytes, availability, filesystem type, and growth;
- disk throughput, utilization, and await;
- network rates, totals, errors, drops, TCP states, retransmits, conntrack,
  link properties, latency, DNS, and speed-test results;
- CPU, memory, and I/O PSI;
- uptime, reboot-required, failed units, file-descriptor pressure;
- every visible temperature channel;
- alerts and Highway health.

### 10.2 New read-only hardware signals

Fast or slow sysfs/proc readers add:

- fan RPM and alarm state from hwmon;
- voltage, current, power, and energy channels from hwmon;
- CPU thermal-throttle and package-throttle counters;
- EDAC corrected and uncorrected memory errors;
- machine-check or kernel hardware-error counts without raw journal text;
- inode use and exhaustion;
- md RAID array state from /proc/mdstat;
- battery and UPS state exposed through /sys/class/power_supply;
- NIC carrier-change counters and driver/firmware identity when exposed;
- DMI vendor, model, board, BIOS version, and chassis type;
- virtualization and cloud-host class;
- Highway and HYN install manifests.

Optional tools, used only when already installed and enabled:

- smartctl with non-waking standby behavior for SATA/SAS health;
- nvme smart-log for wear, media errors, unsafe shutdowns, spare, temperature,
  and critical warnings;
- ipmitool read-only sensor and PSU commands for BMC-equipped bare metal;
- dmidecode for DIMM inventory when sysfs is insufficient;
- vendor RAID status tools through an explicit allowlist.

Every optional command has a hard timeout, output-size cap, idle I/O priority,
locale fixed to C, version parser tests, and no shell evaluation of output.
The agent never starts a SMART test, wakes a standby disk deliberately, changes
a BMC setting, or installs a tool.

### 10.3 Capabilities

Each collector publishes one state:

- available;
- unsupported by this platform;
- optional tool missing;
- permission denied;
- timed out;
- temporarily failed;
- disabled by local policy.

It also publishes last success, last attempt, source, and a safe reason code.
The dashboard renders that status. Missing and zero are never interchangeable.

Serial numbers, MAC addresses, external IPs, and account-bearing DMI values are
excluded from hosted inventory by default. A customer may enable a separately
documented identifier policy locally; the portal cannot enable it remotely.

## 11. Process and Highway visibility

### 11.1 General process inventory

The current snapshot contains, for each process visible at sampling time:

- process key formed from boot ID, PID, and kernel start ticks;
- PID and parent PID;
- comm/name;
- state;
- UID and sanitized local username;
- CPU rate;
- RSS;
- thread count;
- read and write byte rates when available;
- open-file count when readable;
- start time and uptime;
- systemd unit or normalized cgroup;
- container identity only when it can be named without copying labels or
  command arguments.

The default payload excludes argv, environment, working directory, full
executable path, socket peers, and open-file names.

The current snapshot replaces prior current state transactionally. It is not
appended into every metric payload. Top 25 processes by CPU and top 25 by RSS
are retained as bounded history.

A 2,000-process cap protects the node and API. If exceeded, the snapshot
contains every Highway cgroup process plus the highest-resource general
processes and reports the omitted count.

### 11.2 Highway process trees

For every matched Highway, hw-, Nebula, and Mosaic unit, the agent reads:

- ControlGroup;
- MainPID;
- cgroup.procs and child cgroups;
- unit state and substate;
- restart count;
- cgroup CPU, memory, I/O, and task count where exposed;
- each current process using the sanitized process fields above.

The dashboard reports an explicit Highway process count and groups processes by
unit. It no longer equates one MainPID with the complete Highway workload.

### 11.3 Honest limitations

This design is a sampled current inventory. A process that starts and exits
between snapshots may not appear. Capturing every exec would require audit or
eBPF infrastructure and is outside this low-impact release.

## 12. Maintenance findings

Maintenance recommendations are deterministic rules, not generative-AI
diagnoses. Each finding contains:

- stable finding code;
- affected node and component;
- severity and urgency;
- confidence;
- first seen, last seen, and resolved time;
- evidence values and window;
- capability source;
- recommended operator action;
- rule version.

Initial rule families:

- RAM capacity: sustained low MemAvailable plus memory PSI, swap churn, and OOM
  evidence. High mem_pct alone never recommends more RAM.
- Memory reliability: EDAC corrected-error acceleration or any uncorrected
  error.
- Disk capacity: sustained growth and projected exhaustion with a confidence
  band.
- Disk replacement: SMART/NVMe critical warning, media/pending sector errors,
  spare depletion, or wear threshold.
- RAID maintenance: degraded or rebuilding arrays.
- Thermal service: sustained threshold breach, new throttling, failed/zero fan
  where the platform declares a fan, or correlated disk temperature.
- PSU/power: redundancy loss, failure state, voltage alarm, or power-cap event
  only when a BMC/hwmon source reports it.
- CPU/platform: repeated machine checks, throttling under load, or clock pinned
  near minimum under sustained demand.
- Network/NIC: link flaps, accelerating physical errors, or persistent
  retransmission/drop anomalies.
- Highway: failed/inactive units, crash loops, missing process tree, unhealthy
  mesh, repeated journal error counts, or stale supported version.
- Agent: stale node, old agent, spool pressure, repeated ingest rejection, or
  missing required capability.

Rules use consecutive windows and hysteresis so a single spike does not open
and close a maintenance ticket. Findings resolve only after the healthy window
defined by the same rule version.

## 13. Database design

Existing tables remain during migration. New or changed structures are:

### 13.1 Telemetry

- telemetry_batches: batch identity, node, sequence range, schema, received
  bytes, status, rejection code, and receive time.
- metrics: add boot_id, sequence, received_at, schema_version, sample duration,
  and extrema fields; unique on node, boot, sequence.
- metric_hourly: per-node hourly min/avg/max/p95 and coverage.
- metric_daily: per-node daily aggregates, uptime coverage, growth, and counts.
- hardware_health_samples: bounded typed JSON plus extracted overall status.
- node_inventory: one current row per node with fingerprint and observed time.
- node_inventory_events: append only when the fingerprint changes.
- node_capabilities: one row per node and collector.
- process_snapshots: snapshot metadata, counts, omitted count, and observed time.
- node_processes_current: current sanitized process rows.
- process_top_samples: bounded top CPU/RSS history.
- service_processes_current: current process-to-Highway-unit mapping.
- maintenance_findings: current and resolved deterministic findings.
- node_credentials: token prefix and one-way verifier, created, last-used,
  expiry and revocation times, and rotation relationship. Revocation nulls the
  active verifier and requires re-pairing; an owner cannot clear it.

### 13.2 Reports

- report_preferences: owner, scope, node or fleet selector, cadence, IANA
  timezone, local time, weekly weekday, monthly day, format, selected sections,
  enabled, config revision, next_run_at, and timestamps.
- report_recipients: preference, normalized email, verification source,
  verified_at, enabled, and timestamps.
- report_runs: preference, scheduled_for, period bounds, status, workflow run
  ID, config snapshot, data coverage, attempts, error code, and timestamps.
- report_deliveries: run, recipient, provider, provider message ID, idempotency
  key, status, attempts, safe error, and timestamps.

A unique constraint on preference plus scheduled_for creates exactly one
application occurrence. A unique constraint on run plus recipient creates one
delivery target.

### 13.3 Authorization

RLS rules preserve the current ownership model:

- a customer reads only their own nodes, telemetry, processes, capabilities,
  findings, preferences, runs, and deliveries;
- a customer writes preferences only through validated RPCs or Server Actions
  that recheck ownership;
- a browser never inserts telemetry or claims a report run;
- an administrator reads fleet data through audited, narrow RPCs;
- agent tokens write only their own node through ingest RPCs;
- the service-role key exists only in server-side Vercel environment variables
  and never enters a Client Component or agent.

Every owner predicate also requires an active, non-suspended account. Direct
owner updates cannot modify administrative lifecycle fields such as revoked,
paused, suspended, owner, or token verifier. The ingest gateway uses a dedicated
least-privilege database role and narrow RPCs rather than a general service-role
credential. Server-only report orchestration may use a separate narrowly scoped
worker credential.

Administrator inspection of a customer node records an audit event with actor,
target owner, target node, and route context.

## 14. Retention and rollups

Default hosted retention:

- raw one-minute metrics: 35 days;
- hourly rollups: 13 months;
- daily rollups: 25 months;
- top-process history: 35 days;
- current process rows: replaced by the next snapshot and deleted 24 hours
  after a node is deleted or revoked;
- inventory change history: 13 months;
- hardware-health raw snapshots: 90 days;
- resolved maintenance findings: 13 months;
- report runs and delivery metadata: 13 months;
- pairing codes: physically purge after expiry;
- rejected raw request bodies: never retained;
- security and administrator audit: explicit approved policy, default 13
  months, with identifier minimization.

A secured scheduled cleanup covers active, dormant, paused, suspended, revoked,
and deleted nodes. Cleanup is not dependent on a future ingest from the same
node.

Rollups record sample coverage. A report never treats a period with 30 percent
coverage as a complete period.

The Privacy Policy, DPA, retention schedule, deletion/export procedures,
customer notice, and subprocessor inventory must be updated before central
report delivery is enabled. The current documents say notification destinations
remain on monitored servers, which will no longer be true for scheduled cloud
reports. The revised documents must describe centrally stored verified
recipients and report content, full current process-name collection, retention
periods, and the continued local-only handling of urgent-alert credentials.

## 15. Scheduled reports

### 15.1 Customer settings

The account page provides:

- enabled;
- scope: one node or all real nodes;
- cadence: daily, weekly, monthly;
- IANA timezone;
- local send time;
- weekday for weekly reports;
- day 1 through 31 for monthly reports;
- format: compact HTML, detailed HTML, CSV attachment, or JSON attachment;
- selected sections;
- verified recipients;
- send-test action;
- next scheduled occurrence in both local time and UTC;
- recent run and delivery history.

The authenticated account email is the initial verified recipient. Additional
addresses require verification before they can be enabled.

Process-name inventory is covered by an explicit pairing/account disclosure and
tenant consent. Disabling it stops future detailed snapshots while retaining
only aggregate process counts and deleting detailed current rows on the
documented schedule.

Monthly day 29, 30, or 31 means the last day of a shorter month. During a
spring-forward DST gap, the report runs at the first valid local minute after
the gap. During a repeated fall-back minute, it runs once at the first
occurrence. These rules are covered by fixtures for multiple zones.

### 15.2 Scheduler

A secured Vercel Cron route runs every minute on a Pro or Enterprise project.
The route verifies CRON_SECRET and calls one database RPC that:

1. selects due enabled preferences with row locking and skip-locked behavior;
2. inserts missing report_runs using the unique occurrence key;
3. advances next_run_at transactionally;
4. returns newly claimed run IDs in bounded pages.

The handler starts one Workflow run per report run and returns quickly.

Vercel cron delivery can be missed or duplicated, so the scheduler is
reconciliation-based. Every invocation considers all due occurrences in the
previous 24 hours. The unique occurrence constraint handles duplicates; the
lookback catches missed invocations. Occurrences older than 24 hours are marked
missed rather than sending a stale surprise.

Per-minute precision requires a Vercel Pro or Enterprise plan. Production
enablement fails closed with an administrator-visible configuration error when
the project cannot support that cadence.

### 15.3 Durable delivery workflow

The workflow receives only the report_run ID. Its steps:

1. Claim a deterministic report-run execution token, then re-read the run,
   preference, owner status, recipient verification, and node
   ownership. Disabled or suspended state cancels safely.
2. Snapshot the report period and calculate coverage and deterministic
   aggregates.
3. Render HTML, plain text, and the selected bounded attachment.
4. Create one report_delivery row per verified recipient.
5. Send through Resend using a stable idempotency key derived from the delivery
   row.
6. Store the provider message ID and final state.
7. Finalize the report run and administrator/customer counters.

Transient provider and network errors are retried by Workflow. Permanent input,
authorization, and unverified-domain errors fail without repeated sending.
Resend idempotency uses the report_delivery ID, not a workflow-local step ID,
inside its supported retention window. This also deduplicates two workflows
started for the same persisted run. The database occurrence and delivery keys
remain the permanent application ledger.

The Next.js configuration is wrapped with the Workflow integration. proxy.ts
excludes the generated .well-known/workflow paths.

### 15.4 Report content

Every report begins with period, timezone, node scope, sample coverage, and
offline gaps. Available sections are:

- executive health and availability;
- Highway units, process count, restarts, version, and mesh;
- CPU/load/clock/steal/iowait;
- memory capacity, pressure, swap, and OOM evidence;
- thermal extrema, duration over threshold, fans, throttling, and power;
- filesystem growth, inodes, disk I/O, SMART/NVMe, and RAID;
- network throughput, errors, drops, retransmits, conntrack, and latency;
- alerts and maintenance findings opened, resolved, or still active;
- software and install provenance;
- top processes by CPU and RSS;
- unavailable capabilities;
- recommended actions ordered by urgency.

Reports use stored telemetry. An offline node still produces a report that
states exactly when data stopped rather than suppressing the report.

## 16. Customer dashboard

The customer dashboard gains:

- accurate connected, delayed, stale, paused, suspended, and offline states;
- observed time and receive time;
- automatic refresh without claiming second-by-second live data;
- all existing unrendered CPU, network, filesystem, sensor, and PSI fields;
- a hardware-health section grouped by thermal, cooling, power, memory, storage,
  network, and platform;
- a capability matrix with safe reason text;
- a maintenance section with evidence and lifecycle;
- a process explorer with search, CPU/RSS/I/O sort, process tree, systemd unit,
  and Highway-only filter;
- top process history;
- installation and agent provenance;
- report settings and report history in account.

The existing visual language remains: terminal panels, Sentient headings,
monospace operational text, existing color tokens, accessible tables, and
responsive layouts.

The real-agent dashboard must not display demo journal lines. Raw journal
messages remain local-only; the portal shows warning and error counts.

## 17. Administrator dashboard

The reduced embedded client dashboard is replaced with shared full node-detail
components so administrator and owner views do not drift.

Fleet views add:

- stale/offline and spool-pressure filters;
- Highway health and complete process counts;
- hardware status and open maintenance findings;
- missing required capability and permission failure;
- telemetry schema and minimum-supported version;
- report success/failure and late/missed runs;
- raw/rollup coverage and ingest rejection rates.

Fleet trends query rollups instead of downloading a hard-capped set of raw rows.
All administrator actions remain database-authorized and audited.

## 18. Security and privacy controls

### 18.1 Agent boundary

- Root is used only where visibility requires it.
- The main collector has the smallest proven capability set.
- Optional device access is isolated from the main service.
- All Highway interaction remains read-only and regression-tested.
- Config files are parsed, never sourced.
- Remote config remains allowlisted and value-validated.
- Tokens and provider credentials are mode 0600.
- The state root is mode 0700, services use UMask=0077, and secret permission or
  ownership failures stop the affected path.
- Secrets never appear in argv, process inventory payloads, logs, report errors,
  or audit details.
- Endpoint override, collection identifiers, command-line capture, and optional
  privileged probes remain local-only policy.

### 18.2 API boundary

- TLS only;
- bearer node token stored only as a one-way verifier;
- request and decompression size limits;
- rate limits by node and source;
- schema validation in route and database;
- transactional idempotency;
- timestamp-skew isolation;
- generic authentication errors;
- structured safe error codes;
- no raw body logging;
- revocation and account suspension checks on every call;
- server-side secrets managed through Vercel environment variables.

### 18.3 Portal and report boundary

- Server Components perform privileged reads;
- Client Components receive only serializable, owner-authorized data;
- report settings recheck ownership server-side;
- recipients are verified;
- HTML is generated from typed data and escaped;
- CSV protects against formula injection;
- JSON contains only selected, hosted fields;
- attachments have strict size limits;
- report send has permanent and provider idempotency;
- admin customer inspection is audited;
- workflow and cron internal routes are excluded from user-session proxy work
  and independently authenticated.

## 19. Release and migration plan

### Phase 0 — make the existing release real

- synchronize 1.5.0 version metadata;
- run agent, cloud integration, database, migration, portal test, lint, and
  build gates;
- add prepublish package-content verification;
- publish and smoke-test npm 1.5.0 with provenance;
- expose fleet adoption and minimum-supported version;
- correct documentation that currently overstates portal timer updates.

### Phase 1 — agent v2 transport and runtime

- add persistent baselines, privilege-separated fixed timers, locks, resource
  limits, spool, batch schema, capability state, branded defaults, and API
  compatibility;
- deploy v2 gateway and idempotent ingest while retaining v1;
- canary on internal nodes, then an opt-in customer cohort;
- prove overhead and outage replay before broad rollout.

### Phase 2 — process and hardware health

- add cgroup process trees, current inventory, top history, hardware collectors,
  capability tables, and maintenance rules;
- ship portal process, sensor, capability, and findings views;
- run bare-metal, VM, no-sensor, missing-tool, permission-denied, large-process,
  and degraded-device fixtures.

### Phase 3 — cloud reports

- add preference, recipient, run, delivery, rollup, scheduler, Workflow, and
  Resend integration;
- add account controls and administrator reporting;
- update legal documents before enabling customer delivery;
- obtain explicit process-inventory consent before uploading detailed names;
- enable only after test-recipient, DST, duplicate, missed-cron, offline-node,
  and provider-failure scenarios pass.

### Phase 4 — Highway installer

- publish the signed archive;
- integrate the explicit monitoring step and Highway manifest in the installer
  repository;
- canary a pinned archive version;
- advance the signed latest pointer only after rollback is tested.

### Phase 5 — retirement

- require a minimum v2 agent after adoption threshold and notice period;
- remove direct v1 RPC access;
- disable obsolete local scheduled summary timers on cloud-managed nodes while
  retaining manual hyn report and local urgent alerts;
- keep documented rollback to the previous signed agent release.

Database changes are additive until the retirement phase. Portal parsing remains
tolerant of old payloads. Agent downgrade does not erase spooled data.

## 20. Verification strategy

### 20.1 Agent tests

- fixture tests for every parser and unavailable state;
- fuzzed labels, process names, DMI values, and optional-tool output;
- 2,000-plus process fixture and cap behavior;
- PID reuse and parent-tree correctness;
- cgroup v1 and v2 Highway trees;
- no raw argv, environment, journal message, or secret in payload;
- persistent-rate baseline across one-shot runs;
- atomic spool crash recovery;
- retry, partial acknowledgement, duplicate acknowledgement, quota eviction,
  clock jump, boot change, and week-long outage;
- overlapping timers and notification-queue concurrency;
- systemd unit hardening and capability assertions;
- read-only static checks for Highway, firewall, storage, SMART, RAID, and BMC
  mutation;
- measured CPU, memory, runtime, task count, disk writes, and payload size on
  Ubuntu 22.04 and 24.04 with 512 MB RAM.

### 20.2 Database and API tests

- unknown, revoked, paused, suspended, and cross-node tokens;
- decompression bomb, oversize array, long strings, malformed numbers, null
  sensors, and unsupported schema;
- duplicate batch, sequence, alert transition, process snapshot, and delivery
  event;
- out-of-order and clock-skewed samples;
- rate limit and retry-after;
- RLS isolation for every new table;
- non-admin denial for every privileged RPC;
- dormant-node retention;
- rollup coverage and raw deletion;
- process snapshot replacement transaction;
- finding hysteresis and versioning.

### 20.3 Report tests

- daily, weekly, monthly, month-end, leap-year, spring-forward, and fall-back;
- preference edits and disable immediately before send;
- suspended owner and revoked node;
- one-node and fleet scope;
- partial coverage and completely offline period;
- duplicate and missed cron invocation;
- concurrent scheduler claims;
- workflow retry before and after provider acceptance;
- Resend idempotency;
- unverified recipient;
- HTML escaping, CSV formula neutralization, bounded JSON, and attachment limit;
- customer and administrator run visibility.

### 20.4 Portal tests

- Server Component data authorization;
- process search/sort/tree and 2,000-row usability;
- null/unavailable capability rendering;
- shared owner/admin node details;
- report form validation and accessible controls;
- stale state and automatic refresh;
- responsive layouts and keyboard/screen-reader checks;
- no demo data presented as real telemetry.

### 20.5 Release gates

The outer and portal CI workflows must block production on:

- shell syntax and ShellCheck;
- agent self-check and cloud integration;
- database clean-schema, upgrade, migration, and RLS tests;
- portal unit and integration tests;
- lint, TypeScript, and Next.js production build;
- package dry run and manifest/version match;
- dependency and secret scan;
- preview smoke tests;
- signed artifact verification;
- canary telemetry and report delivery.

Production deployment uses linked Vercel project configuration and environment
management. Vercel CLI tokens are supplied through VERCEL_TOKEN rather than
command-line arguments. CI pins the audited Vercel CLI version instead of
installing vercel@latest. Preview is promoted only after checks pass.

## 21. Acceptance criteria

The feature is complete only when all of the following are demonstrated:

1. A fresh supported Highway host can install the signed HYN artifact without
   Node.js or npm.
2. npm latest installs the same tested agent version and manifest.
3. Pairing is explicit and the first authenticated upload succeeds.
4. A seven-day simulated outage backfills all samples within the configured
   spool bounds, with duplicates safely ignored.
5. Collector jobs never overlap each other, shipper jobs never overlap each
   other, the handoff is atomic, and both paths stay within published resource
   budgets.
6. Highway unit process counts and complete sampled cgroup trees appear on both
   customer and administrator views.
7. The current general process inventory appears without argv, environment, or
   raw journal text.
8. Every hardware category renders a value or a truthful capability reason.
9. Maintenance findings use multi-signal evidence and resolve with hysteresis.
10. A customer can create daily, weekly, and monthly schedules in their
    timezone and choose scope, sections, format, and verified recipients.
11. Duplicate scheduler/workflow/provider retries produce one email per
    occurrence and recipient.
12. An offline node still produces a report with an explicit data-gap section.
13. Owner RLS, administrator authorization, audit, node revocation, and report
    recipient security tests pass.
14. Retention jobs remove dormant-node data on schedule and rollups preserve
    reportable history.
15. Portal tests, lint, TypeScript, production build, agent tests, database
    tests, artifact verification, and canary smoke tests all pass freshly.

## 22. Planned file boundaries

Outer repository:

- bin/hyn — command routing and backward-compatible CLI surface
- lib/core.sh — configuration, version, intervals, and validation
- lib/agent.sh — one-shot orchestration, persistent baselines, locks, tiers
- lib/spool.sh — atomic queue, batching, acknowledgements, quota
- lib/hardware.sh — hwmon/sysfs/EDAC/RAID/power collectors
- lib/device-health.sh — isolated optional SMART/NVMe/IPMI/tool adapters
- lib/processes.sh — current process and cgroup inventories
- lib/highway.sh — Highway cgroup mapping and read-only service health
- lib/cloud.sh — v2 protocol and v1 transition
- lib/setup.sh — hardened consolidated units and old-timer migration
- lib/report.sh and lib/notify.sh — manual report and local urgent alerts
- supabase/migrations — additive v2 schema, RPCs, RLS, rollups, retention
- test — fixtures, transport, concurrency, security, performance
- release scripts and CI — deterministic archive, provenance, signing

Portal repository:

- app/api/agent/v2 — branded agent route handlers
- app/api/internal/report-scheduler — authenticated reconciliation route
- workflows/reports — durable orchestration and steps
- app/account — report preference and delivery history
- app/dashboard — complete customer node view
- app/admin — shared node view and fleet operations
- components/dashboard/processes — current and historical process UI
- components/dashboard/hardware — sensors and capabilities
- components/dashboard/maintenance — deterministic findings
- components/account/reports — schedule, format, section, recipient UI
- lib/telemetry — typed parsing and data access
- lib/reports — recurrence, aggregation, rendering, and safety
- next.config.ts — Workflow integration
- proxy.ts — Workflow internal-path exclusion
- vercel.ts — typed cron configuration
- tests — route, authorization, rendering, recurrence, workflow, and UI tests

## 23. Operational prerequisites

Before production enablement:

- upgrade the local Vercel CLI from 50.39.0 to 59.3.0 with
  npm i -g vercel@latest or pnpm add -g vercel@latest, and pin 59.3.0 in CI;
- use a Vercel Pro or Enterprise project for per-minute cron precision;
- configure CRON_SECRET, server-only Supabase credentials, Resend credentials,
  verified sending domain, portal/API origins, and telemetry limits through
  managed environment variables;
- point api.highwaynetworks.io to the production API deployment;
- apply database migrations and verify RLS before agent rollout;
- approve revised privacy, DPA, retention, and subprocessor documents;
- approve the Vercel Workflow region and retention boundary; workflow inputs and
  outputs contain opaque IDs and small statuses, never report bodies,
  recipients, tokens, or raw telemetry;
- establish npm publishing provenance and cosign release identity;
- select internal and customer canary nodes representing VM, bare metal,
  sensorless, high-process-count, and degraded hardware cases;
- publish incident and rollback runbooks.

## 24. Final product guarantees

HYN guarantees authenticated, bounded, idempotent monitoring within the
capabilities exposed by the host. It guarantees that unavailable evidence is
shown as unavailable, that agent work is resource constrained, that missed
network uploads are retried within a disclosed spool bound, and that report
occurrences are durably tracked and deduplicated.

It does not claim access to sensors a platform hides, lossless retention after
local storage is exhausted, capture of processes that exist only between
samples, or exact recipient-inbox timing. Those limits are visible product
states rather than hidden failure modes.
