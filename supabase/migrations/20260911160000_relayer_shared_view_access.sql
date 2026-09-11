-- A physical relayer has one priority assignment and any number of view grants.
-- Keep the existing three-argument admin API and all portal UI unchanged.
begin;

-- Existing, previously exclusive assignments retain their priority and IDs.
alter table public.relayer_assignments
  add column if not exists assignment_role text not null default 'primary';
do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.relayer_assignments'::regclass and conname='relayer_assignments_assignment_role_check') then
    alter table public.relayer_assignments add constraint relayer_assignments_assignment_role_check
      check (assignment_role in ('primary','view'));
  end if;
end $$;
create unique index if not exists relayer_assignments_owner_relayer_key
  on public.relayer_assignments(owner,relayer_id);
create unique index if not exists relayer_assignments_primary_relayer_key
  on public.relayer_assignments(relayer_id) where assignment_role='primary';
create unique index if not exists relayer_assignments_id_owner_role_key
  on public.relayer_assignments(id,owner,assignment_role);
alter table public.relayer_assignments drop constraint if exists relayer_assignments_relayer_id_key;

-- Only the priority relationship can back a Highway Node link. A composite FK
-- also enforces this for direct privileged writes and concurrent role changes.
-- Removing one assignment cannot revoke any other user's independent view grant.
alter table public.node_relayer_links
  add column if not exists assignment_role text not null default 'primary';
do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.node_relayer_links'::regclass and conname='node_relayer_links_primary_role_check') then
    alter table public.node_relayer_links add constraint node_relayer_links_primary_role_check
      check (assignment_role='primary');
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.node_relayer_links'::regclass and conname='node_relayer_links_primary_assignment_fkey') then
    alter table public.node_relayer_links add constraint node_relayer_links_primary_assignment_fkey
      foreign key (assignment_id,owner,assignment_role)
      references public.relayer_assignments(id,owner,assignment_role)
      on update restrict on delete cascade;
  end if;
end $$;

create or replace function public.hyn_admin_assign_relayer(p_owner uuid,p_relayer_id integer,p_relayer_name text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_role text;
begin
  perform public._hyn_require_admin();
  if p_owner is null or p_relayer_id is null or p_relayer_id<=0
    or p_relayer_name is null or length(trim(p_relayer_name)) not between 1 and 160 then
    raise exception 'A user, positive relayer ID and name are required';
  end if;
  if not exists(select 1 from public.profiles where id=p_owner and status='active') then
    raise exception 'Select an active portal account';
  end if;
  -- Serialize first-assignment selection across different users of this relay.
  perform pg_advisory_xact_lock(hashtext('hyn.relayer.assignment'),p_relayer_id);
  select assignment_role into v_role from public.relayer_assignments
    where owner=p_owner and relayer_id=p_relayer_id;
  if v_role is null then
    v_role:=case when exists(select 1 from public.relayer_assignments
      where relayer_id=p_relayer_id and assignment_role='primary') then 'view' else 'primary' end;
  end if;
  insert into public.relayer_assignments(owner,relayer_id,relayer_name,assignment_role)
    values(p_owner,p_relayer_id,trim(p_relayer_name),v_role)
    on conflict(owner,relayer_id) do update set relayer_name=excluded.relayer_name
    returning id,assignment_role into v_id,v_role;
  perform public._hyn_audit('relayer.assign',p_owner,null,
    jsonb_build_object('relayer_id',p_relayer_id,'relayer_name',trim(p_relayer_name),'assignment_role',v_role));
  return v_id;
end $$;

-- Priority changes are explicit, never a side effect of adding a viewer.
-- A linked priority assignment must be unlinked before transferring priority;
-- no existing server association is silently moved or removed.
create or replace function public.hyn_admin_set_relayer_priority(p_assignment_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_relayer_id integer; v_assignment public.relayer_assignments; v_previous uuid;
begin
  perform public._hyn_require_admin();
  select relayer_id into v_relayer_id from public.relayer_assignments where id=p_assignment_id;
  if not found then raise exception 'Assignment no longer exists'; end if;
  perform pg_advisory_xact_lock(hashtext('hyn.relayer.assignment'),v_relayer_id);
  select * into v_assignment from public.relayer_assignments where id=p_assignment_id for update;
  if not found then raise exception 'Assignment no longer exists'; end if;
  if not exists(select 1 from public.profiles where id=v_assignment.owner and status='active') then
    raise exception 'Select an active portal account';
  end if;
  if v_assignment.assignment_role='primary' then return; end if;
  select id into v_previous from public.relayer_assignments
    where relayer_id=v_relayer_id and assignment_role='primary' for update;
  if exists(select 1 from public.node_relayer_links where assignment_id=v_previous) then
    raise exception 'Unlink this relayer from its Highway Node server before changing priority' using errcode='PT409';
  end if;
  update public.relayer_assignments set assignment_role='view' where id=v_previous;
  update public.relayer_assignments set assignment_role='primary' where id=p_assignment_id;
  perform public._hyn_audit('relayer.priority',v_assignment.owner,null,
    jsonb_build_object('relayer_id',v_relayer_id,'assignment_id',p_assignment_id,'previous_assignment_id',v_previous));
end $$;

create or replace function public.hyn_request_relayer(p_relayer_id integer,p_relayer_name text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not public.hyn_can_monitor() then raise exception 'monitor or super administrator role required'; end if;
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'An active account is required'; end if;
  if p_relayer_id is null or p_relayer_id<=0 or p_relayer_name is null or length(trim(p_relayer_name)) not between 1 and 160 then
    raise exception 'A positive relayer ID and name are required';
  end if;
  perform 1 from public.profiles where id=auth.uid() for update;
  -- Another user's priority or view assignment does not prevent a request.
  -- A request itself still grants no access; an admin must approve it.
  if exists(select 1 from public.relayer_assignments where owner=auth.uid() and relayer_id=p_relayer_id) then
    raise exception 'This relayer is already assigned to your account';
  end if;
  select id into v_id from public.relayer_requests where owner=auth.uid() and relayer_id=p_relayer_id and status='pending';
  if v_id is not null then return v_id; end if;
  if (select count(*) from public.relayer_requests where owner=auth.uid() and status='pending')>=10 then
    raise exception 'You already have 10 pending requests. Cancel one or wait for a review';
  end if;
  if not exists(select 1 from public.relayer_requests where owner=auth.uid() and relayer_id=p_relayer_id)
    and (select count(*) from public.relayer_requests where owner=auth.uid())>=50 then
    raise exception 'Request limit reached. Contact an administrator';
  end if;
  insert into public.relayer_requests(owner,relayer_id,relayer_name)
    values(auth.uid(),p_relayer_id,trim(p_relayer_name))
    on conflict(owner,relayer_id) do update set relayer_name=excluded.relayer_name,status='pending',created_at=now(),reviewed_at=null,reviewed_by=null
    returning id into v_id;
  return v_id;
end $$;

create or replace function public.hyn_admin_set_node_relayer(p_node_id uuid,p_assignment_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_actor uuid; v_owner uuid; v_previous uuid; v_relayer_id integer; v_role text;
begin
  v_actor:=public._hyn_require_admin();
  select owner into v_owner from public.nodes where id=p_node_id and not revoked and not is_demo for update;
  if not found then raise exception 'Choose an available, non-demo server'; end if;
  select assignment_id into v_previous from public.node_relayer_links where node_id=p_node_id;
  if v_previous is not distinct from p_assignment_id then return; end if;
  if p_assignment_id is null then
    delete from public.node_relayer_links where node_id=p_node_id;
  else
    if not exists(select 1 from public.profiles where id=v_owner and status='active') then
      raise exception 'Restore this account before linking a relayer';
    end if;
    select relayer_id,assignment_role into v_relayer_id,v_role from public.relayer_assignments
      where id=p_assignment_id and owner=v_owner for update;
    if not found then raise exception 'Choose a relayer assigned to this server''s account'; end if;
    if v_role<>'primary' then
      raise exception 'This is view-only relay access. Only the priority assignment can link to a Highway Node server' using errcode='PT409';
    end if;
    if exists(select 1 from public.node_relayer_links where assignment_id=p_assignment_id and node_id<>p_node_id) then
      raise exception 'This relayer is linked to another server. Unlink it there first' using errcode='PT409';
    end if;
    insert into public.node_relayer_links(node_id,owner,assignment_id,linked_by)
      values(p_node_id,v_owner,p_assignment_id,v_actor)
      on conflict(node_id) do update set assignment_id=excluded.assignment_id,owner=excluded.owner,linked_by=excluded.linked_by,linked_at=now();
  end if;
  perform public._hyn_audit(case when p_assignment_id is null then 'node.relayer.unlink' else 'node.relayer.link' end,
    v_owner,p_node_id,jsonb_build_object('assignment_id',p_assignment_id,'previous_assignment_id',v_previous,'relayer_id',v_relayer_id));
end $$;

-- Preserve existing read visibility and admin-only writes. No dashboard or
-- server access is granted merely by adding a relayer view assignment.
revoke all on function public.hyn_admin_assign_relayer(uuid,integer,text) from public,anon;
revoke all on function public.hyn_admin_set_relayer_priority(uuid) from public,anon;
revoke all on function public.hyn_request_relayer(integer,text) from public,anon;
revoke all on function public.hyn_admin_set_node_relayer(uuid,uuid) from public,anon;
grant execute on function public.hyn_admin_assign_relayer(uuid,integer,text) to authenticated;
grant execute on function public.hyn_admin_set_relayer_priority(uuid) to authenticated;
grant execute on function public.hyn_request_relayer(integer,text) to authenticated;
grant execute on function public.hyn_admin_set_node_relayer(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
