-- Adds dashboard_view as the twelfth portal-managed setting: 'dash' (the full
-- multi-panel view) or 'simple' (the premium glance view -- node status, speed
-- now + today's high, cpu temp, essentials). An administrator sets this per
-- node from the client control room; the value is pulled by the agent on its
-- next check-in the same way every other managed setting is.

begin;

create or replace function public._hyn_portal_config_valid(p_config jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare e record; v text;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object' then return false; end if;
  for e in select key, value from jsonb_each(p_config) loop
    if jsonb_typeof(e.value) not in ('number', 'string') then return false; end if;
    v := e.value #>> '{}';
    case
      when e.key in ('alert_mem_pct', 'alert_disk_pct') then
        if v !~ '^(0|[1-9][0-9]{0,2})$' or v::integer > 100 then return false; end if;
      when e.key = 'alert_temp_c' then
        if v !~ '^(0|[1-9][0-9]{0,2})$' or v::integer > 200 then return false; end if;
      when e.key = 'alert_load_per_core' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' or v::integer > 10000 then return false; end if;
      when e.key = 'alert_latency_ms' then
        if v !~ '^(0|[1-9][0-9]{0,5})$' or v::integer > 600000 then return false; end if;
      when e.key = 'alert_repeat_hours' then
        if v !~ '^(0|[1-9][0-9]{0,3})$' or v::integer > 8760 then return false; end if;
      when e.key = 'notify_max_per_day' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' or v::integer > 10000 then return false; end if;
      when e.key = 'cloud_push_min' then
        if v !~ '^[1-9][0-9]{0,3}$' or v::integer > 1440 then return false; end if;
      when e.key = 'alert_min_severity' then
        if v not in ('crit', 'warn', 'info') then return false; end if;
      when e.key = 'auto_update' then
        if v not in ('install', 'check', 'off') then return false; end if;
      when e.key = 'dashboard_view' then
        if v not in ('dash', 'simple') then return false; end if;
      when e.key = 'report_at' then
        if v !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then return false; end if;
      else return false;
    end case;
  end loop;
  return true;
end;
$$;

-- Drop before rewriting rows: a value the old constraint rejects (there is
-- none here, but the pattern matters more than this one case) must not block
-- a repairable row from being sanitised.
alter table public.nodes drop constraint if exists nodes_config_portal_keys_check;

update public.nodes n
   set config = coalesce((
     select jsonb_object_agg(e.key, e.value)
       from jsonb_each(case when jsonb_typeof(n.config) = 'object' then n.config else '{}'::jsonb end) e
      where e.key = any (array[
        'alert_mem_pct', 'alert_disk_pct', 'alert_temp_c', 'alert_load_per_core',
        'alert_latency_ms', 'alert_min_severity', 'alert_repeat_hours', 'report_at',
        'notify_max_per_day', 'cloud_push_min', 'auto_update', 'dashboard_view'
      ]::text[])
        and public._hyn_portal_config_valid(jsonb_build_object(e.key, e.value))
   ), '{}'::jsonb);

alter table public.nodes add constraint nodes_config_portal_keys_check
  check (public._hyn_portal_config_valid(config));

-- An administrator sets the same managed settings a client can set for their
-- own node -- the client-facing RPC (hyn_update_node_config) is owner-scoped
-- and refuses everyone else, so this is a deliberate second entry point for
-- the client control room, not a bypass of it. Restricted to the identical
-- allowlist for the identical reason: an admin console is not a bigger trust
-- boundary than the account page, just a different caller.
create or replace function public.hyn_admin_set_node_config(
  p_node_id uuid,
  p_config jsonb
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_config jsonb;
begin
  perform public._hyn_require_admin();
  if not public._hyn_portal_config_valid(p_config) then
    raise exception 'invalid portal configuration';
  end if;
  update public.nodes set config = p_config
   where id = p_node_id and revoked = false and is_demo = false
  returning config into v_config;
  if not found then
    raise exception 'no such node';
  end if;
  perform public._hyn_audit('node.config', null, p_node_id, p_config);
  return json_build_object('status', 'ok', 'config', v_config);
end;
$$;

revoke all on function public.hyn_admin_set_node_config(uuid, jsonb) from public;
grant execute on function public.hyn_admin_set_node_config(uuid, jsonb) to authenticated;

commit;
