-- The portal selects last_heartbeat_at together with the existing safe node
-- columns. nodes uses column-level SELECT privileges to keep token_hash out of
-- browser sessions, so adding this column also requires an explicit grant.

begin;

grant select (last_heartbeat_at) on public.nodes to authenticated;

commit;
