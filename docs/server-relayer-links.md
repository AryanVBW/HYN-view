# Link a relayer to a server

As a Super admin, open **Admin > Clients**, select the client and server, then expand **Server settings and automatic operation**. Choose **Linked Highway relayer** and select **Save relay link**. Relayers must first be assigned to that client using the existing assignment controls above.

Each server has at most one linked relayer, and each relayer can be linked to only one server. Options already linked elsewhere identify that server and cannot be selected. Select **No relayer linked** and save to unlink it before moving it to another server.

The Highway node card below Running now reads this explicit link. A server without a link shows an empty state, even when its owner has assigned relayers. Heartbeat ages and the five health checks continue to refresh automatically. The full relay details link retains the server scope.

Users with permission to view a server can view its linked relayer without gaining access to the owner's other relayers. Only Super admins can change links. The database enforces matching ownership and records link changes in the audit log. Removing an account assignment or deleting its server removes the link automatically.

## Deployment

Apply `supabase/migrations/20260911120000_node_relayer_links.sql` after the existing role and server-access migrations, then deploy the portal. Fresh installations can use the updated `supabase/schema.sql`. Existing assignments are preserved; no server links are guessed or created automatically.

Verify one client's two servers show their respective links, then confirm a user with access to only one server can see only that server's linked relay. Production migration and deployment are separate from local validation.
