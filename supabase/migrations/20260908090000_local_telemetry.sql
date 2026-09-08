-- Control-plane metadata only. Detailed readings never enter this RPC.
alter table public.nodes add column if not exists telemetry_mode text not null default 'cloud'
  check (telemetry_mode in ('local', 'cloud'));
grant select (telemetry_mode) on public.nodes to authenticated;

create or replace function public.hyn_local_heartbeat(p_node_token text, p_agent_version text default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_result json; v_node public.nodes;
begin
  v_result := public.hyn_heartbeat(p_node_token, p_agent_version);
  select * into v_node from public.nodes where id = (v_result->>'node_id')::uuid;
  if not exists (select 1 from public.profiles where id = v_node.owner and status = 'active') then
    raise exception 'account suspended';
  end if;
  update public.nodes set telemetry_mode = 'local' where id = v_node.id and telemetry_mode <> 'local';
  return v_result;
end;
$$;
revoke all on function public.hyn_local_heartbeat(text, text) from public;
grant execute on function public.hyn_local_heartbeat(text, text) to anon, authenticated;

-- Local history does not need email templates, dispatch queues or a Workflow
-- lease on every settings poll. Return only the managed property allowlist.
create or replace function public.hyn_fetch_local_config(p_node_token text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_result json; v_node public.nodes;
begin
  v_result := public.hyn_local_heartbeat(p_node_token);
  update public.nodes set last_config_pull_at = now()
    where id = (v_result->>'node_id')::uuid returning * into v_node;
  return json_build_object('node_id', v_node.id, 'node_status', v_node.status,
    'status_reason', v_node.status_reason, 'config', v_node.config);
end;
$$;
revoke all on function public.hyn_fetch_local_config(text) from public;
grant execute on function public.hyn_fetch_local_config(text) to anon, authenticated;

-- An operator explicitly enabling the legacy archive is reflected in the UI.
create or replace function public._hyn_mark_cloud_telemetry()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.nodes set telemetry_mode = 'cloud' where id = new.node_id and telemetry_mode <> 'cloud';
  return new;
end;
$$;
revoke all on function public._hyn_mark_cloud_telemetry() from public, anon, authenticated;
drop trigger if exists hyn_mark_cloud_telemetry on public.metrics;
create trigger hyn_mark_cloud_telemetry after insert on public.metrics
for each row execute function public._hyn_mark_cloud_telemetry();
