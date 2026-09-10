-- Self-service pairing establishes ownership. Sharing grants are for other users.
begin;
create or replace function public.hyn_can_link()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and status='active'
    and role in ('monitor','admin','super_admin'));
$$;
revoke all on function public.hyn_can_link() from public,anon;
grant execute on function public.hyn_can_link() to authenticated;

create or replace function public._hyn_require_linker()
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.hyn_can_link() then
    raise exception 'an active Monitor, Admin or Super admin account is required to link a server';
  end if;
end;
$$;
revoke all on function public._hyn_require_linker() from public,anon,authenticated;

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
  perform public._hyn_require_linker();
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

create or replace function public.hyn_claim_device_linked_email(p_node_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_node public.nodes; v_recipient text; v_key text;
begin
  perform public._hyn_require_linker();
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
  perform public._hyn_require_linker();
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
  perform public._hyn_require_linker();
  if auth.uid() is null or not exists (
    select 1 from public.nodes where id = p_node_id and owner = auth.uid()
  ) then raise exception 'node not found'; end if;
  delete from public.cloud_email_dispatches
   where idempotency_key = 'device-linked:' || p_node_id::text
     and node_id = p_node_id and provider_id is null;
  return json_build_object('status', 'ok');
end;
$$;

create or replace function public.hyn_can_view_node(p_node uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.hyn_is_active() and exists(
    select 1 from public.nodes n join public.profiles p on p.id=n.owner
    where n.id=p_node and not n.revoked and (public.hyn_is_admin() or (p.status='active' and
      (n.owner=auth.uid() or coalesce(
        (select a.allowed from public.server_access a where a.viewer_id=auth.uid() and a.node_id=n.id),
        public.hyn_can_view_dashboard(n.owner)))))
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
  if exists(select 1 from public.nodes where id=p_node and owner=p_viewer) then
    raise exception 'the owner already has access; choose another user';
  end if;
  select allowed into v_old from public.server_access where viewer_id=p_viewer and node_id=p_node;
  if v_old is not distinct from p_allow then return; end if;
  insert into public.server_access(viewer_id,node_id,allowed,granted_by) values(p_viewer,p_node,p_allow,auth.uid())
    on conflict(viewer_id,node_id) do update set allowed=excluded.allowed,granted_by=excluded.granted_by,updated_at=now();
  insert into public.server_access_events(actor,viewer_id,node_id,allowed) values(auth.uid(),p_viewer,p_node,p_allow);
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
        else 180 end)
  )
  select coalesce(json_agg(e order by ts desc,id),'[]'::json) into result
    from (select * from events order by ts desc,id limit p_limit) e;
  return result;
end $$;
notify pgrst, 'reload schema';
commit;
