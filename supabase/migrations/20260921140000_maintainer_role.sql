-- ===========================================================================
-- `maintainer`: a role that watches the whole fleet and administers none of it
-- ===========================================================================
-- The requirement is a person on 24/7 duty who sees every server combined in one
-- view, with per-server "send notification" / "send report" actions. That is a
-- read-and-notify job, not an administrative one.
--
-- The tempting shortcut is to add 'maintainer' to hyn_is_admin(), because every
-- fleet-wide SELECT policy already calls it. That would be a privilege
-- escalation: hyn_is_admin() also backs _hyn_require_admin(), which gates role
-- assignment, machine suspension, node deletion, relayer assignment and template
-- edits. A monitoring account must not inherit those by being able to read a
-- temperature.
--
-- So fleet *visibility* gets its own predicate. hyn_is_admin() is left exactly as
-- it was, and only the read paths move to the new one.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('viewer','monitor','maintainer','admin','super_admin'));

create or replace function public.hyn_can_view_fleet()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles
    where id=auth.uid() and status='active'
      and role in ('maintainer','admin','super_admin'));
$$;
revoke all on function public.hyn_can_view_fleet() from public,anon;
grant execute on function public.hyn_can_view_fleet() to authenticated;

-- Role assignment must accept the new value, or the admin UI can offer it and the
-- database will still refuse it.
create or replace function public.hyn_admin_set_role(p_user_id uuid,p_role text)
returns json language plpgsql security definer set search_path=public as $$
declare v_actor uuid; v_old text;
begin
  perform pg_advisory_xact_lock(74821901);
  v_actor:=public._hyn_require_staff();
  if p_role is null or p_role not in ('viewer','monitor','maintainer','admin','super_admin') then
    raise exception 'unknown role';
  end if;
  select role into v_old from public.profiles where id=p_user_id for update;
  if not found then raise exception 'no such client'; end if;
  if v_actor=p_user_id and v_old<>p_role then raise exception 'refusing to change your own role'; end if;
  -- An Admin may still only create Admins. Maintainer is a fleet-wide read grant,
  -- so it stays a Super admin decision rather than something an Admin hands out.
  if not public.hyn_is_super_admin() and (p_role<>'admin' or v_old not in ('viewer','monitor','admin')) then
    raise exception 'admins can only add other admins';
  end if;
  if v_old<>p_role then
    update public.profiles set role=p_role,updated_at=now() where id=p_user_id;
    perform public._hyn_audit('client.role.'||p_role,p_user_id,null,jsonb_build_object('previous_role',v_old));
  end if;
  return json_build_object('status','ok','role',p_role);
end $$;

-- Read paths: swap hyn_is_admin() for hyn_can_view_fleet(). Owner-scoped access
-- is untouched, so nothing a customer could see changes.
drop policy if exists nodes_select_own on public.nodes;
create policy nodes_select_own on public.nodes
  for select using (owner = auth.uid() or public.hyn_can_view_fleet());

drop policy if exists metrics_select_own on public.metrics;
create policy metrics_select_own on public.metrics
  for select using (
    public.hyn_can_view_fleet() or exists (
      select 1 from public.nodes n where n.id = metrics.node_id and n.owner = auth.uid()
    )
  );

drop policy if exists speedtests_select_own on public.speedtests;
create policy speedtests_select_own on public.speedtests
  for select using (
    public.hyn_can_view_fleet() or exists (
      select 1 from public.nodes n where n.id = speedtests.node_id and n.owner = auth.uid()
    )
  );

drop policy if exists alert_events_select_own on public.alert_events;
create policy alert_events_select_own on public.alert_events
  for select using (
    public.hyn_can_view_fleet() or exists (
      select 1 from public.nodes n where n.id = alert_events.node_id and n.owner = auth.uid()
    )
  );

-- Delivery history is how the maintainer sees that a notification actually went
-- out, which is part of the job.
drop policy if exists notification_log_select_own on public.notification_log;
create policy notification_log_select_own on public.notification_log
  for select using (owner = auth.uid() or public.hyn_can_view_fleet());

-- Per-node visibility (bandwidth_daily and the relayer views hang off this).
create or replace function public.hyn_can_view_node(p_node uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.hyn_is_active() and exists(
    select 1 from public.nodes n join public.profiles p on p.id=n.owner
    where n.id=p_node and not n.revoked and (public.hyn_can_view_fleet() or (p.status='active' and
      (n.owner=auth.uid() or coalesce(
        (select a.allowed from public.server_access a where a.viewer_id=auth.uid() and a.node_id=n.id),
        public.hyn_can_view_dashboard(n.owner)))))
  );
$$;

-- Dashboard account list: a maintainer resolves every account, which is what
-- makes the combined "all servers" view selectable for them.
create or replace function public.hyn_can_view_dashboard(p_owner uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.hyn_is_active() and (
    public.hyn_can_view_fleet() or
    exists(select 1 from public.profiles p where p.id=p_owner and p.status='active' and (
      p.id=auth.uid() or exists(select 1 from public.dashboard_access a where a.viewer_id=auth.uid() and a.owner_id=p_owner)
    ))
  );
$$;
