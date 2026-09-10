# Server assignments

Open **Admin > Assignments** as a Super admin. Select a user on the left, check the server cards they should see, then select **Save assignments**. One user can have any number of servers, and the same server can be selected for several users. Each card includes **Open dashboard** for inspecting that server.

Search users or servers, use **Assigned only** to inspect the current selection, or select **Clear selection** to remove additional shared access. Owned devices stay checked because ownership already gives access. Save or discard edits before switching users. Notification preferences are available in a collapsed section and are preserved when saving assignments.

The save is atomic: an unavailable server rejects the whole change. It affects only the selected user. Existing whole-dashboard shares for that user become the explicit server selection, so an unchecked sibling or a future server is not automatically visible. Account-owned relayer assignments are unchanged; server-only users can see the explicit relayer linked to their assigned server. Users without owned devices land on an assigned server when opening the dashboard.

Apply `supabase/migrations/20260911123000_user_server_assignments.sql` after the existing migrations and deploy the portal. Fresh installs can use `supabase/schema.sql`. Super admins manage assignments; regular Admins retain their existing fleet-read role. Viewers and Monitors cannot grant themselves access.
