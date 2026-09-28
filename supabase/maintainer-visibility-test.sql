-- Fleet visibility for maintainers, without losing any owner/share boundary.
-- Guards the policies restored by 20260928100000_restore_shared_node_visibility.sql.
begin;
insert into auth.users(id,email) values
  ('31000000-0000-4000-8000-000000000001','maintainer@visibility.test'),
  ('31000000-0000-4000-8000-000000000002','owner@visibility.test'),
  ('31000000-0000-4000-8000-000000000003','monitor@visibility.test'),
  ('31000000-0000-4000-8000-000000000004','viewer@visibility.test');
update public.profiles set role='maintainer' where email='maintainer@visibility.test';
update public.profiles set role='monitor' where email='monitor@visibility.test';
update public.profiles set role='viewer' where email='viewer@visibility.test';
insert into public.nodes(id,owner,name) values
  ('41000000-0000-4000-8000-000000000001','31000000-0000-4000-8000-000000000002','visible-node'),
  ('41000000-0000-4000-8000-000000000002','31000000-0000-4000-8000-000000000002','revoked-node');
update public.nodes set revoked=true where id='41000000-0000-4000-8000-000000000002';
insert into public.metrics(node_id,ts,cpu_pct) values
  ('41000000-0000-4000-8000-000000000001', now()-interval '5 minutes', 10),
  ('41000000-0000-4000-8000-000000000001', now()-interval '3 days', 20);
insert into public.server_access(viewer_id,node_id,allowed)
  values ('31000000-0000-4000-8000-000000000004','41000000-0000-4000-8000-000000000001',true);

set local role authenticated;
set local "test.uid"='31000000-0000-4000-8000-000000000001';
do $$ begin
  if (select count(*) from public.nodes) <> 1 then raise exception 'maintainer should see the one live foreign node'; end if;
  if (select count(*) from public.metrics) <> 1 then raise exception 'maintainer should see only in-window metrics'; end if;
  raise notice 'PASS  a maintainer sees the fleet, inside the 48-hour window, without revoked nodes';
end $$;
set local "test.uid"='31000000-0000-4000-8000-000000000003';
do $$ begin
  if exists(select 1 from public.nodes) or exists(select 1 from public.metrics) then
    raise exception 'a monitor saw a server that was never shared';
  end if;
  raise notice 'PASS  a monitor without a share sees no foreign server';
end $$;
set local "test.uid"='31000000-0000-4000-8000-000000000004';
do $$ begin
  if (select count(*) from public.nodes) <> 1 or (select count(*) from public.metrics) <> 1 then
    raise exception 'a viewer lost access to an explicitly shared server';
  end if;
  raise notice 'PASS  a viewer sees an explicitly shared server';
end $$;
rollback;
