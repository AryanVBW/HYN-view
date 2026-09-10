# Portal roles and dashboard sharing

| Role | Dashboard access | Actions |
| --- | --- | --- |
| Viewer | Own dashboard and dashboards explicitly shared with them | Read only |
| Monitor | Own dashboard and dashboards explicitly shared with them | Refresh readings; request or cancel their own relayer access requests |
| Admin | Every dashboard and the admin dashboard | View data and promote existing Viewers/Monitors to Admin |
| Super admin | Every dashboard and the admin dashboard | Write settings, link/update/control machines, manage relayers, review requests, change roles, and share dashboards |

Changing display mode or hiding delivery history in the current browser is a
personal view preference; it does not change stored monitoring data.

## Use the dashboard

The role badge explains the signed-in account's capabilities. **Viewing dashboard**
switches between authorized dashboards; machine tabs stay within that dashboard.
Shared dashboard labels use the owner's display name, with a short ID fallback.
Sharing does not expose another person's account profile or email preferences.

At **Admin → Clients**, search by name or email, or filter using the four role
counts. Admins can select **Make Admin** or promote by email from Overview.
The account must sign in once before it can be promoted.

Super admins can change an account's role with the role selector. They can use
**Share a dashboard** to give a Viewer or Monitor access to another account's
machines and assigned relayers, then **Revoke access** to remove it. Access is
checked for every database query and relayer API request.

To resolve **No relayer assigned yet**, a Monitor submits **Request a relayer**
with the Highway name or numeric ID. A Super admin verifies ownership at
**Admin → Clients → Relayer requests** and selects **Approve relayer**.
Super admins can also assign directly from the client's detail view. A pending
request never grants access by itself.

## Database upgrade and release order

Apply pending migrations in timestamp order to the same Supabase project used
by the portal. This release includes:

1. `20260908090000_local_telemetry.sql`
2. `20260908110000_unattended_settings.sql`
3. `20260909090000_relayer_requests.sql`
4. `20260909120000_portal_roles.sql`

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
