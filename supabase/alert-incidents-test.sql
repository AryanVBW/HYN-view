-- Alert incident lifecycle through hyn_ingest: one row per incident, closed when
-- the agent reports it cleared or stops reporting it, never reopened after a
-- maintainer dismissed it. Runs against the complete schema.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email) values ('4a000000-0000-4000-8000-000000000001','incidents@alerts.test');
insert into public.nodes(id,owner,name,token_hash) values
  ('4a000000-0000-4000-8000-0000000000aa','4a000000-0000-4000-8000-000000000001','incident node',
   public._hyn_sha256('incident-token'));

create function pg_temp.push(p_minutes_ago integer, p_alerts jsonb) returns json language sql as $$
  select public.hyn_ingest('incident-token', jsonb_build_object(
    'ts', now() - make_interval(mins => p_minutes_ago), 'cpu', jsonb_build_object('pct', 5), 'alerts', p_alerts));
$$;
create function pg_temp.rows(p_rule text) returns bigint language sql as $$
  select count(*) from public.alert_events where node_id='4a000000-0000-4000-8000-0000000000aa' and rule=p_rule;
$$;
create function pg_temp.open_rows(p_rule text) returns bigint language sql as $$
  select count(*) from public.alert_events
   where node_id='4a000000-0000-4000-8000-0000000000aa' and rule=p_rule and not resolved;
$$;

-- 2.0.1 agent: stable start time, repeated uploads, then cleared.
do $$ declare r json; s bigint := extract(epoch from now() - interval '40 minutes')::bigint; begin
  r := pg_temp.push(30, jsonb_build_array(jsonb_build_object('rule','disk_root','severity','warn','message','Disk / at 86%','resolved',false,'since',s)));
  if r->>'alerts_written' <> '1' then raise exception 'first report did not open an incident: %', r; end if;
  r := pg_temp.push(28, jsonb_build_array(jsonb_build_object('rule','disk_root','severity','warn','message','Disk / at 87%','resolved',false,'since',s)));
  r := pg_temp.push(26, jsonb_build_array(jsonb_build_object('rule','disk_root','severity','warn','message','Disk / at 87%','resolved',false,'since',s)));
  if r->>'alerts_written' <> '0' or pg_temp.rows('disk_root') <> 1 then
    raise exception 'repeated uploads of one incident stored % rows', pg_temp.rows('disk_root');
  end if;
  if (select started_at from public.alert_events where rule='disk_root') <> to_timestamp(s) then
    raise exception 'incident start is not the agent''s since';
  end if;
  r := pg_temp.push(24, jsonb_build_array(jsonb_build_object('rule','disk_root','severity','warn','message','Disk / at 79%','resolved',true,'since',s)));
  r := pg_temp.push(22, jsonb_build_array(jsonb_build_object('rule','disk_root','severity','warn','message','Disk / at 79%','resolved',true,'since',s)));
  if pg_temp.rows('disk_root') <> 1 or pg_temp.open_rows('disk_root') <> 0
     or (select resolved_at from public.alert_events where rule='disk_root') <> now() - interval '24 minutes' then
    raise exception 'a cleared report did not close the incident exactly once';
  end if;
  raise notice 'PASS  one incident row across uploads, closed when the agent reports it cleared';
end $$;

-- Before 2.0.1: no start time, only firing rules. Absence closes the incident.
do $$ declare r json; begin
  r := pg_temp.push(20, '[{"rule":"mem_high","severity":"warn","message":"Memory at 91%"}]');
  r := pg_temp.push(18, '[{"rule":"mem_high","severity":"warn","message":"Memory at 92%"}]');
  if pg_temp.rows('mem_high') <> 1 or pg_temp.open_rows('mem_high') <> 1 then raise exception 'legacy reports split one incident'; end if;
  r := pg_temp.push(16, '[]');
  if pg_temp.open_rows('mem_high') <> 0 then raise exception 'an incident missing from a complete list stayed open'; end if;
  r := pg_temp.push(14, '[{"rule":"mem_high","severity":"crit","message":"Memory at 97%"}]');
  if pg_temp.rows('mem_high') <> 2 or pg_temp.open_rows('mem_high') <> 1 then raise exception 'a recurrence did not open a new incident'; end if;
  raise notice 'PASS  agents without start times still get one row per incident, closed by absence';
end $$;

-- Only the newest reading drives the lifecycle; payloads without an alert list
-- or with more alerts than the bound close nothing.
do $$ declare r json; begin
  r := pg_temp.push(40, '[]');
  if pg_temp.open_rows('mem_high') <> 1 then raise exception 'an older replayed reading closed a current incident'; end if;
  r := public.hyn_ingest('incident-token', jsonb_build_object('ts', now() - interval '13 minutes', 'cpu', jsonb_build_object('pct', 5)));
  if pg_temp.open_rows('mem_high') <> 1 then raise exception 'a reading without an alert list closed an incident'; end if;
  r := pg_temp.push(12, (select jsonb_agg(jsonb_build_object('rule','bulk'||n,'severity','info','message','bulk')) from generate_series(1,33) n));
  if pg_temp.open_rows('mem_high') <> 1 then raise exception 'a truncated alert list closed an incident it did not include'; end if;
  raise notice 'PASS  replays, partial and truncated alert lists never close incidents';
end $$;

-- A maintainer dismissal holds while the condition continues, with or without
-- a start time, and a genuinely new occurrence after a gap opens a new incident.
do $$ declare r json; s bigint := extract(epoch from now() - interval '12 minutes')::bigint; begin
  r := pg_temp.push(11, jsonb_build_array(
    jsonb_build_object('rule','load_high','severity','warn','message','Load 9','since',s),
    jsonb_build_object('rule','speed_drop','severity','warn','message','Slow link')));
  update public.alert_events set resolved = true, resolved_at = now(), dismissed_at = now()
   where rule in ('load_high','speed_drop') and not resolved;
  r := pg_temp.push(10, jsonb_build_array(
    jsonb_build_object('rule','load_high','severity','warn','message','Load 9','since',s),
    jsonb_build_object('rule','speed_drop','severity','warn','message','Slow link')));
  r := pg_temp.push(5, jsonb_build_array(
    jsonb_build_object('rule','load_high','severity','warn','message','Load 9','since',s),
    jsonb_build_object('rule','speed_drop','severity','warn','message','Slow link')));
  if pg_temp.open_rows('load_high') <> 0 or pg_temp.rows('load_high') <> 1
     or pg_temp.open_rows('speed_drop') <> 0 or pg_temp.rows('speed_drop') <> 1 then
    raise exception 'a dismissed incident was reopened or duplicated';
  end if;
  update public.alert_events set ts = now() - interval '2 hours' where rule = 'speed_drop';
  r := pg_temp.push(4, '[{"rule":"speed_drop","severity":"warn","message":"Slow link again"}]');
  if pg_temp.open_rows('speed_drop') <> 1 or pg_temp.rows('speed_drop') <> 2 then
    raise exception 'a new occurrence after a long gap stayed covered by an old dismissal';
  end if;
  raise notice 'PASS  a dismissed incident stays closed while it continues; a later recurrence is new';
end $$;
rollback;
