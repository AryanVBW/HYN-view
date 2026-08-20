-- End-to-end test of the device pairing and ingest flow.
--
--   bash supabase/run-tests.sh
--
-- Asserts the behaviours that matter and would be expensive to discover in
-- production: a token is released exactly once, a replayed poll fails, an
-- unknown token cannot write, and one user cannot read another's telemetry.
-- Any failed assertion raises and aborts with a non-zero exit.

\set ON_ERROR_STOP on
\pset pager off

begin;

-- Two separate accounts, because the interesting RLS question is whether one
-- can see the other's data.
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com');

create temporary table t (k text primary key, v text);
-- The test switches roles with SET ROLE, so the scratch table has to be usable
-- by each of them.
grant all on t to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. the headless agent requests a code (as anon)
-- ---------------------------------------------------------------------------
set local role anon;
set local "test.uid" = '';

do $$
declare r json;
begin
  r := public.hyn_device_start('web-01', 'Ubuntu 24.04 LTS', '1.4.0');
  insert into t values ('user_code', r->>'user_code'), ('device_code', r->>'device_code');
  if length(r->>'device_code') <> 64 then
    raise exception 'device_code should be 32 bytes hex, got %', length(r->>'device_code');
  end if;
  if (r->>'user_code') !~ '^[0-9A-Z]{4}-[0-9A-Z]{4}$' then
    raise exception 'user_code has the wrong shape: %', r->>'user_code';
  end if;
  raise notice 'PASS  device_start issues a well-formed code (%)', r->>'user_code';
end $$;

-- The plaintext code must not be stored; only its hash. Inspecting storage
-- directly needs superuser, since anon deliberately cannot read this table.
do $$
declare n integer;
begin
  set local role postgres;
  select count(*) into n from public.device_codes
   where device_code_hash = (select v from t where k = 'device_code');
  if n <> 0 then raise exception 'device_code was stored in plaintext'; end if;
  select count(*) into n from public.device_codes
   where device_code_hash = encode(extensions.digest((select v from t where k = 'device_code'), 'sha256'), 'hex');
  if n <> 1 then raise exception 'device_code hash was not stored'; end if;
  set local role anon;
  raise notice 'PASS  device code is stored hashed, not in plaintext';
end $$;

-- ---------------------------------------------------------------------------
-- 2. polling before approval says pending, and yields no token
-- ---------------------------------------------------------------------------
do $$
declare r json;
begin
  r := public.hyn_device_poll((select v from t where k = 'device_code'));
  if r->>'status' <> 'pending' then raise exception 'expected pending, got %', r->>'status'; end if;
  if r::jsonb ? 'node_token' then raise exception 'a pending poll leaked a token'; end if;
  raise notice 'PASS  poll before approval is pending and tokenless';
end $$;

-- An unauthenticated lookup must be refused: the pairing code is shown on the
-- server's terminal, and anonymous enumeration would defeat the whole flow.
do $$
declare ok boolean := false;
begin
  begin
    perform public.hyn_device_lookup((select v from t where k = 'user_code'));
  exception when others then ok := true;
  end;
  if not ok then raise exception 'anon was allowed to look up a pairing code'; end if;
  raise notice 'PASS  anonymous lookup is refused';
end $$;

-- ---------------------------------------------------------------------------
-- 3. alice approves it from a browser
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "test.uid" = '11111111-1111-1111-1111-111111111111';

do $$
declare r json;
begin
  r := public.hyn_device_lookup((select v from t where k = 'user_code'));
  if r->>'status' <> 'pending' then raise exception 'lookup: expected pending, got %', r->>'status'; end if;
  if r->>'hostname' <> 'web-01' then raise exception 'lookup lost the hostname'; end if;
  raise notice 'PASS  lookup shows which host is asking (%)', r->>'hostname';
end $$;

do $$
declare r json;
begin
  r := public.hyn_device_approve((select v from t where k = 'user_code'), 'web-01');
  if r->>'status' <> 'approved' then raise exception 'approve failed: %', r->>'status'; end if;
  insert into t values ('node_id', r->>'node_id');
  raise notice 'PASS  approve creates the node';
end $$;

-- The browser must not receive the node token; only the polling server does.
do $$
declare r json;
begin
  r := public.hyn_device_approve((select v from t where k = 'user_code'), 'web-01');
  if r->>'status' <> 'already_approved' then
    raise exception 'a second approval was allowed: %', r->>'status';
  end if;
  raise notice 'PASS  a code cannot be approved twice';
end $$;

-- ---------------------------------------------------------------------------
-- 4. the server polls again and collects its token, exactly once
-- ---------------------------------------------------------------------------
set local role anon;
set local "test.uid" = '';

do $$
declare r json;
begin
  r := public.hyn_device_poll((select v from t where k = 'device_code'));
  if r->>'status' <> 'approved' then raise exception 'expected approved, got %', r->>'status'; end if;
  if coalesce(length(r->>'node_token'), 0) <> 64 then raise exception 'no usable node_token returned'; end if;
  insert into t values ('node_token', r->>'node_token');
  raise notice 'PASS  poll after approval returns the node token';
end $$;

do $$
declare r json;
begin
  r := public.hyn_device_poll((select v from t where k = 'device_code'));
  if r->>'status' <> 'claimed' then
    raise exception 'a replayed poll was honoured: %', r->>'status';
  end if;
  raise notice 'PASS  a replayed poll is rejected (token issued exactly once)';
end $$;

-- ---------------------------------------------------------------------------
-- 5. ingest
-- ---------------------------------------------------------------------------
do $$
declare r json; payload jsonb;
begin
  payload := jsonb_build_object(
    'ts', '2026-08-19T12:00:00Z',
    'host', 'web-01',
    'agent_version', '1.4.0',
    'uptime_s', 123456,
    'load', jsonb_build_array(0.42, 0.31, 0.28),
    'cpu', jsonb_build_object('pct', 37.5, 'temp_c', 52, 'mhz', 3400,
                              'model', 'AMD EPYC 9354', 'steal', 0.2,
                              'iowait', 1.1, 'cores', 8),
    'memory', jsonb_build_object('pct', 61.2, 'total', 33285996544,
                                 'used', 20000000000, 'swap_used', 0),
    'disk', jsonb_build_object('pct', 58.4),
    'network', jsonb_build_object('iface', 'eth0', 'rx_bps', 81250000,
                                  'tx_bps', 22500000, 'retrans_permille', 3.1),
    'latency_ms', 8.62,
    'speedtest', jsonb_build_object('ts', 1755600000, 'down_bps', 105000000,
                                    'up_bps', 54000000, 'latency_us', 8600, 'note', ''),
    'alerts', jsonb_build_array(
      jsonb_build_object('rule', 'disk_root', 'severity', 'warn',
                         'message', 'Disk / at 86%', 'resolved', false))
  );
  r := public.hyn_ingest((select v from t where k = 'node_token'), payload);
  if r->>'status' <> 'ok' then raise exception 'ingest failed: %', r; end if;
  raise notice 'PASS  ingest accepted the agent payload';
end $$;

-- Extracted columns must match what the agent sent, since the charts read those
-- rather than the jsonb blob. Read as superuser: anon cannot select these.
do $$
declare m public.metrics;
begin
  set local role postgres;
  select * into m from public.metrics
   where node_id = (select v from t where k = 'node_id')::uuid
   order by ts desc limit 1;
  if m.cpu_pct <> 37.5    then raise exception 'cpu_pct wrong: %', m.cpu_pct; end if;
  if m.cpu_mhz <> 3400    then raise exception 'cpu_mhz wrong: %', m.cpu_mhz; end if;
  if m.cpu_temp_c <> 52   then raise exception 'cpu_temp_c wrong: %', m.cpu_temp_c; end if;
  if m.cpu_cores <> 8     then raise exception 'cpu_cores wrong: %', m.cpu_cores; end if;
  if m.load1 <> 0.42      then raise exception 'load1 wrong: %', m.load1; end if;
  if m.mem_pct <> 61.2    then raise exception 'mem_pct wrong: %', m.mem_pct; end if;
  if m.disk_pct <> 58.4   then raise exception 'disk_pct wrong: %', m.disk_pct; end if;
  if m.net_rx_bps <> 81250000 then raise exception 'net_rx_bps wrong: %', m.net_rx_bps; end if;
  if m.latency_ms <> 8.62 then raise exception 'latency_ms wrong: %', m.latency_ms; end if;
  if m.cpu_model <> 'AMD EPYC 9354' then raise exception 'cpu_model wrong: %', m.cpu_model; end if;
  set local role anon;
  raise notice 'PASS  every charted column round-trips from the payload';
end $$;

do $$
declare n integer;
begin
  set local role postgres;
  select count(*) into n from public.speedtests where node_id = (select v from t where k = 'node_id')::uuid;
  if n <> 1 then raise exception 'expected 1 speedtest row, got %', n; end if;
  select count(*) into n from public.alert_events where node_id = (select v from t where k = 'node_id')::uuid;
  if n <> 1 then raise exception 'expected 1 alert row, got %', n; end if;
  set local role anon;
  raise notice 'PASS  speed test and alert rows were written';
end $$;

-- A repeated push of the same speed test must not duplicate it: the agent
-- resends its last result on every push.
do $$
declare n integer;
begin
  perform public.hyn_ingest((select v from t where k = 'node_token'), jsonb_build_object(
    'ts', '2026-08-19T12:05:00Z',
    'cpu', jsonb_build_object('pct', 40),
    'speedtest', jsonb_build_object('ts', 1755600000, 'down_bps', 105000000,
                                    'up_bps', 54000000, 'latency_us', 8600)
  ));
  set local role postgres;
  select count(*) into n from public.speedtests where node_id = (select v from t where k = 'node_id')::uuid;
  if n <> 1 then raise exception 'resent speed test was duplicated: % rows', n; end if;
  set local role anon;
  raise notice 'PASS  a resent speed test is deduplicated';
end $$;

-- last_seen_at is what the dashboard shows as "last push".
do $$
declare seen timestamptz;
begin
  set local role postgres;
  select last_seen_at into seen from public.nodes where id = (select v from t where k = 'node_id')::uuid;
  if seen is null then raise exception 'last_seen_at was not updated'; end if;
  set local role anon;
  raise notice 'PASS  last_seen_at is updated on ingest';
end $$;

-- A bad token must be refused outright.
do $$
declare ok boolean := false;
begin
  begin
    perform public.hyn_ingest('deadbeef', '{"cpu":{"pct":1}}'::jsonb);
  exception when others then ok := true;
  end;
  if not ok then raise exception 'ingest accepted an invalid token'; end if;
  raise notice 'PASS  ingest rejects an unknown token';
end $$;

-- A revoked node must stop being able to write.
do $$
declare ok boolean := false;
begin
  set local role postgres;
  update public.nodes set revoked = true where id = (select v from t where k = 'node_id')::uuid;
  set local role anon;
  begin
    perform public.hyn_ingest((select v from t where k = 'node_token'), '{"cpu":{"pct":1}}'::jsonb);
  exception when others then ok := true;
  end;
  if not ok then raise exception 'a revoked node was still able to write'; end if;
  set local role postgres;
  update public.nodes set revoked = false where id = (select v from t where k = 'node_id')::uuid;
  set local role anon;
  raise notice 'PASS  a revoked node cannot write';
end $$;

-- ---------------------------------------------------------------------------
-- 6. row level security
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "test.uid" = '11111111-1111-1111-1111-111111111111';

do $$
declare n integer;
begin
  select count(*) into n from public.nodes;
  if n <> 1 then raise exception 'alice should see exactly her 1 node, saw %', n; end if;
  select count(*) into n from public.metrics;
  if n <> 2 then raise exception 'alice should see her 2 metric rows, saw %', n; end if;
  raise notice 'PASS  alice sees her own node and metrics';
end $$;

set local "test.uid" = '22222222-2222-2222-2222-222222222222';

do $$
declare n integer;
begin
  select count(*) into n from public.nodes;
  if n <> 0 then raise exception 'bob can see % of alice''s nodes', n; end if;
  select count(*) into n from public.metrics;
  if n <> 0 then raise exception 'bob can see % of alice''s metric rows', n; end if;
  select count(*) into n from public.speedtests;
  if n <> 0 then raise exception 'bob can see % of alice''s speed tests', n; end if;
  select count(*) into n from public.alert_events;
  if n <> 0 then raise exception 'bob can see % of alice''s alerts', n; end if;
  raise notice 'PASS  bob cannot see any of alice''s telemetry';
end $$;

-- Pending pairing codes must not be listable by a signed-in user, or "approve
-- the code in front of me" degrades into "approve whatever is pending".
do $$
declare ok boolean := false;
begin
  begin
    perform 1 from public.device_codes;
  exception when insufficient_privilege then ok := true;
  end;
  if not ok then raise exception 'device_codes is readable by an authenticated user'; end if;
  raise notice 'PASS  device_codes is not readable from a session';
end $$;

-- Telemetry must not be forgeable from a browser session, even for your own
-- node: writes go through hyn_ingest, which requires the node token.
do $$
declare ok boolean := false;
begin
  set local "test.uid" = '11111111-1111-1111-1111-111111111111';
  begin
    insert into public.metrics (node_id, ts, cpu_pct)
    values ((select v from t where k = 'node_id')::uuid, now(), 99);
  exception when others then ok := true;
  end;
  if not ok then raise exception 'a browser session could forge a metric row'; end if;
  raise notice 'PASS  a session cannot insert telemetry directly';
end $$;

-- ---------------------------------------------------------------------------
-- 7. demo data
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "test.uid" = '22222222-2222-2222-2222-222222222222';

do $$
declare r json; n integer; flagged boolean;
begin
  r := public.hyn_demo_seed();
  if r->>'status' <> 'ok' then raise exception 'demo seed failed: %', r; end if;

  select count(*) into n from public.metrics where node_id = (r->>'node_id')::uuid;
  if n < 200 then raise exception 'demo seed produced only % metric rows', n; end if;

  select is_demo into flagged from public.nodes where id = (r->>'node_id')::uuid;
  if not flagged then raise exception 'the demo node is not flagged is_demo'; end if;
  raise notice 'PASS  demo seed creates a flagged node with % samples', n;
end $$;

-- The dashboard's Highway section reads metrics.payload->'highway'. A demo node
-- seeded without it renders the "no Highway telemetry" empty state, which looks
-- like a broken panel rather than like demo data.
do $$
declare hw jsonb;
begin
  select m.payload->'highway' into hw
    from public.metrics m
    join public.nodes n on n.id = m.node_id
   where n.is_demo
   order by m.ts desc
   limit 1;
  if hw is null then raise exception 'demo metrics carry no highway payload'; end if;
  if jsonb_array_length(hw->'units') <> 2 then
    raise exception 'demo highway payload has % units', jsonb_array_length(hw->'units');
  end if;
  if hw->'units'->0->>'state' <> 'active' then
    raise exception 'demo highway unit is not active: %', hw->'units'->0;
  end if;
  if (hw->>'mesh_iface') is null or (hw->>'pid') is null then
    raise exception 'demo highway payload is missing process or mesh detail: %', hw;
  end if;
  raise notice 'PASS  demo seed carries highway services, process and mesh detail';
end $$;

-- Seeding twice must replace, not accumulate.
do $$
declare n integer;
begin
  perform public.hyn_demo_seed();
  select count(*) into n from public.nodes where is_demo = true;
  if n <> 1 then raise exception 'reseeding left % demo nodes', n; end if;
  raise notice 'PASS  reseeding replaces the previous demo node';
end $$;

do $$
declare n integer;
begin
  perform public.hyn_demo_clear();
  select count(*) into n from public.nodes where is_demo = true;
  if n <> 0 then raise exception 'demo clear left % demo nodes', n; end if;
  select count(*) into n from public.metrics;
  if n <> 0 then raise exception 'demo clear left % orphaned metric rows', n; end if;
  raise notice 'PASS  demo clear removes the node and cascades its metrics';
end $$;

-- Demo data belongs to whoever asked for it, and must not touch anyone else's.
do $$
declare n integer;
begin
  set local "test.uid" = '11111111-1111-1111-1111-111111111111';
  select count(*) into n from public.nodes;
  if n <> 1 then raise exception 'alice''s real node was disturbed by bob''s demo data'; end if;
  raise notice 'PASS  demo seed and clear are scoped to one account';
end $$;

-- An anonymous caller must not be able to seed demo data into the database.
set local role anon;
set local "test.uid" = '';
do $$
declare ok boolean := false;
begin
  begin
    perform public.hyn_demo_seed();
  exception when others then ok := true;
  end;
  if not ok then raise exception 'anon was able to seed demo data'; end if;
  raise notice 'PASS  anon cannot seed demo data';
end $$;

-- ---------------------------------------------------------------------------
-- 8. profiles, roles and the control plane
-- ---------------------------------------------------------------------------
set local role postgres;
set local "test.uid" = '';

-- The signup trigger must have created a profile for each user, or a client
-- would be invisible in the admin dashboard.
do $$
declare n integer; em text;
begin
  select count(*) into n from public.profiles;
  if n <> 2 then raise exception 'expected 2 profiles from the signup trigger, got %', n; end if;
  select email into em from public.profiles where id = '11111111-1111-1111-1111-111111111111';
  if em <> 'alice@example.com' then raise exception 'profile email not mirrored: %', em; end if;
  select count(*) into n from public.profiles where role = 'user' and status = 'active';
  if n <> 2 then raise exception 'new profiles should default to active users'; end if;
  raise notice 'PASS  a profile is created automatically for every new client';
end $$;

-- Promote carol to administrator out of band, the way a first admin is made.
insert into auth.users (id, email) values
  ('33333333-3333-3333-3333-333333333333', 'carol@example.com');
update public.profiles set role = 'admin' where id = '33333333-3333-3333-3333-333333333333';

-- ---------------------------------------------------------------------------
-- 9. server-side configuration, pulled by the agent
-- ---------------------------------------------------------------------------
set local role postgres;
update public.nodes
   set config = '{"alert_mem_pct": 80, "report_at": "07:30"}'::jsonb
 where id = (select v from t where k = 'node_id')::uuid;

insert into public.notification_channels (owner, node_id, kind, target, secret)
values ('11111111-1111-1111-1111-111111111111', null, 'resend', 'ops@alice.example', 're_secret_key');

set local role anon;
set local "test.uid" = '';

do $$
declare r json;
begin
  r := public.hyn_fetch_config((select v from t where k = 'node_token'));
  if r->>'status' <> 'ok' then raise exception 'config pull failed: %', r; end if;
  if (r#>>'{config,report_at}') <> '07:30' then
    raise exception 'config did not round-trip: %', r->'config';
  end if;
  if (r#>>'{channels,0,kind}') <> 'resend' then
    raise exception 'channels missing from config pull: %', r->'channels';
  end if;
  -- The agent needs the provider key to be able to send at all.
  if (r#>>'{channels,0,secret}') <> 're_secret_key' then
    raise exception 'the node token should receive the channel secret';
  end if;
  raise notice 'PASS  the agent pulls its own config and channels by node token';
end $$;

do $$
declare ok boolean := false;
begin
  begin
    perform public.hyn_fetch_config('not-a-real-token');
  exception when others then ok := true;
  end;
  if not ok then raise exception 'config pull accepted an invalid token'; end if;
  raise notice 'PASS  config pull rejects an unknown token';
end $$;

do $$
declare seen timestamptz;
begin
  set local role postgres;
  select last_config_pull_at into seen from public.nodes
   where id = (select v from t where k = 'node_id')::uuid;
  if seen is null then raise exception 'last_config_pull_at was not recorded'; end if;
  set local role anon;
  raise notice 'PASS  a config pull is recorded against the node';
end $$;

-- The dashboard must be able to manage channels without being able to read a
-- secret back out. This is enforced by a column grant, not by convention.
set local role authenticated;
set local "test.uid" = '11111111-1111-1111-1111-111111111111';

do $$
declare ok boolean := false; n integer;
begin
  -- Non-secret columns are readable.
  select count(*) into n from public.notification_channels;
  if n <> 1 then raise exception 'alice should see her 1 channel, saw %', n; end if;
  begin
    perform secret from public.notification_channels;
  exception when insufficient_privilege then ok := true;
  end;
  if not ok then raise exception 'a browser session could read a channel secret'; end if;
  raise notice 'PASS  channel secrets are write-only from a session';
end $$;

do $$
declare n integer;
begin
  set local "test.uid" = '22222222-2222-2222-2222-222222222222';
  select count(*) into n from public.notification_channels;
  if n <> 0 then raise exception 'bob can see % of alice''s channels', n; end if;
  raise notice 'PASS  channels are private to their owner';
end $$;

-- ---------------------------------------------------------------------------
-- 10. notification reporting
-- ---------------------------------------------------------------------------
set local role anon;
set local "test.uid" = '';

do $$
declare r json;
begin
  r := public.hyn_report_notification((select v from t where k = 'node_token'), jsonb_build_array(
    jsonb_build_object('kind','resend','target','ops@alice.example','severity','warn',
                       'subject','[hyn] web-01 disk 86%','status','sent','category','alert'),
    jsonb_build_object('kind','resend','target','ops@alice.example','severity','info',
                       'subject','[hyn] daily report','status','failed',
                       'error','HTTP 403: domain is not verified','category','report')
  ));
  if (r->>'written')::int <> 2 then raise exception 'expected 2 log rows, got %', r->>'written'; end if;
  raise notice 'PASS  the agent reports notification deliveries';
end $$;

set local role authenticated;
set local "test.uid" = '11111111-1111-1111-1111-111111111111';

do $$
declare n integer; failed integer; err text;
begin
  select count(*) into n from public.notification_log;
  if n <> 2 then raise exception 'alice should see 2 notification rows, saw %', n; end if;
  select count(*) into failed from public.notification_log where status = 'failed';
  if failed <> 1 then raise exception 'expected 1 failure, got %', failed; end if;
  select error into err from public.notification_log where status = 'failed';
  if err not like '%domain is not verified%' then raise exception 'the failure reason was lost'; end if;
  raise notice 'PASS  a client sees their delivery counts and why one failed';
end $$;

do $$
declare n integer;
begin
  set local "test.uid" = '22222222-2222-2222-2222-222222222222';
  select count(*) into n from public.notification_log;
  if n <> 0 then raise exception 'bob can see % of alice''s notifications', n; end if;
  raise notice 'PASS  notification logs are private to their owner';
end $$;

-- ---------------------------------------------------------------------------
-- 11. a non-admin must be refused everything privileged
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "test.uid" = '22222222-2222-2222-2222-222222222222';

do $$
declare fn text; ok boolean;
begin
  foreach fn in array array[
    'select public.hyn_admin_overview()',
    'select public.hyn_admin_nodes()',
    'select public.hyn_admin_clients()',
    'select public.hyn_admin_notifications(10)',
    'select public.hyn_admin_audit(10)'
  ] loop
    ok := false;
    begin
      execute fn;
    exception when others then ok := true;
    end;
    if not ok then raise exception 'a non-admin was allowed: %', fn; end if;
  end loop;
  raise notice 'PASS  a non-admin is refused every admin read';
end $$;

do $$
declare ok boolean := false;
begin
  begin
    perform public.hyn_admin_set_node_status(
      (select v from t where k = 'node_id')::uuid, 'suspended', null, 'mischief');
  exception when others then ok := true;
  end;
  if not ok then raise exception 'a non-admin could suspend another client''s node'; end if;
  raise notice 'PASS  a non-admin cannot change a node''s status';
end $$;

do $$
declare ok boolean := false;
begin
  begin
    perform public.hyn_admin_set_role('22222222-2222-2222-2222-222222222222', 'admin');
  exception when others then ok := true;
  end;
  if not ok then raise exception 'a non-admin could promote themselves to admin'; end if;
  raise notice 'PASS  a non-admin cannot promote themselves';
end $$;

do $$
declare ok boolean := false;
begin
  begin
    perform 1 from public.admin_audit;
  exception when insufficient_privilege then ok := true;
  end;
  -- RLS returns zero rows rather than an error for a select, so check both.
  if not ok then
    if exists (select 1 from public.admin_audit) then
      raise exception 'a non-admin could read the audit trail';
    end if;
  end if;
  raise notice 'PASS  a non-admin cannot read the audit trail';
end $$;

-- The escalation this fixed: hyn_claim_env_admin is granted to `authenticated`,
-- so it is reachable with nothing but the public anon key and any session. If
-- the allow list is not checked *inside* the function, every user of the portal
-- is one direct RPC call away from reading the whole fleet.
do $$
declare r json; v_role text;
begin
  r := public.hyn_claim_env_admin(null);
  if r->>'status' <> 'not_allowed' then
    raise exception 'claim by a non-allow-listed user returned %', r;
  end if;
  select role into v_role from public.profiles where id = '22222222-2222-2222-2222-222222222222';
  if v_role <> 'user' then
    raise exception 'a non-allow-listed user was promoted to %', v_role;
  end if;
  raise notice 'PASS  a signed-in user cannot promote themselves by calling the claim RPC';
end $$;

do $$
declare ok boolean := false;
begin
  begin
    perform 1 from public.admin_allowlist;
  exception when insufficient_privilege then ok := true;
  end;
  if not ok then raise exception 'a session could read the administrator allow list'; end if;
  ok := false;
  begin
    insert into public.admin_allowlist (email) values ('mischief@example.com');
  exception when insufficient_privilege then ok := true;
  end;
  if not ok then raise exception 'a session could add itself to the allow list'; end if;
  raise notice 'PASS  the administrator allow list is unreachable from any session';
end $$;

-- A node token verifier is half a credential and no page needs it, so the column
-- grant leaves it out. This also documents the consequence: `select *` on nodes
-- is refused for a session, which is why the portal names its columns.
do $$
declare ok boolean := false; n integer;
begin
  begin
    perform token_hash from public.nodes limit 1;
  exception when insufficient_privilege then ok := true;
  end;
  if not ok then raise exception 'a session could read nodes.token_hash'; end if;
  -- The granted columns must still be selectable. Row count is not the subject:
  -- RLS shows this caller no rows, and that is a different guarantee tested above.
  begin
    select count(*) into n from (
      select id, owner, name, hostname, os, agent_version, is_demo, revoked, created_at,
             last_seen_at, status, paused_until, status_reason, config, last_config_pull_at
        from public.nodes) t;
  exception when insufficient_privilege then
    raise exception 'the granted node columns are not readable';
  end;
  raise notice 'PASS  nodes.token_hash is unreadable while the other columns are not';
end $$;

-- And the other half: an address the operator put on the list in the SQL editor
-- does get promoted, so the mechanism still works. Uses a throwaway account and
-- cleans up, because later sections count administrators.
reset role;
insert into auth.users (id, email) values
  ('12121212-1212-4121-8121-121212121212', 'listed@example.com');
insert into public.profiles (id, email, role) values
  ('12121212-1212-4121-8121-121212121212', 'listed@example.com', 'user')
on conflict (id) do update set role = 'user';
insert into public.admin_allowlist (email, note) values ('listed@example.com', 'flow test')
on conflict (email) do nothing;

set local role authenticated;
set local "test.uid" = '12121212-1212-4121-8121-121212121212';

do $$
declare r json; v_role text;
begin
  r := public.hyn_claim_env_admin('listed@example.com');
  if r->>'status' <> 'ok' then raise exception 'an allow-listed user was refused: %', r; end if;
  select role into v_role from public.profiles where id = '12121212-1212-4121-8121-121212121212';
  if v_role <> 'admin' then raise exception 'an allow-listed user was not promoted (role %)', v_role; end if;
  raise notice 'PASS  an allow-listed address claims administrator on sign-in';
end $$;

reset role;
delete from public.admin_allowlist where email = 'listed@example.com';
delete from auth.users where id = '12121212-1212-4121-8121-121212121212';
set local role authenticated;
set local "test.uid" = '22222222-2222-2222-2222-222222222222';

-- ---------------------------------------------------------------------------
-- 12. the administrator sees the whole fleet
-- ---------------------------------------------------------------------------
set local "test.uid" = '33333333-3333-3333-3333-333333333333';

do $$
declare r json;
begin
  r := public.hyn_admin_overview();
  if (r->>'clients_total')::int <> 3 then
    raise exception 'overview should count 3 clients, got %', r->>'clients_total';
  end if;
  if (r->>'nodes_total')::int <> 1 then
    raise exception 'overview should count 1 real node, got %', r->>'nodes_total';
  end if;
  if (r->>'notifications_24h')::int <> 2 then
    raise exception 'overview should count 2 notifications, got %', r->>'notifications_24h';
  end if;
  if (r->>'notifications_failed_24h')::int <> 1 then
    raise exception 'overview should count 1 failure, got %', r->>'notifications_failed_24h';
  end if;
  raise notice 'PASS  admin overview counts clients, nodes and notifications';
end $$;

do $$
declare r json;
begin
  r := public.hyn_admin_nodes();
  if (r#>>'{0,owner_email}') <> 'alice@example.com' then
    raise exception 'admin node list should name the owner, got %', r#>>'{0,owner_email}';
  end if;
  if (r#>>'{0,notifications_24h}')::int <> 2 then
    raise exception 'admin node list should carry notification volume';
  end if;
  if (r#>>'{0,last_cpu_pct}') is null then
    raise exception 'admin node list should carry the latest reading';
  end if;
  raise notice 'PASS  admin node list joins owner, health and notification volume';
end $$;

do $$
declare r json; n integer;
begin
  r := public.hyn_admin_clients();
  select count(*) into n from json_array_elements(r);
  if n <> 3 then raise exception 'admin client list should have 3 rows, got %', n; end if;
  raise notice 'PASS  admin client list covers every account';
end $$;

-- Cross-tenant reads: the admin can see another client's telemetry.
do $$
declare n integer;
begin
  select count(*) into n from public.nodes;
  if n < 1 then raise exception 'admin cannot see any nodes'; end if;
  select count(*) into n from public.metrics;
  if n < 1 then raise exception 'admin cannot see any metrics'; end if;
  select count(*) into n from public.notification_log;
  if n <> 2 then raise exception 'admin should see all 2 notifications, saw %', n; end if;
  raise notice 'PASS  an admin reads across tenants';
end $$;

-- ---------------------------------------------------------------------------
-- 13. pause, suspend, resume
-- ---------------------------------------------------------------------------
do $$
declare r json;
begin
  r := public.hyn_admin_set_node_status(
    (select v from t where k = 'node_id')::uuid, 'paused', 30, 'maintenance window');
  if r->>'node_status' <> 'paused' then raise exception 'pause failed: %', r; end if;
  if r->>'paused_until' is null then raise exception 'a timed pause needs a deadline'; end if;
  raise notice 'PASS  an admin can pause a node for a fixed window';
end $$;

set local role anon;
do $$
declare ok boolean := false; msg text;
begin
  begin
    perform public.hyn_ingest((select v from t where k = 'node_token'), '{"cpu":{"pct":5}}'::jsonb);
  exception when others then ok := true; msg := sqlerrm;
  end;
  if not ok then raise exception 'a paused node was still able to write'; end if;
  if msg not like '%paused%' then raise exception 'pause should say so, said: %', msg; end if;
  raise notice 'PASS  a paused node cannot write, and is told why';
end $$;

-- A pause whose deadline has passed must resolve itself.
do $$
declare r json;
begin
  set local role postgres;
  update public.nodes set paused_until = now() - interval '1 minute'
   where id = (select v from t where k = 'node_id')::uuid;
  set local role anon;
  r := public.hyn_ingest((select v from t where k = 'node_token'), '{"cpu":{"pct":6}}'::jsonb);
  if r->>'status' <> 'ok' then raise exception 'an expired pause did not resolve: %', r; end if;
  set local role postgres;
  if (select status from public.nodes where id = (select v from t where k = 'node_id')::uuid) <> 'active' then
    raise exception 'the node was not returned to active';
  end if;
  set local role anon;
  raise notice 'PASS  a temporary pause expires by itself';
end $$;

set local role authenticated;
set local "test.uid" = '33333333-3333-3333-3333-333333333333';

do $$
begin
  perform public.hyn_admin_set_node_status(
    (select v from t where k = 'node_id')::uuid, 'suspended', null, 'abuse investigation');
  raise notice 'PASS  an admin can suspend a node';
end $$;

set local role anon;
do $$
declare ok boolean := false; msg text;
begin
  begin
    perform public.hyn_ingest((select v from t where k = 'node_token'), '{"cpu":{"pct":7}}'::jsonb);
  exception when others then ok := true; msg := sqlerrm;
  end;
  if not ok then raise exception 'a suspended node was still able to write'; end if;
  if msg not like '%suspended%' then raise exception 'suspension should say so, said: %', msg; end if;
  raise notice 'PASS  a suspended node cannot write';
end $$;

set local role authenticated;
set local "test.uid" = '33333333-3333-3333-3333-333333333333';
do $$
begin
  perform public.hyn_admin_set_node_status((select v from t where k = 'node_id')::uuid, 'active');
  raise notice 'PASS  an admin can reinstate a node';
end $$;

set local role anon;
do $$
declare r json;
begin
  r := public.hyn_ingest((select v from t where k = 'node_token'), '{"cpu":{"pct":8}}'::jsonb);
  if r->>'status' <> 'ok' then raise exception 'a reinstated node still cannot write: %', r; end if;
  raise notice 'PASS  a reinstated node writes again';
end $$;

-- ---------------------------------------------------------------------------
-- 14. client suspension cascades to their fleet
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "test.uid" = '33333333-3333-3333-3333-333333333333';

do $$
declare st text;
begin
  perform public.hyn_admin_set_user_status(
    '11111111-1111-1111-1111-111111111111', 'suspended', 'non-payment');
  set local role postgres;
  select status into st from public.nodes where id = (select v from t where k = 'node_id')::uuid;
  if st <> 'suspended' then
    raise exception 'suspending a client should suspend their nodes, node is %', st;
  end if;
  set local role authenticated;
  raise notice 'PASS  suspending a client suspends their fleet';
end $$;

do $$
declare st text;
begin
  perform public.hyn_admin_set_user_status('11111111-1111-1111-1111-111111111111', 'active');
  set local role postgres;
  select status into st from public.nodes where id = (select v from t where k = 'node_id')::uuid;
  if st <> 'active' then
    raise exception 'reinstating a client should reinstate their fleet, node is %', st;
  end if;
  set local role authenticated;
  raise notice 'PASS  reinstating a client reinstates their fleet';
end $$;

-- Guard rails on the destructive edges of administration.
do $$
declare ok boolean := false;
begin
  begin
    perform public.hyn_admin_set_user_status(
      '33333333-3333-3333-3333-333333333333', 'suspended', 'oops');
  exception when others then ok := true;
  end;
  if not ok then raise exception 'an admin was allowed to suspend their own account'; end if;
  raise notice 'PASS  an admin cannot suspend themselves';
end $$;

do $$
declare ok boolean := false;
begin
  begin
    perform public.hyn_admin_set_role('33333333-3333-3333-3333-333333333333', 'user');
  exception when others then ok := true;
  end;
  if not ok then raise exception 'the last administrator could be demoted'; end if;
  raise notice 'PASS  the last administrator cannot be demoted';
end $$;

-- ---------------------------------------------------------------------------
-- 15. the audit trail
-- ---------------------------------------------------------------------------
do $$
declare r json; n integer;
begin
  r := public.hyn_admin_audit(100);
  select count(*) into n from json_array_elements(r);
  -- pause, suspend, active, client suspend, client active = 5 recorded actions
  if n < 5 then raise exception 'expected at least 5 audit rows, got %', n; end if;
  if (r#>>'{0,actor_email}') <> 'carol@example.com' then
    raise exception 'audit should name the actor, got %', r#>>'{0,actor_email}';
  end if;
  raise notice 'PASS  every privileged action is attributed in the audit trail (% rows)', n;
end $$;

do $$
declare n integer;
begin
  set local role postgres;
  select count(*) into n from public.admin_audit where action = 'node.status.paused';
  if n <> 1 then raise exception 'the pause was not audited'; end if;
  select count(*) into n from public.admin_audit
   where action = 'client.status.suspended' and target_user = '11111111-1111-1111-1111-111111111111';
  if n <> 1 then raise exception 'the client suspension was not audited'; end if;
  set local role authenticated;
  raise notice 'PASS  pause and client suspension are individually recorded';
end $$;

rollback;
