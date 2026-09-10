begin;
insert into auth.users(id,email) values
 ('f1000000-0000-4000-8000-000000000001','super@assignments.test'),
 ('f1000000-0000-4000-8000-000000000002','alice@assignments.test'),
 ('f1000000-0000-4000-8000-000000000003','bob@assignments.test'),
 ('f1000000-0000-4000-8000-000000000004','owner@assignments.test'),
 ('f1000000-0000-4000-8000-000000000005','other@assignments.test'),
 ('f1000000-0000-4000-8000-000000000006','admin@assignments.test');
update public.profiles set role=case
  when email='super@assignments.test' then 'super_admin'
  when email='admin@assignments.test' then 'admin' else 'viewer' end where email like '%@assignments.test';
insert into public.nodes(id,owner,name) values
 ('f2000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000004','Primary'),
 ('f2000000-0000-4000-8000-000000000002','f1000000-0000-4000-8000-000000000004','Backup'),
 ('f2000000-0000-4000-8000-000000000003','f1000000-0000-4000-8000-000000000005','Remote'),
 ('f2000000-0000-4000-8000-000000000004','f1000000-0000-4000-8000-000000000002','Own device');
insert into public.metrics(node_id,ts,cpu_pct) select id,now(),10 from public.nodes where id::text like 'f2000000-%';
set local role authenticated;
set local "test.uid"='f1000000-0000-4000-8000-000000000001';
select public.hyn_admin_set_dashboard_access('f1000000-0000-4000-8000-000000000002','f1000000-0000-4000-8000-000000000004',true);
select public.hyn_admin_share_server(array['f1000000-0000-4000-8000-000000000002']::uuid[],'f2000000-0000-4000-8000-000000000001',true,false);
select public.hyn_admin_set_user_servers('f1000000-0000-4000-8000-000000000002',array[
 'f2000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000003','f2000000-0000-4000-8000-000000000001']::uuid[]);
select public.hyn_admin_set_user_servers('f1000000-0000-4000-8000-000000000003',array[
 'f2000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000002','f2000000-0000-4000-8000-000000000003']::uuid[]);
do $$ declare v_count integer; begin
  if exists(select 1 from public.dashboard_access where viewer_id='f1000000-0000-4000-8000-000000000002') then raise exception 'broad share survived explicit selection'; end if;
  if (select notifications_allowed from public.server_access where viewer_id='f1000000-0000-4000-8000-000000000002' and node_id='f2000000-0000-4000-8000-000000000001') then raise exception 'notification preference lost'; end if;
  if (select count(*) from public.server_access where node_id='f2000000-0000-4000-8000-000000000001' and allowed)<>2 then raise exception 'server could not be shared with two users'; end if;
  select count(*) into v_count from public.server_access_events;
  perform public.hyn_admin_set_user_servers('f1000000-0000-4000-8000-000000000003',array[
    'f2000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000002','f2000000-0000-4000-8000-000000000003']::uuid[]);
  if (select count(*) from public.server_access_events)<>v_count then raise exception 'unchanged assignments duplicated events'; end if;
  begin
    perform public.hyn_admin_set_user_servers('f1000000-0000-4000-8000-000000000002',array['f2000000-0000-4000-8000-000000000002','ffffffff-ffff-4fff-8fff-ffffffffffff']::uuid[]);
    raise exception 'invalid batch accepted';
  exception when raise_exception then if sqlerrm<>'One or more selected servers are unavailable. Refresh and try again' then raise; end if; end;
  if (select count(*) from public.server_access where viewer_id='f1000000-0000-4000-8000-000000000002' and allowed)<>2 then raise exception 'invalid batch partially changed assignments'; end if;
  if not exists(select 1 from public.admin_audit where action='user.servers.assign' and target_user='f1000000-0000-4000-8000-000000000002') then raise exception 'assignment save not audited'; end if;
  raise notice 'PASS  many-to-many assignments save atomically, preserve notifications and replace broad shares';
end $$;
set local "test.uid"='f1000000-0000-4000-8000-000000000002';
do $$ begin
  if (select count(*) from public.nodes)<>3 or (select count(*) from public.metrics)<>3 then raise exception 'Alice server isolation'; end if;
  if exists(select 1 from public.nodes where name='Backup') then raise exception 'unselected sibling visible'; end if;
  begin perform public.hyn_admin_set_user_servers('f1000000-0000-4000-8000-000000000002','{}'); raise exception 'user changed assignments';
  exception when raise_exception then if sqlerrm<>'super administrator role required' then raise; end if; end;
  raise notice 'PASS  users see selected servers plus owned devices and cannot assign themselves';
end $$;
set local "test.uid"='f1000000-0000-4000-8000-000000000003';
do $$ begin
  if (select count(*) from public.nodes)<>3 or exists(select 1 from public.nodes where name='Own device') then raise exception 'Bob server isolation'; end if;
  raise notice 'PASS  another user independently sees the same shared server and their other assignments';
end $$;
set local "test.uid"='f1000000-0000-4000-8000-000000000006';
do $$ begin
  begin perform public.hyn_admin_set_user_servers('f1000000-0000-4000-8000-000000000002','{}'); raise exception 'restricted admin changed assignments';
  exception when raise_exception then if sqlerrm<>'super administrator role required' then raise; end if; end;
  raise notice 'PASS  restricted Admins retain read access without assignment authority';
end $$;
set local "test.uid"='f1000000-0000-4000-8000-000000000001';
select public.hyn_admin_set_user_servers('f1000000-0000-4000-8000-000000000002','{}');
reset role;
insert into public.nodes(id,owner,name) values ('f2000000-0000-4000-8000-000000000005','f1000000-0000-4000-8000-000000000004','Future server');
set local role authenticated;
set local "test.uid"='f1000000-0000-4000-8000-000000000002';
do $$ begin
  if (select count(*) from public.nodes)<>1 or (select name from public.nodes)<>'Own device' then raise exception 'clearing assignments left extra access or removed ownership'; end if;
  raise notice 'PASS  clearing assignments removes shared and future-server access but preserves ownership';
end $$;
set local "test.uid"='f1000000-0000-4000-8000-000000000003';
do $$ begin
  if (select count(*) from public.nodes)<>3 then raise exception 'editing Alice changed Bob assignments'; end if;
  raise notice 'PASS  updating one user leaves every other user''s assignments intact';
end $$;
set local role anon;
set local "test.uid"='';
do $$ begin
  begin perform public.hyn_admin_set_user_servers('f1000000-0000-4000-8000-000000000002','{}'); raise exception 'anonymous assignment write'; exception when insufficient_privilege then null; end;
  raise notice 'PASS  anonymous callers cannot save assignments';
end $$;
rollback;
