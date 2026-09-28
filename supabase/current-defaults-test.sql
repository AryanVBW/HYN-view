-- Current-schema defaults and portal-managed cadence keys. Runs only against the
-- complete schema (after the migration chain, and after schema.sql reapply),
-- because these behaviours are newer than the historical schema flow-test.sql is
-- also exercised against.
begin;
insert into auth.users (id, email) values ('c0c0c0c0-0000-4000-8000-000000000001', 'cadence@example.com');
insert into public.nodes (id, owner, name) values
  ('c0c0c0c0-0000-4000-8000-0000000000aa', 'c0c0c0c0-0000-4000-8000-000000000001', 'cadence-node');

do $$
declare candidate jsonb; rejected boolean;
begin
  foreach candidate in array array[
    '{"cloud_checkin_min":"0"}'::jsonb, '{"cloud_checkin_min":"61"}'::jsonb,
    '{"heartbeat_sec":"4"}'::jsonb, '{"heartbeat_sec":"3601"}'::jsonb,
    '{"heartbeat_sec":"024"}'::jsonb
  ] loop
    rejected := false;
    begin
      update public.nodes set config = candidate where id = 'c0c0c0c0-0000-4000-8000-0000000000aa';
    exception when check_violation then rejected := true;
    end;
    if not rejected then raise exception 'cadence value outside the agent bound was stored: %', candidate; end if;
  end loop;
  raise notice 'PASS  cadence values the agent would refuse are rejected';
end $$;

do $$
begin
  update public.nodes set config = '{"cloud_checkin_min":"1","heartbeat_sec":"24","cloud_push_min":"1"}'
   where id = 'c0c0c0c0-0000-4000-8000-0000000000aa';
  update public.nodes set config = '{"cloud_checkin_min":"60","heartbeat_sec":"3600"}'
   where id = 'c0c0c0c0-0000-4000-8000-0000000000aa';
  raise notice 'PASS  cadence values inside the agent bound are writable';
end $$;
do $$
declare pref public.email_preferences;
begin
  select * into pref from public.email_preferences
   where node_id = 'c0c0c0c0-0000-4000-8000-0000000000aa';
  if pref.node_id is null then raise exception 'a new node received no email schedule'; end if;
  -- Every stream is opt-in: a machine that pairs itself must not start mailing an
  -- account that never asked to be mailed.
  if pref.incident_enabled or pref.daily_enabled or pref.system_enabled then
    raise exception 'a new node defaults to sending email: %', row_to_json(pref);
  end if;
  raise notice 'PASS  every email stream of a new node is opt-in';
end $$;
rollback;
