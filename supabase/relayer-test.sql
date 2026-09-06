-- Run by flow-test.sql for both fresh schema and migration-chain verification.
begin;
insert into auth.users(id,email) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','relayer-admin@example.com'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','relayer-alice@example.com'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','relayer-bob@example.com');
update public.profiles set role='admin' where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local role authenticated;
set local "test.uid" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select public.hyn_admin_assign_relayer('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',457,'praveen256');
select public.hyn_admin_assign_relayer('cccccccc-cccc-4ccc-8ccc-cccccccccccc',458,'bob-relayer');
do $$ begin
  if (select count(*) from public.relayer_assignments) <> 2 then raise exception 'admin cannot read assignments'; end if;
  begin
    perform public.hyn_admin_assign_relayer('cccccccc-cccc-4ccc-8ccc-cccccccccccc',457,'stolen');
    raise exception 'assignment was silently transferred';
  exception when raise_exception then
    if sqlerrm not like '%already assigned%' then raise; end if;
  end;
  raise notice 'PASS  administrators assign relayers; duplicate IDs cannot silently transfer access';
end $$;

set local "test.uid" = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
do $$ begin
  if (select count(*) from public.relayer_assignments) <> 1 or
     (select relayer_id from public.relayer_assignments) <> 457 then raise exception 'cross-account assignment exposure'; end if;
  begin
    insert into public.relayer_assignments(owner,relayer_id,relayer_name)
      values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',459,'forged');
    raise exception 'customer inserted assignment';
  exception when insufficient_privilege then null; end;
  begin
    update public.relayer_assignments set owner='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' where relayer_id=458;
    raise exception 'customer updated assignment';
  exception when insufficient_privilege then null; end;
  begin
    perform public.hyn_admin_assign_relayer('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',459,'forged');
    raise exception 'customer called assignment RPC';
  exception when raise_exception then
    if sqlerrm <> 'administrator role required' then raise; end if;
  end;
  begin
    perform public.hyn_admin_remove_relayer((select id from public.relayer_assignments limit 1));
    raise exception 'customer removed assignment';
  exception when raise_exception then
    if sqlerrm <> 'administrator role required' then raise; end if;
  end;
  raise notice 'PASS  owners read only their relayers and cannot forge, transfer or remove assignments';
end $$;
reset role;
update public.profiles set status='suspended' where id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
set local role authenticated;
do $$ begin
  if exists(select 1 from public.relayer_assignments) then raise exception 'suspended owner still has access'; end if;
  raise notice 'PASS  suspended accounts lose relayer access';
end $$;
set local "test.uid" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
do $$ begin
  perform public.hyn_admin_remove_relayer((select id from public.relayer_assignments where relayer_id=457));
  if exists(select 1 from public.relayer_assignments where relayer_id=457) then raise exception 'removal did not revoke access'; end if;
  if (select count(*) from public.admin_audit where action in ('relayer.assign','relayer.remove')) < 3 then raise exception 'missing audit'; end if;
  raise notice 'PASS  assignment removal revokes access and changes are audited';
end $$;
set local role anon;
set local "test.uid" = '';
do $$ begin
  begin
    perform * from public.relayer_assignments;
    raise exception 'anonymous assignment read succeeded';
  exception when insufficient_privilege then null; end;
  begin
    perform public.hyn_admin_assign_relayer('cccccccc-cccc-4ccc-8ccc-cccccccccccc',460,'anonymous');
    raise exception 'anonymous assignment RPC succeeded';
  exception when insufficient_privilege then null; end;
  raise notice 'PASS  anonymous callers cannot read assignments or invoke administrative RPCs';
end $$;
rollback;
