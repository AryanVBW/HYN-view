-- Final-schema authorization tests. No service key or UI hiding is relied on.
begin;
insert into auth.users(id,email) values
 ('10000000-0000-4000-8000-000000000001','super@roles.test'),
 ('10000000-0000-4000-8000-000000000002','admin@roles.test'),
 ('10000000-0000-4000-8000-000000000003','monitor@roles.test'),
 ('10000000-0000-4000-8000-000000000004','viewer@roles.test'),
 ('10000000-0000-4000-8000-000000000005','owner@roles.test');
do $$ begin
  if exists(select 1 from public.profiles where email like '%@roles.test' and role<>'monitor') then raise exception 'new signup role is not Monitor'; end if;
  raise notice 'PASS  new accounts default to Monitor';
end $$;
update public.profiles set role=case right(id::text,1) when '1' then 'super_admin' when '2' then 'admin' when '4' then 'viewer' else 'monitor' end where email like '%@roles.test';
insert into public.nodes(id,owner,name,token_hash) values
 ('20000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000005','Shared machine',public._hyn_sha256('role-agent-token')),
 ('20000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004','Viewer-owned machine',null);
insert into public.metrics(node_id,ts,cpu_pct) values('20000000-0000-4000-8000-000000000005',now(),37);
insert into public.relayer_assignments(owner,relayer_id,relayer_name) values('10000000-0000-4000-8000-000000000005',98765,'Role test relayer');
set local role authenticated;
set local "test.uid"='10000000-0000-4000-8000-000000000004';
do $$ begin
  if exists(select 1 from public.nodes where name='Shared machine') or exists(select 1 from public.metrics) or exists(select 1 from public.relayer_assignments) then raise exception 'unshared telemetry leaked'; end if;
  if json_array_length(public.hyn_dashboard_accounts())<>1 then raise exception 'unshared accounts leaked'; end if;
  raise notice 'PASS  viewer cannot discover or read unshared dashboards';
end $$;
-- Both Viewer and Admin are forbidden from every operational admin RPC, even
-- with forged direct RPC requests. Read RPCs and promotion are intentionally exempt.
do $$ declare r record; uid text; args text; denied boolean;
begin
  foreach uid in array array['10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000002'] loop
    perform set_config('test.uid',uid,true);
    for r in select p.* from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
      and p.proname like 'hyn_admin_%' and p.proname not in ('hyn_admin_overview','hyn_admin_nodes','hyn_admin_clients','hyn_admin_notifications','hyn_admin_audit','hyn_admin_templates','hyn_admin_set_role','hyn_admin_promote_by_email') loop
      select string_agg('null::'||format_type(t,null),',') into args from unnest(r.proargtypes::oid[]) t;
      denied:=false;
      begin execute format('select public.%I(%s)',r.proname,coalesce(args,''));
      exception when raise_exception then
        if sqlerrm<>'super administrator role required' then raise; end if;
        denied:=true;
      end;
      if not denied then raise exception 'unauthorized admin RPC: %',r.proname; end if;
    end loop;
  end loop;
  raise notice 'PASS  viewer and admin cannot call any operational admin RPC';
end $$;
set local "test.uid"='10000000-0000-4000-8000-000000000004';
do $$ declare call_sql text; denied boolean; n integer;
begin
  foreach call_sql in array array[
    'select public.hyn_device_approve(null,null)', 'select public.hyn_demo_seed()', 'select public.hyn_demo_clear()',
    'select public.hyn_update_node_config(null,null)', 'select public.hyn_claim_device_linked_email(null)',
    'select public.hyn_complete_device_linked_email(null,null)', 'select public.hyn_release_device_linked_email(null)',
    'select public.hyn_claim_admin_report(null)', 'select public.hyn_request_relayer(76543,''test'')',
    'select public.hyn_cancel_relayer_request(null)',
    'select public.hyn_request_node_command(''20000000-0000-4000-8000-000000000004'',''sync'')'
  ] loop
    denied:=false;
    begin execute call_sql;
    exception when raise_exception then
      if sqlerrm not in ('super administrator role required','monitor or super administrator role required','an active Monitor, Admin or Super admin account is required to link a server') then raise; end if;
      denied:=true;
    end;
    if not denied then raise exception 'viewer wrote using %',call_sql; end if;
  end loop;
  update public.nodes set name='forged' where owner=auth.uid(); get diagnostics n=row_count;
  if n<>0 then raise exception 'viewer renamed own node'; end if;
  delete from public.nodes where owner=auth.uid(); get diagnostics n=row_count;
  if n<>0 then raise exception 'viewer deleted own node'; end if;
  begin insert into public.dashboard_access(viewer_id,owner_id) values(auth.uid(),'10000000-0000-4000-8000-000000000005'); raise exception 'viewer granted access'; exception when insufficient_privilege then null; end;
  begin update public.profiles set role='super_admin' where id=auth.uid(); get diagnostics n=row_count; if n<>0 then raise exception 'viewer escalated'; end if; exception when insufficient_privilege then null; end;
  raise notice 'PASS  viewer cannot mutate owned machines, request access, grant sharing or escalate';
end $$;
set local "test.uid"='10000000-0000-4000-8000-000000000002';
do $$ begin
  perform public.hyn_admin_overview(); perform public.hyn_admin_nodes(); perform public.hyn_admin_clients();
  perform public.hyn_admin_notifications(); perform public.hyn_admin_audit(); perform public.hyn_admin_templates();
  perform public.hyn_admin_promote_by_email('owner@roles.test');
  if not exists(select 1 from public.profiles where email='owner@roles.test' and role='admin') then raise exception 'admin could not promote'; end if;
  begin perform public.hyn_admin_set_role('10000000-0000-4000-8000-000000000002','super_admin'); raise exception 'self escalation'; exception when raise_exception then if sqlerrm<>'refusing to change your own role' then raise; end if; end;
  begin perform public.hyn_admin_set_role('10000000-0000-4000-8000-000000000001','admin'); raise exception 'super demoted'; exception when raise_exception then if sqlerrm<>'admins can only add other admins' then raise; end if; end;
  begin perform public.hyn_admin_set_role('10000000-0000-4000-8000-000000000005','viewer'); raise exception 'admin demoted'; exception when raise_exception then if sqlerrm<>'admins can only add other admins' then raise; end if; end;
  raise notice 'PASS  admin reads fleet and adds admins without elevation or demotion powers';
end $$;
set local "test.uid"='10000000-0000-4000-8000-000000000001';
select public.hyn_admin_set_role('10000000-0000-4000-8000-000000000005','monitor');
select public.hyn_admin_set_dashboard_access('10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000005',true);
select public.hyn_admin_set_dashboard_access('10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000005',true);
select public.hyn_admin_set_node_config('20000000-0000-4000-8000-000000000005','{}'::jsonb);
select public.hyn_admin_assign_relayer('10000000-0000-4000-8000-000000000005',98766,'Super assigned');
do $$ begin
  begin perform public.hyn_admin_set_role(auth.uid(),'viewer'); raise exception 'last super removed'; exception when raise_exception then if sqlerrm<>'refusing to change your own role' then raise; end if; end;
  begin perform public.hyn_admin_set_user_status(auth.uid(),'suspended',null); raise exception 'last super suspended'; exception when raise_exception then if sqlerrm<>'refusing to suspend your own account' then raise; end if; end;
  begin update public.profiles set role='viewer' where id=auth.uid(); raise exception 'super bypassed role guard'; exception when insufficient_privilege then null; end;
  begin update public.nodes set owner=auth.uid() where name='Shared machine'; raise exception 'super changed node owner directly'; exception when insufficient_privilege then null; end;
  raise notice 'PASS  super admin configures machines and assignments while preserving own access';
end $$;
set local "test.uid"='10000000-0000-4000-8000-000000000004';
do $$ begin
  if not exists(select 1 from public.nodes where name='Shared machine') or not exists(select 1 from public.metrics where cpu_pct=37) or not exists(select 1 from public.relayer_assignments where relayer_id=98765) then raise exception 'shared telemetry inaccessible'; end if;
  if json_array_length(public.hyn_dashboard_accounts())<>2 then raise exception 'shared selector missing'; end if;
  if exists(select 1 from public.profiles where email='owner@roles.test') then raise exception 'sharing leaked account profile'; end if;
  raise notice 'PASS  shared viewer sees telemetry and relayers without private profiles';
end $$;
set local "test.uid"='10000000-0000-4000-8000-000000000003';
select public.hyn_request_node_command('20000000-0000-4000-8000-000000000005','sync');
select public.hyn_request_relayer(87654,'Monitor requested');
do $$ begin
  begin perform public.hyn_request_node_command('20000000-0000-4000-8000-000000000005','update'); raise exception 'monitor updated'; exception when raise_exception then if sqlerrm<>'super administrator role required' then raise; end if; end;
  begin perform public.hyn_request_node_command('20000000-0000-4000-8000-000000000004','sync'); raise exception 'monitor synced foreign'; exception when raise_exception then if sqlerrm<>'dashboard access required' then raise; end if; end;
  if not exists(select 1 from public.node_commands where command='sync') then raise exception 'monitor cannot see shared command progress'; end if;
  raise notice 'PASS  monitor refreshes authorized readings and requests relayers but cannot update servers';
end $$;
set local "test.uid"='10000000-0000-4000-8000-000000000001';
select public.hyn_admin_set_dashboard_access('10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000005',false);
select public.hyn_admin_set_user_status('10000000-0000-4000-8000-000000000003','suspended',null);
set local "test.uid"='10000000-0000-4000-8000-000000000004';
do $$ begin
  if exists(select 1 from public.nodes where name='Shared machine') then raise exception 'revoked sharing still readable'; end if;
  raise notice 'PASS  revoking a share removes access immediately';
end $$;
set local "test.uid"='10000000-0000-4000-8000-000000000003';
do $$ begin
  if exists(select 1 from public.nodes) or public.hyn_can_monitor() then raise exception 'suspended monitor has access'; end if;
  raise notice 'PASS  suspended roles lose dashboard and monitoring access';
end $$;
reset role;
do $$ begin
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '\_hyn\_%' and p.proname<>'_hyn_portal_config_valid' and (has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('anon',p.oid,'execute'))) then raise exception 'internal helper exposed'; end if;
  raise notice 'PASS  internal role and audit helpers remain unreachable';
end $$;
insert into auth.users(id,email) values('10000000-0000-4000-8000-000000000006','bootstrap@roles.test');
insert into public.admin_allowlist(email) values('bootstrap@roles.test');
set local role authenticated;
set local "test.uid"='10000000-0000-4000-8000-000000000006';
do $$ begin
  if public.hyn_claim_env_admin('bootstrap@roles.test')->>'role'<>'super_admin' then raise exception 'bootstrap failed'; end if;
end $$;
reset role;
update public.profiles set role='viewer' where email='bootstrap@roles.test';
set local role authenticated;
do $$ begin
  if public.hyn_claim_env_admin('bootstrap@roles.test')->>'status'<>'not_allowed' or public.hyn_is_super_admin() then raise exception 'bootstrap regained removed access'; end if;
  raise notice 'PASS  database bootstrap is single-use and cannot restore revoked privileges';
end $$;
set local role anon;
set local "test.uid"='';
select public.hyn_local_heartbeat('role-agent-token','1.10.0');
do $$ begin raise notice 'PASS  existing node-token agents continue reporting after role migration'; end $$;
rollback;
