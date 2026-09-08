-- A request never grants access. Only an active administrator can assign an ID.
create table if not exists public.relayer_requests (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references auth.users(id) on delete cascade,
  relayer_id integer not null check (relayer_id > 0),
  relayer_name text not null check (length(trim(relayer_name)) between 1 and 160),
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  unique (owner, relayer_id)
);
create index if not exists relayer_requests_pending_idx on public.relayer_requests(created_at) where status='pending';
alter table public.relayer_requests enable row level security;
drop policy if exists relayer_requests_read on public.relayer_requests;
create policy relayer_requests_read on public.relayer_requests for select to authenticated
  using (public.hyn_is_admin() or (owner=auth.uid() and public.hyn_is_active()));
revoke all on public.relayer_requests from anon, authenticated;
grant select on public.relayer_requests to authenticated;

create or replace function public.hyn_request_relayer(p_relayer_id integer, p_relayer_name text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'An active account is required'; end if;
  if p_relayer_id is null or p_relayer_id<=0 or p_relayer_name is null or length(trim(p_relayer_name)) not between 1 and 160 then
    raise exception 'A positive relayer ID and name are required';
  end if;
  -- Serialize this owner's submissions so concurrent calls cannot evade limits.
  perform 1 from public.profiles where id=auth.uid() for update;
  if exists(select 1 from public.relayer_assignments where relayer_id=p_relayer_id) then
    raise exception 'This relayer is already assigned. Ask an administrator to check its assignment';
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

create or replace function public.hyn_cancel_relayer_request(p_request_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'An active account is required'; end if;
  update public.relayer_requests set status='cancelled',reviewed_at=now()
    where id=p_request_id and owner=auth.uid() and status='pending';
  if not found then raise exception 'Pending request not found'; end if;
end $$;

-- Direct admin assignment also resolves a matching request, so the two paths
-- cannot leave a customer both assigned and waiting for approval.
create or replace function public._hyn_resolve_relayer_request()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  update public.relayer_requests set status='approved',relayer_name=new.relayer_name,reviewed_at=now(),reviewed_by=auth.uid()
    where owner=new.owner and relayer_id=new.relayer_id and status='pending';
  if found then
    perform public._hyn_audit('relayer.request.approved',new.owner,null,jsonb_build_object('relayer_id',new.relayer_id));
  end if;
  return new;
end $$;
drop trigger if exists relayer_assignment_resolves_request on public.relayer_assignments;
create trigger relayer_assignment_resolves_request after insert or update on public.relayer_assignments
  for each row execute function public._hyn_resolve_relayer_request();

create or replace function public.hyn_admin_review_relayer_request(p_request_id uuid, p_approve boolean, p_relayer_name text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_request public.relayer_requests;
begin
  perform public._hyn_require_admin();
  if p_approve is null then raise exception 'Choose approve or reject'; end if;
  select * into v_request from public.relayer_requests where id=p_request_id and status='pending' for update;
  if not found then raise exception 'This request is no longer pending'; end if;
  if p_approve then
    perform public.hyn_admin_assign_relayer(v_request.owner,v_request.relayer_id,p_relayer_name);
  else
    update public.relayer_requests set status='rejected',reviewed_at=now(),reviewed_by=auth.uid() where id=p_request_id;
    perform public._hyn_audit('relayer.request.rejected',v_request.owner,null,jsonb_build_object('relayer_id',v_request.relayer_id));
  end if;
end $$;
revoke all on function public._hyn_resolve_relayer_request() from public,anon,authenticated;
revoke all on function public.hyn_request_relayer(integer,text) from public,anon;
revoke all on function public.hyn_cancel_relayer_request(uuid) from public,anon;
revoke all on function public.hyn_admin_review_relayer_request(uuid,boolean,text) from public,anon;
grant execute on function public.hyn_request_relayer(integer,text) to authenticated;
grant execute on function public.hyn_cancel_relayer_request(uuid) to authenticated;
grant execute on function public.hyn_admin_review_relayer_request(uuid,boolean,text) to authenticated;
