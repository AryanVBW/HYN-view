-- Limit portal-delivered node configuration to the fields intentionally
-- exposed by components/account/node-settings.tsx.
--
-- Existing keys outside this allowlist and unsafe values are deleted. This
-- includes local notification destinations, provider endpoints, portal
-- connection settings, malformed arithmetic, and out-of-range values that a
-- direct PostgREST caller previously stored.

begin;

create or replace function public._hyn_portal_config_valid(p_config jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  e record;
  v text;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object' then return false; end if;
  for e in select key, value from jsonb_each(p_config) loop
    if jsonb_typeof(e.value) not in ('number', 'string') then return false; end if;
    v := e.value #>> '{}';
    case
      when e.key in ('alert_mem_pct', 'alert_disk_pct') then
        if v !~ '^(0|[1-9][0-9]{0,2})$' then return false; end if;
        if v::integer > 100 then return false; end if;
      when e.key = 'alert_temp_c' then
        if v !~ '^(0|[1-9][0-9]{0,2})$' then return false; end if;
        if v::integer > 200 then return false; end if;
      when e.key = 'alert_load_per_core' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' then return false; end if;
        if v::integer > 10000 then return false; end if;
      when e.key = 'alert_latency_ms' then
        if v !~ '^(0|[1-9][0-9]{0,5})$' then return false; end if;
        if v::integer > 600000 then return false; end if;
      when e.key = 'alert_repeat_hours' then
        if v !~ '^(0|[1-9][0-9]{0,3})$' then return false; end if;
        if v::integer > 8760 then return false; end if;
      when e.key = 'notify_max_per_day' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' then return false; end if;
        if v::integer > 10000 then return false; end if;
      when e.key = 'cloud_push_min' then
        if v !~ '^[1-9][0-9]{0,3}$' then return false; end if;
        if v::integer > 1440 then return false; end if;
      when e.key = 'alert_min_severity' then
        if v not in ('crit', 'warn', 'info') then return false; end if;
      when e.key = 'report_at' then
        if v !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then return false; end if;
      else return false;
    end case;
  end loop;
  return true;
end;
$$;

update public.nodes n
   set config = coalesce((
     select jsonb_object_agg(e.key, e.value)
       from jsonb_each(
         case when jsonb_typeof(n.config) = 'object' then n.config else '{}'::jsonb end
       ) as e
      where e.key = any (array[
        'alert_mem_pct', 'alert_disk_pct', 'alert_temp_c',
        'alert_load_per_core', 'alert_latency_ms', 'alert_min_severity',
        'alert_repeat_hours', 'report_at', 'notify_max_per_day', 'cloud_push_min'
      ]::text[])
        and public._hyn_portal_config_valid(jsonb_build_object(e.key, e.value))
   ), '{}'::jsonb);

alter table public.nodes drop constraint if exists nodes_config_portal_keys_check;
alter table public.nodes add constraint nodes_config_portal_keys_check check (
  public._hyn_portal_config_valid(config)
);

commit;
