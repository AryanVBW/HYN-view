-- ===========================================================================
-- Let a maintainer dismiss a false alert, without becoming an admin
-- ===========================================================================
-- alert_events has no update policy and no RPC touches `resolved` from a
-- browser session -- rows only flip to resolved through hyn_ingest() when the
-- agent itself stops reporting the condition. That is correct for a real
-- fault, but a maintainer watching the fleet needs to be able to say "this one
-- was a false alarm" without waiting for the agent to agree, and without
-- ssh'ing in.
--
-- The tempting shortcut is _hyn_require_staff() or _hyn_require_admin(), since
-- every other write RPC in this file uses one of them. Both actually gate on
-- hyn_is_admin()/hyn_is_super_admin() (see their definitions), not on fleet
-- visibility -- reusing either would hand a Maintainer role assignment,
-- suspension and node deletion just to let them clear a warning. So this gets
-- its own guard, parallel to hyn_can_view_fleet(), and the new RPC is the only
-- thing that calls it.
create or replace function public._hyn_require_fleet()
returns uuid language plpgsql stable security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.hyn_can_view_fleet() then raise exception 'fleet access required'; end if;
  return auth.uid();
end $$;
revoke all on function public._hyn_require_fleet() from public,anon,authenticated;

-- Marks one open alert resolved with a reason, e.g. "false alarm -- disk usage
-- was a one-off backup job". Idempotent: resolving an already-resolved alert
-- is a no-op rather than an error, since two maintainers clicking the same
-- warning a moment apart is an ordinary race, not a mistake either of them made.
-- Scoped to the alert's own node through hyn_can_view_node(), so this cannot be
-- used to touch a row outside what the caller's fleet visibility already covers.
create or replace function public.hyn_maintainer_resolve_alert(p_alert_id bigint, p_reason text default null)
returns json language plpgsql security definer set search_path=public as $$
declare
  v_actor uuid;
  v_node uuid;
  v_was_resolved boolean;
begin
  v_actor := public._hyn_require_fleet();

  select node_id, resolved into v_node, v_was_resolved
    from public.alert_events where id = p_alert_id for update;
  if not found then
    raise exception 'no such alert';
  end if;
  if not public.hyn_can_view_node(v_node) then
    raise exception 'that alert is not visible to this account';
  end if;

  if not v_was_resolved then
    update public.alert_events set resolved = true where id = p_alert_id;
    perform public._hyn_audit(
      'alert.resolve.manual', null, v_node,
      jsonb_build_object('alert_id', p_alert_id, 'reason', coalesce(p_reason, ''))
    );
  end if;
  return json_build_object('status', 'ok', 'alert_id', p_alert_id, 'resolved', true);
end $$;
revoke all on function public.hyn_maintainer_resolve_alert(bigint, text) from public,anon;
grant execute on function public.hyn_maintainer_resolve_alert(bigint, text) to authenticated;
