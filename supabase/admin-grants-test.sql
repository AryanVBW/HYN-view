-- Email-based administrator grants need a confirmed address
-- (migrations/20260929130000_confirmed_email_grants.sql). Rolled back.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,email_confirmed_at) values
  ('4e000000-0000-4000-8000-000000000001','boss@grants.test',now()),
  ('4e000000-0000-4000-8000-000000000002','squatted@grants.test',null),
  ('4e000000-0000-4000-8000-000000000003','renamed@grants.test',now());
update public.profiles set role = 'super_admin' where id = '4e000000-0000-4000-8000-000000000001';
update public.profiles set role = 'monitor' where id in ('4e000000-0000-4000-8000-000000000002','4e000000-0000-4000-8000-000000000003');
-- profiles keeps the sign-up address; Auth now holds a different one.
update public.profiles set email = 'old-address@grants.test' where id = '4e000000-0000-4000-8000-000000000003';
insert into public.admin_allowlist(email, note) values ('squatted@grants.test', 'grants test');

set local role authenticated;
set local "test.uid" = '4e000000-0000-4000-8000-000000000002';
do $$ declare r json; begin
  r := public.hyn_claim_env_admin('squatted@grants.test');
  if r->>'status' <> 'unconfirmed' then raise exception 'an unconfirmed address claimed the allowlist: %', r; end if;
end $$;
reset role;
do $$ begin
  if (select role from public.profiles where id = '4e000000-0000-4000-8000-000000000002') <> 'monitor'
     or not exists(select 1 from public.admin_allowlist where email = 'squatted@grants.test') then
    raise exception 'an unconfirmed claim changed the role or used up the allowlist entry';
  end if;
end $$;
update auth.users set email_confirmed_at = now() where id = '4e000000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ declare r json; begin
  r := public.hyn_claim_env_admin(null);
  if r->>'status' <> 'ok' then raise exception 'a confirmed allow-listed address was refused: %', r; end if;
  raise notice 'PASS  the admin allowlist is claimed only once the address is confirmed';
end $$;

reset role;
update auth.users set email_confirmed_at = null where id = '4e000000-0000-4000-8000-000000000002';
update public.profiles set role = 'monitor' where id = '4e000000-0000-4000-8000-000000000002';
set local role authenticated;
set local "test.uid" = '4e000000-0000-4000-8000-000000000001';
do $$ declare r json; v_refused boolean := false; begin
  begin
    r := public.hyn_admin_promote_by_email('squatted@grants.test');
  exception when others then
    v_refused := sqlerrm like '%has not confirmed its email address%';
  end;
  if not v_refused then raise exception 'promotion by email reached an unconfirmed account: %', r; end if;
  r := public.hyn_admin_promote_by_email('old-address@grants.test');
  if r->>'status' <> 'not_found' then raise exception 'promotion matched a stale profile address: %', r; end if;
  r := public.hyn_admin_promote_by_email('RENAMED@grants.test');
  if r->>'status' <> 'ok' then raise exception 'promotion by the current confirmed address failed: %', r; end if;
  raise notice 'PASS  promotion by email reaches only a confirmed account at its current address';
end $$;
reset role;
do $$ begin
  if (select role from public.profiles where id = '4e000000-0000-4000-8000-000000000002') <> 'monitor'
     or (select role from public.profiles where id = '4e000000-0000-4000-8000-000000000003') <> 'admin' then
    raise exception 'promotion changed the wrong accounts';
  end if;
end $$;
rollback;
