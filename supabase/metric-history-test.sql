-- Chart history returns exactly what row level security allows, and checks
-- access once per call (migrations/20260929140000_fast_metric_history.sql).
-- Rolled back.
\set ON_ERROR_STOP on
begin;
set local track_functions = 'all';
insert into auth.users(id,email) values
  ('4f000000-0000-4000-8000-000000000001','owner@history.test'),
  ('4f000000-0000-4000-8000-000000000002','viewer@history.test'),
  ('4f000000-0000-4000-8000-000000000003','stranger@history.test'),
  ('4f000000-0000-4000-8000-000000000004','admin@history.test');
update public.profiles set role = 'monitor', status = 'active' where email like '%@history.test';
update public.profiles set role = 'admin' where id = '4f000000-0000-4000-8000-000000000004';
insert into public.nodes(id,owner,name,revoked) values
  ('4f000000-0000-4000-8000-0000000000a1','4f000000-0000-4000-8000-000000000001','history node',false),
  ('4f000000-0000-4000-8000-0000000000a2','4f000000-0000-4000-8000-000000000001','history revoked',true);
insert into public.server_access(viewer_id,node_id,allowed) values
  ('4f000000-0000-4000-8000-000000000002','4f000000-0000-4000-8000-0000000000a1',true);
insert into public.metrics(node_id,ts,cpu_pct,net_rx_bps,net_tx_bps)
  select n, now() - s * interval '2 minutes', s % 100, 100 + s, 200
    from unnest(array['4f000000-0000-4000-8000-0000000000a1','4f000000-0000-4000-8000-0000000000a2']::uuid[]) n,
         generate_series(0, 1500) s;

set local role authenticated;
do $$
declare
  p record; v_fn bigint[]; v_ref bigint[]; c0 bigint; c1 bigint; v_fleet jsonb; v_ref_fleet jsonb; v_uid text;
  v_check constant regprocedure := 'public.hyn_can_view_node(uuid)'::regprocedure;
begin
  for p in select * from (values
      ('owner', '4f000000-0000-4000-8000-000000000001', '4f000000-0000-4000-8000-0000000000a1', true),
      ('shared viewer', '4f000000-0000-4000-8000-000000000002', '4f000000-0000-4000-8000-0000000000a1', true),
      ('admin', '4f000000-0000-4000-8000-000000000004', '4f000000-0000-4000-8000-0000000000a1', true),
      ('stranger', '4f000000-0000-4000-8000-000000000003', '4f000000-0000-4000-8000-0000000000a1', false),
      ('owner of a revoked server', '4f000000-0000-4000-8000-000000000001', '4f000000-0000-4000-8000-0000000000a2', false)
    ) v(who, uid, node, sees)
  loop
    perform set_config('test.uid', p.uid, true);
    c0 := coalesce(pg_stat_get_xact_function_calls(v_check), 0);
    select array_agg((e->>'id')::bigint order by (e->>'ts')::timestamptz) into v_fn
      from jsonb_array_elements(public.hyn_metric_history(p.node::uuid)) e;
    c1 := coalesce(pg_stat_get_xact_function_calls(v_check), 0);
    -- The same selection, filtered by row level security as this caller.
    select array_agg(id order by ts) into v_ref from (
      select distinct on (floor(extract(epoch from ts)/300)) id, ts from public.metrics
       where node_id = p.node::uuid and ts >= now() - interval '48 hours' and ts <= now() + interval '5 minutes'
       order by floor(extract(epoch from ts)/300) desc, ts desc limit 600) x;
    if v_fn is distinct from v_ref or (v_fn is not null) <> p.sees then
      raise exception '% sees % chart points, row level security allows %', p.who, cardinality(v_fn), cardinality(v_ref);
    end if;
    if c1 - c0 > 2 then raise exception 'one chart for the % checked server access % times', p.who, c1 - c0; end if;
  end loop;
  raise notice 'PASS  server chart history matches row level security for owner, viewer, admin, stranger and revoked servers';

  foreach v_uid in array array['4f000000-0000-4000-8000-000000000004', '4f000000-0000-4000-8000-000000000001'] loop
    perform set_config('test.uid', v_uid, true);
    c0 := coalesce(pg_stat_get_xact_function_calls(v_check), 0);
    v_fleet := public.hyn_fleet_metric_history();
    c1 := coalesce(pg_stat_get_xact_function_calls(v_check), 0);
    select coalesce(jsonb_agg(to_jsonb(h) order by h.ts), '[]'::jsonb) into v_ref_fleet from (
      select to_timestamp(floor(extract(epoch from m.ts)/1800)*1800) as ts,
        avg(m.cpu_pct) as cpu_pct, avg(m.net_rx_bps) as net_rx_bps, avg(m.net_tx_bps) as net_tx_bps
        from public.metrics m join public.nodes n on n.id = m.node_id
       where public.hyn_is_admin() and not n.is_demo and m.ts >= now() - interval '24 hours' and m.ts <= now()
       group by floor(extract(epoch from m.ts)/1800)
       order by floor(extract(epoch from m.ts)/1800) desc limit 49) h;
    if v_fleet <> v_ref_fleet or (jsonb_array_length(v_fleet) > 0) <> (v_uid = '4f000000-0000-4000-8000-000000000004') then
      raise exception 'fleet history differs from what row level security allows for %', v_uid;
    end if;
    if c1 - c0 > 0 then raise exception 'the fleet chart checked server access % times', c1 - c0; end if;
  end loop;
  raise notice 'PASS  fleet chart history matches row level security and checks access once, not per reading';
end $$;
rollback;
