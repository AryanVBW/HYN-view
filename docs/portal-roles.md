# Portal roles and dashboard sharing

| Role | Dashboard access | Actions |
| --- | --- | --- |
| Viewer | Own dashboard and dashboards explicitly shared with them | Read only |
| Monitor | Own dashboard and dashboards explicitly shared with them | Link their own devices; refresh readings; view assigned relayers |
| Admin | Every dashboard and the admin dashboard | Link their own devices; view data and promote existing Viewers/Monitors to Admin |
| Super admin | Every dashboard and the admin dashboard | Write settings, link/update/control machines, manage relayers, review requests, change roles, and share dashboards |

Changing display mode or hiding delivery history in the current browser is a
personal view preference; it does not change stored monitoring data.

## Use the dashboard

The user dashboard starts with **Servers**, **Relayers**, **Notifications**, and
**Link server** (for accounts allowed to link). It keeps the existing **Simple**
and **Advanced** monitoring views. There is no role banner, request form, fleet
report, or server-settings editor on this page. Account switching appears only
when there is more than one dashboard to choose from. Shared server access and
URL-selected devices continue to use the existing database permissions.

**Relayers** opens assigned relayers separately, with status and earnings. Users
cannot submit linking requests from the dashboard. Administrators manage
assignments from the admin dashboard; relayer access is separate from linking a
server. Old dashboard URLs containing a relayer ID still open the relayer view.

In **Advanced**, **Data usage** shows received, sent, and combined observed bytes
for the selected server. Readings refresh with the dashboard, including while
waiting for telemetry. Missing readings are shown as unavailable, never as zero.
Detailed date filters and daily tables live at **Admin → Bandwidth**. Existing
`/usage` bookmarks send active Admins and Super admins there and other accounts
back to their dashboard.

The role description appears on the admin dashboard. **Admin → Clients → client**
contains server settings and automatic operation, consumption reports, and a link
back to the monitoring view. Admins can inspect these settings; only active Super
admins can edit them. Operational updates and assignment permissions are unchanged.

Active Monitors, Admins and Super admins can use **Link server** with a pairing
code from `sudo hyn link`. The signed-in account becomes the owner and sees the
device immediately, even before its first report. No admin assignment is needed.
Sharing one server with additional users remains a Super admin feature. Sharing
blocks cannot override ownership; suspend an account or revoke a server when
access must be disabled. Viewers remain read-only.
Shared dashboard labels use the owner's display name, with a short ID fallback.
Sharing does not expose another person's account profile or email preferences.

At **Admin → Clients**, search by name or email, or filter using the four role
counts. Admins can select **Make Admin** or promote by email from Overview.
The account must sign in once before it can be promoted.

Super admins can change an account's role with the role selector. They can use
**Share a dashboard** to give a Viewer or Monitor access to another account's
machines and assigned relayers, then **Revoke access** to remove it. Access is
checked for every database query and relayer API request.

To resolve **No relayers linked yet**, a Super admin opens
**Admin → Relayers → Choose a client**, selects the client, and uses
**Assign Highway relayers** with the Highway name or numeric ID. The assignment
appears automatically in that user's **Relayers** view. Existing pending requests
remain reviewable at **Admin → Relayers**; a pending request never grants access.
The legacy request API remains compatible, but the user dashboard no longer
exposes its form.

This dashboard simplification changes portal presentation only and adds no new
database migration or permissions.

## Database upgrade and release order

Apply pending migrations in timestamp order to the same Supabase project used
by the portal. This release includes:

1. `20260908090000_local_telemetry.sql`
2. `20260908110000_unattended_settings.sql`
3. `20260909090000_relayer_requests.sql`
4. `20260909120000_portal_roles.sql`
5. `20260910120000_server_access_bandwidth.sql`
6. `20260910200000_owner_linking.sql`

The existing relayer assignments migration is a prerequisite. Fresh installs
can use `supabase/schema.sql`. Existing installs should use the pending focused
migrations; the complete schema also contains older data cleanup migrations.
Deploy the matching portal **after** these migrations. No new environment
variables or service credentials are required for roles or sharing.

Legacy `user` accounts become `monitor`; legacy `admin` accounts become
`super_admin` to preserve their operational access. The migration detects the
legacy role constraint, so running it again does not elevate new Admin accounts.
New signups default to Monitor. Unknown or missing roles in the portal have no
write capability, and an unavailable role schema shows a setup notice.

For the first Super admin, use the Supabase SQL editor after the user signs in:

```sql
update public.profiles set role = 'super_admin' where email = 'you@example.com';
```

Alternatively add that email to `public.admin_allowlist`. The next authenticated
claim consumes the entry and records the Super admin promotion in the audit log.
The allowlist is a trusted database-only bootstrap, inaccessible from browser
sessions. Removing a Super admin role cannot be undone just by signing in again.

A user cannot change their own role or suspend their own account. Role and status
changes serialize in the database, preserving an active Super admin during
concurrent changes. Direct profile role updates are ungranted to browser roles;
role changes must use the audited RPC.

## Verification

`bash supabase/run-tests.sh` first verifies the existing agent protocol before
applying role restrictions, then runs the final authorization suite. The suite
checks the operational RPC inventory, direct writes, shared reads, revocation,
Admin promotion limits, Monitor commands, suspended users, hidden helpers, and
node-token reporting. It also upgrades legacy fixtures and reapplies both the
role migration and full schema to prove role conversion is idempotent.

Use `HYN_TEST_MIGRATIONS=1 bash supabase/run-tests.sh` for the complete upgrade
chain. Portal permission, component, and API tests run with `pnpm test` in the
separate `web-portal` repository. Production still requires applying migrations,
deploying the portal, and checking real sessions for all four roles.
