-- An administrator maps a Highway identity to one portal account. Provider
-- names are display labels; authorization always uses owner + numeric ID.
create table if not exists public.relayer_assignments (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references auth.users(id) on delete cascade,
  relayer_id integer not null unique check (relayer_id > 0),
  relayer_name text not null check (length(relayer_name) between 1 and 160),
  created_at timestamptz not null default now()
);
create index if not exists relayer_assignments_owner_idx on public.relayer_assignments(owner);
alter table public.relayer_assignments enable row level security;
drop policy if exists relayer_assignments_read on public.relayer_assignments;
create policy relayer_assignments_read on public.relayer_assignments
  for select to authenticated using (
    public.hyn_is_admin() or (owner = auth.uid() and public.hyn_is_active())
  );
revoke all on public.relayer_assignments from anon, authenticated;
grant select on public.relayer_assignments to authenticated;

create or replace function public.hyn_admin_assign_relayer(p_owner uuid, p_relayer_id integer, p_relayer_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform public._hyn_require_admin();
  if p_owner is null or p_relayer_id is null or p_relayer_id <= 0
     or p_relayer_name is null or length(trim(p_relayer_name)) not between 1 and 160 then
    raise exception 'A user, positive relayer ID and name are required';
  end if;
  if not exists (select 1 from public.profiles where id = p_owner and status = 'active') then
    raise exception 'Select an active portal account';
  end if;
  -- Concurrent assignment attempts are serialized by the unique constraint.
  -- Reassignment requires an explicit removal; never silently transfer access.
  insert into public.relayer_assignments(owner, relayer_id, relayer_name)
  values (p_owner, p_relayer_id, trim(p_relayer_name))
  on conflict (relayer_id) do update set relayer_name = excluded.relayer_name
    where relayer_assignments.owner = excluded.owner
  returning id into v_id;
  if v_id is null then raise exception 'This relayer is already assigned to another account'; end if;
  perform public._hyn_audit('relayer.assign', p_owner, null,
    jsonb_build_object('relayer_id', p_relayer_id, 'relayer_name', trim(p_relayer_name)));
  return v_id;
end;
$$;

create or replace function public.hyn_admin_remove_relayer(p_assignment_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_row public.relayer_assignments;
begin
  perform public._hyn_require_admin();
  delete from public.relayer_assignments where id = p_assignment_id returning * into v_row;
  if v_row.id is null then raise exception 'Assignment no longer exists'; end if;
  perform public._hyn_audit('relayer.remove', v_row.owner, null,
    jsonb_build_object('relayer_id', v_row.relayer_id, 'relayer_name', v_row.relayer_name));
end;
$$;
revoke all on function public.hyn_admin_assign_relayer(uuid, integer, text) from public, anon;
revoke all on function public.hyn_admin_remove_relayer(uuid) from public, anon;
grant execute on function public.hyn_admin_assign_relayer(uuid, integer, text) to authenticated;
grant execute on function public.hyn_admin_remove_relayer(uuid) to authenticated;
