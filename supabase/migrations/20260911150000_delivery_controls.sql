-- Managed email budgets, an append-only attempt history, and user digests.
-- Existing email preferences are not enabled, disabled, or deleted by this migration.
begin;

create table if not exists public.delivery_rules (
  scope text not null,
  owner uuid references public.profiles(id) on delete cascade,
  kind text not null check(kind in('all','daily','incident','system','command','signin','device','first_report','admin_report','other')),
  enabled boolean not null default true,
  daily_limit integer check(daily_limit between 0 and 100000),
  max_attempts integer not null default 3 check(max_attempts between 1 and 5),
  retry_minutes integer not null default 15 check(retry_minutes between 1 and 1440),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(scope,kind),
  check((scope='global' and owner is null) or (owner is not null and scope=owner::text))
);
insert into public.delivery_rules(scope,kind) values('global','all') on conflict do nothing;
create table if not exists public.delivery_digest_settings (
  scope text primary key,
  owner uuid references public.profiles(id) on delete cascade,
  configured boolean not null default false,
  enabled boolean not null default false,
  send_at time not null default '08:00',
  timezone text not null default 'UTC',
  updated_at timestamptz not null default now(),
  check((scope='global' and owner is null) or (owner is not null and scope=owner::text))
);
insert into public.delivery_digest_settings(scope) values('global') on conflict do nothing;
create table if not exists public.delivery_events (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique check(length(source_key) between 1 and 500),
  owner uuid not null references public.profiles(id) on delete cascade,
  node_id uuid references public.nodes(id) on delete set null,
  node_label text,
  kind text not null check(kind in('daily','incident','system','command','signin','device','first_report','admin_report','other')),
  recipient text not null,
  subject text not null,
  status text not null default 'pending' check(status in('pending','sending','sent','failed','suppressed','cancelled','unknown')),
  reason text,
  attempt_count integer not null default 0,
  attempt_limit integer not null default 3,
  retry_minutes integer not null default 15,
  terminal boolean not null default false,
  next_retry_at timestamptz,
  last_attempt uuid,
  provider_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.delivery_events(id) on delete cascade,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'sending' check(status in('sending','sent','failed','unknown')),
  provider_id text,
  error text
);
create index if not exists delivery_attempts_day_idx on public.delivery_attempts(started_at,event_id);
create index if not exists delivery_attempts_event_idx on public.delivery_attempts(event_id,started_at);
create index if not exists delivery_events_owner_idx on public.delivery_events(owner,updated_at desc);
create index if not exists delivery_events_updated_idx on public.delivery_events(updated_at desc);
alter table public.delivery_rules enable row level security;
alter table public.delivery_digest_settings enable row level security;
alter table public.delivery_events enable row level security;
alter table public.delivery_attempts enable row level security;
revoke all on public.delivery_rules,public.delivery_digest_settings,public.delivery_events,public.delivery_attempts from public,anon,authenticated;

create or replace function public._hyn_digest_setting(p_owner uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce((select to_jsonb(s) from public.delivery_digest_settings s where s.owner=p_owner),
    (select to_jsonb(s) from public.delivery_digest_settings s where s.scope='global'));
$$;

-- Equivalent to current server visibility, with the notification opt-out also
-- applied. Never adopt an arbitrary owner's entire fleet for a shared viewer.
create or replace function public._hyn_digest_nodes(p_owner uuid)
returns setof public.nodes language sql stable security definer set search_path=public as $$
  select n.* from public.profiles viewer cross join public.nodes n
    join public.profiles owner_profile on owner_profile.id=n.owner
  where viewer.id=p_owner and viewer.status='active' and not n.revoked and not n.is_demo
    and (viewer.role in('admin','super_admin') or (owner_profile.status='active' and
      (n.owner=p_owner or coalesce((select a.allowed from public.server_access a where a.viewer_id=p_owner and a.node_id=n.id),
        exists(select 1 from public.dashboard_access d where d.viewer_id=p_owner and d.owner_id=n.owner)))))
    and (n.owner=p_owner or viewer.role in('admin','super_admin') or coalesce(
      (select a.notifications_allowed from public.server_access a where a.viewer_id=p_owner and a.node_id=n.id),true));
$$;

create or replace function public.hyn_admin_set_delivery_rules(p_owner uuid,p_rules jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare r jsonb; v_scope text:=coalesce(p_owner::text,'global');
begin
  perform public._hyn_require_admin();
  if p_owner is not null and not exists(select 1 from public.profiles where id=p_owner and status='active') then raise exception 'choose an active user'; end if;
  if p_rules is null or jsonb_typeof(p_rules)<>'array' or jsonb_array_length(p_rules) not between 1 and 10 then raise exception 'choose valid delivery rules'; end if;
  if (select count(*) from jsonb_array_elements(p_rules))<>(select count(distinct value->>'kind') from jsonb_array_elements(p_rules)) then raise exception 'duplicate delivery types'; end if;
  for r in select value from jsonb_array_elements(p_rules) loop
    if jsonb_typeof(r->'enabled') is distinct from 'boolean' or jsonb_typeof(r->'max_attempts') is distinct from 'number'
      or jsonb_typeof(r->'retry_minutes') is distinct from 'number'
      or coalesce(jsonb_typeof(r->'daily_limit'),'null') not in('null','number') then raise exception 'invalid delivery rule fields'; end if;
    insert into public.delivery_rules(scope,owner,kind,enabled,daily_limit,max_attempts,retry_minutes)
    values(v_scope,p_owner,r->>'kind',(r->>'enabled')::boolean,(r->>'daily_limit')::integer,(r->>'max_attempts')::integer,(r->>'retry_minutes')::integer)
    on conflict(scope,kind) do update set enabled=excluded.enabled,daily_limit=excluded.daily_limit,
      max_attempts=excluded.max_attempts,retry_minutes=excluded.retry_minutes,updated_at=now();
  end loop;
  perform public._hyn_audit('delivery.rules',p_owner,null,jsonb_build_object('rules',p_rules));
end $$;

create or replace function public.hyn_admin_set_digest(p_owner uuid,p_enabled boolean,p_at text,p_timezone text,p_inherit boolean default false,p_confirm_all boolean default false)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public._hyn_require_admin();
  if p_owner is null and p_confirm_all is distinct from true then raise exception 'confirm the global daily email change'; end if;
  if p_owner is not null and not exists(select 1 from public.profiles where id=p_owner and status='active') then raise exception 'choose an active user'; end if;
  if p_inherit then
    if p_owner is null then raise exception 'global settings cannot inherit'; end if;
    delete from public.delivery_digest_settings where owner=p_owner;
  else
    if p_enabled is null or p_at is null or p_at !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      or not exists(select 1 from pg_timezone_names where name=p_timezone) then raise exception 'choose a valid time and timezone'; end if;
    insert into public.delivery_digest_settings(scope,owner,configured,enabled,send_at,timezone)
    values(coalesce(p_owner::text,'global'),p_owner,true,p_enabled,p_at::time,p_timezone)
    on conflict(scope) do update set configured=true,enabled=excluded.enabled,send_at=excluded.send_at,timezone=excluded.timezone,updated_at=now();
  end if;
  perform public._hyn_audit('delivery.daily_digest',p_owner,null,jsonb_build_object('enabled',p_enabled,'at',p_at,'timezone',p_timezone,'inherit',p_inherit));
end $$;

create or replace function public.hyn_reserve_delivery(p_key text,p_kind text,p_owner uuid,p_node uuid,p_recipient text,p_subject text,p_nodes uuid[] default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_owner uuid:=p_owner; v_node public.nodes; e public.delivery_events; r public.delivery_rules;
  v_start timestamptz:=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
  v_reason text; v_retry timestamptz; v_limit integer:=5; v_wait integer:=1; v_used bigint;
  v_attempt uuid; v_allowed uuid[]; v_requested uuid[]; v_setting jsonb;
begin
  if p_key is null or length(p_key) not between 1 and 500 or p_kind is null or p_kind not in('daily','incident','system','command','signin','device','first_report','admin_report','other')
    or p_recipient is null or length(p_recipient)>320 or p_recipient !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or p_subject is null or length(p_subject) not between 1 and 500 then raise exception 'invalid managed delivery'; end if;
  if p_node is not null then
    select * into v_node from public.nodes where id=p_node and not revoked and not is_demo;
    if not found or (v_owner is not null and v_owner<>v_node.owner) then return jsonb_build_object('allowed',false,'reason','Server access changed. No email was sent.'); end if;
    v_owner:=v_node.owner;
  end if;
  if not exists(select 1 from public.profiles where id=v_owner and status='active') then return jsonb_build_object('allowed',false,'reason','Recipient account is unavailable.'); end if;
  -- Serialize reservations across the provider for exact global and user caps,
  -- even when many telemetry uploads and the cron run concurrently.
  perform pg_advisory_xact_lock(hashtextextended('hyn-delivery:'||v_start::text,0));
  insert into public.delivery_events(source_key,owner,node_id,node_label,kind,recipient,subject)
    values(p_key,v_owner,p_node,v_node.name,p_kind,p_recipient,p_subject) on conflict(source_key) do nothing;
  select * into e from public.delivery_events where source_key=p_key for update;
  if e.owner<>v_owner or e.kind<>p_kind or e.recipient<>p_recipient then raise exception 'delivery identity changed'; end if;
  if e.status='sent' then return jsonb_build_object('allowed',false,'already_sent',true,'provider_id',e.provider_id); end if;
  if e.terminal then return jsonb_build_object('allowed',false,'reason',coalesce(e.reason,'Automatic retries have stopped.')); end if;
  if e.status='sending' then
    if e.updated_at<now()-interval '5 minutes' then
      update public.delivery_attempts set status='unknown',finished_at=now(),error='Worker outcome is unknown; review provider before resending.' where id=e.last_attempt and status='sending';
      update public.delivery_events set status='unknown',terminal=true,reason='Worker outcome is unknown; review provider before resending.',updated_at=now() where id=e.id;
    end if;
    return jsonb_build_object('allowed',false,'reason','A delivery attempt is already in progress or requires provider review.');
  end if;
  if e.next_retry_at>now() then return jsonb_build_object('allowed',false,'reason',coalesce(e.reason,'Waiting before retrying.')); end if;
  if p_kind='daily' then
    v_setting:=public._hyn_digest_setting(v_owner);
    if p_nodes is not null then
      select coalesce(array_agg(n.id order by n.id),'{}'::uuid[]) into v_allowed from public._hyn_digest_nodes(v_owner) n;
      select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_requested from (select distinct unnest(p_nodes) id) x;
      if not coalesce((v_setting->>'configured')::boolean,false) or not coalesce((v_setting->>'enabled')::boolean,false)
        or cardinality(v_allowed)=0 or v_allowed<>v_requested
        or p_recipient is distinct from (select email from public.profiles where id=v_owner) then
        v_reason:='Daily digest permissions or settings changed. Rebuild before sending.'; v_retry:=now()+interval '15 minutes';
      end if;
    elsif coalesce((v_setting->>'configured')::boolean,false) then
      v_reason:='Per-server daily email is replaced by this user''s combined-digest setting.';
    end if;
  end if;
  for r in select * from public.delivery_rules where scope in('global',v_owner::text) and kind in('all',p_kind) loop
    v_limit:=least(v_limit,r.max_attempts); v_wait:=greatest(v_wait,r.retry_minutes);
    if not r.enabled then v_reason:='Sending is paused by an administrator.'; v_retry:=now()+interval '15 minutes'; end if;
    if r.daily_limit is not null then
      select count(*) into v_used from public.delivery_attempts a join public.delivery_events d on d.id=a.event_id
        where a.started_at>=v_start and (r.owner is null or d.owner=r.owner) and (r.kind='all' or d.kind=r.kind);
      if v_used>=r.daily_limit then v_reason:='Daily sending cap reached. Resets at midnight UTC.'; v_retry:=v_start+interval '1 day'; end if;
    end if;
  end loop;
  if e.attempt_count>=v_limit then
    update public.delivery_events set terminal=true,status='suppressed',reason='Retry limit reached. Automatic sending stopped.',updated_at=now() where id=e.id;
    return jsonb_build_object('allowed',false,'reason','Retry limit reached. Automatic sending stopped.');
  end if;
  if v_reason is not null then
    update public.delivery_events set status='suppressed',reason=v_reason,next_retry_at=v_retry,updated_at=now() where id=e.id;
    return jsonb_build_object('allowed',false,'reason',v_reason);
  end if;
  insert into public.delivery_attempts(event_id) values(e.id) returning id into v_attempt;
  update public.delivery_events set status='sending',attempt_count=attempt_count+1,attempt_limit=v_limit,retry_minutes=v_wait,
    last_attempt=v_attempt,next_retry_at=null,reason=null,updated_at=now() where id=e.id;
  return jsonb_build_object('allowed',true,'attempt_id',v_attempt);
end $$;

create or replace function public.hyn_complete_delivery(p_attempt uuid,p_status text,p_provider_id text default null,p_error text default null)
returns void language plpgsql security definer set search_path=public as $$
declare a public.delivery_attempts; e public.delivery_events;
begin
  if p_status is null or p_status not in('sent','failed','unknown') then raise exception 'invalid delivery result'; end if;
  select * into a from public.delivery_attempts where id=p_attempt;
  if not found then raise exception 'delivery attempt not found'; end if;
  select * into e from public.delivery_events where id=a.event_id for update;
  if e.last_attempt is distinct from p_attempt or e.status<>'sending' then return; end if;
  update public.delivery_attempts set status=p_status,finished_at=now(),provider_id=left(p_provider_id,200),error=left(p_error,1000) where id=p_attempt;
  update public.delivery_events set status=p_status,provider_id=left(p_provider_id,200),
    reason=case when p_status='unknown' then 'Provider outcome is unknown. Review before resending.' when p_status='failed' and attempt_count>=attempt_limit then 'Retry limit reached. '||coalesce(left(p_error,900),'Provider rejected the message.') else left(p_error,1000) end,
    terminal=(p_status in('sent','unknown') or attempt_count>=attempt_limit),
    next_retry_at=case when p_status='failed' and attempt_count<attempt_limit then now()+make_interval(mins=>retry_minutes) else null end,
    updated_at=now() where id=e.id;
end $$;

create or replace function public.hyn_admin_stop_delivery(p_event uuid)
returns void language plpgsql security definer set search_path=public as $$
declare e public.delivery_events;
begin
  perform public._hyn_require_admin();
  select * into e from public.delivery_events where id=p_event for update;
  if not found then raise exception 'delivery not found'; end if;
  if e.status in('sending','sent') then raise exception 'a message already sending or accepted cannot be recalled'; end if;
  update public.delivery_events set status='cancelled',terminal=true,next_retry_at=null,reason='Further attempts stopped by administrator.',updated_at=now() where id=e.id;
  perform public._hyn_audit('delivery.stop',e.owner,e.node_id,jsonb_build_object('event',e.id));
end $$;

create or replace function public.hyn_due_user_digests(p_trigger_node uuid default null)
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (
    select p.id owner,((now() at time zone (s->>'timezone'))::date)::text local_date
    from public.profiles p cross join lateral (select public._hyn_digest_setting(p.id) s) settings
    left join public.delivery_events e on e.source_key='user-digest:'||p.id::text||':'||((now() at time zone (s->>'timezone'))::date)::text
    where p.status='active' and p.email is not null and (s->>'configured')::boolean and (s->>'enabled')::boolean
      and (now() at time zone (s->>'timezone'))::time >= (s->>'send_at')::time
      and (e.id is null or (not e.terminal and e.status<>'sending' and (e.next_retry_at is null or e.next_retry_at<=now())))
      and exists(select 1 from public._hyn_digest_nodes(p.id) n where p_trigger_node is null or n.id=p_trigger_node)
    order by e.updated_at nulls first,p.id limit 25
  ) x;
$$;

create or replace function public.hyn_user_digest_content(p_owner uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('name',coalesce(nullif(p.full_name,''),p.email,'Portal user'),'recipient',p.email,
    'nodes',coalesce((select jsonb_agg(to_jsonb(x) order by x.name,x.id) from (
      select n.id,n.name,n.hostname,n.status,n.telemetry_mode,coalesce(n.last_heartbeat_at,n.last_seen_at) last_heartbeat_at,
        m.sample_count,m.cpu_average,m.cpu_peak,m.memory_average,m.temperature_peak,m.download_average,m.upload_average,m.latency_average,m.uptime
      from public._hyn_digest_nodes(p_owner) n cross join lateral (
        select count(*) sample_count,avg(cpu_pct) cpu_average,max(cpu_pct) cpu_peak,avg(mem_pct) memory_average,
          max(cpu_temp_c) temperature_peak,avg(net_rx_bps) download_average,avg(net_tx_bps) upload_average,
          avg(latency_ms) latency_average,(array_agg(uptime_s order by ts desc))[1] uptime
        from public.metrics where node_id=n.id and ts>=now()-interval '24 hours' and n.telemetry_mode<>'local'
      ) m
    ) x),'[]'::jsonb)) from public.profiles p where p.id=p_owner and p.status='active';
$$;

-- Legacy jobs keep their own five-attempt ceiling; a budget deferral is not a
-- provider attempt, so do not exhaust that ceiling while sending is paused.
create or replace function public.hyn_defer_web_delivery(p_job uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.web_notification_jobs set status='queued',attempts=greatest(0,attempts-1),error=left(p_reason,1000),updated_at=now()
  where id=p_job and status='sending';
end $$;
create or replace function public.hyn_claim_web_notification(p_job_id uuid default null)
returns json language plpgsql security definer set search_path=public as $$
declare v_job public.web_notification_jobs; v_node public.nodes; v_recipient text;
begin
  with candidate as (
    select j.id from public.web_notification_jobs j
    where (p_job_id is null or j.id=p_job_id) and (j.status='queued' or (j.status='failed' and j.attempts<5))
      and not exists(select 1 from public.delivery_events e where e.source_key='web-notification:'||j.id::text
        and ((e.terminal and e.status<>'sent') or e.status='sending' or e.next_retry_at>now()))
    order by j.created_at for update of j skip locked limit 1
  ) update public.web_notification_jobs j set status='sending',attempts=j.attempts+1,updated_at=now(),error=null
    from candidate where j.id=candidate.id returning j.* into v_job;
  if not found then return json_build_object('status','idle'); end if;
  select * into v_node from public.nodes where id=v_job.node_id;
  select recipient into v_recipient from public.email_preferences where node_id=v_job.node_id;
  return json_build_object('status','send','id',v_job.id,'node_id',v_job.node_id,'node_name',v_node.name,'hostname',v_node.hostname,
    'owner',v_node.owner,'recipient',v_recipient,'fingerprint',v_job.fingerprint,'category',v_job.category,'severity',v_job.severity,
    'subject',v_job.subject,'text_body',v_job.text_body,'html_body',v_job.html_body,'attempts',v_job.attempts);
end $$;

create or replace function public.hyn_admin_delivery_dashboard(p_owner uuid default null,p_kind text default 'all',p_status text default 'all',p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb; v_day timestamptz:=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
begin
  perform public._hyn_require_staff();
  if p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'invalid history page'; end if;
  select jsonb_build_object('as_of',now(),'day_start',v_day,'started_at',(select created_at from public.delivery_rules where scope='global' and kind='all'),
    'rules',(select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) from public.delivery_rules r where r.scope='global' or r.owner=p_owner),
    'digest_settings',(select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) from public.delivery_digest_settings s where s.scope='global' or s.owner=p_owner),
    'users',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(nullif(p.full_name,''),p.email,'Portal user'),'email',p.email,'status',p.status) order by coalesce(p.full_name,p.email)),'[]'::jsonb) from public.profiles p),
    'usage',(select coalesce(jsonb_agg(to_jsonb(u)),'[]'::jsonb) from (select e.kind,count(*) attempts,count(*) filter(where a.status='sent') sent,count(*) filter(where a.status='failed') failed,count(*) filter(where a.status in('sending','unknown')) unknown from public.delivery_attempts a join public.delivery_events e on e.id=a.event_id where a.started_at>=v_day and (p_owner is null or e.owner=p_owner) group by e.kind) u),
    'global_usage',(select coalesce(jsonb_agg(to_jsonb(u)),'[]'::jsonb) from (select e.kind,count(*) attempts,count(*) filter(where a.status='sent') sent,count(*) filter(where a.status='failed') failed,count(*) filter(where a.status in('sending','unknown')) unknown from public.delivery_attempts a join public.delivery_events e on e.id=a.event_id where a.started_at>=v_day group by e.kind) u),
    'total',(select count(*) from public.delivery_events e where (p_owner is null or e.owner=p_owner) and (p_kind='all' or e.kind=p_kind) and (p_status='all' or e.status=p_status)),
    'events',(select coalesce(jsonb_agg(to_jsonb(x) order by x.updated_at desc),'[]'::jsonb) from (
      select e.id,e.owner,coalesce(nullif(p.full_name,''),p.email,'Portal user') owner_name,p.email owner_email,e.node_label node_name,
        e.kind,e.subject,e.recipient,e.status,e.reason,e.attempt_count,e.attempt_limit,e.terminal,e.updated_at,e.next_retry_at,
        coalesce((select jsonb_agg(to_jsonb(a) order by a.started_at) from public.delivery_attempts a where a.event_id=e.id),'[]'::jsonb) attempts
      from public.delivery_events e join public.profiles p on p.id=e.owner
      where (p_owner is null or e.owner=p_owner) and (p_kind='all' or e.kind=p_kind) and (p_status='all' or e.status=p_status)
      order by e.updated_at desc,e.id offset p_offset limit 25) x),
    'legacy',(select coalesce(jsonb_agg(to_jsonb(x) order by x.ts desc),'[]'::jsonb) from (
      select l.id,l.ts,coalesce(nullif(p.full_name,''),p.email,'Portal user') owner_name,n.name node_name,l.kind,l.status,l.subject,l.error
      from public.notification_log l left join public.profiles p on p.id=l.owner left join public.nodes n on n.id=l.node_id
      where p_owner is null or l.owner=p_owner order by l.ts desc limit 50) x)
  ) into result;
  return result;
end $$;

revoke all on function public._hyn_digest_setting(uuid),public._hyn_digest_nodes(uuid) from public,anon,authenticated;
revoke all on function public.hyn_admin_set_delivery_rules(uuid,jsonb),public.hyn_admin_set_digest(uuid,boolean,text,text,boolean,boolean),public.hyn_admin_stop_delivery(uuid),public.hyn_admin_delivery_dashboard(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.hyn_admin_set_delivery_rules(uuid,jsonb),public.hyn_admin_set_digest(uuid,boolean,text,text,boolean,boolean),public.hyn_admin_stop_delivery(uuid),public.hyn_admin_delivery_dashboard(uuid,text,text,integer) to authenticated;
revoke all on function public.hyn_reserve_delivery(text,text,uuid,uuid,text,text,uuid[]),public.hyn_complete_delivery(uuid,text,text,text),public.hyn_due_user_digests(uuid),public.hyn_user_digest_content(uuid),public.hyn_defer_web_delivery(uuid,text),public.hyn_claim_web_notification(uuid) from public,anon,authenticated;
do $$ begin
  if exists(select 1 from pg_roles where rolname='service_role') then
    grant select on public.delivery_rules,public.delivery_digest_settings to service_role;
    grant execute on function public.hyn_reserve_delivery(text,text,uuid,uuid,text,text,uuid[]),public.hyn_complete_delivery(uuid,text,text,text),public.hyn_due_user_digests(uuid),public.hyn_user_digest_content(uuid),public.hyn_defer_web_delivery(uuid,text),public.hyn_claim_web_notification(uuid) to service_role;
  end if;
end $$;
notify pgrst,'reload schema';
commit;
