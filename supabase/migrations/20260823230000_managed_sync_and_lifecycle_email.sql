-- Repair portal config drift, apply managed agent defaults, make fleet quiet
-- status cadence-aware, and support the once-only first telemetry email.

begin;

create or replace function public._hyn_portal_config_valid(p_config jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare e record; v text;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object' then return false; end if;
  for e in select key, value from jsonb_each(p_config) loop
    if jsonb_typeof(e.value) not in ('number', 'string') then return false; end if;
    v := e.value #>> '{}';
    case
      when e.key in ('alert_mem_pct', 'alert_disk_pct') then
        if v !~ '^(0|[1-9][0-9]{0,2})$' or v::integer > 100 then return false; end if;
      when e.key = 'alert_temp_c' then
        if v !~ '^(0|[1-9][0-9]{0,2})$' or v::integer > 200 then return false; end if;
      when e.key = 'alert_load_per_core' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' or v::integer > 10000 then return false; end if;
      when e.key = 'alert_latency_ms' then
        if v !~ '^(0|[1-9][0-9]{0,5})$' or v::integer > 600000 then return false; end if;
      when e.key = 'alert_repeat_hours' then
        if v !~ '^(0|[1-9][0-9]{0,3})$' or v::integer > 8760 then return false; end if;
      when e.key = 'notify_max_per_day' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' or v::integer > 10000 then return false; end if;
      when e.key = 'cloud_push_min' then
        if v !~ '^[1-9][0-9]{0,3}$' or v::integer > 1440 then return false; end if;
      when e.key = 'alert_min_severity' then
        if v not in ('crit', 'warn', 'info') then return false; end if;
      when e.key = 'auto_update' then
        if v not in ('install', 'check', 'off') then return false; end if;
      when e.key = 'report_at' then
        if v !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then return false; end if;
      else return false;
    end case;
  end loop;
  return true;
end;
$$;

-- Remove the deployed validator before rewriting legacy rows. Some historic
-- versions allowed keys the new contract removes, while others rejected
-- auto_update; keeping either constraint active during the rewrite can make a
-- perfectly repairable row block the migration itself.
alter table public.nodes drop constraint if exists nodes_config_portal_keys_check;

update public.nodes n
   set config = coalesce((
     select jsonb_object_agg(e.key, e.value)
       from jsonb_each(case when jsonb_typeof(n.config) = 'object' then n.config else '{}'::jsonb end) e
      where e.key = any (array[
        'alert_mem_pct', 'alert_disk_pct', 'alert_temp_c', 'alert_load_per_core',
        'alert_latency_ms', 'alert_min_severity', 'alert_repeat_hours', 'report_at',
        'notify_max_per_day', 'cloud_push_min', 'auto_update'
      ]::text[])
        and public._hyn_portal_config_valid(jsonb_build_object(e.key, e.value))
   ), '{}'::jsonb);

alter table public.nodes add constraint nodes_config_portal_keys_check
  check (public._hyn_portal_config_valid(config));
alter table public.nodes alter column config
  set default '{"auto_update":"install","cloud_push_min":"10"}'::jsonb;
update public.nodes
   set config = '{"auto_update":"install","cloud_push_min":"10"}'::jsonb || config;

create or replace function public.hyn_claim_first_telemetry_email(
  p_node_token text,
  p_public_ip text default null
)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_node public.nodes;
  v_recipient text;
  v_system_enabled boolean;
  v_payload jsonb;
  v_key text;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false and is_demo = false;
  if not found then raise exception 'invalid node token'; end if;
  select recipient, system_enabled into v_recipient, v_system_enabled
    from public.email_preferences where node_id = v_node.id;
  if not found or not coalesce(v_system_enabled, false) then
    return json_build_object('status', 'skip', 'reason', 'system email disabled');
  end if;
  select payload into v_payload from public.metrics
   where node_id = v_node.id order by ts desc limit 1;
  if not found then return json_build_object('status', 'skip', 'reason', 'awaiting telemetry'); end if;
  v_payload := coalesce(v_payload, '{}'::jsonb);
  if p_public_ip is not null and octet_length(p_public_ip) <= 64
     and p_public_ip ~ '^[0-9A-Fa-f:.]+$' then
    v_payload := jsonb_set(v_payload, '{network}',
      coalesce(v_payload->'network', '{}'::jsonb) || jsonb_build_object('public_ip', p_public_ip), true);
  end if;
  v_key := 'first-system:' || v_node.id::text;
  insert into public.cloud_email_dispatches (idempotency_key, node_id, kind)
  values (v_key, v_node.id, 'system') on conflict (idempotency_key) do nothing;
  if not found then return json_build_object('status', 'skip', 'reason', 'already sent'); end if;
  return json_build_object(
    'status', 'send', 'idempotency_key', v_key, 'node_id', v_node.id,
    'node_name', v_node.name, 'hostname', v_node.hostname, 'os', v_node.os,
    'agent_version', v_node.agent_version, 'last_seen_at', v_node.last_seen_at,
    'recipient', v_recipient, 'payload', v_payload
  );
end;
$$;

create or replace function public.hyn_complete_first_telemetry_email(
  p_node_token text,
  p_provider_id text default null
)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_node public.nodes; v_key text;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token) and revoked = false;
  if not found then raise exception 'invalid node token'; end if;
  v_key := 'first-system:' || v_node.id::text;
  update public.cloud_email_dispatches set provider_id = left(nullif(p_provider_id, ''), 200)
   where idempotency_key = v_key and node_id = v_node.id;
  return json_build_object('status', 'ok');
end;
$$;

create or replace function public.hyn_release_first_telemetry_email(p_node_token text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_node public.nodes; v_key text;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token) and revoked = false;
  if not found then raise exception 'invalid node token'; end if;
  v_key := 'first-system:' || v_node.id::text;
  delete from public.cloud_email_dispatches
   where idempotency_key = v_key and node_id = v_node.id and provider_id is null;
  return json_build_object('status', 'ok');
end;
$$;

create or replace function public.hyn_claim_device_linked_email(p_node_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_node public.nodes; v_recipient text; v_key text;
begin
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
  if auth.uid() is null or not exists (select 1 from public.nodes where id = p_node_id and owner = auth.uid())
    then raise exception 'node not found'; end if;
  update public.cloud_email_dispatches set provider_id = left(nullif(p_provider_id, ''), 200)
   where idempotency_key = 'device-linked:' || p_node_id::text and node_id = p_node_id;
  return json_build_object('status', 'ok');
end;
$$;

create or replace function public.hyn_release_device_linked_email(p_node_id uuid)
returns json language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not exists (select 1 from public.nodes where id = p_node_id and owner = auth.uid())
    then raise exception 'node not found'; end if;
  delete from public.cloud_email_dispatches
   where idempotency_key = 'device-linked:' || p_node_id::text and node_id = p_node_id and provider_id is null;
  return json_build_object('status', 'ok');
end;
$$;

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
    'nodes_stale', (select count(*) from public.nodes
      where is_demo = false and revoked = false and status = 'active'
        and (last_seen_at is null or last_seen_at < now() - make_interval(
          mins => greatest(15, 3 * case
            when config->>'cloud_push_min' ~ '^[1-9][0-9]{0,3}$'
              then (config->>'cloud_push_min')::integer else 10 end)))),
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
  select coalesce(json_agg(row_to_json(x) order by x.last_seen_at desc nulls last), '[]'::json)
    into v from (
      select n.id, n.name, n.hostname, n.os, n.agent_version, n.status,
             n.paused_until, n.status_reason, n.revoked, n.is_demo,
             n.created_at, n.last_seen_at, n.last_config_pull_at, n.config,
             p.id as owner_id, p.email as owner_email, p.status as owner_status, p.role as owner_role,
             (select count(*) from public.notification_log l where l.node_id = n.id and l.ts > now() - interval '24 hours') as notifications_24h,
             (select count(*) from public.notification_log l where l.node_id = n.id and l.ts > now() - interval '24 hours' and l.status = 'failed') as notifications_failed_24h,
             (select count(*) from public.alert_events a where a.node_id = n.id and a.resolved = false and a.ts > now() - interval '7 days') as alerts_open,
             (select m.cpu_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_cpu_pct,
             (select m.cpu_temp_c from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_temp_c,
             (select m.mem_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_mem_pct,
             (select m.disk_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_disk_pct
        from public.nodes n left join public.profiles p on p.id = n.owner
    ) x;
  return v;
end;
$$;

revoke all on function public.hyn_claim_first_telemetry_email(text, text) from public;
revoke all on function public.hyn_complete_first_telemetry_email(text, text) from public;
revoke all on function public.hyn_release_first_telemetry_email(text) from public;
revoke all on function public.hyn_claim_device_linked_email(uuid) from public;
revoke all on function public.hyn_complete_device_linked_email(uuid, text) from public;
revoke all on function public.hyn_release_device_linked_email(uuid) from public;
grant execute on function public.hyn_claim_first_telemetry_email(text, text) to anon, authenticated;
grant execute on function public.hyn_complete_first_telemetry_email(text, text) to anon, authenticated;
grant execute on function public.hyn_release_first_telemetry_email(text) to anon, authenticated;
grant execute on function public.hyn_claim_device_linked_email(uuid) to authenticated;
grant execute on function public.hyn_complete_device_linked_email(uuid, text) to authenticated;
grant execute on function public.hyn_release_device_linked_email(uuid) to authenticated;

commit;
