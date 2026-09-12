\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email) values
 ('48000000-0000-4000-8000-000000000021','detail@retention.test'),
 ('48000000-0000-4000-8000-000000000022','admin@retention.test');
update public.profiles set role='super_admin' where id='48000000-0000-4000-8000-000000000022';
insert into public.nodes(id,owner,name,token_hash) values
 ('48000000-0000-4000-8000-000000000031','48000000-0000-4000-8000-000000000021','detail active',public._hyn_sha256('detail-token')),
 ('48000000-0000-4000-8000-000000000032','48000000-0000-4000-8000-000000000021','detail idle',null);
insert into public.metrics(node_id,ts) values
 ('48000000-0000-4000-8000-000000000032',now()-interval '49 hours'),
 ('48000000-0000-4000-8000-000000000032',now()+interval '1 day'),
 ('48000000-0000-4000-8000-000000000032','infinity');
set local role authenticated;
set local "test.uid"='48000000-0000-4000-8000-000000000021';
do $$ begin
 if exists(select 1 from public.metrics where node_id='48000000-0000-4000-8000-000000000032') then
   raise exception 'legacy expired or future samples visible'; end if;
 raise notice 'PASS  expired, infinite and future legacy snapshots are hidden immediately';
end $$;
reset role;
set local role anon;
do $$ declare p jsonb; r json; begin
 p:=jsonb_build_object('ts',now()-interval '2 minutes','cpu',jsonb_build_object('pct',42,'cores_mhz',
 (select jsonb_agg(2400) from generate_series(1,200))),
 'power',jsonb_build_object('rails',(select jsonb_object_agg('rail'||n,5) from generate_series(1,32) n)),
 'processes',jsonb_build_object('count',42,'top',(select jsonb_agg(jsonb_build_object('pid',n,'name','worker','args','private arguments')) from generate_series(1,20) n)),
 'alerts',jsonb_build_array(jsonb_build_object('ts',now()-interval '3 minutes','rule','same-event','message','same event','severity','warn')));
 r:=public.hyn_ingest('detail-token',p);
 if r->>'status'<>'ok' then raise exception 'detail ingest failed'; end if;
 r:=public.hyn_ingest('detail-token',jsonb_set(p,'{ts}',to_jsonb(now()-interval '1 minute')));
 if r->>'alerts_written'<>'0' then raise exception 'same event duplicated across snapshots'; end if;
 raise notice 'PASS  repeated alert timestamps deduplicate across different snapshot envelopes';
end $$;
reset role;
do $$ declare p jsonb; begin
 select payload into p from public.metrics where node_id='48000000-0000-4000-8000-000000000031' order by ts desc limit 1;
 if jsonb_array_length(p#>'{cpu,cores_mhz}')<>128 or (select count(*) from jsonb_object_keys(p#>'{power,rails}'))<>16
 or jsonb_array_length(p#>'{processes,top}')<>16 or p::text like '%private%' then
   raise exception 'safe bounded detail missing or command arguments retained'; end if;
 if exists(select 1 from public.metrics where node_id='48000000-0000-4000-8000-000000000032') then
   raise exception 'opportunistic cleanup left idle/future legacy readings'; end if;
 raise notice 'PASS  core clocks, power rails and process names retain bounded detail without arguments';
 raise notice 'PASS  active ingestion opportunistically prunes idle-node and invalid-future history';
 raise notice 'Representative bounded detail payload storage bytes: %',pg_column_size(p);
end $$;
set local role anon;
select public.hyn_ingest('detail-token',jsonb_build_object('ts',now(),'cpu',jsonb_build_object('pct',43),
 'highway',jsonb_build_object('units',(select jsonb_agg(jsonb_build_object('name',repeat('n',250),'state',repeat('s',250),'sub',repeat('x',250))) from generate_series(1,32))),
 'alerts',(select jsonb_agg(jsonb_build_object('rule','event'||n,'message',repeat('a',250),'severity','warn')) from generate_series(1,32) n)));
reset role;
do $$ declare m public.metrics; begin
 select * into m from public.metrics where node_id='48000000-0000-4000-8000-000000000031' order by ts desc limit 1;
 if m.cpu_pct<>43 or octet_length(m.payload::text)>16384 or m.payload->>'monitoring_truncated'<>'true' then
   raise exception 'large inventory did not degrade while preserving current summary'; end if;
 if (select count(*) from public.alert_events where node_id=m.node_id)<>33 then
   raise exception 'payload size degradation lost alert events'; end if;
 raise notice 'PASS  large inventories degrade supplemental payload without losing headline data or alert events';
end $$;

-- More than 5,000 readings still produce the full 24-hour fleet chart.
insert into public.nodes(id,owner,name,is_demo)
 select ('48000000-0000-4000-8000-00000000004'||n)::uuid,'48000000-0000-4000-8000-000000000022','fleet'||n,n=5 from generate_series(1,5) n;
insert into public.metrics(node_id,ts,cpu_pct,net_rx_bps,net_tx_bps)
 select ('48000000-0000-4000-8000-00000000004'||n)::uuid,now()-s*interval '1 minute',case when n=5 then 1000 else 20 end,100,200
 from generate_series(1,5) n cross join generate_series(0,1439) s;
set local role authenticated;
set local "test.uid"='48000000-0000-4000-8000-000000000021';
do $$ begin
 if public.hyn_fleet_metric_history()<>'[]'::jsonb then raise exception 'non-admin fleet history exposed'; end if;
 raise notice 'PASS  aggregate fleet history is admin-only';
end $$;
set local "test.uid"='48000000-0000-4000-8000-000000000022';
do $$ declare r jsonb; begin
 r:=public.hyn_fleet_metric_history();
 if jsonb_array_length(r)<48 or jsonb_array_length(r)>49 or (r->0->>'cpu_pct')::numeric<>20
 or (r->-1->>'ts')::timestamptz<>to_timestamp(floor(extract(epoch from now())/1800)*1800) then
   raise exception 'fleet history lost newest data, included demos, or exceeded bounds'; end if;
 raise notice 'PASS  fleet aggregation covers the newest 24 hours beyond 5,000 samples and excludes demo data';
end $$;
reset role;
rollback;
