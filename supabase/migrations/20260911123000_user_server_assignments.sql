-- Save one user's explicit server set atomically, preserving other users.
begin;
create or replace function public.hyn_admin_set_user_servers(p_viewer uuid, p_nodes uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid; v_nodes uuid[]; v_previous uuid[]; v_shares integer;
begin
  v_actor := public._hyn_require_admin();
  perform 1 from public.profiles where id = p_viewer and status = 'active'
    and role in ('viewer', 'monitor') for update;
  if not found then raise exception 'Choose an active Viewer or Monitor'; end if;
  if p_nodes is null or array_position(p_nodes, null) is not null then
    raise exception 'Choose a valid list of servers';
  end if;
  select coalesce(array_agg(distinct id order by id), '{}'::uuid[]) into v_nodes from unnest(p_nodes) id;
  perform 1 from public.nodes where id = any(v_nodes) order by id for update;
  if (select count(*) from public.nodes n join public.profiles p on p.id = n.owner
      where n.id = any(v_nodes) and not n.revoked and not n.is_demo and p.status = 'active') <> cardinality(v_nodes) then
    raise exception 'One or more selected servers are unavailable. Refresh and try again';
  end if;
  -- Owners retain their own machines independently of additional assignments.
  select coalesce(array_agg(n.id order by n.id), '{}'::uuid[]) into v_nodes
    from public.nodes n where n.id = any(v_nodes) and n.owner <> p_viewer;
  select coalesce(array_agg(n.id order by n.id), '{}'::uuid[]) into v_previous
    from public.nodes n join public.profiles p on p.id = n.owner
    where n.owner <> p_viewer and not n.revoked and not n.is_demo and p.status = 'active'
      and coalesce((select a.allowed from public.server_access a where a.viewer_id = p_viewer and a.node_id = n.id),
        exists(select 1 from public.dashboard_access d where d.viewer_id = p_viewer and d.owner_id = n.owner));

  -- Convert inherited dashboard sharing into the exact selection shown in the
  -- editor, so unselected siblings and future servers do not remain visible.
  delete from public.dashboard_access where viewer_id = p_viewer;
  get diagnostics v_shares = row_count;
  delete from public.server_access where viewer_id = p_viewer and not (node_id = any(v_nodes));
  insert into public.server_access(viewer_id, node_id, allowed, granted_by)
    select p_viewer, id, true, v_actor from unnest(v_nodes) id
    on conflict (viewer_id, node_id) do update set allowed = true,
      granted_by = excluded.granted_by, updated_at = now();
  -- Updating an existing row leaves its notification preference untouched.
  insert into public.server_access_events(actor, viewer_id, node_id, allowed)
    select v_actor, p_viewer, id, true from unnest(v_nodes) id where not (id = any(v_previous))
    union all
    select v_actor, p_viewer, id, false from unnest(v_previous) id where not (id = any(v_nodes));
  if v_nodes is distinct from v_previous or v_shares > 0 then
    perform public._hyn_audit('user.servers.assign', p_viewer, null,
      jsonb_build_object('node_ids', v_nodes, 'previous_node_ids', v_previous, 'dashboard_shares_replaced', v_shares));
  end if;
  return jsonb_build_object('node_ids', v_nodes);
end;
$$;
revoke all on function public.hyn_admin_set_user_servers(uuid, uuid[]) from public, anon;
grant execute on function public.hyn_admin_set_user_servers(uuid, uuid[]) to authenticated;
notify pgrst, 'reload schema';
commit;
