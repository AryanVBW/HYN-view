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

-- Provider destinations, credentials and routing preferences must remain on
-- each monitored server. A portal table creates a cross-tenant credential
-- boundary that a node token must never be able to cross, so the safe schema
-- has no central notification configuration storage at all.
do $$
begin
  if to_regclass('public.notification_channels') is not null then
    raise exception 'notification_channels still stores central provider credentials';
  end if;
  if to_regclass('public.notify_prefs') is not null then
    raise exception 'notify_prefs still stores central notification routing preferences';
  end if;
  raise notice 'PASS  provider credentials and routing preferences have no central storage';
end $$;

do $$
begin
  if to_regprocedure('public.hyn_list_admins()') is not null then
    raise exception 'the notification-routing administrator directory is still exposed';
  end if;
  raise notice 'PASS  no notification-routing administrator directory is exposed';
end $$;

set local role anon;
set local "test.uid" = '';

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

-- The shorter human code needs a slow, independently salted verifier. A fast
-- deterministic digest leaks which pending rows share a code and makes an
-- offline database dump much cheaper to brute-force.
do $$
declare
  n integer;
  v_code text := (select v from t where k = 'user_code');
  v_verifier text;
begin
  set local role postgres;
  select user_code_verifier into v_verifier
    from public.device_codes
   where user_code_verifier = extensions.crypt(upper(trim(v_code)), user_code_verifier)
   limit 1;

  if v_verifier is null then raise exception 'no salted user-code verifier was stored'; end if;
  if v_verifier !~ '^\$2[abxy]\$10\$[./A-Za-z0-9]{53}$' then
    raise exception 'user-code verifier is not a cost-10 bcrypt value: %', v_verifier;
  end if;
  if v_verifier = encode(extensions.digest(upper(trim(v_code)), 'sha256'), 'hex') then
    raise exception 'user-code verifier is still a deterministic SHA-256 digest';
  end if;
  if v_verifier = extensions.crypt('WRONG-CODE', v_verifier) then
    raise exception 'user-code verifier accepted the wrong code';
  end if;
  select count(*) into n from public.device_codes
   where to_jsonb(device_codes)::text like
         '%' || to_jsonb(v_code)::text || '%';
  if n <> 0 then raise exception 'user_code was stored in plaintext'; end if;
  set local role anon;
  raise notice 'PASS  human pairing code uses a slow salted verifier';
end $$;

-- Expiry is a storage boundary, not only a validation check. Every public
-- pairing entry point invokes cleanup, including for rows that expired less
-- than an hour ago. No wall-clock deletion is claimed between pairing calls.
do $$
declare r json; expired_device_code text; n integer;
begin
  r := public.hyn_device_start('expired-by-start', 'Ubuntu', 'test');
  expired_device_code := r->>'device_code';
  set local role postgres;
  update public.device_codes set expires_at = now() - interval '1 minute'
   where device_code_hash = public._hyn_sha256(expired_device_code);
  set local role anon;
  perform public.hyn_device_start('start-cleanup-trigger', 'Ubuntu', 'test');
  set local role postgres;
  select count(*) into n from public.device_codes
   where device_code_hash = public._hyn_sha256(expired_device_code);
  if n <> 0 then raise exception 'device_start retained an expired pairing row'; end if;
  set local role anon;
  raise notice 'PASS  device_start removes newly expired pairing rows';
end $$;

do $$
declare r json; expired_user_code text; expired_device_code text; n integer;
begin
  r := public.hyn_device_start('expired-by-lookup', 'Ubuntu', 'test');
  expired_user_code := r->>'user_code';
  expired_device_code := r->>'device_code';
  set local role postgres;
  update public.device_codes set expires_at = now() - interval '1 minute'
   where device_code_hash = public._hyn_sha256(expired_device_code);
  set local role authenticated;
  perform set_config('test.uid', '11111111-1111-1111-1111-111111111111', true);
  r := public.hyn_device_lookup(expired_user_code);
  if r->>'status' <> 'expired' then raise exception 'lookup: expected expired, got %', r->>'status'; end if;
  set local role postgres;
  select count(*) into n from public.device_codes
   where device_code_hash = public._hyn_sha256(expired_device_code);
  if n <> 0 then raise exception 'device_lookup retained its expired pairing row'; end if;
  set local role anon;
  perform set_config('test.uid', '', true);
  raise notice 'PASS  device_lookup reports and removes an expired pairing row';
end $$;

do $$
declare r json; expired_user_code text; expired_device_code text; n integer;
begin
  r := public.hyn_device_start('expired-by-approve', 'Ubuntu', 'test');
  expired_user_code := r->>'user_code';
  expired_device_code := r->>'device_code';
  set local role postgres;
  update public.device_codes set expires_at = now() - interval '1 minute'
   where device_code_hash = public._hyn_sha256(expired_device_code);
  set local role authenticated;
  perform set_config('test.uid', '11111111-1111-1111-1111-111111111111', true);
  r := public.hyn_device_approve(expired_user_code, 'must-not-exist');
  if r->>'status' <> 'expired' then raise exception 'approve: expected expired, got %', r->>'status'; end if;
  set local role postgres;
  select count(*) into n from public.device_codes
   where device_code_hash = public._hyn_sha256(expired_device_code);
  if n <> 0 then raise exception 'device_approve retained its expired pairing row'; end if;
  if exists (select 1 from public.nodes where name = 'must-not-exist') then
    raise exception 'device_approve created a node from an expired code';
  end if;
  set local role anon;
  perform set_config('test.uid', '', true);
  raise notice 'PASS  device_approve reports and removes an expired pairing row';
end $$;

do $$
declare r json; expired_device_code text; n integer;
begin
  r := public.hyn_device_start('expired-by-poll', 'Ubuntu', 'test');
  expired_device_code := r->>'device_code';
  set local role postgres;
  update public.device_codes set expires_at = now() - interval '1 minute'
   where device_code_hash = public._hyn_sha256(expired_device_code);
  set local role anon;
  r := public.hyn_device_poll(expired_device_code);
  if r->>'status' <> 'expired' then raise exception 'poll: expected expired, got %', r->>'status'; end if;
  set local role postgres;
  select count(*) into n from public.device_codes
   where device_code_hash = public._hyn_sha256(expired_device_code);
  if n <> 0 then raise exception 'device_poll retained its expired pairing row'; end if;
  set local role anon;
  raise notice 'PASS  device_poll reports and removes an expired pairing row';
end $$;

-- Approval creates the portal node before the agent claims its one-time token.
-- If that final poll never arrives before expiry, cleanup must also remove the
-- unusable node; otherwise the account accumulates a node it can never connect.
do $$
declare r json; expired_user_code text; expired_device_code text; orphan_node_id uuid; n integer;
begin
  set local role anon;
  perform set_config('test.uid', '', true);
  r := public.hyn_device_start('expires-after-approval', 'Ubuntu', 'test');
  expired_user_code := r->>'user_code';
  expired_device_code := r->>'device_code';

  set local role authenticated;
  perform set_config('test.uid', '11111111-1111-1111-1111-111111111111', true);
  r := public.hyn_device_approve(expired_user_code, 'unclaimed-expired-node');
  orphan_node_id := (r->>'node_id')::uuid;

  set local role postgres;
  update public.device_codes set expires_at = now() - interval '1 minute'
   where device_code_hash = public._hyn_sha256(expired_device_code);

  set local role anon;
  perform set_config('test.uid', '', true);
  r := public.hyn_device_poll(expired_device_code);
  if r->>'status' <> 'expired' then
    raise exception 'unclaimed poll: expected expired, got %', r->>'status';
  end if;

  set local role postgres;
  select count(*) into n from public.nodes where id = orphan_node_id;
  if n <> 0 then raise exception 'expiry cleanup retained an unclaimable node'; end if;
  set local role anon;
  raise notice 'PASS  expiry cleanup removes an approved but unclaimed node';
end $$;

-- Once the agent has claimed its token, only the pairing row is temporary. A
-- later expiry cleanup must not delete the now-usable monitored node.
do $$
declare
  r json;
  claimed_user_code text;
  claimed_device_code text;
  claimed_node_id uuid;
  claimed_node_token text;
  n integer;
begin
  set local role anon;
  perform set_config('test.uid', '', true);
  r := public.hyn_device_start('claimed-before-expiry', 'Ubuntu', 'test');
  claimed_user_code := r->>'user_code';
  claimed_device_code := r->>'device_code';

  set local role authenticated;
  perform set_config('test.uid', '11111111-1111-1111-1111-111111111111', true);
  r := public.hyn_device_approve(claimed_user_code, 'claimed-node-survives');
  claimed_node_id := (r->>'node_id')::uuid;

  set local role anon;
  perform set_config('test.uid', '', true);
  r := public.hyn_device_poll(claimed_device_code);
  claimed_node_token := r->>'node_token';

  set local role postgres;
  update public.device_codes set expires_at = now() - interval '1 minute'
   where device_code_hash = public._hyn_sha256(claimed_device_code);

  set local role anon;
  perform public.hyn_device_start('claimed-cleanup-trigger', 'Ubuntu', 'test');

  set local role postgres;
  select count(*) into n from public.device_codes
   where device_code_hash = public._hyn_sha256(claimed_device_code);
  if n <> 0 then raise exception 'claimed pairing row survived expiry cleanup'; end if;

  select count(*) into n from public.nodes
   where id = claimed_node_id
     and token_hash = public._hyn_sha256(claimed_node_token);
  if n <> 1 then raise exception 'expiry cleanup removed or changed a claimed node'; end if;

  delete from public.nodes where id = claimed_node_id;
  set local role anon;
  raise notice 'PASS  expiry cleanup preserves a claimed node';
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

do $$
declare first_claim json; second_claim json;
begin
  first_claim := public.hyn_claim_device_linked_email((select v from t where k = 'node_id')::uuid);
  if first_claim->>'status' <> 'send' or first_claim->>'recipient' <> 'alice@example.com' then
    raise exception 'device-link email was not claimable by its owner: %', first_claim;
  end if;
  second_claim := public.hyn_claim_device_linked_email((select v from t where k = 'node_id')::uuid);
  if second_claim->>'status' <> 'skip' then
    raise exception 'device-link email could be claimed twice: %', second_claim;
  end if;
  raise notice 'PASS  device-link email is owner-scoped and idempotent';
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
-- 4b. an owner queues one observable update; only that node may execute it
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "test.uid" = '11111111-1111-1111-1111-111111111111';

do $$
declare first_request json; repeated_request json;
begin
  first_request := public.hyn_request_node_update((select v from t where k = 'node_id')::uuid);
  if first_request->>'status' <> 'queued' or first_request->>'created' <> 'true' then
    raise exception 'owner update request was not queued: %', first_request;
  end if;
  insert into t values ('command_id', first_request->>'id');
  repeated_request := public.hyn_request_node_update((select v from t where k = 'node_id')::uuid);
  if repeated_request->>'id' <> first_request->>'id'
     or repeated_request->>'created' <> 'false' then
    raise exception 'active update request was duplicated: % / %', first_request, repeated_request;
  end if;
  raise notice 'PASS  owner update requests are queued idempotently';
end $$;

set local "test.uid" = '22222222-2222-2222-2222-222222222222';
do $$
declare refused boolean := false;
begin
  begin
    perform public.hyn_request_node_update((select v from t where k = 'node_id')::uuid);
  exception when others then refused := true;
  end;
  if not refused then raise exception 'another owner queued an update for alice''s node'; end if;
  if exists (select 1 from public.node_commands) then
    raise exception 'another owner could read alice''s update progress';
  end if;
  raise notice 'PASS  update requests and progress are owner-scoped';
end $$;

set local role anon;
set local "test.uid" = '';
do $$
declare r json; refused boolean := false;
begin
  begin
    perform public.hyn_claim_node_command('wrong-node-token');
  exception when others then refused := true;
  end;
  if not refused then raise exception 'an invalid node token claimed a command'; end if;

  r := public.hyn_claim_node_command((select v from t where k = 'node_token'));
  if r->>'status' <> 'command' or r->>'action' <> 'update'
     or r->>'id' <> (select v from t where k = 'command_id') then
    raise exception 'the linked node did not claim its update: %', r;
  end if;
  perform public.hyn_report_node_command(
    (select v from t where k = 'node_token'),
    (select v from t where k = 'command_id')::uuid,
    'running', 'installing', 'Installing hyn-view 1.7.0', '1.7.0', null
  );
  r := public.hyn_report_node_command(
    (select v from t where k = 'node_token'),
    (select v from t where k = 'command_id')::uuid,
    'succeeded', 'completed', 'Updated and verified hyn-view 1.7.0', '1.7.0', '1.7.0'
  );
  if r->>'status' <> 'succeeded' or r->>'stage' <> 'completed' then
    raise exception 'node completion was not recorded: %', r;
  end if;
  raise notice 'PASS  a node claims and reports every update lifecycle state';
end $$;

set local role authenticated;
set local "test.uid" = '11111111-1111-1111-1111-111111111111';
do $$
declare n integer; v_status text; v_version text;
begin
  select count(*), max(status), max(result_version)
    into n, v_status, v_version from public.node_commands;
  if n <> 1 or v_status <> 'succeeded' or v_version <> '1.7.0' then
    raise exception 'owner cannot observe completed update: %, %, %', n, v_status, v_version;
  end if;
  raise notice 'PASS  the owner can observe completed update progress';
end $$;

set local role anon;
set local "test.uid" = '';

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

do $$
declare v_config jsonb;
begin
  select config into v_config from public.nodes
   where id = (select v from t where k = 'node_id')::uuid;
  if v_config->>'auto_update' is distinct from 'install' then
    raise exception 'new nodes do not default to automatic updates: %', v_config;
  end if;
  if v_config->>'cloud_push_min' is distinct from '10' then
    raise exception 'new nodes do not default to ten-minute telemetry: %', v_config;
  end if;
  raise notice 'PASS  every newly linked node receives managed sync defaults';
end $$;

update public.nodes
   set config = '{"alert_mem_pct": 80, "report_at": "07:30"}'::jsonb
 where id = (select v from t where k = 'node_id')::uuid;

-- A browser may call PostgREST directly, so the database must reject every
-- config key the account settings UI does not expose. UI filtering alone would
-- still let an owner smuggle a webhook or other destination to the node.
set local role authenticated;
set local "test.uid" = '11111111-1111-1111-1111-111111111111';

do $$
declare rejected boolean := false;
begin
  begin
    update public.nodes
       set config = config || '{"webhook_url":"https://attacker.example/hook"}'::jsonb
     where id = (select v from t where k = 'node_id')::uuid;
  exception when check_violation then
    rejected := true;
  end;
  if not rejected then
    raise exception 'direct API update stored a local-only notification destination';
  end if;
  raise notice 'PASS  direct API updates reject config keys outside the portal allowlist';
end $$;

-- The first successful reading queues exactly one detailed system email. The
-- route claims it using the same node credential that just passed ingest; no
-- service-role key or cross-tenant browser read is needed.
do $$
declare first_claim json; second_claim json;
begin
  set local role anon;
  first_claim := public.hyn_claim_first_telemetry_email(
    (select v from t where k = 'node_token'), '203.0.113.10'
  );
  if first_claim->>'status' <> 'send' then
    raise exception 'first telemetry email was not claimable: %', first_claim;
  end if;
  if first_claim->>'recipient' <> 'alice@example.com' then
    raise exception 'first telemetry email has the wrong recipient: %', first_claim;
  end if;
  if first_claim#>>'{payload,network,public_ip}' <> '203.0.113.10' then
    raise exception 'first telemetry email omitted the observed public IP: %', first_claim;
  end if;
  second_claim := public.hyn_claim_first_telemetry_email(
    (select v from t where k = 'node_token'), '203.0.113.10'
  );
  if second_claim->>'status' <> 'skip' then
    raise exception 'first telemetry email could be claimed twice: %', second_claim;
  end if;
  set local role authenticated;
  set local "test.uid" = '11111111-1111-1111-1111-111111111111';
  raise notice 'PASS  first telemetry email is complete and idempotent';
end $$;

-- Allowed key names are not enough: alert values are later consumed by Bash
-- arithmetic in a root-run service. Reject command substitutions, malformed
-- enums/times, wrong JSON types and out-of-range values at the database edge.
do $$
declare
  candidate jsonb;
  rejected boolean;
begin
  foreach candidate in array array[
    '{"alert_disk_pct":"x[$(touch${IFS}/tmp/hyn-view-rce)]"}'::jsonb,
    '{"alert_disk_pct":"08"}'::jsonb,
    '{"alert_mem_pct":"101"}'::jsonb,
    '{"alert_latency_ms":{}}'::jsonb,
    '{"alert_min_severity":"root"}'::jsonb,
    '{"auto_update":"surprise"}'::jsonb,
    '{"dashboard_view":"fancy"}'::jsonb,
    '{"report_at":"99:99"}'::jsonb,
    '{"cloud_push_min":"0"}'::jsonb
  ] loop
    rejected := false;
    begin
      update public.nodes
         set config = candidate
       where id = (select v from t where k = 'node_id')::uuid;
    exception when check_violation then
      rejected := true;
    end;
    if not rejected then
      raise exception 'direct API accepted unsafe config value: %', candidate;
    end if;
  end loop;
  raise notice 'PASS  direct API rejects unsafe portal-config values';
end $$;

update public.nodes
   set config = '{
     "alert_mem_pct":"80", "alert_disk_pct":"85", "alert_temp_c":"75",
     "alert_load_per_core":"400", "alert_latency_ms":"250",
     "alert_min_severity":"warn", "alert_repeat_hours":"6",
     "report_at":"07:30", "notify_max_per_day":"25", "cloud_push_min":"5",
     "auto_update":"install", "dashboard_view":"simple"
   }'::jsonb
 where id = (select v from t where k = 'node_id')::uuid;

do $$
declare n integer;
begin
  select count(*) into n
    from public.nodes nrow,
         lateral jsonb_object_keys(nrow.config)
   where nrow.id = (select v from t where k = 'node_id')::uuid;
  if n <> 12 then raise exception 'portal allowlist rejected a supported setting'; end if;
  raise notice 'PASS  every portal-exposed monitoring setting remains writable';
end $$;

do $$
declare n integer; pref public.email_preferences;
begin
  select count(*) into n from public.email_preferences;
  if n <> 1 then raise exception 'pairing should create one default email schedule, saw %', n; end if;
  -- Incident mail is opt-in; the two digests are not. A machine that pairs itself
  -- must not start mailing an account that never asked to be mailed -- and this is
  -- the assertion, because the flood that prompted it (4501 failed attempts in a
  -- day) came from a column default, not from anybody's choice.
  select * into pref from public.email_preferences;
  if pref.incident_enabled then
    raise exception 'a newly paired machine defaults to sending incident alert email';
  end if;
  if not pref.daily_enabled or not pref.system_enabled then
    raise exception 'the daily digests lost their default with the incident change';
  end if;
  update public.email_preferences set timezone = 'Asia/Kolkata', daily_at = '08:30';
  if not found then raise exception 'the node owner could not update their email schedule'; end if;
  set local "test.uid" = '22222222-2222-2222-2222-222222222222';
  select count(*) into n from public.email_preferences;
  if n <> 0 then raise exception 'another client can read Alice''s email schedule'; end if;
  set local "test.uid" = '11111111-1111-1111-1111-111111111111';
  raise notice 'PASS  cloud email timing is defaulted and tenant-private, and incident mail is opt-in';
end $$;

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
  if r::jsonb ? 'channels' then
    raise exception 'config pull exposed a central notification channel surface: %', r->'channels';
  end if;
  if convert_from(decode(r->>'alert_template_b64', 'base64'), 'UTF8') <> '{{content}}'
     or convert_from(decode(r->>'report_template_b64', 'base64'), 'UTF8') <> '{{content}}' then
    raise exception 'config pull did not include the installed presentation templates: %', r;
  end if;
  raise notice 'PASS  the agent pulls settings without notification targets or credentials';
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
declare seen timestamptz; heartbeat timestamptz;
begin
  set local role postgres;
  select last_config_pull_at, last_heartbeat_at into seen, heartbeat from public.nodes
   where id = (select v from t where k = 'node_id')::uuid;
  if seen is null then raise exception 'last_config_pull_at was not recorded'; end if;
  if heartbeat is null or heartbeat < now() - interval '5 seconds' then
    raise exception 'last_heartbeat_at was not recorded by config pull: %', heartbeat;
  end if;
  set local role anon;
  raise notice 'PASS  a config pull records a durable machine heartbeat';
end $$;

-- The resident agent's beat. Cheap by construction: it must write the heartbeat
-- and nothing else, because at one call every 24 seconds anything it does extra
-- is multiplied across the whole fleet.
do $$
declare
  r json;
  before_pull timestamptz;
  after_pull timestamptz;
  before_seen timestamptz;
  after_seen timestamptz;
  beat timestamptz;
begin
  set local role postgres;
  update public.nodes
     set last_heartbeat_at = now() - interval '10 minutes',
         last_config_pull_at = now() - interval '10 minutes',
         last_seen_at = now() - interval '10 minutes'
   where id = (select v from t where k = 'node_id')::uuid;
  select last_config_pull_at, last_seen_at into before_pull, before_seen
    from public.nodes where id = (select v from t where k = 'node_id')::uuid;
  set local role anon;

  r := public.hyn_heartbeat((select v from t where k = 'node_token'), '9.9.9');
  if r->>'status' <> 'ok' then raise exception 'heartbeat was refused: %', r; end if;
  if r->>'node_status' <> 'active' then
    raise exception 'heartbeat did not report the node status: %', r;
  end if;
  -- The agent has no use for a config here and the portal should not pay to
  -- build one. If these ever appear, the beat has become the expensive call it
  -- was created to avoid.
  if r::jsonb ? 'config' or r::jsonb ? 'alert_template_b64' then
    raise exception 'the heartbeat returned settings it does not need: %', r;
  end if;

  set local role postgres;
  select last_heartbeat_at, last_config_pull_at, last_seen_at
    into beat, after_pull, after_seen
    from public.nodes where id = (select v from t where k = 'node_id')::uuid;
  if beat is null or beat < now() - interval '5 seconds' then
    raise exception 'the heartbeat did not record a beat: %', beat;
  end if;
  -- last_seen_at means "last sent a reading" and last_config_pull_at means "last
  -- fetched settings". A beat is neither, and portal views distinguish a machine
  -- that is reachable from one that is actually reporting.
  if after_pull <> before_pull then
    raise exception 'the heartbeat pretended to be a settings pull';
  end if;
  if after_seen <> before_seen then
    raise exception 'the heartbeat pretended to be a telemetry reading';
  end if;
  if (select agent_version from public.nodes
       where id = (select v from t where k = 'node_id')::uuid) <> '9.9.9' then
    raise exception 'the heartbeat did not record the reported agent version';
  end if;
  -- Put the paired version back. The admin overview picks its staleness rule from
  -- agent_version, and a later test in this file depends on this node still being
  -- on the pre-heartbeat 1.4.0 branch.
  update public.nodes set agent_version = '1.4.0'
   where id = (select v from t where k = 'node_id')::uuid;
  set local role anon;
  raise notice 'PASS  a heartbeat records liveness without touching telemetry or settings state';
end $$;

do $$
declare ok boolean := false;
begin
  begin
    perform public.hyn_heartbeat('not-a-real-token');
  exception when others then ok := true;
  end;
  if not ok then raise exception 'the heartbeat accepted an unknown token'; end if;
  raise notice 'PASS  the heartbeat rejects an unknown token';
end $$;

-- A timed pause must be able to end on a beat alone. On a machine whose only
-- traffic is beats, waiting for the next settings pull would leave the pause in
-- place for longer than the administrator asked for.
do $$
declare r json;
begin
  set local role postgres;
  update public.nodes
     set status = 'paused', paused_until = now() - interval '1 minute',
         status_reason = 'maintenance window'
   where id = (select v from t where k = 'node_id')::uuid;
  set local role anon;
  r := public.hyn_heartbeat((select v from t where k = 'node_token'));
  if r->>'node_status' <> 'active' then
    raise exception 'an expired pause did not resume on a heartbeat: %', r;
  end if;
  raise notice 'PASS  an expired pause resumes on a heartbeat, not only on a settings pull';
end $$;

do $$
declare ok boolean := false;
begin
  set local role postgres;
  update public.nodes set revoked = true
   where id = (select v from t where k = 'node_id')::uuid;
  set local role anon;
  begin
    perform public.hyn_heartbeat((select v from t where k = 'node_token'));
  exception when others then ok := true;
  end;
  if not ok then raise exception 'a revoked node was still allowed to beat'; end if;
  set local role postgres;
  update public.nodes set revoked = false
   where id = (select v from t where k = 'node_id')::uuid;
  set local role anon;
  raise notice 'PASS  a revoked node cannot beat';
end $$;

do $$
declare r json;
begin
  set local role postgres;
  update public.node_watchdogs
     set state = 'running', run_id = 'abandoned-run', updated_at = now() - interval '6 minutes'
   where node_id = (select v from t where k = 'node_id')::uuid;
  set local role anon;
  r := public.hyn_claim_node_watchdog((select v from t where k = 'node_token'));
  if r->>'created' <> 'true' or r->>'state' <> 'starting' then
    raise exception 'stale running watchdog was not reclaimed: %', r;
  end if;
  raise notice 'PASS  a crashed heartbeat watchdog is reclaimed on the next check-in';
end $$;

do $$
declare
  first_request json;
  repeated_request json;
  queued json;
  rejected boolean := false;
begin
  set local role authenticated;
  perform set_config('test.uid', '11111111-1111-1111-1111-111111111111', true);
  first_request := public.hyn_request_node_command(
    (select v from t where k = 'node_id')::uuid, 'sync'
  );
  repeated_request := public.hyn_request_node_command(
    (select v from t where k = 'node_id')::uuid, 'sync'
  );
  if first_request->>'action' <> 'sync'
     or first_request->>'created' <> 'true'
     or repeated_request->>'id' <> first_request->>'id'
     or repeated_request->>'created' <> 'false' then
    raise exception 'sync commands were not owner-scoped and idempotent: % / %',
      first_request, repeated_request;
  end if;

  perform set_config('test.uid', '22222222-2222-2222-2222-222222222222', true);
  begin
    perform public.hyn_request_node_command(
      (select v from t where k = 'node_id')::uuid, 'sync'
    );
  exception when others then rejected := true;
  end;
  if not rejected then raise exception 'Bob queued a sync for Alice''s node'; end if;

  set local role postgres;
  update public.profiles set role = 'admin'
   where id = '22222222-2222-2222-2222-222222222222';
  set local role authenticated;
  perform set_config('test.uid', '22222222-2222-2222-2222-222222222222', true);
  queued := public.hyn_admin_request_node_command(
    (select v from t where k = 'node_id')::uuid, 'sync'
  );
  if queued->>'id' <> first_request->>'id' or queued->>'created' <> 'false' then
    raise exception 'admin request duplicated an active sync: %', queued;
  end if;

  set local role postgres;
  if not exists (
    select 1 from public.admin_audit
     where actor = '22222222-2222-2222-2222-222222222222'
       and target_node = (select v from t where k = 'node_id')::uuid
       and action = 'node.command.sync'
  ) then raise exception 'admin sync request was not audited'; end if;
  -- Keep the pre-existing control-plane audit ordering assertions isolated;
  -- this row has already proved the command action was persisted correctly.
  delete from public.admin_audit
   where actor = '22222222-2222-2222-2222-222222222222'
     and target_node = (select v from t where k = 'node_id')::uuid
     and action = 'node.command.sync';
  update public.profiles set role = 'user'
   where id = '22222222-2222-2222-2222-222222222222';
  set local role anon;
  perform set_config('test.uid', '', true);
  insert into t values ('sync_command_id', first_request->>'id');
  raise notice 'PASS  owner/admin sync requests are isolated, deduplicated, and audited';
end $$;

do $$
declare r json;
begin
  r := public.hyn_claim_node_command((select v from t where k = 'node_token'));
  if r->>'action' <> 'sync' or r->>'id' <> (select v from t where k = 'sync_command_id') then
    raise exception 'linked node did not claim its sync: %', r;
  end if;
  perform public.hyn_report_node_command(
    (select v from t where k = 'node_token'),
    (select v from t where k = 'sync_command_id')::uuid,
    'running', 'collecting', 'Collecting a complete system snapshot', null, null
  );
  perform public.hyn_report_node_command(
    (select v from t where k = 'node_token'),
    (select v from t where k = 'sync_command_id')::uuid,
    'running', 'uploading', 'Uploading current telemetry to HYN-view', null, null
  );
  r := public.hyn_report_node_command(
    (select v from t where k = 'node_token'),
    (select v from t where k = 'sync_command_id')::uuid,
    'succeeded', 'completed', 'Synchronization verified', null, null
  );
  if r->>'status' <> 'succeeded' then raise exception 'sync completion failed: %', r; end if;
  raise notice 'PASS  a node reports the full sync lifecycle';
end $$;

do $$
declare r json; duplicate json; rejected boolean := false; n integer;
begin
  begin
    perform public.hyn_queue_web_notification(
      (select v from t where k = 'node_token'),
      '{"fingerprint":"recipient-injection","category":"alert","severity":"warn","subject":"Injected","text_body":"No","recipient":"attacker@example.com"}'::jsonb
    );
  exception when others then rejected := true;
  end;
  if not rejected then raise exception 'web alert accepted a CLI-selected recipient'; end if;

  r := public.hyn_queue_web_notification(
    (select v from t where k = 'node_token'),
    '{"fingerprint":"disk:warn:86","category":"alert","severity":"warn","subject":"Disk warning","text_body":"Disk usage is 86%"}'::jsonb
  );
  duplicate := public.hyn_queue_web_notification(
    (select v from t where k = 'node_token'),
    '{"fingerprint":"disk:warn:86","category":"alert","severity":"warn","subject":"Disk warning","text_body":"Disk usage is 86%"}'::jsonb
  );
  if r->>'id' is null or duplicate->>'id' <> r->>'id'
     or duplicate->>'created' <> 'false' then
    raise exception 'web alert was not durable and idempotent: % / %', r, duplicate;
  end if;
  set local role postgres;
  select count(*) into n from public.web_notification_jobs
   where node_id = (select v from t where k = 'node_id')::uuid;
  if n <> 1 then raise exception 'expected one durable web alert, saw %', n; end if;
  set local role anon;
  raise notice 'PASS  web alerts are durable, idempotent, and cannot choose recipients';
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
    'select public.hyn_admin_audit(10)',
    'select public.hyn_admin_templates()',
    'select public.hyn_admin_save_template(''alert'', ''{{content}}'')',
    'select public.hyn_admin_clear_notifications(null::timestamptz, ''mischief'')',
    'select public.hyn_admin_set_node_config(''' || (select v from t where k = 'node_id') || '''::uuid, ''{"dashboard_view":"simple"}''::jsonb)'
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
    perform 1 from public.notification_templates;
  exception when insufficient_privilege then ok := true;
  end;
  if not ok then raise exception 'a browser session could read notification template storage directly'; end if;
  raise notice 'PASS  template storage is reachable only through admin-checked RPCs';
end $$;

-- The internals are not an API, and "not an API" has to mean unreachable rather
-- than undocumented. Every one of them carries `revoke all ... from public`, which
-- is sufficient on plain PostgreSQL and does nothing on Supabase: the project
-- grants EXECUTE on new functions to anon and authenticated by name. Measured on
-- the live project before this was fixed, `POST /rest/v1/rpc/_hyn_audit` with the
-- public anon key returned 204 and inserted a row into the audit trail. The
-- harness now sets those same default privileges, so this check fails the way
-- production would rather than passing because the test cluster was stricter.
do $$
declare r record; leaked text := '';
begin
  for r in
    select p.oid::regprocedure::text as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like '\_hyn\_%'
     order by 1
  loop
    -- Backs a CHECK constraint on public.nodes, which is evaluated as the role
    -- doing the write, so authenticated must keep EXECUTE on this one.
    if r.proname = '_hyn_portal_config_valid' then continue; end if;
    if has_function_privilege('anon', r.sig, 'execute')
       or has_function_privilege('authenticated', r.sig, 'execute') then
      leaked := leaked || ' ' || r.sig;
    end if;
  end loop;
  if leaked <> '' then
    raise exception 'internal helpers are callable from a browser session:%', leaked;
  end if;
  raise notice 'PASS  the internal helpers are unreachable from anon and authenticated';
end $$;

-- The specific one that mattered: a forged audit entry is worse than none, since
-- the whole point of the table is that it can be believed afterwards.
do $$
declare ok boolean := false; n bigint;
begin
  set local role anon;
  begin
    perform public._hyn_audit('forged.by.anon', null, null, '{}'::jsonb);
  exception when insufficient_privilege then ok := true;
  end;
  set local role postgres;
  select count(*) into n from public.admin_audit where action = 'forged.by.anon';
  set local role authenticated;
  if not ok or n <> 0 then
    raise exception 'anon wrote % row(s) into the audit trail', n;
  end if;
  raise notice 'PASS  anon cannot forge an audit entry';
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
             last_seen_at, status, paused_until, status_reason, config,
             last_config_pull_at, last_heartbeat_at
        from public.nodes) t;
  exception when insufficient_privilege then
    raise exception 'the portal node columns are not all readable by authenticated';
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
  set local role postgres;
  update public.nodes
     set last_seen_at = now() - interval '25 minutes',
         config = config || '{"cloud_push_min":"10"}'::jsonb
   where id = (select v from t where k = 'node_id')::uuid;
  set local role authenticated;
  set local "test.uid" = '33333333-3333-3333-3333-333333333333';
  r := public.hyn_admin_overview();
  if (r->>'nodes_stale')::int <> 0 then
    raise exception 'ten-minute node was marked quiet before three missed reports: %', r;
  end if;
  set local role postgres;
  update public.nodes set last_seen_at = now() - interval '31 minutes'
   where id = (select v from t where k = 'node_id')::uuid;
  set local role authenticated;
  set local "test.uid" = '33333333-3333-3333-3333-333333333333';
  r := public.hyn_admin_overview();
  if (r->>'nodes_stale')::int <> 1 then
    raise exception 'ten-minute node stayed reporting after three missed reports: %', r;
  end if;
  set local role postgres;
  update public.nodes set last_seen_at = now() where id = (select v from t where k = 'node_id')::uuid;
  set local role authenticated;
  set local "test.uid" = '33333333-3333-3333-3333-333333333333';
  raise notice 'PASS  fleet quiet status follows each node reporting interval';
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

do $$
declare r json; pulled json; rendered text; rejected boolean;
begin
  r := public.hyn_admin_templates();
  if json_array_length(r) <> 3 then
    raise exception 'admin template list should contain alert, report and system wrappers: %', r;
  end if;

  r := public.hyn_admin_save_template(
    'alert',
    '<section data-template="alert">{{content}}</section>'
  );
  if r->>'status' <> 'ok' then raise exception 'template save failed: %', r; end if;

  rejected := false;
  begin
    perform public.hyn_admin_save_template('report', '<script>alert(1)</script>{{content}}');
  exception when others then rejected := true;
  end;
  if not rejected then raise exception 'active HTML was accepted as an email template'; end if;

  rejected := false;
  begin
    perform public.hyn_admin_save_template('report', '<p>missing placeholder</p>');
  exception when others then rejected := true;
  end;
  if not rejected then raise exception 'a template without {{content}} was accepted'; end if;

  set local role anon;
  pulled := public.hyn_fetch_config((select v from t where k = 'node_token'));
  rendered := convert_from(decode(pulled->>'alert_template_b64', 'base64'), 'UTF8');
  if rendered <> '<section data-template="alert">{{content}}</section>' then
    raise exception 'saved template did not reach the node config pull: %', rendered;
  end if;
  set local role authenticated;
  raise notice 'PASS  an admin template edit reaches the node without centralising delivery credentials';
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

do $$
declare nodes json; overview json; machine jsonb;
begin
  set local role postgres;
  update public.nodes
     set agent_version = '1.7.0', last_seen_at = now(),
         last_heartbeat_at = now() - interval '4 minutes'
   where id = (select v from t where k = 'node_id')::uuid;
  update public.metrics
     set payload = coalesce(payload, '{}'::jsonb)
       || '{"agent_update":{"latest":"1.8.0","available":true}}'::jsonb
   where id = (select max(id) from public.metrics where node_id = (select v from t where k = 'node_id')::uuid);
  set local role authenticated;
  nodes := public.hyn_admin_nodes();
  select value into machine from jsonb_array_elements(nodes::jsonb)
   where value->>'id' = (select v from t where k = 'node_id');
  if machine->>'last_heartbeat_at' is null
     or machine->>'latest_agent_version' <> '1.8.0'
     or machine->>'update_available' <> 'true' then
    raise exception 'admin machine snapshot omitted heartbeat or update state: %', machine;
  end if;
  overview := public.hyn_admin_overview();
  if (overview->>'nodes_stale')::integer <> 1 then
    raise exception 'heartbeat-capable node should be quiet after three misses: %', overview;
  end if;

  set local role postgres;
  update public.nodes set agent_version = '1.6.0'
   where id = (select v from t where k = 'node_id')::uuid;
  set local role authenticated;
  overview := public.hyn_admin_overview();
  if (overview->>'nodes_stale')::integer <> 0 then
    raise exception 'pre-heartbeat node ignored its configured telemetry interval: %', overview;
  end if;
  raise notice 'PASS  admin freshness and version controls remain accurate during the 1.7 rollout';
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

-- An administrator sets a client's node config through the same allowlist a
-- client uses for their own -- dashboard_view is the setting under test, but
-- the point is that the admin entry point enforces the identical bound rather
-- than a looser one, since an admin console is not a bigger trust boundary.
do $$
declare r json;
begin
  r := public.hyn_admin_set_node_config(
    (select v from t where k = 'node_id')::uuid, '{"dashboard_view":"simple"}'::jsonb);
  if r->>'status' <> 'ok' then raise exception 'admin config set failed: %', r; end if;
  if (r->'config')->>'dashboard_view' <> 'simple' then
    raise exception 'dashboard_view did not persist: %', r;
  end if;
  raise notice 'PASS  an admin can set a client node''s dashboard view';
end $$;

do $$
declare ok boolean := false;
begin
  begin
    perform public.hyn_admin_set_node_config(
      (select v from t where k = 'node_id')::uuid, '{"dashboard_view":"not-a-real-mode"}'::jsonb);
  exception when others then ok := true;
  end;
  if not ok then raise exception 'the admin config RPC accepted an out-of-band dashboard_view value'; end if;
  raise notice 'PASS  the admin config RPC enforces the same value bounds as the client one';
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

-- ---------------------------------------------------------------------------
-- 16. deleting a machine, including one that never linked
-- ---------------------------------------------------------------------------
-- The phantom this exists for: approving a pairing code creates the node row
-- immediately, so a client who never finishes `sudo hyn link` keeps a machine on
-- their dashboard for ever. Pause, suspend and revoke all leave the row in
-- place, which is why "never linked" has to be visible and deletable.
do $$
declare v_phantom uuid; machine jsonb; client jsonb;
begin
  set local role postgres;
  insert into public.nodes (owner, name, hostname, token_hash)
  values ('11111111-1111-1111-1111-111111111111', 'approved-never-linked', 'ghost',
          public._hyn_sha256('phantom-node-token'))
  returning id into v_phantom;
  insert into public.device_codes (user_code_verifier, device_code_hash, hostname, node_id, expires_at)
  values ('unused', public._hyn_sha256('phantom-device-code'), 'ghost', v_phantom,
          now() + interval '10 minutes');
  insert into t (k, v) values ('phantom_id', v_phantom::text);

  set local role authenticated;
  set local "test.uid" = '33333333-3333-3333-3333-333333333333';
  select value into machine from jsonb_array_elements(public.hyn_admin_nodes()::jsonb)
   where value->>'id' = v_phantom::text;
  if machine->>'ever_connected' <> 'false' then
    raise exception 'a node whose agent never checked in should not read as connected: %', machine;
  end if;
  select value into client from jsonb_array_elements(public.hyn_admin_clients()::jsonb)
   where value->>'id' = '11111111-1111-1111-1111-111111111111';
  if (client->>'nodes_unlinked')::int <> 1 then
    raise exception 'the client fleet count should show one never-linked machine: %', client;
  end if;
  raise notice 'PASS  a machine that was approved but never linked is reported as such';
end $$;

do $$
declare ok boolean := false;
begin
  set local "test.uid" = '22222222-2222-2222-2222-222222222222';
  begin
    perform public.hyn_admin_delete_node((select v from t where k = 'phantom_id')::uuid, 'mischief');
  exception when others then ok := true;
  end;
  if not ok then raise exception 'a non-admin could delete another client''s machine'; end if;
  set local role postgres;
  if not exists (select 1 from public.nodes where id = (select v from t where k = 'phantom_id')::uuid) then
    raise exception 'the machine was deleted by a non-admin';
  end if;
  set local role authenticated;
  raise notice 'PASS  a non-admin cannot delete a machine';
end $$;

do $$
declare r json; n integer; client jsonb;
begin
  set local "test.uid" = '33333333-3333-3333-3333-333333333333';
  r := public.hyn_admin_delete_node((select v from t where k = 'phantom_id')::uuid, 'never linked');
  if r->>'status' <> 'ok' then raise exception 'delete returned %', r; end if;

  set local role postgres;
  select count(*) into n from public.nodes where id = (select v from t where k = 'phantom_id')::uuid;
  if n <> 0 then raise exception 'the machine survived its deletion'; end if;
  -- A pairing row left pointing at nothing reads as 'pending' to an agent still
  -- polling, so it goes with the node rather than waiting for expiry.
  select count(*) into n from public.device_codes
   where device_code_hash = public._hyn_sha256('phantom-device-code');
  if n <> 0 then raise exception 'the unclaimed pairing row outlived its node'; end if;
  select count(*) into n from public.admin_audit
   where action = 'node.delete' and detail->>'name' = 'approved-never-linked'
     and detail->>'ever_connected' = 'false' and detail->>'reason' = 'never linked';
  if n <> 1 then raise exception 'the deletion was not attributed in the audit trail'; end if;

  set local role authenticated;
  select value into client from jsonb_array_elements(public.hyn_admin_clients()::jsonb)
   where value->>'id' = '11111111-1111-1111-1111-111111111111';
  if (client->>'nodes_unlinked')::int <> 0 then
    raise exception 'the never-linked count did not follow the deletion: %', client;
  end if;
  raise notice 'PASS  an admin deletes a never-linked machine, audited, with its pairing row';
end $$;

-- Any machine, not only a phantom: the readings, speed tests and alerts go with
-- it, which is the whole reason the button asks for the name to be typed.
do $$
declare v_node uuid; n integer;
begin
  v_node := (select v from t where k = 'node_id')::uuid;
  set local role postgres;
  select count(*) into n from public.metrics where node_id = v_node;
  if n < 1 then raise exception 'expected the fixture node to have readings to cascade'; end if;

  set local role authenticated;
  set local "test.uid" = '33333333-3333-3333-3333-333333333333';
  perform public.hyn_admin_delete_node(v_node, 'decommissioned');

  set local role postgres;
  select count(*) into n from public.nodes where id = v_node;
  if n <> 0 then raise exception 'a linked machine could not be deleted'; end if;
  select count(*) into n from public.metrics where node_id = v_node;
  if n <> 0 then raise exception '% readings outlived their machine', n; end if;
  select count(*) into n from public.alert_events where node_id = v_node;
  if n <> 0 then raise exception '% alerts outlived their machine', n; end if;
  -- The audit entry survives the row it refers to: target_node is set null on
  -- delete, so the detail is what keeps the trail readable.
  select count(*) into n from public.admin_audit
   where action = 'node.delete' and detail->>'reason' = 'decommissioned';
  if n <> 1 then raise exception 'deleting a linked machine was not audited'; end if;
  set local role authenticated;
  raise notice 'PASS  deleting a machine takes its telemetry with it and stays in the audit trail';
end $$;

-- ---------------------------------------------------------------------------
-- 17. a refused command names the state that refused it
-- ---------------------------------------------------------------------------
-- The bug this covers: the portal's "Sync now" printed `active node not found`
-- and told the operator to run `sudo hyn doctor` on the machine, for a machine
-- that was in fact paused, suspended, revoked or demo -- none of which anything
-- on the machine can clear. Worse, a pause whose deadline had already passed
-- refused too, although every other RPC treats that as active.
do $$
declare v_node uuid; r json; caught text;
begin
  set local role postgres;
  insert into public.nodes (owner, name, hostname, token_hash, last_seen_at)
  values ('11111111-1111-1111-1111-111111111111', 'krishna', 'krishna',
          public._hyn_sha256('krishna-node-token'), now())
  returning id into v_node;
  insert into t (k, v) values ('cmd_node', v_node::text);

  set local role authenticated;
  perform set_config('test.uid', '11111111-1111-1111-1111-111111111111', true);

  -- 1. an elapsed timed pause is not a refusal: it resolves, and the command runs
  set local role postgres;
  update public.nodes set status = 'paused', paused_until = now() - interval '1 minute',
         status_reason = 'maintenance window'
   where id = v_node;
  set local role authenticated;
  r := public.hyn_request_node_command(v_node, 'sync');
  if r->>'created' <> 'true' then
    raise exception 'a sync was refused for a pause that had already expired: %', r;
  end if;
  set local role postgres;
  if (select status from public.nodes where id = v_node) <> 'active' then
    raise exception 'the expired pause was not resolved by the command request';
  end if;
  delete from public.node_commands where node_id = v_node;

  -- 2. a live pause is refused, and says so
  update public.nodes set status = 'paused', paused_until = now() + interval '30 minutes',
         status_reason = 'maintenance window'
   where id = v_node;
  set local role authenticated;
  caught := '';
  begin
    perform public.hyn_request_node_command(v_node, 'sync');
  exception when others then caught := sqlerrm;
  end;
  if caught not like '%paused%' or caught not like '%maintenance window%' then
    raise exception 'a paused machine refused a sync without saying it was paused: %', caught;
  end if;

  -- 3. suspended
  set local role postgres;
  update public.nodes set status = 'suspended', paused_until = null,
         status_reason = 'non-payment'
   where id = v_node;
  set local role authenticated;
  caught := '';
  begin
    perform public.hyn_request_node_command(v_node, 'sync');
  exception when others then caught := sqlerrm;
  end;
  if caught not like '%suspended%' or caught not like '%non-payment%' then
    raise exception 'a suspended machine refused a sync without saying so: %', caught;
  end if;

  -- 4. revoked, which is the one case the fix is on the server
  set local role postgres;
  update public.nodes set status = 'active', revoked = true, status_reason = null
   where id = v_node;
  set local role authenticated;
  caught := '';
  begin
    perform public.hyn_request_node_command(v_node, 'sync');
  exception when others then caught := sqlerrm;
  end;
  if caught not like '%revoked%' or caught not like '%hyn link%' then
    raise exception 'a revoked machine did not point at re-pairing: %', caught;
  end if;

  -- 5. demo data
  set local role postgres;
  update public.nodes set revoked = false, is_demo = true where id = v_node;
  set local role authenticated;
  caught := '';
  begin
    perform public.hyn_request_node_command(v_node, 'sync');
  exception when others then caught := sqlerrm;
  end;
  if caught not like '%demo%' then
    raise exception 'a demo row refused a sync without saying it was demo data: %', caught;
  end if;

  -- 6. someone else's machine, and one that no longer exists
  set local role postgres;
  update public.nodes set is_demo = false where id = v_node;
  set local role authenticated;
  perform set_config('test.uid', '22222222-2222-2222-2222-222222222222', true);
  caught := '';
  begin
    perform public.hyn_request_node_command(v_node, 'sync');
  exception when others then caught := sqlerrm;
  end;
  if caught not like '%another account%' then
    raise exception 'another account''s machine was refused with the wrong reason: %', caught;
  end if;
  caught := '';
  begin
    perform public.hyn_request_node_command('00000000-0000-4000-8000-000000000000', 'sync');
  exception when others then caught := sqlerrm;
  end;
  if caught not like '%no longer exists%' then
    raise exception 'an unknown machine was refused with the wrong reason: %', caught;
  end if;

  perform set_config('test.uid', '11111111-1111-1111-1111-111111111111', true);
  raise notice 'PASS  a refused command names the state that refused it, and an expired pause does not refuse';
end $$;

-- The admin entry point must agree with the owner one: an administrator clicking
-- Sync in the per-client view on a paused machine used to get the same
-- `active node not found`.
do $$
declare caught text := ''; r json;
begin
  set local role postgres;
  update public.nodes set status = 'paused', paused_until = null, status_reason = 'operator hold'
   where id = (select v from t where k = 'cmd_node')::uuid;
  set local role authenticated;
  perform set_config('test.uid', '33333333-3333-3333-3333-333333333333', true);
  begin
    perform public.hyn_admin_request_node_command(
      (select v from t where k = 'cmd_node')::uuid, 'update');
  exception when others then caught := sqlerrm;
  end;
  if caught not like '%paused%' or caught not like '%operator hold%' then
    raise exception 'the admin command RPC hid the pause behind a not-found: %', caught;
  end if;

  set local role postgres;
  update public.nodes set status = 'active', status_reason = null
   where id = (select v from t where k = 'cmd_node')::uuid;
  set local role authenticated;
  r := public.hyn_admin_request_node_command(
    (select v from t where k = 'cmd_node')::uuid, 'update');
  if r->>'created' <> 'true' then
    raise exception 'an active machine refused an administrator update: %', r;
  end if;
  raise notice 'PASS  the admin command RPC refuses for the same stated reasons, and works otherwise';
end $$;

-- ---------------------------------------------------------------------------
-- 18. an administrator clears the delivery log
-- ---------------------------------------------------------------------------
-- notification_log is the one table nothing prunes, so the admin panel grew a
-- control for it. Two things are worth asserting: the cutoff is honoured, because
-- a purge that quietly took this morning's failures with it would be the same
-- accident every time; and the count reaches the audit trail, which after the
-- delete is the only record that the delete happened.
do $$
declare v_node uuid; r json; n integer;
begin
  v_node := (select v from t where k = 'cmd_node')::uuid;
  set local role postgres;
  delete from public.notification_log;
  insert into public.notification_log (node_id, owner, ts, kind, target, status, category)
  values (v_node, '11111111-1111-1111-1111-111111111111', now() - interval '40 days',
          'resend-cloud', 'alice@example.com', 'failed', 'alert'),
         (v_node, '11111111-1111-1111-1111-111111111111', now() - interval '1 hour',
          'resend-cloud', 'alice@example.com', 'sent', 'report');

  set local role authenticated;
  perform set_config('test.uid', '33333333-3333-3333-3333-333333333333', true);
  r := public.hyn_admin_clear_notifications(now() - interval '30 days', 'routine cleanup');
  if (r->>'deleted')::int <> 1 then
    raise exception 'the retention cutoff was ignored: %', r;
  end if;

  set local role postgres;
  select count(*) into n from public.notification_log;
  if n <> 1 then
    raise exception 'a delivery record inside the retention window was cleared';
  end if;
  select count(*) into n from public.admin_audit
   where action = 'notification_log.clear' and (detail->>'deleted')::int = 1
     and detail->>'reason' = 'routine cleanup';
  if n <> 1 then raise exception 'clearing the log was not attributed in the audit trail'; end if;

  set local role authenticated;
  r := public.hyn_admin_clear_notifications(null, 'start again');
  if (r->>'deleted')::int <> 1 then
    raise exception 'a null cutoff did not clear everything: %', r;
  end if;
  set local role postgres;
  select count(*) into n from public.notification_log;
  if n <> 0 then raise exception '% delivery records survived a full clear', n; end if;
  set local role authenticated;
  raise notice 'PASS  an admin clears the delivery log, honours the cutoff, and is audited for it';
end $$;

rollback;
