-- HYN PORTAL ROLES V1
-- Four roles, explicit dashboard sharing, and database-enforced capabilities.
-- Apply after 20260909090000_relayer_requests.sql. Safe to apply again.
begin;

-- Detect the legacy constraint BEFORE converting. Reapplying must never promote
-- a new, deliberately restricted Admin into a Super admin.
do $$
begin
  if exists (select 1 from pg_constraint where conrelid='public.profiles'::regclass
    and conname='profiles_role_check' and pg_get_constraintdef(oid) like '%''user''%') then
    alter table public.profiles drop constraint profiles_role_check;
    update public.profiles set role=case role when 'admin' then 'super_admin' when 'user' then 'monitor' else role end;
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.profiles'::regclass and conname='profiles_role_check') then
    alter table public.profiles add constraint profiles_role_check check(role in ('viewer','monitor','admin','super_admin'));
  end if;
end $$;
alter table public.profiles alter column role set default 'monitor';

create or replace function public.hyn_is_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and status='active' and role in ('admin','super_admin'));
$$;
create or replace function public.hyn_is_super_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and status='active' and role='super_admin');
$$;
create or replace function public.hyn_can_monitor()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and status='active' and role in ('monitor','super_admin'));
$$;
create or replace function public._hyn_require_staff()
returns uuid language plpgsql stable security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.hyn_is_admin() then raise exception 'administrator role required'; end if;
  return auth.uid();
end $$;
-- Existing operational RPCs all call this guard. Staff read RPCs below use the
-- separate staff guard, so every old write endpoint remains protected.
create or replace function public._hyn_require_admin()
returns uuid language plpgsql stable security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.hyn_is_super_admin() then raise exception 'super administrator role required'; end if;
  return auth.uid();
end $$;

create table if not exists public.dashboard_access (
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  granted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(viewer_id,owner_id),
  check(viewer_id<>owner_id)
);
alter table public.dashboard_access enable row level security;
revoke all on public.dashboard_access from public,anon,authenticated;
grant select on public.dashboard_access to authenticated;
drop policy if exists dashboard_access_read on public.dashboard_access;
create policy dashboard_access_read on public.dashboard_access for select to authenticated
using(public.hyn_is_active() and (viewer_id=auth.uid() or public.hyn_is_admin()));

create or replace function public.hyn_can_view_dashboard(p_owner uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.hyn_is_active() and (
    public.hyn_is_admin() or
    exists(select 1 from public.profiles p where p.id=p_owner and p.status='active' and (
      p.id=auth.uid() or exists(select 1 from public.dashboard_access a where a.viewer_id=auth.uid() and a.owner_id=p_owner)
    ))
  );
$$;
create or replace function public.hyn_dashboard_accounts()
returns json language sql stable security definer set search_path=public as $$
  select coalesce(json_agg(json_build_object('id',p.id,
    'name',case when p.id=auth.uid() then 'My dashboard' else coalesce(nullif(p.full_name,''),'Shared dashboard ' || left(p.id::text,8)) end,
    'own',p.id=auth.uid()) order by (p.id=auth.uid()) desc,p.full_name,p.id),'[]'::json)
  from public.profiles p where public.hyn_can_view_dashboard(p.id);
$$;
create or replace function public.hyn_admin_set_dashboard_access(p_viewer uuid,p_owner uuid,p_allow boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public._hyn_require_admin();
  if p_allow is null then raise exception 'choose whether to grant or revoke access'; end if;
  if p_viewer=p_owner then raise exception 'accounts already have access to their own dashboard'; end if;
  if p_allow then
    insert into public.dashboard_access(viewer_id,owner_id,granted_by) values(p_viewer,p_owner,auth.uid()) on conflict do nothing;
  else
    delete from public.dashboard_access where viewer_id=p_viewer and owner_id=p_owner;
  end if;
  perform public._hyn_audit('dashboard.access',p_viewer,null,jsonb_build_object('owner',p_owner,'allowed',p_allow));
end $$;

create or replace function public.hyn_admin_set_role(p_user_id uuid,p_role text)
returns json language plpgsql security definer set search_path=public as $$
declare v_actor uuid; v_old text;
begin
  -- Serialize role/status changes and recheck the caller after acquiring the lock.
  perform pg_advisory_xact_lock(74821901);
  v_actor:=public._hyn_require_staff();
  if p_role is null or p_role not in ('viewer','monitor','admin','super_admin') then raise exception 'unknown role'; end if;
  select role into v_old from public.profiles where id=p_user_id for update;
  if not found then raise exception 'no such client'; end if;
  if v_actor=p_user_id and v_old<>p_role then raise exception 'refusing to change your own role'; end if;
  if not public.hyn_is_super_admin() and (p_role<>'admin' or v_old not in ('viewer','monitor','admin')) then
    raise exception 'admins can only add other admins';
  end if;
  if v_old<>p_role then
    update public.profiles set role=p_role,updated_at=now() where id=p_user_id;
    perform public._hyn_audit('client.role.'||p_role,p_user_id,null,jsonb_build_object('previous_role',v_old));
  end if;
  return json_build_object('status','ok','role',p_role);
end $$;
create or replace function public.hyn_admin_promote_by_email(p_email text)
returns json language plpgsql security definer set search_path=public as $$
declare v_target uuid; v_role text;
begin
  perform public._hyn_require_staff();
  select id,role into v_target,v_role from public.profiles where lower(email)=lower(trim(p_email));
  if not found then return json_build_object('status','not_found'); end if;
  if v_role='super_admin' then raise exception 'this account is already a super admin'; end if;
  perform public.hyn_admin_set_role(v_target,'admin');
  return json_build_object('status','ok','user_id',v_target);
end $$;


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
            then n.last_heartbeat_at is null or n.last_heartbeat_at <= now() - interval '3 minutes'
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

create or replace function public.hyn_admin_nodes()
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  perform public._hyn_require_staff();
  select coalesce(json_agg(row_to_json(x) order by x.last_heartbeat_at desc nulls last), '[]'::json)
    into v from (
      select n.id, n.name, n.hostname, n.os, n.agent_version, n.status,
             n.paused_until, n.status_reason, n.revoked, n.is_demo,
             n.created_at, n.last_seen_at, n.last_config_pull_at, n.last_heartbeat_at, n.config,
             p.id as owner_id, p.email as owner_email, p.status as owner_status, p.role as owner_role,
             public._hyn_node_ever_connected(n) as ever_connected,
             (select count(*) from public.notification_log l where l.node_id = n.id and l.ts > now() - interval '24 hours') as notifications_24h,
             (select count(*) from public.notification_log l where l.node_id = n.id and l.ts > now() - interval '24 hours' and l.status = 'failed') as notifications_failed_24h,
             (select count(*) from public.alert_events a where a.node_id = n.id and a.resolved = false and a.ts > now() - interval '7 days') as alerts_open,
             (select m.cpu_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_cpu_pct,
             (select m.cpu_temp_c from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_temp_c,
             (select m.mem_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_mem_pct,
             (select m.disk_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_disk_pct,
             (select m.payload #>> '{agent_update,latest}' from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as latest_agent_version,
             coalesce((select m.payload #>> '{agent_update,available}' in ('true', '1') from public.metrics m where m.node_id = n.id order by m.ts desc limit 1), false) as update_available
        from public.nodes n left join public.profiles p on p.id = n.owner
    ) x;
  return v;
end;
$$;

create or replace function public.hyn_admin_clients()
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  perform public._hyn_require_staff();
  select coalesce(json_agg(row_to_json(x) order by x.created_at desc), '[]'::json)
    into v from (
      select p.id, p.email, p.full_name, p.role, p.status, p.suspended_reason, p.created_at,
             (select count(*) from public.nodes n where n.owner = p.id and n.is_demo = false) as nodes,
             (select count(*) from public.nodes n where n.owner = p.id and n.status = 'active'
                and n.revoked = false and n.is_demo = false) as nodes_active,
             (select count(*) from public.nodes n where n.owner = p.id and n.is_demo = false
                and not public._hyn_node_ever_connected(n)) as nodes_unlinked,
             (select count(*) from public.notification_log l where l.owner = p.id
                and l.ts > now() - interval '30 days') as notifications_30d,
             (select count(*) from public.notification_log l where l.owner = p.id
                and l.ts > now() - interval '30 days' and l.status = 'failed') as notifications_failed_30d,
             (select max(n.last_seen_at) from public.nodes n where n.owner = p.id) as last_seen_at
        from public.profiles p
    ) x;
  return v;
end;
$$;

create or replace function public.hyn_admin_notifications(p_limit integer default 200)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v json;
begin
  perform public._hyn_require_staff();
  select coalesce(json_agg(row_to_json(x) order by x.ts desc), '[]'::json)
    into v
    from (
      select l.id, l.ts, l.kind, l.target, l.severity, l.subject, l.status, l.error, l.category,
             n.name as node_name, p.email as owner_email
        from public.notification_log l
        left join public.nodes n on n.id = l.node_id
        left join public.profiles p on p.id = l.owner
       order by l.ts desc
       limit least(greatest(coalesce(p_limit, 200), 1), 1000)
    ) x;
  return v;
end;
$$;

create or replace function public.hyn_admin_audit(p_limit integer default 100)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v json;
begin
  perform public._hyn_require_staff();
  select coalesce(json_agg(row_to_json(x) order by x.ts desc), '[]'::json)
    into v
    from (
      select a.id, a.ts, a.actor_email, a.action, a.detail,
             a.target_user, a.target_node,
             n.name as target_node_name,
             p.email as target_user_email
        from public.admin_audit a
        left join public.nodes n on n.id = a.target_node
        left join public.profiles p on p.id = a.target_user
       order by a.ts desc
       limit least(greatest(coalesce(p_limit, 100), 1), 1000)
    ) x;
  return v;
end;
$$;

create or replace function public.hyn_admin_templates()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v json;
begin
  perform public._hyn_require_staff();
  select coalesce(json_agg(row_to_json(x) order by x.template_key), '[]'::json)
    into v
    from (
      select t.template_key, t.name, t.description, t.html_template, t.updated_at,
             p.email as updated_by_email
        from public.notification_templates t
        left join public.profiles p on p.id = t.updated_by
       order by t.template_key
    ) x;
  return v;
end;
$$;

create or replace function public.hyn_admin_set_user_status(
  p_user_id uuid,
  p_status text,
  p_reason text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  perform pg_advisory_xact_lock(74821901);
  v_actor := public._hyn_require_admin();
  if p_status not in ('active', 'suspended') then
    raise exception 'unknown status: %', p_status;
  end if;
  -- Locking yourself out is never the intent.
  if p_user_id = v_actor and p_status = 'suspended' then
    raise exception 'refusing to suspend your own account';
  end if;

  update public.profiles
     set status = p_status,
         suspended_reason = case when p_status = 'suspended' then left(p_reason, 300) else null end,
         updated_at = now()
   where id = p_user_id;
  if not found then
    raise exception 'no such client';
  end if;

  -- Suspending a client suspends their fleet, otherwise their boxes keep
  -- reporting into an account nobody is allowed to look at.
  if p_status = 'suspended' then
    update public.nodes set status = 'suspended',
           status_reason = 'account suspended'
     where owner = p_user_id and status <> 'suspended';
  else
    update public.nodes set status = 'active', status_reason = null, paused_until = null
     where owner = p_user_id and status = 'suspended'
       and status_reason = 'account suspended';
  end if;

  perform public._hyn_audit('client.status.' || p_status, p_user_id, null,
    jsonb_build_object('reason', p_reason));

  return json_build_object('status', 'ok', 'client_status', p_status);
end;
$$;

create or replace function public.hyn_device_approve(
  p_user_code text,
  p_node_name text default null
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v device_codes;
  v_node_id uuid;
  v_node_token text;
  v_uid uuid := auth.uid();
begin
  perform public._hyn_require_admin();
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into v
    from public.device_codes d
   where d.user_code_verifier = extensions.crypt(
           upper(trim(p_user_code)), d.user_code_verifier
         )
   order by d.created_at desc
   limit 1;

  -- Global cleanup always precedes the single-row approval lock. Purge workers
  -- use ordered SKIP LOCKED scans, eliminating cross-row lock cycles.
  perform public._hyn_purge_expired_device_codes();

  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    return json_build_object('status', 'expired');
  end if;

  select * into v from public.device_codes where id = v.id for update;
  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    perform public._hyn_delete_expired_device_code(v.id);
    return json_build_object('status', 'expired');
  end if;
  if v.node_id is not null then
    return json_build_object('status', 'already_approved');
  end if;

  v_node_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.nodes (owner, name, hostname, os, agent_version, token_hash)
  values (
    v_uid,
    coalesce(nullif(trim(p_node_name), ''), nullif(v.hostname, ''), 'node'),
    v.hostname, v.os, v.agent_version,
    public._hyn_sha256(v_node_token)
  )
  returning id into v_node_id;

  update public.device_codes
     set approved_by = v_uid,
         node_id = v_node_id,
         node_token_hash = public._hyn_sha256(v_node_token)
   where id = v.id;

  -- The plaintext token is handed to the polling server, not to this browser.
  -- Stashing it here (hashed) is what lets the poll succeed exactly once.
  return json_build_object(
    'status', 'approved',
    'node_id', v_node_id,
    'node_name', coalesce(nullif(trim(p_node_name), ''), nullif(v.hostname, ''), 'node')
  );
end;
$$;

create or replace function public.hyn_demo_seed()
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_node_id uuid;
  i integer;
  v_ts timestamptz;
  v_cpu numeric;
begin
  perform public._hyn_require_admin();
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  delete from public.nodes where owner = v_uid and is_demo = true;

  insert into public.nodes (owner, name, hostname, os, agent_version, is_demo)
  values (v_uid, 'demo-node', 'demo-node', 'Ubuntu 24.04 LTS (demo)', '0.0.0-demo', true)
  returning id into v_node_id;

  for i in 0..287 loop
    v_ts := now() - (i * interval '5 minutes');
    v_cpu := 18 + 22 * abs(sin(i / 26.0)) + (random() * 9);
    insert into public.metrics (
      node_id, ts, cpu_pct, cpu_temp_c, cpu_mhz, cpu_model, cpu_steal, cpu_iowait, cpu_cores,
      load1, mem_pct, mem_total, mem_used, swap_used, disk_pct, uptime_s,
      net_iface, net_rx_bps, net_tx_bps, net_retrans_pm, latency_ms, payload
    ) values (
      v_node_id, v_ts,
      round(v_cpu, 1),
      round((41 + v_cpu * 0.32 + random() * 2)::numeric, 1),
      round((2400 + v_cpu * 14 + random() * 60)::numeric),
      'AMD EPYC 9354 32-Core (demo)',
      round((random() * 2)::numeric, 2),
      round((random() * 4)::numeric, 2),
      8,
      round(((v_cpu / 100.0) * 8 * 0.7)::numeric, 2),
      round((52 + 9 * sin(i / 41.0) + random() * 3)::numeric, 1),
      33285996544, 17301504000, 0,
      round((58 + (i / 288.0) * 3)::numeric, 1),
      1900800 - (i * 300),
      'eth0',
      (620000000 + random() * 260000000)::bigint,
      (180000000 + random() * 90000000)::bigint,
      round((random() * 7)::numeric, 2),
      round((7 + random() * 4)::numeric, 2),
      -- The Highway section of the payload, so the demo dashboard shows the
      -- node panel the way a paired relay would. Same key names as the agent's
      -- `highway` object in lib/cloud.sh; flagged demo like everything else here.
      jsonb_build_object(
        'demo', true,
        'highway', jsonb_build_object(
          'present', 1,
          'tracked', true,
          'health', 'ok',
          'health_why', '2 unit(s) active',
          'version', 'v0.1.75',
          'version_src', 'file',
          'latest', 'v0.1.80',
          'update_available', 1,
          'bin_path', '/usr/local/bin/highway',
          'bin_size', 48234496,
          'bin_mtime', extract(epoch from now() - interval '9 days')::bigint,
          'units_total', 2,
          'units_active', 2,
          'units_failed', 0,
          'units', jsonb_build_array(
            jsonb_build_object(
              'name', 'highway.service', 'state', 'active', 'sub', 'running',
              'restarts', 1, 'memory', (402653184 + random() * 20000000)::bigint,
              'active_s', 1900800 - (i * 300)
            ),
            jsonb_build_object(
              'name', 'nebula.service', 'state', 'active', 'sub', 'running',
              'restarts', 0, 'memory', 18874368,
              'active_s', 1900800 - (i * 300)
            )
          ),
          'pid', 1471,
          'cpu_tenths', (40 + random() * 60)::int,
          'rss', (402653184 + random() * 20000000)::bigint,
          'threads', 19,
          'fds', 48,
          'proc_uptime_s', 1900800 - (i * 300),
          'mesh_iface', 'nebula1',
          'mesh_rx_bps', (900000 + random() * 400000)::bigint,
          'mesh_tx_bps', (700000 + random() * 300000)::bigint,
          'mesh_rx_total', 88000000000::bigint,
          'mesh_tx_total', 44000000000::bigint,
          'mesh_drops', 0,
          'qdisc', 'fq_codel',
          'qdisc_drops', 0,
          'congestion', 'bbr',
          'nft_tables', 3,
          'journal_err_1h', 0,
          'journal_warn_1h', 2,
          'journal_tail', jsonb_build_array(
            'demo: peer handshake retry', 'demo: lighthouse reconnect'
          )
        )
      )
    ) on conflict (node_id, ts) do nothing;
  end loop;

  for i in 0..11 loop
    insert into public.speedtests (node_id, ts, down_bps, up_bps, latency_ms, note)
    values (
      v_node_id, now() - (i * interval '6 hours'),
      (720000000 + random() * 180000000)::bigint,
      (330000000 + random() * 120000000)::bigint,
      round((8 + random() * 5)::numeric, 2), 'demo'
    ) on conflict (node_id, ts) do nothing;
  end loop;

  insert into public.alert_events (node_id, ts, rule, severity, message, resolved) values
    (v_node_id, now() - interval '3 hours',  'cpu_temp',  'warn', 'CPU temperature 71C above threshold 70C', true),
    (v_node_id, now() - interval '19 hours', 'disk_pct',  'warn', 'Filesystem / at 86% (projected full in 12 days)', false),
    (v_node_id, now() - interval '2 days',   'unit_failed', 'crit', 'systemd unit highway.service entered failed state', true),
    (v_node_id, now() - interval '4 days',   'report',    'info', 'Daily report delivered', true);

  return json_build_object('status', 'ok', 'node_id', v_node_id);
end;
$$;

create or replace function public.hyn_demo_clear()
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
begin
  perform public._hyn_require_admin();
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  delete from public.nodes where owner = v_uid and is_demo = true;
  get diagnostics v_count = row_count;
  return json_build_object('status', 'ok', 'removed', v_count);
end;
$$;

create or replace function public.hyn_update_node_config(p_node_id uuid, p_config jsonb)
returns json language plpgsql security definer set search_path = public as $$
declare v_config jsonb;
begin
  perform public._hyn_require_admin();
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'not authenticated'; end if;
  if not public._hyn_portal_config_valid(p_config) then raise exception 'invalid portal configuration'; end if;
  update public.nodes set config = p_config
   where id = p_node_id and owner = auth.uid() and revoked = false and is_demo = false
  returning config into v_config;
  if not found then raise exception 'node not found'; end if;
  return json_build_object('status', 'ok', 'config', v_config);
end;
$$;

create or replace function public.hyn_claim_device_linked_email(p_node_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_node public.nodes; v_recipient text; v_key text;
begin
  perform public._hyn_require_admin();
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into v_node from public.nodes
   where id = p_node_id and owner = auth.uid() and revoked = false and is_demo = false;
  if not found then raise exception 'node not found'; end if;
  select recipient into v_recipient from public.email_preferences where node_id = v_node.id;
  if not found then return json_build_object('status', 'skip', 'reason', 'email preference missing'); end if;
  v_key := 'device-linked:' || v_node.id::text;
  insert into public.cloud_email_dispatches (idempotency_key, node_id, kind)
  values (v_key, v_node.id, 'system') on conflict (idempotency_key) do nothing;
  if not found then return json_build_object('status', 'skip', 'reason', 'already sent'); end if;
  return json_build_object(
    'status', 'send', 'node_id', v_node.id, 'node_name', v_node.name,
    'hostname', v_node.hostname, 'os', v_node.os, 'agent_version', v_node.agent_version,
    'recipient', v_recipient, 'linked_at', v_node.created_at
  );
end;
$$;

create or replace function public.hyn_complete_device_linked_email(p_node_id uuid, p_provider_id text default null)
returns json language plpgsql security definer set search_path = public as $$
begin
  perform public._hyn_require_admin();
  if auth.uid() is null or not exists (
    select 1 from public.nodes where id = p_node_id and owner = auth.uid()
  ) then raise exception 'node not found'; end if;
  update public.cloud_email_dispatches set provider_id = left(nullif(p_provider_id, ''), 200)
   where idempotency_key = 'device-linked:' || p_node_id::text and node_id = p_node_id;
  return json_build_object('status', 'ok');
end;
$$;

create or replace function public.hyn_release_device_linked_email(p_node_id uuid)
returns json language plpgsql security definer set search_path = public as $$
begin
  perform public._hyn_require_admin();
  if auth.uid() is null or not exists (
    select 1 from public.nodes where id = p_node_id and owner = auth.uid()
  ) then raise exception 'node not found'; end if;
  delete from public.cloud_email_dispatches
   where idempotency_key = 'device-linked:' || p_node_id::text
     and node_id = p_node_id and provider_id is null;
  return json_build_object('status', 'ok');
end;
$$;

create or replace function public.hyn_request_relayer(p_relayer_id integer, p_relayer_name text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not public.hyn_can_monitor() then raise exception 'monitor or super administrator role required'; end if;
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'An active account is required'; end if;
  if p_relayer_id is null or p_relayer_id<=0 or p_relayer_name is null or length(trim(p_relayer_name)) not between 1 and 160 then
    raise exception 'A positive relayer ID and name are required';
  end if;
  -- Serialize this owner's submissions so concurrent calls cannot evade limits.
  perform 1 from public.profiles where id=auth.uid() for update;
  if exists(select 1 from public.relayer_assignments where relayer_id=p_relayer_id) then
    raise exception 'This relayer is already assigned. Ask an administrator to check its assignment';
  end if;
  select id into v_id from public.relayer_requests where owner=auth.uid() and relayer_id=p_relayer_id and status='pending';
  if v_id is not null then return v_id; end if;
  if (select count(*) from public.relayer_requests where owner=auth.uid() and status='pending')>=10 then
    raise exception 'You already have 10 pending requests. Cancel one or wait for a review';
  end if;
  if not exists(select 1 from public.relayer_requests where owner=auth.uid() and relayer_id=p_relayer_id)
     and (select count(*) from public.relayer_requests where owner=auth.uid())>=50 then
    raise exception 'Request limit reached. Contact an administrator';
  end if;
  insert into public.relayer_requests(owner,relayer_id,relayer_name)
    values(auth.uid(),p_relayer_id,trim(p_relayer_name))
    on conflict(owner,relayer_id) do update set relayer_name=excluded.relayer_name,status='pending',created_at=now(),reviewed_at=null,reviewed_by=null
    returning id into v_id;
  return v_id;
end $$;

create or replace function public.hyn_cancel_relayer_request(p_request_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.hyn_can_monitor() then raise exception 'monitor or super administrator role required'; end if;
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'An active account is required'; end if;
  update public.relayer_requests set status='cancelled',reviewed_at=now()
    where id=p_request_id and owner=auth.uid() and status='pending';
  if not found then raise exception 'Pending request not found'; end if;
end $$;

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
  if not exists(select 1 from public.nodes where id=p_node_id and public.hyn_can_view_dashboard(owner)) then
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

create or replace function public.hyn_claim_env_admin(p_caller_email text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_real_email text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select email into v_real_email from auth.users where id = v_uid;
  if v_real_email is null then
    return json_build_object('status', 'no_email');
  end if;
  -- p_caller_email is optional now that the list lives here; when supplied it
  -- must be the caller's own address.
  if p_caller_email is not null and p_caller_email <> ''
     and lower(v_real_email) <> lower(p_caller_email) then
    raise exception 'email does not match the authenticated session';
  end if;

  if not exists (
    select 1 from public.admin_allowlist a where lower(a.email) = lower(v_real_email)
  ) then
    return json_build_object('status', 'not_allowed');
  end if;

  perform pg_advisory_xact_lock(74821901);
  if not public.hyn_is_active() then raise exception 'active account required'; end if;
  delete from public.admin_allowlist where lower(email)=lower(v_real_email);
  if not found then return json_build_object('status','not_allowed'); end if;
  perform public._hyn_audit('client.role.super_admin',v_uid,null,jsonb_build_object('via','bootstrap_allowlist'));
  update public.profiles
     set role = 'super_admin', updated_at = now()
   where id = v_uid and role <> 'super_admin';

  return json_build_object('status', 'ok', 'role', 'super_admin');
end;
$$;

-- Remove Supabase's table-wide default UPDATE grant before column grants.
-- Otherwise a Super admin could bypass role auditing and the self-lockout guard.
revoke update on public.profiles from authenticated;
grant update(full_name) on public.profiles to authenticated;
revoke update on public.nodes from authenticated;
grant update(name,revoked,config) on public.nodes to authenticated;

-- Read grants contain telemetry only; node credential hashes remain ungranted.
drop policy if exists nodes_select_own on public.nodes;
create policy nodes_select_own on public.nodes for select to authenticated using(public.hyn_can_view_dashboard(owner));
drop policy if exists nodes_update_own on public.nodes;
create policy nodes_update_own on public.nodes for update to authenticated using(public.hyn_is_super_admin()) with check(public.hyn_is_super_admin());
drop policy if exists nodes_delete_own on public.nodes;
create policy nodes_delete_own on public.nodes for delete to authenticated using(public.hyn_is_super_admin());
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated using(id=auth.uid() and public.hyn_is_super_admin()) with check(id=auth.uid() and public.hyn_is_super_admin());


drop policy if exists metrics_select_own on public.metrics;
create policy metrics_select_own on public.metrics for select to authenticated using(exists(select 1 from public.nodes n where n.id=metrics.node_id and public.hyn_can_view_dashboard(n.owner)));

drop policy if exists speedtests_select_own on public.speedtests;
create policy speedtests_select_own on public.speedtests for select to authenticated using(exists(select 1 from public.nodes n where n.id=speedtests.node_id and public.hyn_can_view_dashboard(n.owner)));

drop policy if exists alert_events_select_own on public.alert_events;
create policy alert_events_select_own on public.alert_events for select to authenticated using(exists(select 1 from public.nodes n where n.id=alert_events.node_id and public.hyn_can_view_dashboard(n.owner)));

drop policy if exists node_commands_select_own on public.node_commands;
create policy node_commands_select_own on public.node_commands for select to authenticated using(exists(select 1 from public.nodes n where n.id=node_commands.node_id and public.hyn_can_view_dashboard(n.owner)));

drop policy if exists relayer_assignments_read on public.relayer_assignments;
create policy relayer_assignments_read on public.relayer_assignments for select to authenticated using(public.hyn_can_view_dashboard(owner));
drop policy if exists notification_log_select_own on public.notification_log;
create policy notification_log_select_own on public.notification_log for select to authenticated using(public.hyn_is_active() and (owner=auth.uid() or public.hyn_is_admin()));


drop policy if exists email_preferences_insert_own on public.email_preferences;
create policy email_preferences_insert_own on public.email_preferences for insert to authenticated with check(public.hyn_is_super_admin() and exists(select 1 from public.nodes where id=node_id and owner=auth.uid()));

drop policy if exists email_preferences_update_own on public.email_preferences;
create policy email_preferences_update_own on public.email_preferences for update to authenticated using(public.hyn_is_super_admin() and exists(select 1 from public.nodes where id=node_id and owner=auth.uid())) with check(public.hyn_is_super_admin() and exists(select 1 from public.nodes where id=node_id and owner=auth.uid()));

revoke all on function public._hyn_require_staff() from public,anon,authenticated;
do $$ begin
  if exists(select 1 from pg_roles where rolname='service_role') then
    revoke all on function public._hyn_require_staff() from service_role;
  end if;
end $$;

revoke all on function public.hyn_is_super_admin() from public,anon;
grant execute on function public.hyn_is_super_admin() to authenticated;

revoke all on function public.hyn_can_monitor() from public,anon;
grant execute on function public.hyn_can_monitor() to authenticated;

revoke all on function public.hyn_can_view_dashboard(uuid) from public,anon;
grant execute on function public.hyn_can_view_dashboard(uuid) to authenticated;

revoke all on function public.hyn_dashboard_accounts() from public,anon;
grant execute on function public.hyn_dashboard_accounts() to authenticated;

revoke all on function public.hyn_admin_set_dashboard_access(uuid,uuid,boolean) from public,anon;
grant execute on function public.hyn_admin_set_dashboard_access(uuid,uuid,boolean) to authenticated;

notify pgrst, 'reload schema';
commit;
