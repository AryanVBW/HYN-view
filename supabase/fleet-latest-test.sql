-- Fleet view: one newest reading and speed test per server, complete however
-- many readings exist, only for fleet viewers
-- (migrations/20260929160000_fleet_latest_readings.sql). Rolled back.
\set ON_ERROR_STOP on
begin;
set local track_functions = 'all';
insert into auth.users(id,email) values
  ('4f200000-0000-4000-8000-000000000001','owner@fleet-latest.test'),
  ('4f200000-0000-4000-8000-000000000002','maintainer@fleet-latest.test');
update public.profiles set role = 'monitor', status = 'active' where email like '%@fleet-latest.test';
update public.profiles set role = 'maintainer' where id = '4f200000-0000-4000-8000-000000000002';
insert into public.nodes(id,owner,name,revoked)
  select ('4f200000-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid, '4f200000-0000-4000-8000-000000000001',
         'fleet ' || i, i = 5
    from generate_series(1, 5) i;
-- Busy servers 1-2 (one reading a minute), quiet server 3 (last reading five
-- hours ago: far behind the busy ones' newest 2,000), server 4 with nothing in
-- 24 hours, server 5 revoked.
insert into public.metrics(node_id,ts,cpu_pct,payload)
  select ('4f200000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, now() - s * interval '1 minute', s % 100,
         '{"large":"payload"}'::jsonb
    from generate_series(1, 2) n, generate_series(0, 1439) s;
insert into public.metrics(node_id,ts,cpu_pct) values
  ('4f200000-0000-4000-8000-000000000003', now() - interval '5 hours', 33),
  ('4f200000-0000-4000-8000-000000000003', now() - interval '6 hours', 34),
  ('4f200000-0000-4000-8000-000000000004', now() - interval '30 hours', 44),
  ('4f200000-0000-4000-8000-000000000005', now() - interval '1 minute', 55);
insert into public.speedtests(node_id,ts,down_bps,up_bps) values
  ('4f200000-0000-4000-8000-000000000001', now() - interval '2 hours', 100, 10),
  ('4f200000-0000-4000-8000-000000000001', now() - interval '8 hours', 90, 9),
  ('4f200000-0000-4000-8000-000000000003', now() - interval '20 hours', 50, 5);

set local role authenticated;
set local "test.uid" = '4f200000-0000-4000-8000-000000000001';
do $$ begin
  if public.hyn_fleet_latest_readings() <> '{"metrics":[],"speedtests":[]}'::jsonb then
    raise exception 'a user without fleet access got fleet readings';
  end if;
end $$;
set local "test.uid" = '4f200000-0000-4000-8000-000000000002';
do $$ declare r jsonb; v_calls bigint; v_nodes text; v_ts_ok boolean;
begin
  v_calls := coalesce(pg_stat_get_xact_function_calls('public.hyn_can_view_node(uuid)'::regprocedure), 0);
  r := public.hyn_fleet_latest_readings();
  if coalesce(pg_stat_get_xact_function_calls('public.hyn_can_view_node(uuid)'::regprocedure), 0) <> v_calls then
    raise exception 'the fleet read checked access per reading';
  end if;
  select string_agg(right(e->>'node_id', 2) || ':' || (e->>'cpu_pct'), ',' order by e->>'node_id') into v_nodes
    from jsonb_array_elements(r->'metrics') e where e->>'node_id' like '4f200000-%';
  if v_nodes is distinct from '01:0,02:0,03:33' then
    raise exception 'fleet readings are not the newest per server: %', v_nodes;
  end if;
  select bool_and((e->>'ts')::timestamptz = (select max(ts) from public.metrics m where m.node_id = (e->>'node_id')::uuid
                    and m.ts >= now() - interval '24 hours'))
    into v_ts_ok from jsonb_array_elements(r->'metrics') e;
  if not v_ts_ok or r::text like '%large%' then raise exception 'fleet readings are stale or carry the payload'; end if;
  select string_agg(right(e->>'node_id', 2) || ':' || (e->>'down_bps'), ',' order by e->>'node_id') into v_nodes
    from jsonb_array_elements(r->'speedtests') e where e->>'node_id' like '4f200000-%';
  if v_nodes is distinct from '01:100,03:50' then raise exception 'fleet speed tests are wrong: %', v_nodes; end if;
  raise notice 'PASS  the fleet view gets every server''s newest reading and speed test in one call, fleet viewers only';
end $$;
rollback;
