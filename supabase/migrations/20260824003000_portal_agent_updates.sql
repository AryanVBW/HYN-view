-- Owner-triggered, agent-executed CLI updates with observable progress.
-- Commands are pulled by the node on its existing one-minute check-in; no
-- inbound port or service-role credential is added to a monitored server.

begin;

create table if not exists public.node_commands (
  id               uuid primary key default gen_random_uuid(),
  node_id          uuid not null references public.nodes (id) on delete cascade,
  requested_by     uuid references auth.users (id) on delete set null,
  command          text not null check (command in ('update')),
  status           text not null default 'queued'
                     check (status in ('queued', 'running', 'succeeded', 'failed', 'expired')),
  stage            text not null default 'queued'
                     check (stage in ('queued', 'accepted', 'checking', 'installing',
                                      'restarting', 'verifying', 'completed', 'failed', 'expired')),
  message          text not null default 'Waiting for the machine to check in',
  target_version   text,
  result_version   text,
  requested_at     timestamptz not null default now(),
  started_at       timestamptz,
  finished_at      timestamptz,
  updated_at       timestamptz not null default now(),
  lease_expires_at timestamptz
);

create index if not exists node_commands_node_requested_idx
  on public.node_commands (node_id, requested_at desc);
create unique index if not exists node_commands_one_active_update_idx
  on public.node_commands (node_id, command)
  where status in ('queued', 'running');

alter table public.node_commands enable row level security;
drop policy if exists node_commands_select_own on public.node_commands;
create policy node_commands_select_own on public.node_commands
  for select using (
    exists (
      select 1 from public.nodes n
       where n.id = node_commands.node_id and n.owner = auth.uid()
    )
  );

create or replace function public.hyn_request_node_update(p_node_id uuid)
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
  if not exists (
    select 1 from public.nodes
     where id = p_node_id and owner = auth.uid() and revoked = false
       and is_demo = false and status = 'active'
  ) then
    raise exception 'active node not found';
  end if;

  select * into v_command
    from public.node_commands
   where node_id = p_node_id and command = 'update'
     and status in ('queued', 'running')
   order by requested_at desc
   limit 1;

  if not found then
    insert into public.node_commands (node_id, requested_by, command)
    values (p_node_id, auth.uid(), 'update')
    returning * into v_command;
    v_created := true;
  end if;

  return json_build_object(
    'id', v_command.id,
    'node_id', v_command.node_id,
    'action', v_command.command,
    'status', v_command.status,
    'stage', v_command.stage,
    'message', v_command.message,
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
     where node_id = v_node.id and command = 'update'
       and (
         status = 'queued'
         or (status = 'running' and coalesce(lease_expires_at, '-infinity') <= now())
       )
     order by requested_at
     for update skip locked
     limit 1
  )
  update public.node_commands c
     set status = 'running',
         stage = 'accepted',
         message = 'Machine accepted the update request',
         started_at = coalesce(c.started_at, now()),
         updated_at = now(),
         lease_expires_at = now() + interval '20 minutes'
    from candidate
   where c.id = candidate.id
  returning c.* into v_command;

  if not found then return json_build_object('status', 'idle'); end if;
  return json_build_object(
    'status', 'command',
    'id', v_command.id,
    'action', v_command.command,
    'stage', v_command.stage
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
                     'verifying', 'completed', 'failed') then
    raise exception 'invalid command stage';
  end if;
  if octet_length(coalesce(p_message, '')) > 500 then
    raise exception 'command message is too long';
  end if;
  if octet_length(coalesce(p_target_version, '')) > 64
     or octet_length(coalesce(p_result_version, '')) > 64 then
    raise exception 'command version is too long';
  end if;

  update public.node_commands
     set status = p_status,
         stage = p_stage,
         message = coalesce(nullif(trim(p_message), ''), p_stage),
         target_version = coalesce(nullif(p_target_version, ''), target_version),
         result_version = coalesce(nullif(p_result_version, ''), result_version),
         updated_at = now(),
         lease_expires_at = case when p_status = 'running'
                                 then now() + interval '20 minutes' else null end,
         finished_at = case when p_status in ('succeeded', 'failed')
                            then now() else finished_at end
   where id = p_command_id and node_id = v_node.id and status = 'running'
  returning * into v_command;
  if not found then raise exception 'active command not found'; end if;

  return json_build_object(
    'status', v_command.status,
    'stage', v_command.stage,
    'updated_at', v_command.updated_at
  );
end;
$$;

revoke all on public.node_commands from anon, authenticated;
grant select on public.node_commands to authenticated;

revoke all on function public.hyn_request_node_update(uuid) from public;
revoke all on function public.hyn_claim_node_command(text) from public;
revoke all on function public.hyn_report_node_command(text, uuid, text, text, text, text, text) from public;
grant execute on function public.hyn_request_node_update(uuid) to authenticated;
grant execute on function public.hyn_claim_node_command(text) to anon, authenticated;
grant execute on function public.hyn_report_node_command(text, uuid, text, text, text, text, text) to anon, authenticated;

commit;
