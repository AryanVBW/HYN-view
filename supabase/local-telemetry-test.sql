\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email) values ('99999999-1111-4111-8111-111111111111', 'local-storage@example.com');
insert into public.nodes (id, owner, name, token_hash) values
  ('99999999-2222-4222-8222-222222222222', '99999999-1111-4111-8111-111111111111', 'local-node', public._hyn_sha256('local-token'));

set local role anon;
do $$
declare result json;
begin
  result := public.hyn_local_heartbeat('local-token', '1.10.0');
  if result->>'node_id' <> '99999999-2222-4222-8222-222222222222' or result->>'node_status' <> 'active' then
    raise exception 'presence did not return the authenticated node';
  end if;
  begin
    perform public.hyn_local_heartbeat('wrong-token');
    raise exception 'invalid credential was accepted';
  exception when others then
    if sqlerrm <> 'invalid node token' then raise; end if;
  end;
  raise notice 'PASS  local presence verifies the token and returns only control metadata';
  result := public.hyn_fetch_local_config('local-token');
  if result->'config' is null or result->'watchdog' is not null or result->'alert_template_b64' is not null then
    raise exception 'local config response crossed its metadata boundary';
  end if;
  raise notice 'PASS  local settings polling omits watchdog leases and email templates';
end $$;
reset role;
do $$
begin
  if (select telemetry_mode from public.nodes where name = 'local-node') <> 'local' then raise exception 'local mode was not recorded'; end if;
  if exists (select 1 from public.metrics where node_id = '99999999-2222-4222-8222-222222222222') then raise exception 'local presence stored telemetry'; end if;
  if exists (select 1 from public.notification_log where node_id = '99999999-2222-4222-8222-222222222222') then raise exception 'local presence wrote notification history'; end if;
  raise notice 'PASS  local presence stores no metric or diagnostic history';
end $$;
update public.nodes set revoked = true where name = 'local-node';
set local role anon;
do $$ begin
  begin
    perform public.hyn_local_heartbeat('local-token');
    raise exception 'revoked credential accepted';
  exception when others then if sqlerrm <> 'node revoked' then raise; end if; end;
  raise notice 'PASS  local presence refuses revoked credentials';
end $$;
reset role;
update public.nodes set revoked = false where name = 'local-node';
update public.profiles set status = 'suspended' where id = '99999999-1111-4111-8111-111111111111';
set local role anon;
do $$ begin
  begin
    perform public.hyn_local_heartbeat('local-token');
    raise exception 'suspended owner accepted';
  exception when others then if sqlerrm <> 'account suspended' then raise; end if; end;
  raise notice 'PASS  local presence refuses suspended owners';
end $$;
reset role;
rollback;
