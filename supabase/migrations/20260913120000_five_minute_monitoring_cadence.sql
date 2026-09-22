begin;

-- The hosted cadence is managed data. Keep privacy mode untouched while moving
-- every existing managed node to the same heartbeat, upload and local sample
-- contract as a newly paired node.
create or replace function public._hyn_portal_config_valid(p_config jsonb)
returns boolean language plpgsql immutable set search_path = public as $$
declare e record; v text;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object' then return false; end if;
  for e in select key,value from jsonb_each(p_config) loop
    if jsonb_typeof(e.value) not in ('number','string') then return false; end if;
    v:=e.value #>> '{}';
    case
      when e.key in ('alert_enabled','report_enabled','keep_awake') then if v not in ('on','off') then return false; end if;
      when e.key in ('alert_interval_min','record_interval_min') then if v !~ '^[1-9][0-9]{0,3}$' or v::integer>1440 then return false; end if;
      when e.key='speedtest_per_day' then if v !~ '^[1-9][0-9]?$' or v::integer>24 then return false; end if;
      when e.key in ('alert_mem_pct','alert_disk_pct') then if v !~ '^(0|[1-9][0-9]{0,2})$' or v::integer>100 then return false; end if;
      when e.key='alert_temp_c' then if v !~ '^(0|[1-9][0-9]{0,2})$' or v::integer>200 then return false; end if;
      when e.key='alert_load_per_core' then if v !~ '^(0|[1-9][0-9]{0,4})$' or v::integer>10000 then return false; end if;
      when e.key='alert_latency_ms' then if v !~ '^(0|[1-9][0-9]{0,5})$' or v::integer>600000 then return false; end if;
      when e.key='alert_repeat_hours' then if v !~ '^(0|[1-9][0-9]{0,3})$' or v::integer>8760 then return false; end if;
      when e.key='notify_max_per_day' then if v !~ '^(0|[1-9][0-9]{0,4})$' or v::integer>10000 then return false; end if;
      when e.key='cloud_storage' then if v not in ('cloud','local') then return false; end if;
      when e.key='cloud_push_min' then if v !~ '^[1-9][0-9]{0,3}$' or v::integer>1440 then return false; end if;
      when e.key='cloud_checkin_min' then if v !~ '^[1-9][0-9]{0,2}$' or v::integer>60 then return false; end if;
      when e.key='heartbeat_sec' then if v !~ '^[1-9][0-9]{0,3}$' or v::integer<5 or v::integer>3600 then return false; end if;
      when e.key='alert_min_severity' then if v not in ('crit','warn','info') then return false; end if;
      when e.key='auto_update' then if v not in ('install','check','off') then return false; end if;
      when e.key='dashboard_view' then if v not in ('dash','simple') then return false; end if;
      when e.key='report_at' then if v !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then return false; end if;
      else return false;
    end case;
  end loop;
  return true;
end $$;

update public.nodes
set config=config||jsonb_build_object(
  'heartbeat_sec','300','cloud_checkin_min','5','cloud_push_min','5','record_interval_min','1',
  'cloud_storage',coalesce(config->>'cloud_storage','cloud')
), telemetry_policy_version=2
where telemetry_policy_version<2 and not is_demo;
alter table public.nodes alter column telemetry_policy_version set default 2;
alter table public.nodes alter column config set default
  '{"auto_update":"install","cloud_storage":"cloud","heartbeat_sec":"300","cloud_checkin_min":"5","cloud_push_min":"5","record_interval_min":"1"}'::jsonb;

create or replace function public.hyn_admin_overview()
returns json language plpgsql security definer set search_path=public as $$
begin
  perform public._hyn_require_staff();
  return json_build_object(
    'clients_total',(select count(*) from public.profiles),
    'clients_suspended',(select count(*) from public.profiles where status='suspended'),
    'admins',(select count(*) from public.profiles where role in ('admin','super_admin')),
    'nodes_total',(select count(*) from public.nodes where is_demo=false),
    'nodes_active',(select count(*) from public.nodes where status='active' and revoked=false and is_demo=false),
    'nodes_paused',(select count(*) from public.nodes where status='paused' and is_demo=false),
    'nodes_suspended',(select count(*) from public.nodes where status='suspended' and is_demo=false),
    'nodes_revoked',(select count(*) from public.nodes where revoked=true),
    'nodes_stale',(select count(*) from public.nodes n where n.is_demo=false and n.revoked=false and n.status='active' and case
      when coalesce(n.agent_version,'') ~ '^(1\.([7-9]|[1-9][0-9]+)\.|([2-9]|[1-9][0-9]+)\.)'
        then n.last_heartbeat_at is null or n.last_heartbeat_at<=now()-interval '15 minutes'
      else n.last_seen_at is null or n.last_seen_at<now()-make_interval(mins=>greatest(15,3*case when n.config->>'cloud_push_min'~'^[1-9][0-9]{0,3}$' then (n.config->>'cloud_push_min')::integer else 10 end)) end),
    'alerts_open',(select count(*) from public.alert_events where resolved=false and ts>now()-interval '7 days'),
    'notifications_24h',(select count(*) from public.notification_log where ts>now()-interval '24 hours'),
    'notifications_failed_24h',(select count(*) from public.notification_log where ts>now()-interval '24 hours' and status='failed'),
    'metrics_24h',(select count(*) from public.metrics where ts>now()-interval '24 hours'));
end $$;

create or replace function public.hyn_server_notifications(p_limit integer default 50)
returns json language plpgsql stable security definer set search_path=public as $$
declare result json;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.hyn_is_active() then raise exception 'active account required'; end if;
  if p_limit is null or p_limit<1 or p_limit>100 then raise exception 'choose 1 to 100 notifications'; end if;
  with visible as materialized (
    select n.id,n.owner,n.name,n.status,n.config,n.agent_version,
      coalesce(n.last_heartbeat_at,n.last_config_pull_at,n.last_seen_at,n.created_at) heartbeat_at
    from public.nodes n where not n.revoked and not n.is_demo and public.hyn_can_view_node(n.id)
      and (n.owner=auth.uid() or public.hyn_is_admin() or coalesce((select a.notifications_allowed from public.server_access a where a.viewer_id=auth.uid() and a.node_id=n.id),true))
  ), events as (
    select 'alert:'||a.id::text id,n.id node_id,n.owner,n.name node_name,a.ts,a.severity,a.message,case when a.resolved then 'resolved' else 'alert' end kind
    from visible n cross join lateral (select * from public.alert_events where node_id=n.id and ts>now()-interval '7 days' order by ts desc limit 50) a
    union all
    select 'command:'||c.id::text,n.id,n.owner,n.name,c.finished_at,case when c.status='failed' then 'warn' else 'info' end,
      case when c.command='update' then 'Agent update ' else 'Reading refresh ' end||c.status||coalesce(': '||c.message,''),'command'
    from visible n cross join lateral (select * from public.node_commands where node_id=n.id and status in('succeeded','failed') and finished_at>now()-interval '7 days' order by finished_at desc limit 20) c
    union all
    select 'heartbeat:'||n.id::text||':'||n.heartbeat_at::text,n.id,n.owner,n.name,n.heartbeat_at,'crit',
      'No recent heartbeat. The server may be offline; displayed readings can be stale.','offline'
    from visible n where n.status='active' and n.heartbeat_at<now()-make_interval(secs=>case
      when coalesce(n.agent_version,'')~'^1\.[0-6]\.' or n.agent_version is null then greatest(900,case when n.config->>'cloud_push_min'~'^[1-9][0-9]{0,3}$' then least((n.config->>'cloud_push_min')::integer,1440)*180 else 1800 end)
      else 900 end)
  )
  select coalesce(json_agg(e order by ts desc,id),'[]'::json) into result from (select * from events order by ts desc,id limit p_limit) e;
  return result;
end $$;

notify pgrst,'reload schema';
commit;
