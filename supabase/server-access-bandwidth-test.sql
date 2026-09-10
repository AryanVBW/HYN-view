begin;
insert into auth.users(id,email) values
 ('a0000000-0000-4000-8000-000000000001','super@access.test'),
 ('a0000000-0000-4000-8000-000000000002','admin@access.test'),
 ('a0000000-0000-4000-8000-000000000003','viewer@access.test');
update public.profiles set role=case right(id::text,1) when '1' then 'super_admin' when '2' then 'admin' else 'monitor' end where email like '%@access.test';
insert into public.nodes(id,owner,name,token_hash) values
 ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','Allowed server',public._hyn_sha256('bandwidth-test-token')),
 ('b0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','Private sibling',null);
insert into public.metrics(node_id,ts,cpu_pct) select id,now(),10 from public.nodes where name in ('Allowed server','Private sibling');
set local role authenticated;
set local "test.uid"='a0000000-0000-4000-8000-000000000001';
select public.hyn_admin_set_server_access('a0000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001',true);
do $$ begin
  if (select count(*) from public.server_access_events)<>1 then raise exception 'missing super notification'; end if;
  raise notice 'PASS  server grant creates super-admin notification';
end $$;
set local "test.uid"='a0000000-0000-4000-8000-000000000003';
do $$ begin
  if (select count(*) from public.nodes)<>1 or (select count(*) from public.metrics)<>1 then raise exception 'server isolation failed'; end if;
  if json_array_length(public.hyn_dashboard_accounts())<>2 then raise exception 'shared server owner missing'; end if;
  if public.hyn_can_view_dashboard('a0000000-0000-4000-8000-000000000001') then raise exception 'server grant shared whole dashboard'; end if;
  if exists(select 1 from public.server_access_events) then raise exception 'viewer read notifications'; end if;
  perform public.hyn_request_node_command('b0000000-0000-4000-8000-000000000001','sync');
  begin perform public.hyn_request_node_command('b0000000-0000-4000-8000-000000000002','sync'); raise exception 'sibling command permitted'; exception when raise_exception then if sqlerrm<>'dashboard access required' then raise; end if; end;
  raise notice 'PASS  individual server sharing excludes sibling telemetry and commands';
end $$;
set local "test.uid"='a0000000-0000-4000-8000-000000000002';
do $$ begin
  if exists(select 1 from public.server_access_events) then raise exception 'admin read notifications'; end if;
  begin perform public.hyn_admin_set_server_access('a0000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000002',true); raise exception 'admin granted access'; exception when raise_exception then if sqlerrm<>'super administrator role required' then raise; end if; end;
  raise notice 'PASS  ordinary admin cannot change access or read access notifications';
end $$;
set local "test.uid"='a0000000-0000-4000-8000-000000000001';
select public.hyn_admin_set_dashboard_access('a0000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000001',true);
select public.hyn_admin_set_server_access('a0000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001',false);
set local "test.uid"='a0000000-0000-4000-8000-000000000003';
do $$ begin
  if exists(select 1 from public.nodes where name='Allowed server') then raise exception 'blocked server visible via sharing'; end if;
  if not exists(select 1 from public.nodes where name='Private sibling') then raise exception 'dashboard sharing broken'; end if;
  if exists(select 1 from public.node_commands) then raise exception 'blocked commands visible'; end if;
  raise notice 'PASS  server block overrides dashboard access immediately';
end $$;
set local role anon;
set local "test.uid"='';
select public.hyn_record_bandwidth('bandwidth-test-token','eth0','boot-1',1000,500);
select public.hyn_record_bandwidth('bandwidth-test-token','eth0','boot-1',1500,700);
select public.hyn_record_bandwidth('bandwidth-test-token','eth0','boot-1',1500,700);
select public.hyn_record_bandwidth('bandwidth-test-token','eth0','boot-1',1400,600);
reset role;
do $$ begin
  if (select sum(ingress_bytes+egress_bytes) from public.bandwidth_daily)<>700 then raise exception 'delta, duplicate or reorder miscount'; end if;
  raise notice 'PASS  counters sum ingress and egress without duplicate or reorder inflation';
end $$;
set local role anon;
select public.hyn_record_bandwidth('bandwidth-test-token','eth0','boot-2',200,100);
select public.hyn_record_bandwidth('bandwidth-test-token','eth0','boot-2',250,130);
reset role;
do $$ begin
  if (select sum(ingress_bytes+egress_bytes) from public.bandwidth_daily)<>780 then raise exception 'reboot miscount'; end if;
  raise notice 'PASS  reboot establishes baseline and retains observed lifetime total';
end $$;
-- Force a midnight-spanning interval without waiting for midnight.
update public.bandwidth_counters set sampled_at=((now() at time zone 'UTC')::date::timestamp at time zone 'UTC')-interval '1 minute';
set local role anon;
select public.hyn_record_bandwidth('bandwidth-test-token','eth0','boot-2',1250,1130);
reset role;
do $$ begin
  if (select sum(ingress_bytes+egress_bytes) from public.bandwidth_daily)<>2780 or (select count(*) from public.bandwidth_daily)<>2
    or not exists(select 1 from public.bandwidth_daily where estimated) then raise exception 'UTC allocation lost bytes'; end if;
  raise notice 'PASS  midnight allocation preserves totals and labels estimated daily split';
end $$;
set local role authenticated;
set local "test.uid"='a0000000-0000-4000-8000-000000000003';
do $$ begin
  if exists(select 1 from public.bandwidth_daily) or exists(select 1 from public.bandwidth_counters) then raise exception 'user read admin consumption'; end if;
  begin perform public.hyn_bandwidth_report('b0000000-0000-4000-8000-000000000001',30); raise exception 'user called consumption RPC'; exception when raise_exception then if sqlerrm<>'server access required' then raise; end if; end;
  raise notice 'PASS  blocked user cannot read consumption through tables or RPC';
end $$;
set local "test.uid"='a0000000-0000-4000-8000-000000000002';
do $$ declare r json; begin
  r:=public.hyn_bandwidth_report('b0000000-0000-4000-8000-000000000001',30);
  if (r->>'ingress_bytes')::numeric+(r->>'egress_bytes')::numeric<>2780 then raise exception 'admin total incorrect'; end if;
  raise notice 'PASS  admin sees exact observed totals and daily history';
end $$;
set local role anon;
set local "test.uid"='';
do $$ begin
  begin perform public.hyn_record_bandwidth('wrong-token','eth0','boot-2',9,9); raise exception 'invalid token accepted'; exception when raise_exception then if sqlerrm<>'invalid node token' then raise; end if; end;
  begin perform public.hyn_record_bandwidth('bandwidth-test-token','eth0','boot-2',-1,9); raise exception 'negative accepted'; exception when raise_exception then if sqlerrm<>'invalid network counters' then raise; end if; end;
  raise notice 'PASS  invalid tokens and negative counters rejected';
end $$;
rollback;
