-- HYN SERVER ACCESS AND BANDWIDTH V1
begin;
create table if not exists public.server_access (
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  node_id uuid not null references public.nodes(id) on delete cascade,
  allowed boolean not null,
  notifications_allowed boolean not null default true,
  granted_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key(viewer_id,node_id)
);
alter table public.server_access add column if not exists notifications_allowed boolean not null default true;
create index if not exists server_access_node_idx on public.server_access(node_id);
alter table public.server_access enable row level security;
revoke all on public.server_access from public,anon,authenticated;
grant select on public.server_access to authenticated;
drop policy if exists server_access_read on public.server_access;
create policy server_access_read on public.server_access for select to authenticated
using(public.hyn_is_super_admin() or (public.hyn_is_active() and viewer_id=auth.uid()));
create table if not exists public.server_access_events (
  id bigint generated always as identity primary key,
  ts timestamptz not null default now(),
  actor uuid references public.profiles(id) on delete set null,
  viewer_id uuid references public.profiles(id) on delete set null,
  node_id uuid references public.nodes(id) on delete set null,
  allowed boolean not null
);
alter table public.server_access_events enable row level security;
revoke all on public.server_access_events from public,anon,authenticated;
grant select on public.server_access_events to authenticated;
drop policy if exists server_access_events_read on public.server_access_events;
create policy server_access_events_read on public.server_access_events for select to authenticated using(public.hyn_is_super_admin());

create or replace function public.hyn_can_view_node(p_node uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.hyn_is_active() and exists(
    select 1 from public.nodes n join public.profiles p on p.id=n.owner
    where n.id=p_node and not n.revoked and (public.hyn_is_admin() or (p.status='active' and
      coalesce((select a.allowed from public.server_access a where a.viewer_id=auth.uid() and a.node_id=n.id),
        public.hyn_can_view_dashboard(n.owner))))
  );
$$;
create or replace function public.hyn_admin_set_server_access(p_viewer uuid,p_node uuid,p_allow boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_old boolean;
begin
  perform public._hyn_require_admin();
  if p_allow is null then raise exception 'choose whether to allow access'; end if;
  perform 1 from public.profiles where id=p_viewer and status='active' and role in ('viewer','monitor') for update;
  if not found then raise exception 'choose an active Viewer or Monitor'; end if;
  perform 1 from public.nodes where id=p_node and revoked=false for update;
  if not found then raise exception 'server unavailable'; end if;
  select allowed into v_old from public.server_access where viewer_id=p_viewer and node_id=p_node;
  if v_old is not distinct from p_allow then return; end if;
  insert into public.server_access(viewer_id,node_id,allowed,granted_by) values(p_viewer,p_node,p_allow,auth.uid())
    on conflict(viewer_id,node_id) do update set allowed=excluded.allowed,granted_by=excluded.granted_by,updated_at=now();
  insert into public.server_access_events(actor,viewer_id,node_id,allowed) values(auth.uid(),p_viewer,p_node,p_allow);
end $$;
create or replace function public.hyn_dashboard_accounts()
returns json language sql stable security definer set search_path=public as $$
  select coalesce(json_agg(json_build_object('id',p.id,
    'name',case when p.id=auth.uid() then 'My dashboard' else coalesce(nullif(p.full_name,''),'Shared dashboard '||left(p.id::text,8)) end,
    'own',p.id=auth.uid(),'relayers',public.hyn_can_view_dashboard(p.id)) order by (p.id=auth.uid()) desc,p.full_name,p.id),'[]'::json)
  from public.profiles p where public.hyn_can_view_dashboard(p.id) or exists(
    select 1 from public.nodes n where n.owner=p.id and public.hyn_can_view_node(n.id));
$$;
drop policy if exists nodes_select_own on public.nodes;
create policy nodes_select_own on public.nodes for select to authenticated using(public.hyn_can_view_node(id));
drop policy if exists metrics_select_own on public.metrics;
create policy metrics_select_own on public.metrics for select to authenticated using(public.hyn_can_view_node(node_id));
drop policy if exists speedtests_select_own on public.speedtests;
create policy speedtests_select_own on public.speedtests for select to authenticated using(public.hyn_can_view_node(node_id));
drop policy if exists alert_events_select_own on public.alert_events;
create policy alert_events_select_own on public.alert_events for select to authenticated using(public.hyn_can_view_node(node_id));
drop policy if exists node_commands_select_own on public.node_commands;
create policy node_commands_select_own on public.node_commands for select to authenticated using(public.hyn_can_view_node(node_id));
create or replace function public.hyn_request_node_command(
  p_node_id uuid,
  p_command text
)
returns json language plpgsql security definer set search_path = public as $$
declare v_command public.node_commands; v_created boolean := false;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  -- Separated from the authentication check: "not authenticated" sent a signed-in
  -- customer whose account had been suspended to look for a login problem.
  if not public.hyn_is_active() then
    raise exception 'this account is suspended, so it cannot send commands to its machines';
  end if;
  if p_command not in ('update', 'sync') then raise exception 'invalid command'; end if;
  if not public.hyn_can_monitor() then raise exception 'monitor or super administrator role required'; end if;
  if p_command='update' and not public.hyn_is_super_admin() then raise exception 'super administrator role required'; end if;
  if not public.hyn_can_view_node(p_node_id) then
    raise exception 'dashboard access required';
  end if;
  perform public._hyn_command_node(p_node_id, null);
  select * into v_command from public.node_commands
   where node_id = p_node_id and command = p_command and status in ('queued', 'running')
   order by requested_at desc limit 1;
  if not found then
    insert into public.node_commands (node_id, requested_by, command, message)
    values (
      p_node_id, auth.uid(), p_command,
      case when p_command = 'sync' then 'Waiting for the machine to synchronize'
           else 'Waiting for the machine to check in' end
    ) returning * into v_command;
    v_created := true;
  end if;
  return json_build_object(
    'id', v_command.id, 'node_id', v_command.node_id,
    'action', v_command.command, 'status', v_command.status,
    'stage', v_command.stage, 'message', v_command.message,
    'target_version', v_command.target_version, 'result_version', v_command.result_version,
    'requested_at', v_command.requested_at, 'started_at', v_command.started_at,
    'finished_at', v_command.finished_at, 'updated_at', v_command.updated_at,
    'created', v_created
  );
end;
$$;


-- Only daily aggregates and the latest counter baseline are retained. Detailed
-- telemetry stays local. Values measure the selected WAN interface, not billing.
create table if not exists public.bandwidth_counters (
  node_id uuid primary key references public.nodes(id) on delete cascade,
  iface text not null, boot_id text not null,
  rx numeric(20,0) not null, tx numeric(20,0) not null,
  sampled_at timestamptz not null
);
create table if not exists public.bandwidth_daily (
  node_id uuid not null references public.nodes(id) on delete cascade,
  day date not null,
  ingress_bytes numeric(24,0) not null default 0 check(ingress_bytes>=0),
  egress_bytes numeric(24,0) not null default 0 check(egress_bytes>=0),
  samples integer not null default 0,
  incomplete boolean not null default false,
  estimated boolean not null default false,
  primary key(node_id,day)
);
alter table public.bandwidth_counters enable row level security;
alter table public.bandwidth_daily enable row level security;
revoke all on public.bandwidth_counters,public.bandwidth_daily from public,anon,authenticated;
grant select on public.bandwidth_counters,public.bandwidth_daily to authenticated;
drop policy if exists bandwidth_counters_read on public.bandwidth_counters;
create policy bandwidth_counters_read on public.bandwidth_counters for select to authenticated using(public.hyn_can_view_node(node_id));
drop policy if exists bandwidth_daily_read on public.bandwidth_daily;
create policy bandwidth_daily_read on public.bandwidth_daily for select to authenticated using(public.hyn_can_view_node(node_id));

create or replace function public.hyn_record_bandwidth(p_node_token text,p_iface text,p_boot_id text,p_rx numeric,p_tx numeric)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare n public.nodes; prev public.bandwidth_counters; t timestamptz:=clock_timestamp();
  rx numeric:=0; tx numeric:=0; bad boolean:=false; split boolean:=false;
  cursor_ts timestamptz; until_ts timestamptz; fraction numeric; part_rx numeric; part_tx numeric;
  remaining_rx numeric; remaining_tx numeric;
begin
  select * into n from public.nodes where token_hash=public._hyn_sha256(p_node_token) for update;
  if not found then raise exception 'invalid node token'; end if;
  if n.revoked then raise exception 'node revoked'; end if;
  if n.status<>'active' or not exists(select 1 from public.profiles where id=n.owner and status='active') then raise exception 'node or account suspended'; end if;
  if p_iface is null or p_iface !~ '^[a-zA-Z0-9_.:-]{1,64}$' or p_boot_id is null or p_boot_id !~ '^[a-zA-Z0-9-]{1,64}$'
    or p_rx is null or p_tx is null or p_rx<0 or p_tx<0 or p_rx>18446744073709551615 or p_tx>18446744073709551615
    or p_rx<>trunc(p_rx) or p_tx<>trunc(p_tx) then raise exception 'invalid network counters'; end if;
  select * into prev from public.bandwidth_counters where node_id=n.id;
  if not found or prev.iface<>p_iface or prev.boot_id<>p_boot_id or p_rx<prev.rx or p_tx<prev.tx then
    bad:=true;
  else
    rx:=p_rx-prev.rx; tx:=p_tx-prev.tx;
  end if;
  -- Ignore immediate duplicate/reordered requests rather than moving a baseline
  -- backwards. A changed boot/interface is a new baseline and counts no bytes.
  if prev.node_id is not null and prev.iface=p_iface and prev.boot_id=p_boot_id and (p_rx<prev.rx or p_tx<prev.tx)
     and t-prev.sampled_at<interval '30 seconds' then return json_build_object('status','ignored'); end if;
  if prev.node_id is not null and t-prev.sampled_at>interval '3 minutes' then bad:=true; end if;
  -- Very long gaps cannot be assigned to days reliably; retain a new baseline.
  if prev.node_id is not null and t-prev.sampled_at>interval '7 days' then rx:=0; tx:=0; end if;
  cursor_ts:=case when rx+tx>0 then prev.sampled_at else t end;
  split:=(cursor_ts at time zone 'UTC')::date<>(t at time zone 'UTC')::date;
  remaining_rx:=rx; remaining_tx:=tx;
  loop
    until_ts:=least(t,(((cursor_ts at time zone 'UTC')::date+1)::timestamp at time zone 'UTC'));
    fraction:=case when t=cursor_ts or prev.sampled_at is null then 1 else extract(epoch from until_ts-cursor_ts)/nullif(extract(epoch from t-prev.sampled_at),0) end;
    part_rx:=case when until_ts=t then remaining_rx else floor(rx*fraction) end;
    part_tx:=case when until_ts=t then remaining_tx else floor(tx*fraction) end;
    insert into public.bandwidth_daily(node_id,day,ingress_bytes,egress_bytes,samples,incomplete,estimated)
      values(n.id,(cursor_ts at time zone 'UTC')::date,part_rx,part_tx,1,bad,split)
      on conflict(node_id,day) do update set ingress_bytes=bandwidth_daily.ingress_bytes+excluded.ingress_bytes,
        egress_bytes=bandwidth_daily.egress_bytes+excluded.egress_bytes,samples=bandwidth_daily.samples+1,
        incomplete=bandwidth_daily.incomplete or excluded.incomplete,estimated=bandwidth_daily.estimated or excluded.estimated;
    exit when until_ts=t;
    remaining_rx:=remaining_rx-part_rx; remaining_tx:=remaining_tx-part_tx; cursor_ts:=until_ts;
  end loop;
  insert into public.bandwidth_counters values(n.id,p_iface,p_boot_id,p_rx,p_tx,t)
    on conflict(node_id) do update set iface=excluded.iface,boot_id=excluded.boot_id,rx=excluded.rx,tx=excluded.tx,sampled_at=excluded.sampled_at;
  return json_build_object('status','ok');
end $$;
create or replace function public.hyn_bandwidth_report(p_node uuid,p_days integer default 30)
returns json language plpgsql stable security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.hyn_can_view_node(p_node) then raise exception 'server access required'; end if;
  if p_days is null or p_days<1 or p_days>366 then raise exception 'choose 1 to 366 days'; end if;
  return json_build_object(
    'iface',(select iface from public.bandwidth_counters where node_id=p_node),
    'sampled_at',(select sampled_at from public.bandwidth_counters where node_id=p_node),
    'since',(select min(day) from public.bandwidth_daily where node_id=p_node),
    'ingress_bytes',(select coalesce(sum(ingress_bytes),0)::text from public.bandwidth_daily where node_id=p_node),
    'egress_bytes',(select coalesce(sum(egress_bytes),0)::text from public.bandwidth_daily where node_id=p_node),
    'days',(select coalesce(json_agg(json_build_object('day',day,'ingress_bytes',ingress_bytes::text,'egress_bytes',egress_bytes::text,
      'samples',samples,'incomplete',incomplete,'estimated',estimated) order by day desc),'[]'::json)
      from public.bandwidth_daily where node_id=p_node and day>=(now() at time zone 'UTC')::date-(p_days-1)));
end $$;
revoke all on function public.hyn_can_view_node(uuid) from public,anon;
grant execute on function public.hyn_can_view_node(uuid) to authenticated;
revoke all on function public.hyn_admin_set_server_access(uuid,uuid,boolean) from public,anon;
grant execute on function public.hyn_admin_set_server_access(uuid,uuid,boolean) to authenticated;
revoke all on function public.hyn_record_bandwidth(text,text,text,numeric,numeric) from public;
grant execute on function public.hyn_record_bandwidth(text,text,text,numeric,numeric) to anon,authenticated;
revoke all on function public.hyn_bandwidth_report(uuid,integer) from public,anon;
grant execute on function public.hyn_bandwidth_report(uuid,integer) to authenticated;
-- Batch assignment is atomic: one invalid account rolls back the entire grant.
create or replace function public.hyn_admin_share_server(p_viewers uuid[],p_node uuid,p_allow boolean,p_notify boolean default true)
returns json language plpgsql security definer set search_path=public as $$
declare v_viewer uuid; v_count integer:=0; v_previous boolean;
begin
  perform public._hyn_require_admin();
  if p_viewers is null or cardinality(p_viewers) not between 1 and 100 or p_notify is null then
    raise exception 'choose 1 to 100 users and a notification permission';
  end if;
  for v_viewer in select distinct unnest(p_viewers) order by 1 loop
    perform public.hyn_admin_set_server_access(v_viewer,p_node,p_allow);
    select notifications_allowed into v_previous from public.server_access where viewer_id=v_viewer and node_id=p_node;
    update public.server_access set notifications_allowed=p_notify where viewer_id=v_viewer and node_id=p_node;
    if v_previous is distinct from p_notify then
      perform public._hyn_audit('server_access.notifications',v_viewer,p_node,jsonb_build_object('allowed',p_notify));
    end if;
    v_count:=v_count+1;
  end loop;
  return json_build_object('updated',v_count);
end $$;

create or replace function public.hyn_fleet_bandwidth_report(p_days integer default 30)
returns json language plpgsql stable security definer set search_path=public as $$
declare result json;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.hyn_is_active() then raise exception 'active account required'; end if;
  if p_days is null or p_days<1 or p_days>366 then raise exception 'choose 1 to 366 days'; end if;
  with visible as materialized (
    select id from public.nodes where not revoked and not is_demo and public.hyn_can_view_node(id)
  ), totals as (
    select min(day) since,coalesce(sum(ingress_bytes),0)::text ingress_bytes,
      coalesce(sum(egress_bytes),0)::text egress_bytes from public.bandwidth_daily where node_id in(select id from visible)
  ), days as (
    select day,sum(ingress_bytes)::text ingress_bytes,sum(egress_bytes)::text egress_bytes,
      sum(samples) samples,bool_or(incomplete) incomplete,bool_or(estimated) estimated
    from public.bandwidth_daily where node_id in(select id from visible)
      and day>=(now() at time zone 'UTC')::date-(p_days-1) group by day
  )
  select json_build_object('iface',null,'node_count',(select count(*) from visible),
    'reporting_count',(select count(*) from public.bandwidth_counters where node_id in(select id from visible)),
    'stale_count',(select count(*) from public.bandwidth_counters where node_id in(select id from visible) and sampled_at<now()-interval '3 minutes'),
    'sampled_at',(select max(sampled_at) from public.bandwidth_counters where node_id in(select id from visible)),
    'since',totals.since,'ingress_bytes',totals.ingress_bytes,'egress_bytes',totals.egress_bytes,
    'days',(select coalesce(json_agg(days order by day desc),'[]'::json) from days)) into result from totals;
  return result;
end $$;

-- The inbox exposes server events, never another user's delivery addresses.
-- Results are derived from current access on every read, including revocation.
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
      and (public.hyn_is_admin() or coalesce((select a.notifications_allowed from public.server_access a
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
        else 180 end)
  )
  select coalesce(json_agg(e order by ts desc,id),'[]'::json) into result
    from (select * from events order by ts desc,id limit p_limit) e;
  return result;
end $$;

revoke all on function public.hyn_admin_share_server(uuid[],uuid,boolean,boolean) from public,anon;
revoke all on function public.hyn_fleet_bandwidth_report(integer) from public,anon;
revoke all on function public.hyn_server_notifications(integer) from public,anon;
grant execute on function public.hyn_admin_share_server(uuid[],uuid,boolean,boolean) to authenticated;
grant execute on function public.hyn_fleet_bandwidth_report(integer) to authenticated;
grant execute on function public.hyn_server_notifications(integer) to authenticated;

notify pgrst,'reload schema';
commit;
