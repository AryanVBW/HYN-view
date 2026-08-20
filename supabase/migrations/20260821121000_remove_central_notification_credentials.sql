-- Notification provider credentials and destinations belong only on the
-- monitored server in /etc/hyn-view/secrets and /etc/hyn-view/config.
--
-- DESTRUCTIVE: applying this migration permanently deletes every existing row
-- in notification_channels and notify_prefs. Export anything an operator needs
-- to reconfigure locally before applying it. notification_log is preserved.

begin;

create or replace function public.hyn_fetch_config(p_node_token text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token);

  if not found then
    raise exception 'invalid node token';
  end if;
  if v_node.revoked then
    raise exception 'node revoked';
  end if;

  if v_node.status = 'paused' and v_node.paused_until is not null
     and v_node.paused_until <= now() then
    update public.nodes
       set status = 'active', paused_until = null, status_reason = null
     where id = v_node.id
     returning * into v_node;
  end if;

  update public.nodes set last_config_pull_at = now() where id = v_node.id;

  return json_build_object(
    'status', 'ok',
    'node_id', v_node.id,
    'node_name', v_node.name,
    'node_status', v_node.status,
    'paused_until', v_node.paused_until,
    'status_reason', v_node.status_reason,
    'config', v_node.config
  );
end;
$$;

drop function if exists public.hyn_list_admins();
drop table if exists public.notify_prefs;
drop table if exists public.notification_channels;

commit;
