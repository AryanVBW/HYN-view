-- Durable one-minute heartbeats, generalized machine commands, portal-owned
-- web notification delivery, and audited administrator report requests.

begin;

alter table public.nodes add column if not exists last_heartbeat_at timestamptz;
update public.nodes
   set last_heartbeat_at = coalesce(last_config_pull_at, last_seen_at, created_at)
 where last_heartbeat_at is null;
create index if not exists nodes_last_heartbeat_idx
  on public.nodes (last_heartbeat_at desc) where is_demo = false and revoked = false;

-- New agents check for config/commands every minute even when the telemetry
-- collection interval is longer. Until 1.7 is published, preserve the legacy
-- three-configured-interval rule so an installed 1.6 agent is not mislabeled.
create or replace function public.hyn_admin_overview()
returns json language plpgsql security definer set search_path = public as $$
begin
  perform public._hyn_require_admin();
  return json_build_object(
    'clients_total', (select count(*) from public.profiles),
    'clients_suspended', (select count(*) from public.profiles where status = 'suspended'),
    'admins', (select count(*) from public.profiles where role = 'admin'),
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
  perform public._hyn_require_admin();
  select coalesce(json_agg(row_to_json(x) order by x.last_heartbeat_at desc nulls last), '[]'::json)
    into v from (
      select n.id, n.name, n.hostname, n.os, n.agent_version, n.status,
             n.paused_until, n.status_reason, n.revoked, n.is_demo,
             n.created_at, n.last_seen_at, n.last_config_pull_at, n.last_heartbeat_at, n.config,
             p.id as owner_id, p.email as owner_email, p.status as owner_status, p.role as owner_role,
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

alter table public.node_commands drop constraint if exists node_commands_command_check;
alter table public.node_commands add constraint node_commands_command_check
  check (command in ('update', 'sync'));
alter table public.node_commands drop constraint if exists node_commands_stage_check;
alter table public.node_commands add constraint node_commands_stage_check
  check (stage in ('queued', 'accepted', 'checking', 'installing', 'restarting',
                   'collecting', 'uploading', 'verifying', 'completed', 'failed',
                   'expired'));
drop index if exists public.node_commands_one_active_update_idx;
create unique index if not exists node_commands_one_active_kind_idx
  on public.node_commands (node_id, command)
  where status in ('queued', 'running');

create table if not exists public.node_watchdogs (
  node_id          uuid primary key references public.nodes (id) on delete cascade,
  state            text not null default 'starting'
                     check (state in ('starting', 'running', 'stopped')),
  run_id           text,
  last_alert_state text not null default 'unknown'
                     check (last_alert_state in ('unknown', 'online', 'offline')),
  started_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists public.web_notification_jobs (
  id          uuid primary key default gen_random_uuid(),
  node_id     uuid not null references public.nodes (id) on delete cascade,
  fingerprint text not null,
  category    text not null default 'alert'
                check (category in ('alert', 'report', 'test', 'other')),
  severity    text not null default 'info'
                check (severity in ('info', 'warn', 'crit')),
  subject     text not null,
  text_body   text not null,
  html_body   text,
  status      text not null default 'queued'
                check (status in ('queued', 'sending', 'sent', 'failed')),
  attempts    integer not null default 0 check (attempts between 0 and 5),
  provider_id text,
  error       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  sent_at     timestamptz,
  unique (node_id, fingerprint)
);
create index if not exists web_notification_jobs_retry_idx
  on public.web_notification_jobs (status, updated_at)
  where status in ('queued', 'failed');

create table if not exists public.admin_report_jobs (
  id           uuid primary key default gen_random_uuid(),
  requested_by uuid not null references auth.users (id) on delete cascade,
  target_user  uuid not null references auth.users (id) on delete cascade,
  status       text not null default 'queued'
                 check (status in ('queued', 'sending', 'sent', 'failed')),
  provider_id  text,
  error        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  sent_at      timestamptz
);
create unique index if not exists admin_report_jobs_one_active_idx
  on public.admin_report_jobs (target_user)
  where status in ('queued', 'sending');

alter table public.node_watchdogs enable row level security;
alter table public.web_notification_jobs enable row level security;
alter table public.admin_report_jobs enable row level security;
revoke all on public.node_watchdogs from anon, authenticated;
revoke all on public.web_notification_jobs from anon, authenticated;
revoke all on public.admin_report_jobs from anon, authenticated;

create or replace function public.hyn_request_node_command(
  p_node_id uuid,
  p_command text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_command public.node_commands;
  v_created boolean := false;
begin
  if auth.uid() is null or not public.hyn_is_active() then
    raise exception 'not authenticated';
  end if;
  if p_command not in ('update', 'sync') then
    raise exception 'invalid command';
  end if;
  if not exists (
    select 1 from public.nodes
     where id = p_node_id and owner = auth.uid() and revoked = false
       and is_demo = false and status = 'active'
  ) then
    raise exception 'active node not found';
  end if;

  select * into v_command from public.node_commands
   where node_id = p_node_id and command = p_command
     and status in ('queued', 'running')
   order by requested_at desc limit 1;
  if not found then
    insert into public.node_commands (node_id, requested_by, command, message)
    values (
      p_node_id,
      auth.uid(),
      p_command,
      case when p_command = 'sync'
           then 'Waiting for the machine to synchronize'
           else 'Waiting for the machine to check in' end
    ) returning * into v_command;
    v_created := true;
  end if;

  return json_build_object(
    'id', v_command.id, 'node_id', v_command.node_id,
    'action', v_command.command, 'status', v_command.status,
    'stage', v_command.stage, 'message', v_command.message,
    'target_version', v_command.target_version,
    'result_version', v_command.result_version,
    'requested_at', v_command.requested_at,
    'started_at', v_command.started_at,
    'finished_at', v_command.finished_at,
    'updated_at', v_command.updated_at,
    'created', v_created
  );
end;
$$;

create or replace function public.hyn_request_node_update(p_node_id uuid)
returns json
language sql
security definer
set search_path = public
as $$
  select public.hyn_request_node_command(p_node_id, 'update');
$$;

create or replace function public.hyn_admin_request_node_command(
  p_node_id uuid,
  p_command text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_command public.node_commands;
  v_owner uuid;
  v_created boolean := false;
begin
  perform public._hyn_require_admin();
  if p_command not in ('update', 'sync') then raise exception 'invalid command'; end if;
  select owner into v_owner from public.nodes
   where id = p_node_id and revoked = false and is_demo = false and status = 'active';
  if not found then raise exception 'active node not found'; end if;

  select * into v_command from public.node_commands
   where node_id = p_node_id and command = p_command
     and status in ('queued', 'running')
   order by requested_at desc limit 1;
  if not found then
    insert into public.node_commands (node_id, requested_by, command, message)
    values (
      p_node_id,
      auth.uid(),
      p_command,
      case when p_command = 'sync'
           then 'Administrator requested a complete synchronization'
           else 'Administrator requested an agent update' end
    ) returning * into v_command;
    v_created := true;
  end if;

  perform public._hyn_audit(
    'node.command.' || p_command,
    v_owner,
    p_node_id,
    jsonb_build_object('command_id', v_command.id, 'created', v_created)
  );
  return json_build_object(
    'id', v_command.id, 'node_id', v_command.node_id,
    'action', v_command.command, 'status', v_command.status,
    'stage', v_command.stage, 'message', v_command.message,
    'target_version', v_command.target_version,
    'result_version', v_command.result_version,
    'requested_at', v_command.requested_at,
    'started_at', v_command.started_at,
    'finished_at', v_command.finished_at,
    'updated_at', v_command.updated_at,
    'created', v_created
  );
end;
$$;

create or replace function public.hyn_claim_node_command(p_node_token text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
  v_command public.node_commands;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false and is_demo = false and status = 'active';
  if not found then raise exception 'invalid or inactive node token'; end if;

  with candidate as (
    select id from public.node_commands
     where node_id = v_node.id and command in ('update', 'sync')
       and (
         status = 'queued'
         or (status = 'running' and coalesce(lease_expires_at, '-infinity') <= now())
       )
     order by requested_at
     for update skip locked limit 1
  )
  update public.node_commands c
     set status = 'running', stage = 'accepted',
         message = case when c.command = 'sync'
                        then 'Machine accepted the synchronization request'
                        else 'Machine accepted the update request' end,
         started_at = coalesce(c.started_at, now()), updated_at = now(),
         lease_expires_at = now() + interval '20 minutes'
    from candidate where c.id = candidate.id
  returning c.* into v_command;

  if not found then return json_build_object('status', 'idle'); end if;
  return json_build_object(
    'status', 'command', 'id', v_command.id,
    'action', v_command.command, 'stage', v_command.stage
  );
end;
$$;

create or replace function public.hyn_report_node_command(
  p_node_token text,
  p_command_id uuid,
  p_status text,
  p_stage text,
  p_message text,
  p_target_version text default null,
  p_result_version text default null
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
  v_command public.node_commands;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false and is_demo = false;
  if not found then raise exception 'invalid node token'; end if;
  if p_status not in ('running', 'succeeded', 'failed') then
    raise exception 'invalid command status';
  end if;
  if p_stage not in ('accepted', 'checking', 'installing', 'restarting',
                     'collecting', 'uploading', 'verifying', 'completed', 'failed') then
    raise exception 'invalid command stage';
  end if;
  select * into v_command from public.node_commands
   where id = p_command_id and node_id = v_node.id and status = 'running'
   for update;
  if not found then raise exception 'active command not found'; end if;
  if (v_command.command = 'update' and p_stage in ('collecting', 'uploading'))
     or (v_command.command = 'sync' and p_stage in ('checking', 'installing', 'restarting')) then
    raise exception 'stage does not belong to command';
  end if;
  if octet_length(coalesce(p_message, '')) > 500 then
    raise exception 'command message is too long';
  end if;
  if octet_length(coalesce(p_target_version, '')) > 64
     or octet_length(coalesce(p_result_version, '')) > 64 then
    raise exception 'command version is too long';
  end if;

  update public.node_commands
     set status = p_status, stage = p_stage,
         message = coalesce(nullif(trim(p_message), ''), p_stage),
         target_version = coalesce(nullif(p_target_version, ''), target_version),
         result_version = coalesce(nullif(p_result_version, ''), result_version),
         updated_at = now(),
         lease_expires_at = case when p_status = 'running'
                                 then now() + interval '20 minutes' else null end,
         finished_at = case when p_status in ('succeeded', 'failed')
                            then now() else finished_at end
   where id = p_command_id
  returning * into v_command;
  return json_build_object(
    'status', v_command.status, 'stage', v_command.stage,
    'updated_at', v_command.updated_at
  );
end;
$$;

create or replace function public.hyn_update_node_config(
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
  if auth.uid() is null or not public.hyn_is_active() then
    raise exception 'not authenticated';
  end if;
  if not public._hyn_portal_config_valid(p_config) then
    raise exception 'invalid portal configuration';
  end if;
  update public.nodes set config = p_config
   where id = p_node_id and owner = auth.uid() and revoked = false and is_demo = false
  returning config into v_config;
  if not found then raise exception 'node not found'; end if;
  return json_build_object('status', 'ok', 'config', v_config);
end;
$$;

create or replace function public.hyn_claim_node_watchdog(p_node_token text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_node public.nodes; v_watchdog public.node_watchdogs; v_created boolean := false;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false and is_demo = false and status = 'active';
  if not found then raise exception 'invalid or inactive node token'; end if;
  insert into public.node_watchdogs (node_id)
  values (v_node.id) on conflict (node_id) do nothing
  returning * into v_watchdog;
  if found then
    v_created := true;
  else
    select * into v_watchdog from public.node_watchdogs where node_id = v_node.id for update;
    if v_watchdog.state = 'stopped'
       or v_watchdog.updated_at < now() - interval '5 minutes' then
      update public.node_watchdogs
         set state = 'starting', run_id = null, updated_at = now()
       where node_id = v_node.id returning * into v_watchdog;
      v_created := true;
    end if;
  end if;
  return json_build_object(
    'node_id', v_node.id, 'created', v_created,
    'state', v_watchdog.state, 'last_alert_state', v_watchdog.last_alert_state
  );
end;
$$;

create or replace function public.hyn_queue_web_notification(
  p_node_token text,
  p_event jsonb
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
  v_job public.web_notification_jobs;
  v_created boolean := false;
  v_fingerprint text;
  v_category text;
  v_severity text;
  v_subject text;
  v_text text;
  v_html text;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false and is_demo = false and status = 'active';
  if not found then raise exception 'invalid or inactive node token'; end if;
  if p_event is null or jsonb_typeof(p_event) <> 'object'
     or octet_length(p_event::text) > 32768 then raise exception 'invalid web event'; end if;
  if p_event ?| array['recipient', 'to', 'from', 'sender', 'email'] then
    raise exception 'web event cannot select a recipient or sender';
  end if;
  v_fingerprint := trim(coalesce(p_event->>'fingerprint', ''));
  v_category := coalesce(nullif(trim(p_event->>'category'), ''), 'alert');
  v_severity := coalesce(nullif(trim(p_event->>'severity'), ''), 'info');
  v_subject := trim(coalesce(p_event->>'subject', ''));
  v_text := trim(coalesce(p_event->>'text_body', ''));
  v_html := nullif(p_event->>'html_body', '');
  if length(v_fingerprint) not between 1 and 200
     or v_category not in ('alert', 'report', 'test', 'other')
     or v_severity not in ('info', 'warn', 'crit')
     or length(v_subject) not between 1 and 300
     or length(v_text) not between 1 and 10000
     or length(coalesce(v_html, '')) > 20000 then
    raise exception 'invalid web event fields';
  end if;

  insert into public.web_notification_jobs (
    node_id, fingerprint, category, severity, subject, text_body, html_body
  ) values (
    v_node.id, v_fingerprint, v_category, v_severity, v_subject, v_text, v_html
  ) on conflict (node_id, fingerprint) do nothing returning * into v_job;
  if found then
    v_created := true;
  else
    select * into v_job from public.web_notification_jobs
     where node_id = v_node.id and fingerprint = v_fingerprint;
  end if;
  return json_build_object(
    'status', v_job.status, 'id', v_job.id,
    'created', v_created, 'fingerprint', v_job.fingerprint
  );
end;
$$;

create or replace function public.hyn_claim_web_notification(p_job_id uuid default null)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_job public.web_notification_jobs; v_node public.nodes; v_recipient text;
begin
  with candidate as (
    select id from public.web_notification_jobs
     where (p_job_id is null or id = p_job_id)
       and (status = 'queued' or (status = 'failed' and attempts < 5))
     order by created_at for update skip locked limit 1
  )
  update public.web_notification_jobs j
     set status = 'sending', attempts = j.attempts + 1,
         updated_at = now(), error = null
    from candidate where j.id = candidate.id returning j.* into v_job;
  if not found then return json_build_object('status', 'idle'); end if;
  select * into v_node from public.nodes where id = v_job.node_id;
  select recipient into v_recipient from public.email_preferences where node_id = v_job.node_id;
  return json_build_object(
    'status', 'send', 'id', v_job.id, 'node_id', v_job.node_id,
    'node_name', v_node.name, 'hostname', v_node.hostname,
    'owner', v_node.owner, 'recipient', v_recipient,
    'fingerprint', v_job.fingerprint, 'category', v_job.category,
    'severity', v_job.severity, 'subject', v_job.subject,
    'text_body', v_job.text_body, 'html_body', v_job.html_body,
    'attempts', v_job.attempts
  );
end;
$$;

create or replace function public.hyn_complete_web_notification(
  p_job_id uuid,
  p_status text,
  p_target text default null,
  p_provider_id text default null,
  p_error text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_job public.web_notification_jobs; v_owner uuid;
begin
  if p_status not in ('sent', 'failed') then raise exception 'invalid delivery status'; end if;
  update public.web_notification_jobs
     set status = p_status,
         provider_id = left(nullif(p_provider_id, ''), 200),
         error = left(nullif(p_error, ''), 1000), updated_at = now(),
         sent_at = case when p_status = 'sent' then now() else null end
   where id = p_job_id and status = 'sending' returning * into v_job;
  if not found then raise exception 'active web notification not found'; end if;
  select owner into v_owner from public.nodes where id = v_job.node_id;
  insert into public.notification_log (
    node_id, owner, kind, target, severity, subject, status, error, category
  ) values (
    v_job.node_id, v_owner, 'web', left(p_target, 320), v_job.severity,
    v_job.subject, p_status, left(p_error, 1000), v_job.category
  );
  return json_build_object('status', p_status, 'id', v_job.id);
end;
$$;

create or replace function public.hyn_claim_admin_report(p_target_user uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_job public.admin_report_jobs; v_created boolean := false;
begin
  perform public._hyn_require_admin();
  if not exists (select 1 from public.profiles where id = p_target_user and status = 'active') then
    raise exception 'active client not found';
  end if;
  if not exists (
    select 1 from public.nodes
     where owner = p_target_user and revoked = false and is_demo = false and status = 'active'
  ) then raise exception 'client has no active machines'; end if;
  select * into v_job from public.admin_report_jobs
   where target_user = p_target_user and status in ('queued', 'sending')
   order by created_at desc limit 1;
  if not found then
    insert into public.admin_report_jobs (requested_by, target_user)
    values (auth.uid(), p_target_user) returning * into v_job;
    v_created := true;
  end if;
  perform public._hyn_audit(
    'client.report.requested', p_target_user, null,
    jsonb_build_object('report_id', v_job.id, 'created', v_created)
  );
  return json_build_object(
    'id', v_job.id, 'status', v_job.status,
    'target_user', v_job.target_user, 'created', v_created
  );
end;
$$;

create or replace function public.hyn_complete_admin_report(
  p_report_id uuid,
  p_status text,
  p_provider_id text default null,
  p_error text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_job public.admin_report_jobs;
begin
  perform public._hyn_require_admin();
  if p_status not in ('sending', 'sent', 'failed') then raise exception 'invalid report status'; end if;
  update public.admin_report_jobs
     set status = p_status, provider_id = left(nullif(p_provider_id, ''), 200),
         error = left(nullif(p_error, ''), 1000), updated_at = now(),
         sent_at = case when p_status = 'sent' then now() else sent_at end
   where id = p_report_id returning * into v_job;
  if not found then raise exception 'report not found'; end if;
  perform public._hyn_audit(
    'client.report.' || p_status, v_job.target_user, null,
    jsonb_build_object('report_id', v_job.id, 'error', v_job.error)
  );
  return json_build_object('id', v_job.id, 'status', v_job.status);
end;
$$;

create or replace function public.hyn_fetch_config(p_node_token text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
  v_alert_template text;
  v_report_template text;
  v_watchdog json;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token);
  if not found then raise exception 'invalid node token'; end if;
  if v_node.revoked then raise exception 'node revoked'; end if;
  if v_node.status = 'paused' and v_node.paused_until is not null
     and v_node.paused_until <= now() then
    update public.nodes
       set status = 'active', paused_until = null, status_reason = null
     where id = v_node.id returning * into v_node;
  end if;

  update public.nodes
     set last_config_pull_at = now(), last_heartbeat_at = now()
   where id = v_node.id;
  if v_node.status = 'active' and not v_node.is_demo then
    v_watchdog := public.hyn_claim_node_watchdog(p_node_token);
  else
    v_watchdog := json_build_object('created', false, 'state', 'stopped');
  end if;
  select replace(encode(convert_to(t.html_template, 'UTF8'), 'base64'), E'\n', '')
    into v_alert_template from public.notification_templates t where t.template_key = 'alert';
  select replace(encode(convert_to(t.html_template, 'UTF8'), 'base64'), E'\n', '')
    into v_report_template from public.notification_templates t where t.template_key = 'report';
  return json_build_object(
    'status', 'ok', 'node_id', v_node.id, 'node_name', v_node.name,
    'node_status', v_node.status, 'paused_until', v_node.paused_until,
    'status_reason', v_node.status_reason, 'config', v_node.config,
    'heartbeat_at', now(), 'watchdog', v_watchdog,
    'alert_template_b64', coalesce(v_alert_template, ''),
    'report_template_b64', coalesce(v_report_template, '')
  );
end;
$$;

revoke all on function public.hyn_request_node_command(uuid, text) from public;
revoke all on function public.hyn_request_node_update(uuid) from public;
revoke all on function public.hyn_admin_request_node_command(uuid, text) from public;
revoke all on function public.hyn_update_node_config(uuid, jsonb) from public;
revoke all on function public.hyn_claim_node_command(text) from public;
revoke all on function public.hyn_report_node_command(text, uuid, text, text, text, text, text) from public;
revoke all on function public.hyn_claim_node_watchdog(text) from public;
revoke all on function public.hyn_queue_web_notification(text, jsonb) from public;
revoke all on function public.hyn_claim_web_notification(uuid) from public;
revoke all on function public.hyn_complete_web_notification(uuid, text, text, text, text) from public;
revoke all on function public.hyn_claim_admin_report(uuid) from public;
revoke all on function public.hyn_complete_admin_report(uuid, text, text, text) from public;

grant execute on function public.hyn_request_node_command(uuid, text) to authenticated;
grant execute on function public.hyn_request_node_update(uuid) to authenticated;
grant execute on function public.hyn_admin_request_node_command(uuid, text) to authenticated;
grant execute on function public.hyn_update_node_config(uuid, jsonb) to authenticated;
grant execute on function public.hyn_claim_node_command(text) to anon, authenticated;
grant execute on function public.hyn_report_node_command(text, uuid, text, text, text, text, text) to anon, authenticated;
grant execute on function public.hyn_claim_node_watchdog(text) to anon, authenticated;
grant execute on function public.hyn_queue_web_notification(text, jsonb) to anon, authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.hyn_claim_web_notification(uuid) to service_role;
    grant execute on function public.hyn_complete_web_notification(uuid, text, text, text, text) to service_role;
  end if;
end;
$$;
grant execute on function public.hyn_claim_admin_report(uuid) to authenticated;
grant execute on function public.hyn_complete_admin_report(uuid, text, text, text) to authenticated;

commit;
