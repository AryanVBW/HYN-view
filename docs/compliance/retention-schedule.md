# Data retention schedule and implementation inventory

**Internal use only**<br>
**Owner:** NEXUSV TECHNOLOGIES PRIVATE LIMITED<br>
**Operational contact:** vivek.aryanvbw@gmail.com<br>
**Assessment date:** 21 August 2026

## How to read this inventory

- **Code-enforced** means the repository contains a deletion or bounded-history
  mechanism. Many such mechanisms run only when a later event occurs; an idle system
  may retain older data.
- **Lifecycle cascade** means data is removed when its parent node or account is
  deleted, but has no independent age limit.
- **Owner/provider decision required** means no reliable period was found in code and
  no period should be promised until configuration and contracts are verified.
- A legal hold or mandatory security-log requirement overrides ordinary disposal only
  for the minimum necessary scope and time, with restricted access and a review date.

## Local agent data

| Data | Current state on 21 August 2026 | Control status | Required action |
|---|---|---|---|
| Local metric samples, normally `metrics.tsv` | Default `metrics_keep_days=8`; rows older than eight days are trimmed when the next sample is recorded. The value is locally configurable. | Code-enforced, event-driven | Decide permitted configuration bounds. Add a scheduled cleanup if dormant installations must not retain old rows. |
| Local alert history, normally `alert-log` | Rows older than 31 days are trimmed when the alert command next runs, even if no new alert fires. If alerting/timers stop, old rows can remain. | Code-enforced, event-driven | Add an independent cleanup if the 31-day maximum must apply while alert execution is disabled. |
| Local speed-test history, normally `speedtest.tsv` | Default `speedtest_history=90`; the newest 90 **records**, not days, are retained after a later test is appended. The value is configurable. | Code-enforced by count, event-driven | Decide a maximum count or age and document that count is not a time period. |
| System and user configuration | Stored under `/etc/hyn-view` or the applicable XDG config directory until manually removed. Ordinary uninstall preserves it. | No age purge | Define lifecycle disposal and instruct authorised owners when `sudo hyn uninstall --purge` is required. |
| Local secrets and node token | Stored in `/etc/hyn-view/secrets` with mode 0600 until overwritten, explicitly cleared, or purged. Unlink clears the local node token but does not delete the hosted node. | No age purge | Define rotation and revocation events; verify purge on device disposal and administrator departure. |
| Cloud configuration cache, legacy `cloud-channels` cache, push stamps and notification queue | State files persist until overwritten, successfully flushed or purged. Current agents remove the obsolete central-channel cache on a configuration pull, but an installation that never pulls again can retain its old local copy until purge. A freshness window does not itself delete the other files. | Event-driven legacy cleanup; no general age purge | Rotate any credential that was previously centralised, verify the legacy cache is gone, and set maximum queue/cache ages or lifecycle cleanup. |
| Onboarding and update/discovery caches | Persist until overwritten or the state directory is purged. | No general age purge | Confirm whether these contain identifiers; set a lifecycle rule or document why no personal data is retained. |
| Ubuntu journal and third-party notification copies | HYN-view may read the system journal and send messages, but journald and recipient retention are controlled outside the agent. | External controller | Server owners must set OS/provider retention. HYN-view cannot recall delivered messages. |

The state directory is normally `/var/lib/hyn-view` when writable, otherwise the
applicable user's XDG state directory. Local files belong to the server owner; NexusV
must not claim to have erased them without owner evidence.

## Hosted Supabase application data

| Data/table | Current state on 21 August 2026 | Control status | Required action |
|---|---|---|---|
| `metrics` | During a successful ingest, rows for that same node older than 30 days are deleted. No global scheduled purge is present. A node that stops pushing can retain older rows. | Code-enforced, node/push-triggered | Add and monitor a scheduled tenant-safe purge if 30 days is intended as a maximum. Test dormant and revoked nodes. |
| `speedtests` | No age-based purge found. Rows cascade when the parent node is deleted. | Lifecycle cascade only | Approve a period and implement scheduled deletion. |
| `alert_events` | No age-based purge found. Rows cascade when the parent node is deleted. | Lifecycle cascade only | Approve a period and implement scheduled deletion. |
| `device_codes` | Pairing validity is 15 minutes. Human codes use salted bcrypt verifiers; device secrets use SHA-256 verifiers. Expired rows are rejected immediately and purged when a pairing RPC later runs. An idle service can retain an unusable expired row. | Code-enforced logical expiry; event-driven physical deletion | Schedule and monitor physical cleanup if expired rows must be removed without later pairing traffic. |
| `nodes` | Kept until the owner/admin deletes the node or the Auth owner is deleted. Revocation/suspension does not delete the row. | Lifecycle only | Approve inactive/revoked-node disposal and automate notices/deletion if desired. |
| `profiles` | Kept until the Supabase Auth user is deleted; the foreign key cascades. | Account lifecycle | Ensure the seven-day privacy-request SOP deletes the Auth user after application cleanup and verifies the cascade. |
| Local notification configuration | Provider destinations are in `/etc/hyn-view/config`; API keys, passwords, tokens and webhook URLs are in `/etc/hyn-view/secrets` on the customer-controlled server. The Hosted Service has no channel or preference table. | Customer-controlled local lifecycle | Tell server owners that unlinking does not erase local configuration; use `sudo hyn uninstall --purge` or remove the files under their own retention policy. |
| `notification_log` | No scheduled age purge. An administrator can clear the fleet-wide delivery log from `/admin` — everything, or only rows older than a chosen cutoff — via `hyn_admin_clear_notifications`, which audits who cleared it and how many rows went. Rows also cascade on node or Auth-user deletion. Delivered messages at external providers/recipients remain outside this table. | Admin-triggered purge plus lifecycle cascade | Approve an operational/security retention period and automate it on that cadence rather than by hand. Minimise target, subject and error text. |
| `admin_audit` | No age purge. Deleting a user or node sets foreign keys to null, but `actor_email` and free-text/detail JSON may remain. | Indefinite unless manually handled | Approve a security/audit period and pseudonymisation rule. Ensure privacy deletion reviews email and detail, not only foreign keys. |
| `admin_allowlist` | No relationship cascade or age purge; email remains until explicitly removed. | Manual lifecycle | Remove departed/deleted admins promptly and review the list on a defined cadence. |
| Demo data | Cleared only by the demo-clear operation or parent deletion; no age purge identified. | Manual lifecycle | Decide whether production allows demo data and add cleanup if it does. |

The owner states that the primary Supabase database region is Mumbai, India. Treat
that as a configuration assertion to verify in the Supabase project dashboard and
contract; it does not establish where Auth logs, support data, backups or every
subprocessor operates.

## Authentication, hosting, email, backups and case evidence

| System/data | Verified period | Current gap and pre-production action |
|---|---|---|
| Supabase Auth users, identities, sessions and Auth/API/database logs | No application-enforced age period was established, except deletion of the Auth user during a verified account-deletion workflow. | Export actual project settings and provider terms; decide session, inactive-account and log periods; automate account deletion and evidence collection. |
| Supabase backups and point-in-time recovery | Provider/project period not confirmed. | Record plan-specific retention, deletion behaviour and restore controls. Maintain a minimal deletion-suppression manifest and test reapplying deletions after restore. |
| Vercel request, function, security, build and deployment logs | Provider/project period not confirmed. | Export actual plan/settings and data locations; decide which logs are necessary, restrict access and configure disposal where supported. Do not infer a Mumbai-only location from the application domain. |
| Resend message content, metadata, contacts and suppression records | Provider/account period not confirmed. | Verify settings and contract, minimise stored content, and document what can be deleted. Delivered recipient copies cannot be recalled. |
| Privacy-request evidence | Not yet approved. | Select a restricted repository and approve a period long enough to prove fulfilment without retaining the requester's underlying export. Prefer case IDs, actions and counts over copied personal data. |
| Incident and legal-hold evidence | Not yet approved. | Select a restricted India-capable evidence store; define hold review and disposal. Preserve only the evidence required for the incident, law or defence. |
| Customer support and abuse mail | Mailbox/provider period not confirmed. | Configure access and disposal; move necessary decision evidence to the restricted case system and remove unnecessary message copies. |

## CERT-In log action

The 28 April 2022 CERT-In directions state that covered service providers,
intermediaries, data centres, bodies corporate and government organisations must
enable ICT-system logs, retain them securely for a rolling **180 days**, and keep
those logs within India. That requirement is distinct from telemetry retention and
does not justify keeping all dashboard content for 180 days.

Pre-production action: obtain an applicability decision, define the minimum ICT log
set, verify Indian storage, protect integrity and access, and test production of logs
to CERT-In. The current repository and unverified provider settings do **not** prove
this control operates.

Official source: [CERT-In directions under section 70B](https://www.cert-in.org.in/PDF/CERT-In_Directions_70B_28.04.2022.pdf).

## Quarterly control test

1. Export deployed schema/functions and compare them with this inventory.
2. Create old test rows for every age-limited data set, run the real cleanup trigger,
   and prove deletion without crossing tenant boundaries.
3. Test an idle/revoked node; event-driven cleanup must not be reported as a hard
   maximum if the row remains.
4. Delete a test node and test account; verify every cascade plus `admin_audit` and
   `admin_allowlist` residual identifiers.
5. Inspect local uninstall with and without `--purge` in a disposable environment.
6. Export Supabase, Vercel and Resend retention/region settings as dated evidence.
7. Review legal holds, suppression manifests and restored backups for expired items.
8. Record exceptions, owners, due dates and retest evidence.
