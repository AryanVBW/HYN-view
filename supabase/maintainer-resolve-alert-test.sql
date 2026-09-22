-- Standalone check for hyn_maintainer_resolve_alert(). Run against the same
-- throwaway cluster the other *-test.sql files use, after schema.sql (or the
-- full migration chain) and test-harness.sql are applied:
--
--   psql -f supabase/test-harness.sql
--   psql -f supabase/schema.sql
--   psql -f supabase/maintainer-resolve-alert-test.sql
--
-- Not wired into run-tests.sh's orchestration: it needs no fixtures from the
-- rest of that chain, and keeping it separate means it can be run on its own
-- while iterating on this one RPC.
begin;

insert into auth.users(id,email) values
  ('30000000-0000-4000-8000-000000000001','maintainer@resolve.test'),
  ('30000000-0000-4000-8000-000000000002','owner@resolve.test'),
  ('30000000-0000-4000-8000-000000000003','viewer@resolve.test');
update public.profiles set role='maintainer' where email='maintainer@resolve.test';
update public.profiles set role='viewer' where email='viewer@resolve.test';

insert into public.nodes(id,owner,name) values
  ('40000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002','Resolve test node');
insert into public.alert_events(id,node_id,rule,severity,message,resolved) values
  (900001,'40000000-0000-4000-8000-000000000001','disk','crit','disk at 91%',false);

set local role authenticated;

-- A viewer with no fleet access and no share on this node is refused, and the
-- alert is left exactly as it was.
set local "test.uid"='30000000-0000-4000-8000-000000000003';
do $$ begin
  begin
    perform public.hyn_maintainer_resolve_alert(900001, 'false alarm');
    raise exception 'viewer was not refused';
  exception when others then
    if sqlerrm not like '%not visible%' and sqlerrm not like '%fleet access required%' then
      raise exception 'unexpected refusal reason: %', sqlerrm;
    end if;
  end;
  if (select resolved from public.alert_events where id=900001) then
    raise exception 'refused call must not have side effects';
  end if;
  raise notice 'PASS  a viewer without fleet access cannot resolve an alert';
end $$;

-- The maintainer role can resolve an alert on a node it does not own, and the
-- reason is recorded in the audit log. The audit check runs after `reset role`
-- (back to postgres) because admin_audit's own RLS policy restricts select to
-- admins, and a maintainer -- correctly -- is not one; asserting on it as the
-- maintainer would fail for the wrong reason.
set local "test.uid"='30000000-0000-4000-8000-000000000001';
do $$ begin
  perform public.hyn_maintainer_resolve_alert(900001, 'false alarm - one-off backup job');
  if not (select resolved from public.alert_events where id=900001) then
    raise exception 'alert was not marked resolved';
  end if;
end $$;
reset role;
do $$ begin
  if not exists(
    select 1 from public.admin_audit
     where action='alert.resolve.manual' and target_node='40000000-0000-4000-8000-000000000001'
       and detail->>'reason' = 'false alarm - one-off backup job'
  ) then
    raise exception 'manual resolution was not audited with its reason';
  end if;
  raise notice 'PASS  a maintainer can resolve an alert on a node it does not own, with a reason';
end $$;
set local role authenticated;

-- Resolving an already-resolved alert is a no-op, not an error, and does not
-- write a second audit row. Same reset-role reasoning as above for the count.
do $$ declare v_audit_count int; begin
  perform public.hyn_maintainer_resolve_alert(900001, 'clicked twice');
end $$;
reset role;
do $$ begin
  if (select count(*) from public.admin_audit where action='alert.resolve.manual') <> 1 then
    raise exception 'resolving an already-resolved alert must not audit again';
  end if;
  raise notice 'PASS  resolving an already-resolved alert is idempotent';
end $$;
set local role authenticated;

-- An unknown alert id is refused rather than silently succeeding.
do $$ begin
  begin
    perform public.hyn_maintainer_resolve_alert(999999, null);
    raise exception 'unknown alert id was not refused';
  exception when others then
    if sqlerrm not like '%no such alert%' then raise exception 'unexpected refusal reason: %', sqlerrm; end if;
  end;
  raise notice 'PASS  an unknown alert id is refused';
end $$;

rollback;
