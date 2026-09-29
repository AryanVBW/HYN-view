-- Read-only privilege floor check. Safe against a live database:
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/privilege-check.sql
--
-- Fails with every violation listed. run-tests.sh runs it in each CI mode and
-- after simulating the privilege loss a schema-only restore causes.
-- Repair: supabase/migrations/20260928110000_reassert_role_privileges.sql.
do $$
declare
  v_problems text[] := '{}';
  r record;
  v_internal text[] := array[
    'admin_allowlist', 'admin_report_jobs', 'cloud_email_dispatches', 'delivery_attempts',
    'delivery_digest_settings', 'delivery_events', 'delivery_rules', 'device_codes',
    'node_watchdogs', 'notification_templates', 'web_notification_jobs'];
  v_service_only text[] := array[
    'hyn_claim_web_notification', 'hyn_complete_web_notification', 'hyn_defer_web_delivery',
    'hyn_reserve_delivery', 'hyn_complete_delivery', 'hyn_due_user_digests',
    'hyn_user_digest_content', 'hyn_prune_telemetry'];
begin
  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity
  loop
    v_problems := v_problems || format('row level security is off on %s', r.relname);
  end loop;

  for r in
    select c.relname, c.relkind from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p', 'S')
       and (has_table_privilege('anon', c.oid, 'SELECT') or has_table_privilege('anon', c.oid, 'INSERT')
         or has_table_privilege('anon', c.oid, 'UPDATE') or has_table_privilege('anon', c.oid, 'DELETE')
         or has_table_privilege('anon', c.oid, 'TRUNCATE')
         or (c.relkind = 'S' and has_sequence_privilege('anon', c.oid, 'USAGE')))
  loop
    v_problems := v_problems || format('anon has access to %s', r.relname);
  end loop;

  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and (has_table_privilege('authenticated', c.oid, 'TRUNCATE')
         or has_table_privilege('authenticated', c.oid, 'REFERENCES')
         or has_table_privilege('authenticated', c.oid, 'TRIGGER'))
  loop
    v_problems := v_problems || format('authenticated has TRUNCATE/REFERENCES/TRIGGER on %s', r.relname);
  end loop;

  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = any(v_internal)
       and (has_table_privilege('authenticated', c.oid, 'SELECT') or has_table_privilege('authenticated', c.oid, 'INSERT')
         or has_table_privilege('authenticated', c.oid, 'UPDATE') or has_table_privilege('authenticated', c.oid, 'DELETE'))
  loop
    v_problems := v_problems || format('authenticated can reach internal table %s', r.relname);
  end loop;

  if to_regclass('public.nodes') is not null
     and has_column_privilege('authenticated', 'public.nodes', 'token_hash', 'SELECT') then
    v_problems := v_problems || 'authenticated can read nodes.token_hash'::text;
  end if;

  for r in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and ((p.proname like '\_hyn\_%' and p.proname <> '_hyn_portal_config_valid') or p.proname = any(v_service_only))
       and (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  loop
    v_problems := v_problems || format('anon/authenticated can execute %s', r.sig);
  end loop;

  if cardinality(v_problems) > 0 then
    raise exception 'privilege check failed (% problems):%', cardinality(v_problems),
      E'\n  - ' || array_to_string(v_problems, E'\n  - ');
  end if;
  raise notice 'PASS  role privileges match the schema floor (RLS on, anon has no table access, internals unreachable)';
end $$;
