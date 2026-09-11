# Server and relayer assignments

Open **Admin > Assignments** as a Super admin. Select a user on the left, check the server cards they should see, then select **Save assignments**. One user can have any number of servers, and the same server can be selected for several users. Each card includes **Open dashboard** for inspecting that server.

Search users or servers, use **Assigned only** to inspect the current selection, or select **Clear selection** to remove additional shared access. Owned devices stay checked because ownership already gives access. Save or discard edits before switching users. Notification preferences are available in a collapsed section and are preserved when saving assignments.

The same selected user has a **User relayers** section. Search Highway and assign or remove relayers there, independently of their server access. Viewers and Monitors see their complete assigned relay list in **Relayers**, including relays that are not linked to any server. Changing the selected computer does not change that list. Relayer names, not account IDs or computer groups, select relayers in this tab.

Expand **Highway Node relay** on a saved server card to link one of that server owner's assigned relays. Each server has at most one linked relay, and an assignment cannot be linked to two servers. The linked relay's heartbeat and health appear below **Running** in the server dashboard. Everyone with access to that server sees the same linked relay, but sharing a server does not grant access to the owner's other relays. Removing a user relayer assignment also removes its server link through the existing database constraint.

The save is atomic: an unavailable server rejects the whole change. It affects only the selected user. Existing whole-dashboard shares for that user become the explicit server selection, so an unchecked sibling or a future server is not automatically visible. Account-owned relayer assignments are unchanged; server-only users can see the explicit relayer linked to their assigned server. Users without owned devices land on an assigned server when opening the dashboard.

Apply `supabase/migrations/20260911123000_user_server_assignments.sql` after the existing migrations and deploy the portal. Fresh installs can use `supabase/schema.sql`. Super admins manage assignments; regular Admins retain their existing fleet-read role. Viewers and Monitors cannot grant themselves access.
