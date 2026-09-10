-- Account assignment controls ownership; an explicit link identifies the server.
begin;

create unique index if not exists nodes_id_owner_key on public.nodes(id, owner);
create unique index if not exists relayer_assignments_id_owner_key on public.relayer_assignments(id, owner);

create table if not exists public.node_relayer_links (
  node_id uuid primary key,
  owner uuid not null,
  assignment_id uuid not null unique,
  linked_at timestamptz not null default now(),
  linked_by uuid references auth.users(id) on delete set null,
  foreign key (node_id, owner) references public.nodes(id, owner) on delete cascade,
  foreign key (assignment_id, owner) references public.relayer_assignments(id, owner) on delete cascade
);
create index if not exists node_relayer_links_owner_idx on public.node_relayer_links(owner);
alter table public.node_relayer_links enable row level security;
revoke all on public.node_relayer_links from public, anon, authenticated;
grant select (node_id, owner, assignment_id, linked_at) on public.node_relayer_links to authenticated;
drop policy if exists node_relayer_links_read on public.node_relayer_links;
create policy node_relayer_links_read on public.node_relayer_links
  for select to authenticated using (public.hyn_can_view_node(node_id));

create or replace function public.hyn_admin_set_node_relayer(p_node_id uuid, p_assignment_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_actor uuid; v_owner uuid; v_previous uuid; v_relayer_id integer;
begin
  v_actor := public._hyn_require_admin();
  select owner into v_owner from public.nodes
    where id = p_node_id and not revoked and not is_demo for update;
  if not found then raise exception 'Choose an available, non-demo server'; end if;
  select assignment_id into v_previous from public.node_relayer_links where node_id = p_node_id;
  if v_previous is not distinct from p_assignment_id then return; end if;

  if p_assignment_id is null then
    delete from public.node_relayer_links where node_id = p_node_id;
  else
    if not exists(select 1 from public.profiles where id = v_owner and status = 'active') then
      raise exception 'Restore this account before linking a relayer';
    end if;
    -- Lock the assignment as well as the server so concurrent links cannot move it.
    select relayer_id into v_relayer_id from public.relayer_assignments
      where id = p_assignment_id and owner = v_owner for update;
    if not found then raise exception 'Choose a relayer assigned to this server''s account'; end if;
    if exists(select 1 from public.node_relayer_links where assignment_id = p_assignment_id and node_id <> p_node_id) then
      raise exception 'This relayer is linked to another server. Unlink it there first' using errcode = 'PT409';
    end if;
    insert into public.node_relayer_links(node_id, owner, assignment_id, linked_by)
      values (p_node_id, v_owner, p_assignment_id, v_actor)
      on conflict (node_id) do update set assignment_id = excluded.assignment_id,
        owner = excluded.owner, linked_by = excluded.linked_by, linked_at = now();
  end if;
  perform public._hyn_audit(
    case when p_assignment_id is null then 'node.relayer.unlink' else 'node.relayer.link' end,
    v_owner, p_node_id,
    jsonb_build_object('assignment_id', p_assignment_id, 'previous_assignment_id', v_previous, 'relayer_id', v_relayer_id)
  );
end;
$$;

-- A server share exposes exactly its linked relay, without granting access to
-- the owner's other relayers or changing account-level assignment policies.
create or replace function public.hyn_node_relayer(p_node uuid)
returns table(id uuid, owner uuid, relayer_id integer, relayer_name text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.hyn_can_view_node(p_node) then
    raise exception 'Server unavailable' using errcode = '42501';
  end if;
  return query select a.id, a.owner, a.relayer_id, a.relayer_name, a.created_at
    from public.node_relayer_links l
    join public.relayer_assignments a on a.id = l.assignment_id and a.owner = l.owner
    where l.node_id = p_node;
end;
$$;

revoke all on function public.hyn_admin_set_node_relayer(uuid, uuid) from public, anon;
revoke all on function public.hyn_node_relayer(uuid) from public, anon;
grant execute on function public.hyn_admin_set_node_relayer(uuid, uuid) to authenticated;
grant execute on function public.hyn_node_relayer(uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
