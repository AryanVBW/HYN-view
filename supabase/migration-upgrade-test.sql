-- Assertions specific to upgrading an existing project. run-tests.sh seeds a
-- plaintext legacy pairing immediately before the verifier migration; this
-- proves the migration preserves the active pairing without retaining a fast
-- or plaintext credential.

\set ON_ERROR_STOP on
\pset pager off

begin;

insert into auth.users (id, email) values
  ('33333333-3333-3333-3333-333333333333', 'migration@example.com');

set local role authenticated;
set local "test.uid" = '33333333-3333-3333-3333-333333333333';

do $$
declare r json;
begin
  r := public.hyn_device_lookup('  7abc-defg  ');
  if r->>'status' <> 'pending' then
    raise exception 'legacy pairing was not usable after verifier migration: %', r;
  end if;
  if r->>'hostname' <> 'legacy-host' then
    raise exception 'legacy pairing metadata was not preserved';
  end if;
  raise notice 'PASS  an in-flight legacy pairing survives the verifier migration';
end $$;

set local role postgres;

do $$
begin
  if to_regclass('public.notification_channels') is not null then
    raise exception 'upgrade retained centrally stored notification credentials';
  end if;
  if to_regclass('public.notify_prefs') is not null then
    raise exception 'upgrade retained central notification routing preferences';
  end if;
  if to_regprocedure('public.hyn_list_admins()') is not null then
    raise exception 'upgrade retained the notification-routing administrator directory';
  end if;
  raise notice 'PASS  upgrade removes central notification configuration storage and directory RPC';
end $$;

do $$
declare
  v_config jsonb;
  rejected boolean := false;
begin
  select config into v_config from public.nodes
   where owner = '66666666-6666-6666-6666-666666666666';
  if v_config <> '{"alert_mem_pct":"81","report_at":"06:15","auto_update":"install","cloud_push_min":"10"}'::jsonb then
    raise exception 'upgrade did not remove unsafe legacy config keys: %', v_config;
  end if;

  begin
    update public.nodes
       set config = config || '{"heartbeat_url":"https://attacker.example/ping"}'::jsonb
     where owner = '66666666-6666-6666-6666-666666666666';
  exception when check_violation then
    rejected := true;
  end;
  if not rejected then
    raise exception 'upgrade constraint accepted a local-only config key';
  end if;
  raise notice 'PASS  upgrade removes unsafe config and enforces the portal allowlist';
end $$;

do $$
declare
  n integer;
  v_verifier text;
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'device_codes'
       and column_name = 'user_code'
  ) then
    raise exception 'legacy plaintext user_code column survived the migration';
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'device_codes'
       and column_name = 'user_code_hash'
  ) then
    raise exception 'deterministic user_code_hash column survived the migration';
  end if;

  select user_code_verifier into v_verifier
    from public.device_codes
   where user_code_verifier = extensions.crypt('7ABC-DEFG', user_code_verifier);
  if v_verifier is null then
    raise exception 'legacy user_code was not backfilled as a verifier';
  end if;
  if v_verifier !~ '^\$2[abxy]\$10\$[./A-Za-z0-9]{53}$' then
    raise exception 'legacy user_code did not receive a cost-10 bcrypt verifier';
  end if;
  if v_verifier = encode(extensions.digest('7ABC-DEFG', 'sha256'), 'hex') then
    raise exception 'legacy user_code was backfilled with fast SHA-256';
  end if;

  select count(*) into n from public.device_codes
   where to_jsonb(device_codes)::text like '%"7ABC-DEFG"%';
  if n <> 0 then raise exception 'legacy user_code plaintext remains in storage'; end if;
  raise notice 'PASS  the legacy plaintext code becomes a salted bcrypt verifier';
end $$;

delete from public.device_codes
 where user_code_verifier = extensions.crypt('7ABC-DEFG', user_code_verifier);
delete from auth.users where id = '33333333-3333-3333-3333-333333333333';
delete from auth.users where id = '66666666-6666-6666-6666-666666666666';

commit;
