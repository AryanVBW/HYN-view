# Server access and consumption

Release 1.11.0 adds **Admin → Server access**, **Admin → Bandwidth**, and **Server notifications**. The web portal remains a separate repository, `V1vekW/HYN-view-web`.

Super admins select up to 100 Viewers or Monitors and a server from the existing fleet, then grant or block access in one atomic operation. Owners automatically see devices they link and are excluded from assignment controls. An explicit block applies to additional users and overrides whole-dashboard sharing for those users. A grant exposes only that server, its readings, saved settings, consumption, and command progress; it does not expose siblings or the owner's relayers. Shared users cannot change configuration or install updates. Monitors can request fresh readings. Admin and Super admin roles retain fleet-wide read access. Existing role controls manage who becomes an administrator. Only Super admins can modify server permissions or see the access activity feed. Role checks and row-level policies enforce these rules for direct API calls too.

The server access activity feed records the acting Super admin, target user, server, action, and UTC time. It shows the latest 50 changes, including changes made by other Super admins. It is an activity feed, not an unread-message or email delivery system. Existing delivery logs and relayer requests keep their existing permissions.

## Consumption

All active accounts can view ingress, egress, combined observed total, and 7/30/90/366 days of UTC daily consumption for servers they can access. **Admin → Bandwidth** combines accessible servers or shows a selected server. Admin reporting includes date filters and daily tables. The user dashboard keeps only automatic received, sent, and total counters in its Advanced monitoring view; Simple view stays focused on server health. Server settings and relayer assignment controls live in the admin client view. Fleet totals show reporting and stale server counts; servers without counters are excluded, and traffic between two monitored servers can be counted at both interfaces. Database permissions filter both direct table reads and aggregate reports on every request.

The 1.11.0 agent sends its selected WAN interface's cumulative receive/send counters and boot identity after a successful heartbeat. `wan_iface` selects the interface; automatic selection uses the default route. Only these counters and daily aggregates are stored in the portal. Detailed snapshots and logs remain local by default. This is a requested exception to local-only telemetry, not an opt-in to the full cloud archive.

Totals begin at the first received baseline. Reboots, interface changes, and counter resets establish a fresh baseline without counting old bytes again. Repeated identical samples add zero. Immediate backwards samples are ignored to avoid reordering inflation. Gaps over three minutes mark the day incomplete. Samples spanning UTC midnight are allocated proportionally by elapsed time and marked estimated, preserving the exact observed combined total. Gaps over seven days establish a fresh baseline rather than inventing daily usage. Traffic before collection, across unobserved counter resets, or on other interfaces is not included. These are observed WAN totals, not lifetime whole-machine or provider billing totals. Old agents continue working but do not provide this new report until updated.

Automatic WAN selection follows default-route changes and supports IPv6-only hosts. Local daily reports preserve usage already observed before a reboot or interface change and identify resets that leave traffic unobserved.

## Shared notifications and updates

Super admins control notification delivery separately for each server grant. **Server notifications** shows recent cloud-shared alerts, completed reading refreshes and updates, and missing heartbeats for currently accessible servers. Blocking a server or suspending an account removes its reporting and inbox access on the next read. Disabling notifications preserves server access and statistics.

The inbox refreshes every minute while visible. Read event IDs stay in that user's browser; event bodies are not stored there. Browser notifications require an explicit click and browser permission, apply while the inbox is open, and only announce new events. They do not provide background push while the page is closed. Detailed alerts remain local unless the server explicitly enables cloud sharing.

Super admins use the existing web update controls to queue agent upgrades and inspect progress. Shared viewers cannot queue updates or edit automatic-update settings. Automatic installation is shown as enabled only when `auto_update` is `install`; `check` checks for updates without installing them.

## Release order

1. Apply the existing local telemetry, unattended settings, relayer requests, and portal roles migrations in timestamp order if not already present.
2. Apply `supabase/migrations/20260910120000_server_access_bandwidth.sql`. Fresh installations can use `supabase/schema.sql`; do not reapply historical migrations out of order on a live installation.
3. Deploy the matching portal commit. Its deployment workflow checks schema availability before pushing to Heroku.
4. Update server agents to 1.11.0 and allow two successful heartbeats to establish a baseline and first delta.
5. Verify with real authorized accounts: share one server with two users, confirm its sibling stays hidden, inspect usage in Advanced view and settings in the admin client view, toggle notifications independently, then block one user and confirm their access disappears. Confirm ordinary Admin cannot see access activity. Verify daily totals with a controlled WAN transfer and update progress on an authorized test agent.

The release has local database, agent, portal, and build checks. Live validation requires access to the HYN Supabase project and Heroku app; successful local checks alone do not establish production readiness.
