-- ===========================================================================
-- an administrator can delete one machine, and can see which never linked
-- ===========================================================================
-- Pause, suspend and revoke all leave the row in place, which is correct for a
-- machine that exists: a revoked box is history worth keeping. It is wrong for a
-- machine that never existed. Approving a pairing code creates the node row
-- immediately, so a client who approves a code and then never finishes
-- `sudo hyn link` -- wrong box, a typo, a changed mind -- keeps a machine on
-- their dashboard that will never report anything. The only thing that ever
-- removed one was the pairing-expiry sweep, and only while the pairing row
-- survived; after that the phantom was permanent and nobody, client or
-- administrator, had a button for it.

-- "Never connected" is a different fact from "gone quiet", and the two must not
-- be conflated: quiet means go and look at the box, never connected means the
-- row was created by an approval the agent never completed. Defined once and
-- called from both admin views, because a duplicated definition of this drifts
-- and then the count and the badge disagree.
--
-- last_heartbeat_at is compared against created_at rather than tested for null:
-- migration 20260824023000 backfilled it to coalesce(..., created_at) for every
-- pre-existing row, so a never-connected node from before that migration has a
-- non-null heartbeat equal to its creation time. A real beat is always later.
create or replace function public._hyn_node_ever_connected(p_node public.nodes)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_node.last_seen_at is not null
      or p_node.last_config_pull_at is not null
      or coalesce(p_node.last_heartbeat_at > p_node.created_at, false);
$$;

revoke all on function public._hyn_node_ever_connected(public.nodes) from public;

-- Delete one machine and everything recorded for it. Irreversible, and the
-- audit entry is written first: admin_audit.target_node is ON DELETE SET NULL,
-- so the row survives the delete but loses its reference -- the detail is what
-- keeps the trail readable afterwards.
create or replace function public.hyn_admin_delete_node(
  p_node_id uuid,
  p_reason text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_node public.nodes;
  v_owner_email text;
begin
  perform public._hyn_require_admin();

  select * into v_node from public.nodes where id = p_node_id;
  if not found then
    raise exception 'no such node';
  end if;
  select email into v_owner_email from public.profiles where id = v_node.owner;

  perform public._hyn_audit('node.delete', v_node.owner, p_node_id,
    jsonb_build_object(
      'reason', p_reason,
      'name', v_node.name,
      'hostname', v_node.hostname,
      'owner_email', v_owner_email,
      'ever_connected', public._hyn_node_ever_connected(v_node),
      'agent_version', v_node.agent_version
    ));

  -- An unclaimed pairing row points here with ON DELETE SET NULL, and a code
  -- whose node_id is null reads as 'pending' to the polling agent: it would sit
  -- there until expiry waiting for an approval that already happened.
  delete from public.device_codes where node_id = p_node_id;
  -- metrics, speedtests, alert_events, node_commands, watchdogs, web jobs and
  -- email preferences are all ON DELETE CASCADE from nodes.
  delete from public.nodes where id = p_node_id;

  return json_build_object('status', 'ok', 'deleted', p_node_id, 'name', v_node.name);
end;
$$;

revoke all on function public.hyn_admin_delete_node(uuid, text) from public;
grant execute on function public.hyn_admin_delete_node(uuid, text) to authenticated;

-- ever_connected joins the fleet list so a phantom is visible as one rather than
-- looking like a machine that has been quiet since it was created.
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

-- How many machines a client has, how many are enabled, and how many are
-- phantoms -- which is the number an administrator is asked about, because it is
-- the one the client can see and cannot explain.
create or replace function public.hyn_admin_clients()
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  perform public._hyn_require_admin();
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
