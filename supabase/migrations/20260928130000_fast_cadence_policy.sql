-- Return to the fast monitoring cadence the portal and every deployed agent use.
-- See the matching block in schema.sql for the reasoning.
begin;
-- The five-minute policy (20260913120000) was made for Cloudflare D1's free
-- write cap. Production moved to self-hosted Supabase on 2026-09-20, and every
-- deployed agent (2.0.0) runs the fast cadence the portal is built for: a
-- 24-second heartbeat, one-minute check-ins and uploads. Its 300-second beat
-- against the portal's 180-second quiet threshold would have shown every
-- healthy machine as gone quiet. Nodes still carrying exactly the five-minute
-- policy return to the fast defaults; explicit per-node choices are kept.
--
-- "Quiet" follows each node's own heartbeat interval: three missed beats, and
-- never less than three minutes. The portal applies the same rule.
create or replace function public._hyn_quiet_after_seconds(p_config jsonb)
returns integer language sql immutable set search_path = public as $$
  select greatest(180, 3 * case when p_config->>'heartbeat_sec' ~ '^[1-9][0-9]{0,3}$'
    then least((p_config->>'heartbeat_sec')::integer, 3600) else 24 end);
$$;
revoke all on function public._hyn_quiet_after_seconds(jsonb) from public, anon, authenticated;

update public.nodes
   set config = (config - 'heartbeat_sec' - 'cloud_checkin_min' - 'record_interval_min')
                || '{"cloud_push_min":"1"}'::jsonb,
       telemetry_policy_version = 3
 where telemetry_policy_version < 3 and not is_demo
   and config->>'heartbeat_sec' = '300' and config->>'cloud_checkin_min' = '5'
   and config->>'cloud_push_min' = '5' and config->>'record_interval_min' = '1';
update public.nodes set telemetry_policy_version = 3 where telemetry_policy_version < 3;
alter table public.nodes alter column telemetry_policy_version set default 3;
alter table public.nodes alter column config set default
  '{"auto_update":"install","cloud_storage":"cloud","cloud_push_min":"1"}'::jsonb;

create or replace function public.hyn_admin_overview()
returns json language plpgsql security definer set search_path = public as $$
begin
  perform public._hyn_require_staff();
  return json_build_object(
    'clients_total', (select count(*) from public.profiles),
    'clients_suspended', (select count(*) from public.profiles where status = 'suspended'),
    'admins', (select count(*) from public.profiles where role in ('admin','super_admin')),
    'nodes_total', (select count(*) from public.nodes where is_demo = false),
    'nodes_active', (select count(*) from public.nodes where status = 'active' and revoked = false and is_demo = false),
    'nodes_paused', (select count(*) from public.nodes where status = 'paused' and is_demo = false),
    'nodes_suspended', (select count(*) from public.nodes where status = 'suspended' and is_demo = false),
    'nodes_revoked', (select count(*) from public.nodes where revoked = true),
    'nodes_stale', (select count(*) from public.nodes n
      where n.is_demo = false and n.revoked = false and n.status = 'active'
        and case
          when coalesce(n.agent_version, '') ~ '^(1\.([7-9]|[1-9][0-9]+)\.|([2-9]|[1-9][0-9]+)\.)'
            then n.last_heartbeat_at is null
              or n.last_heartbeat_at <= now() - make_interval(secs => public._hyn_quiet_after_seconds(n.config))
          else n.last_seen_at is null or n.last_seen_at < now() - make_interval(
            mins => greatest(15, 3 * case
              when n.config->>'cloud_push_min' ~ '^[1-9][0-9]{0,3}$'
                then (n.config->>'cloud_push_min')::integer else 10 end))
        end),
    'alerts_open', (select count(*) from public.alert_events where resolved = false and ts > now() - interval '7 days'),
    'notifications_24h', (select count(*) from public.notification_log where ts > now() - interval '24 hours'),
    'notifications_failed_24h', (select count(*) from public.notification_log where ts > now() - interval '24 hours' and status = 'failed'),
    'metrics_24h', (select count(*) from public.metrics where ts > now() - interval '24 hours')
  );
end;
$$;

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
      and (n.owner=auth.uid() or public.hyn_is_admin() or coalesce((select a.notifications_allowed from public.server_access a
        where a.viewer_id=auth.uid() and a.node_id=n.id),true))
  ), events as (
    select 'alert:'||a.id::text id,n.id node_id,n.owner,n.name node_name,a.ts,a.severity,
      a.message,case when a.resolved then 'resolved' else 'alert' end kind
    from visible n cross join lateral (
      select * from public.alert_events where node_id=n.id and ts>now()-interval '7 days' order by ts desc limit 50
    ) a
    union all
    select 'command:'||c.id::text,n.id,n.owner,n.name,c.finished_at,
      case when c.status='failed' then 'warn' else 'info' end,
      case when c.command='update' then 'Agent update ' else 'Reading refresh ' end||c.status||coalesce(': '||c.message,''),'command'
    from visible n cross join lateral (
      select * from public.node_commands where node_id=n.id and status in('succeeded','failed')
        and finished_at>now()-interval '7 days' order by finished_at desc limit 20
    ) c
    union all
    select 'heartbeat:'||n.id::text||':'||n.heartbeat_at::text,n.id,n.owner,n.name,n.heartbeat_at,'crit',
      'No recent heartbeat. The server may be offline; displayed readings can be stale.','offline'
    from visible n where n.status='active' and n.heartbeat_at < now()-make_interval(secs=>
      case when coalesce(n.agent_version,'') ~ '^1\.[0-6]\.' or n.agent_version is null
        then greatest(900,case when n.config->>'cloud_push_min' ~ '^[1-9][0-9]{0,3}$'
          then least((n.config->>'cloud_push_min')::integer,1440)*180 else 1800 end)
        else public._hyn_quiet_after_seconds(n.config) end)
  )
  select coalesce(json_agg(e order by ts desc,id),'[]'::json) into result
    from (select * from events order by ts desc,id limit p_limit) e;
  return result;
end $$;

grant execute on function public.hyn_admin_overview() to authenticated;
grant execute on function public.hyn_server_notifications(integer) to authenticated;

notify pgrst, 'reload schema';
commit;
