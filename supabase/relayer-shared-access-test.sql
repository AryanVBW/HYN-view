-- Final-policy tests. Historical exclusive-assignment tests still cover the
-- older migration stages in flow-test.sql. These fixtures never touch production.
begin;
create function pg_temp.check_shared_relayer(ok boolean,label text) returns void language plpgsql as $$
begin
  if not coalesce(ok,false) then raise exception 'FAIL shared relay: %',label; end if;
  raise notice 'PASS shared relay: %',label;
end $$;
insert into auth.users(id,email) values
 ('f1000000-0000-4000-8000-000000000001','super@shared-relay.test'),
 ('f1000000-0000-4000-8000-000000000002','priority@shared-relay.test'),
 ('f1000000-0000-4000-8000-000000000003','view-a@shared-relay.test'),
 ('f1000000-0000-4000-8000-000000000004','view-b@shared-relay.test'),
 ('f1000000-0000-4000-8000-000000000005','admin@shared-relay.test'),
 ('f1000000-0000-4000-8000-000000000006','requester@shared-relay.test');
update public.profiles set status='active',role=case right(id::text,1)
  when '1' then 'super_admin' when '4' then 'viewer' when '5' then 'admin' else 'monitor' end
  where email like '%@shared-relay.test';
insert into public.nodes(id,owner,name) values
 ('f2000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000002','Priority server'),
 ('f2000000-0000-4000-8000-000000000002','f1000000-0000-4000-8000-000000000003','Other user server');
set local role authenticated;
set local "test.uid"='f1000000-0000-4000-8000-000000000001';
select set_config('test.relay_priority',public.hyn_admin_assign_relayer('f1000000-0000-4000-8000-000000000002',2457,'Shared relay')::text,true);
select public.hyn_admin_assign_relayer('f1000000-0000-4000-8000-000000000002',2458,'Private relay');
select set_config('test.relay_view_a',public.hyn_admin_assign_relayer('f1000000-0000-4000-8000-000000000003',2457,'Shared relay')::text,true);
select set_config('test.relay_view_b',public.hyn_admin_assign_relayer('f1000000-0000-4000-8000-000000000004',2457,'Shared relay')::text,true);
select pg_temp.check_shared_relayer((select count(*)=3 and count(*) filter(where assignment_role='primary')=1 and count(*) filter(where assignment_role='view')=2 from public.relayer_assignments where relayer_id=2457),'one priority assignment and multiple independent view assignments');
select pg_temp.check_shared_relayer(public.hyn_admin_assign_relayer('f1000000-0000-4000-8000-000000000003',2457,'Updated display name')=current_setting('test.relay_view_a')::uuid
  and (select assignment_role='view' from public.relayer_assignments where id=current_setting('test.relay_view_a')::uuid),'repeat assignment is idempotent and cannot take priority');
select public.hyn_admin_set_node_relayer('f2000000-0000-4000-8000-000000000001',current_setting('test.relay_priority')::uuid);
do $$ begin
  begin perform public.hyn_admin_set_node_relayer('f2000000-0000-4000-8000-000000000002',current_setting('test.relay_view_a')::uuid);
    raise exception 'view access linked a Highway Node'; exception when sqlstate 'PT409' then null; end;
  begin perform public.hyn_admin_set_relayer_priority(current_setting('test.relay_view_a')::uuid);
    raise exception 'priority transferred without unlinking'; exception when sqlstate 'PT409' then null; end;
  perform pg_temp.check_shared_relayer((select assignment_id=current_setting('test.relay_priority')::uuid from public.node_relayer_links where node_id='f2000000-0000-4000-8000-000000000001'),'adding viewers and refused priority transfers preserve the server link');
end $$;

set local "test.uid"='f1000000-0000-4000-8000-000000000003';
select pg_temp.check_shared_relayer((select count(*)=1 and bool_and(relayer_id=2457 and assignment_role='view') from public.relayer_assignments),'view assignee sees only their assigned relay, not the priority account private relay');
select pg_temp.check_shared_relayer(not public.hyn_can_view_dashboard('f1000000-0000-4000-8000-000000000002')
  and not exists(select 1 from public.nodes where id='f2000000-0000-4000-8000-000000000001')
  and not exists(select 1 from public.node_relayer_links),'relay view access does not grant dashboard or server access');
do $$ declare actor text; begin
  foreach actor in array array['f1000000-0000-4000-8000-000000000002','f1000000-0000-4000-8000-000000000003','f1000000-0000-4000-8000-000000000004','f1000000-0000-4000-8000-000000000005'] loop
    perform set_config('test.uid',actor,true);
    begin perform public.hyn_admin_set_relayer_priority(current_setting('test.relay_view_a')::uuid); raise exception 'non-super-admin changed priority';
      exception when raise_exception then if sqlerrm<>'super administrator role required' then raise; end if; end;
    begin update public.relayer_assignments set assignment_role='primary' where id=current_setting('test.relay_view_a')::uuid; raise exception 'direct role mutation succeeded';
      exception when insufficient_privilege then null; end;
  end loop;
  raise notice 'PASS shared relay: priority owner, viewers and ordinary admins cannot promote assignments';
end $$;
reset role;
do $$ begin
  begin insert into public.relayer_assignments(owner,relayer_id,relayer_name,assignment_role)
    values('f1000000-0000-4000-8000-000000000005',2457,'Second priority','primary');
    raise exception 'multiple priority assignments bypassed the database'; exception when unique_violation then null; end;
  begin insert into public.relayer_assignments(owner,relayer_id,relayer_name,assignment_role)
    values('f1000000-0000-4000-8000-000000000003',2457,'Duplicate viewer','view');
    raise exception 'duplicate user-relay pair bypassed the database'; exception when unique_violation then null; end;
  begin insert into public.node_relayer_links(node_id,owner,assignment_id)
    values('f2000000-0000-4000-8000-000000000002','f1000000-0000-4000-8000-000000000003',current_setting('test.relay_view_a')::uuid);
    raise exception 'view assignment bypassed the primary-link foreign key'; exception when foreign_key_violation then null; end;
  begin update public.relayer_assignments set assignment_role='view' where id=current_setting('test.relay_priority')::uuid;
    raise exception 'linked priority assignment was demoted directly'; exception when foreign_key_violation then null; end;
  raise notice 'PASS shared relay: database constraints enforce one priority, unique user pairs and primary-only server links';
end $$;

set local role authenticated;
set local "test.uid"='f1000000-0000-4000-8000-000000000001';
select public.hyn_admin_set_node_relayer('f2000000-0000-4000-8000-000000000001',null);
select public.hyn_admin_set_relayer_priority(current_setting('test.relay_view_a')::uuid);
select public.hyn_admin_set_relayer_priority(current_setting('test.relay_view_a')::uuid);
select pg_temp.check_shared_relayer((select assignment_role='primary' from public.relayer_assignments where id=current_setting('test.relay_view_a')::uuid)
  and (select assignment_role='view' from public.relayer_assignments where id=current_setting('test.relay_priority')::uuid)
  and (select count(*)=3 from public.relayer_assignments where relayer_id=2457)
  and (select count(*)=1 from public.admin_audit where action='relayer.priority' and target_user='f1000000-0000-4000-8000-000000000003'),'explicit priority transfer preserves all grants and is audited once');
select public.hyn_admin_set_node_relayer('f2000000-0000-4000-8000-000000000002',current_setting('test.relay_view_a')::uuid);
select public.hyn_admin_remove_relayer(current_setting('test.relay_view_b')::uuid);
select pg_temp.check_shared_relayer((select count(*)=2 from public.relayer_assignments where relayer_id=2457)
  and exists(select 1 from public.node_relayer_links where assignment_id=current_setting('test.relay_view_a')::uuid),'removing one viewer preserves other grants and the priority server link');
select set_config('test.relay_view_b',public.hyn_admin_assign_relayer('f1000000-0000-4000-8000-000000000004',2457,'Shared relay')::text,true);
select public.hyn_admin_remove_relayer(current_setting('test.relay_view_a')::uuid);
select pg_temp.check_shared_relayer((select count(*)=2 and bool_and(assignment_role='view') from public.relayer_assignments where relayer_id=2457)
  and not exists(select 1 from public.node_relayer_links where node_id='f2000000-0000-4000-8000-000000000002'),'removing priority clears only its server link and retains independent view grants');
select public.hyn_admin_assign_relayer('f1000000-0000-4000-8000-000000000002',2457,'Shared relay');
select pg_temp.check_shared_relayer((select assignment_role='view' from public.relayer_assignments where id=current_setting('test.relay_priority')::uuid),'re-saving an existing viewer never silently promotes them after priority removal');
select public.hyn_admin_set_relayer_priority(current_setting('test.relay_priority')::uuid);
select public.hyn_admin_set_node_relayer('f2000000-0000-4000-8000-000000000001',current_setting('test.relay_priority')::uuid);

reset role;
update public.profiles set status='suspended' where id='f1000000-0000-4000-8000-000000000004';
set local role authenticated;
set local "test.uid"='f1000000-0000-4000-8000-000000000004';
select pg_temp.check_shared_relayer(not exists(select 1 from public.relayer_assignments),'suspended viewers lose shared relayer visibility');
set local "test.uid"='f1000000-0000-4000-8000-000000000001';
do $$ begin
  begin perform public.hyn_admin_set_relayer_priority(current_setting('test.relay_view_b')::uuid); raise exception 'suspended user took priority';
    exception when raise_exception then if sqlerrm<>'Select an active portal account' then raise; end if; end;
  raise notice 'PASS shared relay: priority cannot be transferred to a suspended account';
end $$;
reset role;
delete from auth.users where id='f1000000-0000-4000-8000-000000000004';
select pg_temp.check_shared_relayer(exists(select 1 from public.relayer_assignments where id=current_setting('test.relay_priority')::uuid and assignment_role='primary')
  and exists(select 1 from public.node_relayer_links where assignment_id=current_setting('test.relay_priority')::uuid),'deleting a view-only account does not affect priority access or its server');

set local role authenticated;
set local "test.uid"='f1000000-0000-4000-8000-000000000006';
select set_config('test.shared_request',public.hyn_request_relayer(2457,'Already assigned to another user')::text,true);
select pg_temp.check_shared_relayer(not exists(select 1 from public.relayer_assignments)
  and exists(select 1 from public.relayer_requests where id=current_setting('test.shared_request')::uuid and status='pending'),'users can request an already-assigned relay without receiving access before approval');
set local "test.uid"='f1000000-0000-4000-8000-000000000003';
select public.hyn_request_relayer(2457,'Separate pending request');
set local "test.uid"='f1000000-0000-4000-8000-000000000001';
select public.hyn_admin_review_relayer_request(current_setting('test.shared_request')::uuid,true,'Verified relay');
select pg_temp.check_shared_relayer(exists(select 1 from public.relayer_assignments where owner='f1000000-0000-4000-8000-000000000006' and relayer_id=2457 and assignment_role='view')
  and exists(select 1 from public.relayer_requests where id=current_setting('test.shared_request')::uuid and status='approved')
  and exists(select 1 from public.relayer_requests where owner='f1000000-0000-4000-8000-000000000003' and relayer_id=2457 and status='pending')
  and exists(select 1 from public.relayer_assignments where id=current_setting('test.relay_priority')::uuid and assignment_role='primary'),'approval grants only the requester view access without taking priority or approving other requests');
set local "test.uid"='f1000000-0000-4000-8000-000000000006';
do $$ begin
  begin perform public.hyn_request_relayer(2457,'Duplicate access'); raise exception 'request for existing own assignment succeeded';
    exception when raise_exception then if sqlerrm<>'This relayer is already assigned to your account' then raise; end if; end;
  perform pg_temp.check_shared_relayer((select count(*)=1 and bool_and(relayer_id=2457 and assignment_role='view') from public.relayer_assignments),'approved viewer reads only their shared assignment');
end $$;
set local role anon;
set local "test.uid"='';
do $$ begin
  begin perform * from public.relayer_assignments; raise exception 'anonymous assignment read succeeded'; exception when insufficient_privilege then null; end;
  begin perform public.hyn_admin_set_relayer_priority(current_setting('test.relay_priority')::uuid); raise exception 'anonymous priority change succeeded'; exception when insufficient_privilege then null; end;
  raise notice 'PASS shared relay: anonymous users cannot read assignments or change priority';
end $$;
rollback;
