-- ===========================================================================
-- a refused machine command says which state refused it
-- ===========================================================================
-- `active node not found` was one message for six different situations: a paused
-- machine, one whose pause deadline had already passed, one suspended by an
-- administrator, one whose credential was revoked, a demo row, and a node id
-- belonging to another account. The portal printed it verbatim under "Recovery
-- on the server: sudo hyn doctor", which is the fix for none of them -- no amount
-- of doctoring on the box clears a pause that is held in the portal.
--
-- One of those cases was a refusal that should have succeeded. Ingest, the
-- settings pull and the heartbeat all resolve an elapsed `paused_until` lazily,
-- because a timed pause is meant to expire by itself; the command RPCs tested
-- `status = 'active'` without doing so. On a machine whose agent is not beating
-- -- exactly when someone reaches for "Sync now" -- nothing else would ever
-- clear it, so the button stayed broken permanently.

-- Resolves the node a command is aimed at, or raises the reason it cannot be.
-- Shared by the owner-scoped and admin RPCs so the two cannot drift into
-- disagreeing about what a paused machine means. p_owner null means "an
-- administrator is asking", which skips only the ownership test.
create or replace function public._hyn_command_node(p_node_id uuid, p_owner uuid)
returns public.nodes
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_node public.nodes;
begin
  select * into v_node from public.nodes where id = p_node_id;
  if not found then
    raise exception 'that machine no longer exists in the portal';
  end if;
  if p_owner is not null and v_node.owner <> p_owner then
    raise exception 'that machine belongs to another account';
  end if;
  if v_node.revoked then
    raise exception 'this machine''s credential was revoked, so the portal can no longer reach it. Pair it again on the server: sudo hyn link';
  end if;
  if v_node.is_demo then
    raise exception 'this is demo data rather than a real server, so there is nothing to collect from it';
  end if;

  -- Same lazy rule as ingest and the heartbeat: a timed pause that outlived its
  -- deadline is not a refusal, it is a pause nobody has cleared yet.
  if v_node.status = 'paused' and v_node.paused_until is not null
     and v_node.paused_until <= now() then
    update public.nodes
       set status = 'active', paused_until = null, status_reason = null
     where id = v_node.id
    returning * into v_node;
  end if;

  if v_node.status = 'paused' then
    raise exception 'monitoring is paused for this machine%, so it is not accepting readings or commands. Resume it in the portal.%',
      case when v_node.paused_until is not null
        then ' until ' || to_char(v_node.paused_until at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC'
        else '' end,
      case when v_node.status_reason is not null
        then ' Reason: ' || v_node.status_reason || '.' else '' end;
  end if;
  if v_node.status = 'suspended' then
    raise exception 'this machine is suspended, so it is not accepting readings or commands. An administrator has to lift it.%',
      case when v_node.status_reason is not null
        then ' Reason: ' || v_node.status_reason || '.' else '' end;
  end if;

  return v_node;
end;
$$;

revoke all on function public._hyn_command_node(uuid, uuid) from public;

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
  perform public._hyn_command_node(p_node_id, auth.uid());
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

create or replace function public.hyn_admin_request_node_command(p_node_id uuid, p_command text)
returns json language plpgsql security definer set search_path = public as $$
declare v_command public.node_commands; v_node public.nodes; v_created boolean := false;
begin
  perform public._hyn_require_admin();
  if p_command not in ('update', 'sync') then raise exception 'invalid command'; end if;
  v_node := public._hyn_command_node(p_node_id, null);
  select * into v_command from public.node_commands
   where node_id = p_node_id and command = p_command and status in ('queued', 'running')
   order by requested_at desc limit 1;
  if not found then
    insert into public.node_commands (node_id, requested_by, command, message)
    values (
      p_node_id, auth.uid(), p_command,
      case when p_command = 'sync' then 'Administrator requested a complete synchronization'
           else 'Administrator requested an agent update' end
    ) returning * into v_command;
    v_created := true;
  end if;
  perform public._hyn_audit(
    'node.command.' || p_command, v_node.owner, p_node_id,
    jsonb_build_object('command_id', v_command.id, 'created', v_created)
  );
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
