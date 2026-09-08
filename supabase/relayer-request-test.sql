begin;
insert into auth.users(id,email) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','request-admin@example.com'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','request-alice@example.com'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','request-bob@example.com');
update public.profiles set role='admin' where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local role authenticated;
set local "test.uid"='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
select public.hyn_request_relayer(457,'alice-relayer');
select public.hyn_request_relayer(457,'alice-relayer');
select set_config('test.alice_request',(select id::text from public.relayer_requests limit 1),true);
do $$ begin
  if (select count(*) from public.relayer_requests) <> 1 then raise exception 'duplicate request'; end if;
  if exists(select 1 from public.relayer_assignments) then raise exception 'request granted access'; end if;
  begin
    perform public.hyn_admin_review_relayer_request((select id from public.relayer_requests limit 1),true,'forged');
    raise exception 'customer approved request';
  exception when raise_exception then
    if sqlerrm <> 'administrator role required' then raise; end if;
  end;
  begin
    update public.relayer_requests set status='approved';
    raise exception 'customer mutated status';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.relayer_requests(owner,relayer_id,relayer_name,status) values(auth.uid(),999,'forged','approved');
    raise exception 'customer inserted approved request';
  exception when insufficient_privilege then null; end;
  raise notice 'PASS  relayer requests are idempotent and cannot grant customer access';
end $$;
set local "test.uid"='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
do $$ begin
  if exists(select 1 from public.relayer_requests) then raise exception 'cross-owner request leak'; end if;
  begin
    perform public.hyn_cancel_relayer_request(current_setting('test.alice_request')::uuid);
    raise exception 'cancelled another account request';
  exception when raise_exception then
    if sqlerrm <> 'Pending request not found' then raise; end if;
  end;
  raise notice 'PASS  customers see only their own relayer requests';
end $$;
select public.hyn_request_relayer(457,'same-relayer');
set local "test.uid"='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
do $$ begin
  perform public.hyn_admin_review_relayer_request((select id from public.relayer_requests where owner='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),true,'verified-provider-name');
  if not exists(select 1 from public.relayer_assignments where owner='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and relayer_name='verified-provider-name') then raise exception 'approval did not assign'; end if;
  begin
    perform public.hyn_admin_review_relayer_request((select id from public.relayer_requests where owner='cccccccc-cccc-4ccc-8ccc-cccccccccccc'),true,'stolen');
    raise exception 'approval transferred ownership';
  exception when raise_exception then
    if sqlerrm not like '%already assigned%' then raise; end if;
  end;
  perform public.hyn_admin_review_relayer_request((select id from public.relayer_requests where owner='cccccccc-cccc-4ccc-8ccc-cccccccccccc'),false,null);
  if not exists(select 1 from public.relayer_requests where owner='cccccccc-cccc-4ccc-8ccc-cccccccccccc' and status='rejected') then raise exception 'rejection not saved'; end if;
  if (select count(*) from public.admin_audit where action in ('relayer.request.approved','relayer.request.rejected')) <> 2 then raise exception 'review audit missing'; end if;
  raise notice 'PASS  admin approval assigns the verified identity, rejects conflicts and audits reviews';
end $$;
set local "test.uid"='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
do $$ begin
  if not exists(select 1 from public.relayer_requests where relayer_id=457 and status='approved') then raise exception 'customer does not see approved status'; end if;
  if not exists(select 1 from public.relayer_assignments where relayer_id=457) then raise exception 'approved relayer invisible to customer'; end if;
  for i in 1000..1009 loop perform public.hyn_request_relayer(i,'request-limit'); end loop;
  begin
    perform public.hyn_request_relayer(1010,'eleventh');
    raise exception 'pending quota not enforced';
  exception when raise_exception then
    if sqlerrm not like '%10 pending%' then raise; end if;
  end;
  raise notice 'PASS  approved relayers become visible to their owner and pending requests are bounded';
end $$;
set local "test.uid"='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select public.hyn_admin_assign_relayer('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',1000,'direct-assignment');
do $$ begin
  if not exists(select 1 from public.relayer_requests where relayer_id=1000 and status='approved') then raise exception 'direct assignment left request pending'; end if;
  raise notice 'PASS  direct administrator assignment also resolves matching pending requests';
end $$;
set local "test.uid"='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
select public.hyn_request_relayer(458,'bob-relayer');
select public.hyn_cancel_relayer_request((select id from public.relayer_requests where relayer_id=458));
do $$ begin
  if not exists(select 1 from public.relayer_requests where relayer_id=458 and status='cancelled') then raise exception 'cancellation missing'; end if;
  raise notice 'PASS  owners can cancel their pending requests';
end $$;
select public.hyn_request_relayer(458,'bob-relayer');
reset role;
update public.profiles set status='suspended' where id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
set local role authenticated;
do $$ begin
  if exists(select 1 from public.relayer_requests) then raise exception 'suspended owner read requests'; end if;
  begin
    perform public.hyn_request_relayer(459,'suspended');
    raise exception 'suspended owner requested';
  exception when raise_exception then
    if sqlerrm <> 'An active account is required' then raise; end if;
  end;
  raise notice 'PASS  suspended accounts cannot read or create relayer requests';
end $$;
set local "test.uid"='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
do $$ begin
  begin
    perform public.hyn_admin_review_relayer_request((select id from public.relayer_requests where relayer_id=458),true,'suspended');
    raise exception 'approved suspended owner';
  exception when raise_exception then
    if sqlerrm <> 'Select an active portal account' then raise; end if;
  end;
  raise notice 'PASS  administrators cannot approve a suspended requester';
end $$;
set local role anon;
set local "test.uid"='';
do $$ begin
  begin
    perform public.hyn_request_relayer(459,'anonymous');
    raise exception 'anonymous request accepted';
  exception when insufficient_privilege then null; end;
  begin
    perform * from public.relayer_requests;
    raise exception 'anonymous request read';
  exception when insufficient_privilege then null; end;
  raise notice 'PASS  anonymous callers cannot read or create relayer requests';
end $$;
rollback;
