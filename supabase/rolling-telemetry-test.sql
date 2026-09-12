-- Real SQL behavior after both migration upgrades and full-schema application.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_retention(p_ok boolean,p_name text) returns void
language plpgsql as $$ begin
  if not coalesce(p_ok,false) then raise exception '%',p_name; end if;
  raise notice 'PASS  %',p_name;
end $$;
insert into auth.users(id,email) values
 ('48000000-0000-4000-8000-000000000001','owner@retention.test'),
 ('48000000-0000-4000-8000-000000000002','other@retention.test');
update public.profiles set status='active' where email like '%@retention.test';
insert into public.nodes(id,owner,name,token_hash) values
 ('48000000-0000-4000-8000-000000000011','48000000-0000-4000-8000-000000000001','retention active',public._hyn_sha256('retention-token')),
 ('48000000-0000-4000-8000-000000000012','48000000-0000-4000-8000-000000000002','retention idle',null);
select pg_temp.check_retention(
 not has_function_privilege('anon','public.hyn_prune_telemetry(integer)','EXECUTE')
 and not has_function_privilege('authenticated','public.hyn_prune_telemetry(integer)','EXECUTE')
 and has_function_privilege('service_role','public.hyn_prune_telemetry(integer)','EXECUTE'),
 'retention cleanup is service-only');
select pg_temp.check_retention(
 not has_function_privilege('anon','public._hyn_monitoring_payload(jsonb)','EXECUTE')
 and not has_function_privilege('authenticated','public._hyn_monitoring_fields(jsonb,text[])','EXECUTE'),
 'monitoring payload helpers are private');
select pg_temp.check_retention((select config->>'cloud_storage'='cloud' and config->>'cloud_push_min'='1'
 and telemetry_policy_version=1 from public.nodes where id='48000000-0000-4000-8000-000000000011'),
 'new servers default to continuous cloud monitoring with one-minute sampling');
set local role anon;
do $$ declare p jsonb; r json; begin
 p:=jsonb_build_object('ts',now()-interval '1 minute','host','current-host','agent_version','1.12.0',
 'cpu',jsonb_build_object('pct',37.5,'cores',2,'temp_c',null),
 'memory',jsonb_build_object('pct',48,'total',104857600),
 'processes',jsonb_build_object('count',42,'top',jsonb_build_array(jsonb_build_object('name','hyn-agent','args','private command'))),
 'highway',jsonb_build_object('health','healthy','journal','private journal'),
 'platform',jsonb_build_object('provider','gcp','cpu_limit_cores',2,'instance_id','private-id'),
 'monitoring_logs',jsonb_build_array(
 jsonb_build_object('ts',now()-interval '1 minute','level','info','code','sample_collected','count',1,'message','private log'),
 jsonb_build_object('level','warn','code','arbitrary_message','count',1)),
 'speedtest',jsonb_build_object('ts',extract(epoch from now()-interval '2 minutes')::bigint,'down_bps',5000),
 'alerts',jsonb_build_array(jsonb_build_object('rule','disk_root','severity','warn','message','Disk / at 86%')),
 'environment',jsonb_build_object('secret','private-value'));
 r:=public.hyn_ingest('retention-token',p);
 if r->>'status'<>'ok' or r->>'alerts_written'<>'1' then raise exception 'ingest contract failed: %',r; end if;
 r:=public.hyn_ingest('retention-token',p);
 if r->>'duplicate'<>'true' or r->>'alerts_written'<>'0' then raise exception 'duplicate snapshot was not acknowledged: %',r; end if;
 perform public.hyn_ingest('retention-token',jsonb_build_object('ts',now()-interval '2 hours','host','old-host','agent_version','1.8.0','cpu',jsonb_build_object('pct',2)));
 raise notice 'PASS  current, duplicate, and older replay preserve the existing agent ingest contract';
 r:=public.hyn_ingest('retention-token',jsonb_build_object('ts',now()-interval '49 hours','cpu',jsonb_build_object('pct',1)));
 if r->>'discarded'<>'expired' or r->>'status'<>'ok' then raise exception 'expired replay cannot drain from outbox'; end if;
 begin
   perform public.hyn_ingest('retention-token',jsonb_build_object('ts',now()+interval '6 minutes'));
   raise exception 'future timestamp accepted';
 exception when raise_exception then if sqlerrm<>'monitoring timestamp is in the future or invalid' then raise; end if; end;
 begin
   perform public.hyn_ingest('retention-token','{"ts":"infinity"}');
   raise exception 'infinite timestamp accepted';
 exception when raise_exception then if sqlerrm<>'monitoring timestamp is in the future or invalid' then raise; end if; end;
 begin
   perform public.hyn_ingest('retention-token',jsonb_build_object('raw',repeat('x',66000)));
   raise exception 'unbounded payload accepted';
 exception when raise_exception then if sqlerrm<>'monitoring payload exceeds 64 KiB' then raise; end if; end;
 raise notice 'PASS  timestamps and payload sizes bound replay without retaining expired data';
end $$;
reset role;
select pg_temp.check_retention((select count(*)=2 from public.metrics where node_id='48000000-0000-4000-8000-000000000011')
 and (select count(*)=1 from public.alert_events where node_id='48000000-0000-4000-8000-000000000011')
 and (select count(*)=1 from public.speedtests where node_id='48000000-0000-4000-8000-000000000011'),
 'retry stores each snapshot, alert group, and speed test once');
select pg_temp.check_retention((select hostname='current-host' and agent_version='1.12.0'
 and last_metric_at=now()-interval '1 minute' and last_seen_at=now()-interval '1 minute'
 from public.nodes where id='48000000-0000-4000-8000-000000000011'),
 'out-of-order replay cannot regress node identity or falsely refresh sample time');
select pg_temp.check_retention((select cpu_pct=37.5 and cpu_temp_c is null and proc_count=42
 and payload#>>'{platform,provider}'='gcp' and payload#>>'{monitoring_logs,0,code}'='sample_collected'
 and jsonb_array_length(payload->'monitoring_logs')=1 and payload::text not like '%private%'
 from public.metrics where node_id='48000000-0000-4000-8000-000000000011' order by ts desc limit 1),
 'bounded monitoring fields retain measurements and structured logs without arbitrary detail');

-- Child event timestamps may predate a fresh reading because a speed test was
-- last run days ago. Neither those cached events nor their payload copies survive.
set local role anon;
select public.hyn_ingest('retention-token',jsonb_build_object('ts',now(),
 'speedtest',jsonb_build_object('ts',extract(epoch from now()-interval '72 hours')::bigint,'down_bps',9000),
 'alerts',jsonb_build_array(jsonb_build_object('ts',now()-interval '72 hours','rule','expired','message','expired','severity','warn'))));
reset role;
select pg_temp.check_retention(
 not exists(select 1 from public.speedtests where node_id='48000000-0000-4000-8000-000000000011' and down_bps=9000)
 and not exists(select 1 from public.alert_events where node_id='48000000-0000-4000-8000-000000000011' and rule='expired'),
 'fresh uploads cannot reinsert expired child events');
select pg_temp.check_retention((select not(payload ? 'speedtest') and payload->'alerts'='[]'::jsonb
 from public.metrics where node_id='48000000-0000-4000-8000-000000000011' and ts=now()),
 'expired child events are removed from stored payload copies too');

-- Seed idle-node rows directly, representing history that existed before upgrade.
insert into public.metrics(node_id,ts,cpu_pct)
 select '48000000-0000-4000-8000-000000000012',now()-interval '49 hours'-n*interval '1 minute',10 from generate_series(1,3) n;
insert into public.speedtests(node_id,ts,down_bps)
 select '48000000-0000-4000-8000-000000000012',now()-interval '49 hours'-n*interval '1 minute',10 from generate_series(1,3) n;
insert into public.alert_events(node_id,ts,severity,message)
 select '48000000-0000-4000-8000-000000000012',now()-interval '49 hours'-n*interval '1 minute','info','old' from generate_series(1,3) n;
set local role authenticated;
set local "test.uid"='48000000-0000-4000-8000-000000000002';
select pg_temp.check_retention(not exists(select 1 from public.metrics)
 and not exists(select 1 from public.speedtests) and not exists(select 1 from public.alert_events),
 'expired monitoring and other owners remain hidden before physical pruning');
reset role;
set local role service_role;
do $$ declare r jsonb; begin
 r:=public.hyn_prune_telemetry(1);
 if r->>'retention_hours'<>'48' or r->>'metrics_deleted'<>'1' or r->>'speedtests_deleted'<>'1'
    or r->>'alerts_deleted'<>'1' or r->>'has_more'<>'true' then raise exception 'bounded pruning failed: %',r; end if;
 r:=public.hyn_prune_telemetry(5000);
 if r->>'metrics_deleted'<>'2' or r->>'speedtests_deleted'<>'2' or r->>'alerts_deleted'<>'2' then
    raise exception 'idle rows not pruned: %',r; end if;
 raise notice 'PASS  fixed 48-hour pruning is bounded and removes idle-node history';
end $$;
reset role;
select pg_temp.check_retention((select count(*)=3 from public.metrics where node_id='48000000-0000-4000-8000-000000000011')
 and (select count(*)=1 from public.speedtests where node_id='48000000-0000-4000-8000-000000000011'),
 'retention leaves recent readings and speed tests intact');
insert into public.metrics(node_id,ts,cpu_pct,payload)
 select '48000000-0000-4000-8000-000000000011',now()-n*interval '1 minute',10,'{"history":"large payload omitted"}'::jsonb
 from generate_series(1,2879) n on conflict(node_id,ts) do nothing;
set local role authenticated;
set local "test.uid"='48000000-0000-4000-8000-000000000001';
do $$ declare r jsonb; begin
 r:=public.hyn_metric_history('48000000-0000-4000-8000-000000000011');
 if jsonb_array_length(r)<576 or jsonb_array_length(r)>578
    or (r->-1->>'ts')::timestamptz<>now()
    or (r->0->>'ts')::timestamptz>now()-interval '47 hours 50 minutes'
    or r->0->'payload'<>'null'::jsonb or r::text like '%large payload%' then
   raise exception 'history is incomplete, out of order, unbounded, or copies payload: %',jsonb_array_length(r);
 end if;
 raise notice 'PASS  five-minute chart history covers 48 hours and includes the newest scalar reading';
end $$;
set local "test.uid"='48000000-0000-4000-8000-000000000002';
select pg_temp.check_retention(public.hyn_metric_history('48000000-0000-4000-8000-000000000011')='[]'::jsonb,
 'chart history obeys the existing server authorization boundary');
reset role;
update public.nodes set status='paused' where id='48000000-0000-4000-8000-000000000011';
set local role anon;
do $$ begin
 begin perform public.hyn_ingest('retention-token','{}'); raise exception 'paused accepted';
 exception when raise_exception then if sqlerrm not like 'node paused%' then raise; end if; end;
 raise notice 'PASS  paused-node ingestion still refuses telemetry';
end $$;
reset role;
update public.nodes set status='active',revoked=true where id='48000000-0000-4000-8000-000000000011';
set local role anon;
do $$ begin
 begin perform public.hyn_ingest('retention-token','{}'); raise exception 'revoked accepted';
 exception when raise_exception then if sqlerrm<>'invalid node token' then raise; end if; end;
 raise notice 'PASS  revoked-node ingestion still refuses telemetry';
end $$;
reset role;
update public.nodes set revoked=false where id='48000000-0000-4000-8000-000000000011';
update public.profiles set status='suspended' where id='48000000-0000-4000-8000-000000000001';
set local role anon;
do $$ begin
 begin perform public.hyn_ingest('retention-token','{}'); raise exception 'suspended account accepted';
 exception when raise_exception then if sqlerrm<>'account suspended' then raise; end if; end;
 raise notice 'PASS  account suspension still refuses telemetry';
end $$;
reset role;
rollback;
