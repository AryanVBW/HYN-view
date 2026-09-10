\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email) values
 ('c1000000-0000-4000-8000-000000000001','monitor@linking.test'),
 ('c1000000-0000-4000-8000-000000000002','admin@linking.test'),
 ('c1000000-0000-4000-8000-000000000003','super@linking.test'),
 ('c1000000-0000-4000-8000-000000000004','viewer@linking.test'),
 ('c1000000-0000-4000-8000-000000000005','other@linking.test');
update public.profiles set role=case right(id::text,1) when '2' then 'admin' when '3' then 'super_admin' when '4' then 'viewer' else 'monitor' end where email like '%@linking.test';
create temporary table paired(account uuid, request json, node uuid);
grant all on paired to anon,authenticated;
set local role anon;
set local "test.uid"='';
insert into paired(account,request) select ('c1000000-0000-4000-8000-00000000000'||i)::uuid, public.hyn_device_start('own-server-'||i,'Ubuntu','test') from generate_series(1,3) i;
set local role authenticated;
do $$ declare p record; r json; begin
  for p in select * from paired loop
    perform set_config('test.uid',p.account::text,true);
    if not public.hyn_can_link() then raise exception 'active linker denied'; end if;
    r:=public.hyn_device_approve(p.request->>'user_code',null);
    if r->>'status'<>'approved' then raise exception 'pairing failed'; end if;
    update paired set node=(r->>'node_id')::uuid where account=p.account;
    if not exists(select 1 from public.nodes where id=(r->>'node_id')::uuid and owner=p.account) then raise exception 'linked server not immediately visible to owner'; end if;
    if exists(select 1 from public.server_access where node_id=(r->>'node_id')::uuid) then raise exception 'owner needs assignment'; end if;
    perform public.hyn_claim_device_linked_email((r->>'node_id')::uuid);
    perform public.hyn_release_device_linked_email((r->>'node_id')::uuid);
    perform public.hyn_claim_device_linked_email((r->>'node_id')::uuid);
    perform public.hyn_complete_device_linked_email((r->>'node_id')::uuid,'test-delivery');
  end loop;
  raise notice 'PASS  Monitor, Admin and Super admin pair and immediately see their own server without assignments';
  raise notice 'PASS  link confirmation dispatch retains owner-only idempotent lifecycle';
end $$;
set local "test.uid"='c1000000-0000-4000-8000-000000000004';
do $$ begin
  if public.hyn_can_link() then raise exception 'viewer can link'; end if;
  begin perform public.hyn_device_approve('BAD-CODE',null); raise exception 'viewer approved'; exception when raise_exception then if sqlerrm<>'an active Monitor, Admin or Super admin account is required to link a server' then raise; end if; end;
  if exists(select 1 from public.nodes where id in(select node from paired)) then raise exception 'private server leaked'; end if;
  raise notice 'PASS  Viewer remains read-only and private servers are hidden';
end $$;
set local "test.uid"='c1000000-0000-4000-8000-000000000005';
do $$ begin
  begin perform public.hyn_claim_device_linked_email((select node from paired limit 1)); raise exception 'foreign email claimed'; exception when raise_exception then if sqlerrm<>'node not found' then raise; end if; end;
  begin perform public.hyn_admin_share_server(array['c1000000-0000-4000-8000-000000000004'::uuid],(select node from paired limit 1),true,true); raise exception 'monitor shared server'; exception when raise_exception then if sqlerrm<>'super administrator role required' then raise; end if; end;
  raise notice 'PASS  linking does not permit sharing or another owner\''s email';
end $$;
-- Old owner-specific denies cannot make a user's own linked device disappear.
reset role;
insert into public.server_access(viewer_id,node_id,allowed,notifications_allowed,granted_by) select account,node,false,false,'c1000000-0000-4000-8000-000000000003' from paired where right(account::text,1)='1';
insert into public.alert_events(node_id,ts,severity,message) select node,now(),'warn','Owner alert' from paired where right(account::text,1)='1';
set local role authenticated;
set local "test.uid"='c1000000-0000-4000-8000-000000000001';
do $$ begin
  if not exists(select 1 from public.nodes where owner=auth.uid()) then raise exception 'owner blocked by assignment'; end if;
  if not exists(select 1 from json_array_elements(public.hyn_server_notifications()) item where item->>'message'='Owner alert') then raise exception 'owner notifications blocked by assignment'; end if;
  raise notice 'PASS  ownership and notifications are independent of sharing overrides';
end $$;
set local "test.uid"='c1000000-0000-4000-8000-000000000003';
do $$ declare n uuid:=(select node from paired where right(account::text,1)='1'); begin
  begin perform public.hyn_admin_set_server_access('c1000000-0000-4000-8000-000000000001',n,false); raise exception 'owner assigned'; exception when raise_exception then if sqlerrm<>'the owner already has access; choose another user' then raise; end if; end;
  perform public.hyn_admin_share_server(array['c1000000-0000-4000-8000-000000000004'::uuid,'c1000000-0000-4000-8000-000000000005'::uuid],n,true,true);
  raise notice 'PASS  Super admin shares one server with multiple additional users and cannot override its owner';
end $$;
set local "test.uid"='c1000000-0000-4000-8000-000000000004';
do $$ begin
  if (select count(*) from public.nodes where id in(select node from paired))<>1 then raise exception 'shared server visibility wrong'; end if;
  raise notice 'PASS  additional user sees the shared server without sibling access';
end $$;
reset role;
update public.profiles set status='suspended' where id='c1000000-0000-4000-8000-000000000001';
set local role authenticated;
set local "test.uid"='c1000000-0000-4000-8000-000000000001';
do $$ begin
  if public.hyn_can_link() or exists(select 1 from public.nodes) then raise exception 'suspended owner has access'; end if;
  begin perform public.hyn_device_approve('BAD-CODE',null); raise exception 'suspended user approved'; exception when raise_exception then if sqlerrm<>'an active Monitor, Admin or Super admin account is required to link a server' then raise; end if; end;
  raise notice 'PASS  suspended owners cannot pair or read servers';
end $$;
rollback;
