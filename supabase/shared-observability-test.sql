begin;
insert into auth.users(id,email) values
 ('c0000000-0000-4000-8000-000000000001','super@shared.test'),
 ('c0000000-0000-4000-8000-000000000002','one@shared.test'),
 ('c0000000-0000-4000-8000-000000000003','two@shared.test'),
 ('c0000000-0000-4000-8000-000000000004','private@shared.test');
update public.profiles set role=case when email='super@shared.test' then 'super_admin' else 'viewer' end where email like '%@shared.test';
insert into public.nodes(id,owner,name,config,last_heartbeat_at) values
 ('d0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','Shared server','{"auto_update":"check"}',now()-interval '2 hours'),
 ('d0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000004','Hidden server','{}',now()-interval '2 hours');
insert into public.bandwidth_daily(node_id,day,ingress_bytes,egress_bytes,samples) values
 ('d0000000-0000-4000-8000-000000000001',current_date,1000,500,2),
 ('d0000000-0000-4000-8000-000000000002',current_date,900000,300000,2);
insert into public.alert_events(node_id,ts,severity,message) values
 ('d0000000-0000-4000-8000-000000000001',now(),'warn','Shared CPU alert'),
 ('d0000000-0000-4000-8000-000000000002',now(),'crit','Private CPU alert');
set local role authenticated;
set local "test.uid"='c0000000-0000-4000-8000-000000000001';
select public.hyn_admin_share_server(array['c0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000003']::uuid[],'d0000000-0000-4000-8000-000000000001',true,true);
do $$ declare v text; r json; begin
  foreach v in array array['c0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000003'] loop
    perform set_config('test.uid',v,true);
    if (select count(*) from public.nodes)<>1 or (select config->>'auto_update' from public.nodes)<>'check' then raise exception 'shared settings visibility'; end if;
    r:=public.hyn_bandwidth_report('d0000000-0000-4000-8000-000000000001',30);
    if r->>'ingress_bytes'<>'1000' then raise exception 'shared usage missing'; end if;
    r:=public.hyn_fleet_bandwidth_report(30);
    if r->>'ingress_bytes'<>'1000' or r->>'node_count'<>'1' then raise exception 'private fleet usage leaked'; end if;
    if (select count(*) from public.bandwidth_daily)<>1 then raise exception 'direct usage isolation failed'; end if;
    r:=public.hyn_server_notifications();
    if r::text not like '%Shared CPU alert%' or r::text like '%Private%' or r::text not like '%offline%' then raise exception 'notification isolation failed'; end if;
    begin perform public.hyn_update_node_config('d0000000-0000-4000-8000-000000000001','{"auto_update":"install"}'); raise exception 'viewer wrote config'; exception when raise_exception then if sqlerrm<>'super administrator role required' then raise; end if; end;
    begin perform public.hyn_admin_set_node_config('d0000000-0000-4000-8000-000000000001','{}'); raise exception 'viewer used admin config'; exception when raise_exception then if sqlerrm<>'super administrator role required' then raise; end if; end;
    begin perform public.hyn_request_node_command('d0000000-0000-4000-8000-000000000001','update'); raise exception 'viewer updated agent'; exception when raise_exception then if sqlerrm not like '%role required' then raise; end if; end;
    begin update public.server_access set notifications_allowed=true; raise exception 'direct permission update allowed'; exception when insufficient_privilege then null; end;
  end loop;
  raise notice 'PASS  two users share one server with settings, usage and notifications but cannot write or update';
end $$;
set local "test.uid"='c0000000-0000-4000-8000-000000000001';
select public.hyn_admin_share_server(array['c0000000-0000-4000-8000-000000000002']::uuid[],'d0000000-0000-4000-8000-000000000001',true,false);
set local "test.uid"='c0000000-0000-4000-8000-000000000002';
do $$ begin
  if json_array_length(public.hyn_server_notifications())<>0 or (select count(*) from public.nodes)<>1 then raise exception 'notification permission affected viewing or leaked alerts'; end if;
  raise notice 'PASS  notifications can be disabled without revoking read access';
end $$;
set local "test.uid"='c0000000-0000-4000-8000-000000000001';
do $$ begin
  begin
    perform public.hyn_admin_share_server(array['c0000000-0000-4000-8000-000000000002','ffffffff-ffff-4fff-8fff-ffffffffffff']::uuid[],'d0000000-0000-4000-8000-000000000001',false,true);
    raise exception 'invalid batch accepted';
  exception when raise_exception then if sqlerrm<>'choose an active Viewer or Monitor' then raise; end if; end;
  if not (select allowed from public.server_access where viewer_id='c0000000-0000-4000-8000-000000000002') then raise exception 'batch left partial permissions'; end if;
  raise notice 'PASS  invalid batch assignment rolls back all permission changes';
end $$;
select public.hyn_admin_set_server_access('c0000000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-000000000001',false);
set local "test.uid"='c0000000-0000-4000-8000-000000000003';
do $$ begin
  if exists(select 1 from public.nodes) or exists(select 1 from public.bandwidth_daily) or json_array_length(public.hyn_server_notifications())<>0
     or public.hyn_fleet_bandwidth_report()->>'ingress_bytes'<>'0' then raise exception 'revoked data leaked'; end if;
  raise notice 'PASS  revocation immediately removes server data, fleet totals and notifications';
end $$;
reset role;
update public.profiles set status='suspended' where id='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
set local "test.uid"='c0000000-0000-4000-8000-000000000002';
do $$ begin
  if exists(select 1 from public.nodes) then raise exception 'suspended viewer sees nodes'; end if;
  begin perform public.hyn_server_notifications(); raise exception 'suspended inbox visible'; exception when raise_exception then if sqlerrm<>'active account required' then raise; end if; end;
  begin perform public.hyn_fleet_bandwidth_report(); raise exception 'suspended usage visible'; exception when raise_exception then if sqlerrm<>'active account required' then raise; end if; end;
  raise notice 'PASS  suspended accounts lose reporting and notifications';
end $$;
rollback;
