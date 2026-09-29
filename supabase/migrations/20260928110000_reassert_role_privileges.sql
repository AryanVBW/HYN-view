-- Reassert the role privileges supabase/schema.sql defines.
--
-- The 2026-09-20 move to self-hosted Supabase restored the schema without its
-- privileges. Every object was re-created under Supabase's default privileges,
-- which grant tables, sequences and functions to `anon` and `authenticated` by
-- name, so the REVOKEs this schema relies on were lost. Measured on the live
-- database afterwards: the public anon key could execute 101 of 104 functions
-- (the schema allows 47) and had full access to every table, including
-- nodes.token_hash. With it an unauthenticated caller could list every server
-- and its owner through _hyn_digest_nodes(), read owner ids through
-- hyn_due_user_digests(), claim queued email jobs and forge audit rows.
--
-- This migration is idempotent and safe to re-run:
--   1. service_role keeps exactly the functions it can execute today (the
--      portal's server-side paths depend on them);
--   2. public, anon and authenticated lose every privilege on the application's
--      tables, sequences and functions;
--   3. the grants a fresh schema.sql produces are applied again, generated from
--      a clean apply of schema.sql (supabase/test-harness.sql defaults) on
--      2026-09-28. TRUNCATE, REFERENCES and TRIGGER are not re-granted.
--
-- Verify afterwards, read-only: psql -f supabase/privilege-check.sql
begin;
do $$
declare
  r record;
  g text;
  v_sig text;
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    for r in
      select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname ~ '^_?hyn_'
         and has_function_privilege('service_role', p.oid, 'EXECUTE')
    loop
      execute format('grant execute on function %s to service_role', r.sig);
    end loop;
  end if;

  for r in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?hyn_'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
  execute 'revoke all on all tables in schema public from anon, authenticated';
  execute 'revoke all on all sequences in schema public from anon, authenticated';

  foreach g in array array[
    'public._hyn_portal_config_valid(jsonb)|anon, authenticated, public',
    'public.hyn_admin_assign_relayer(uuid,integer,text)|authenticated',
    'public.hyn_admin_audit(integer)|anon, authenticated',
    'public.hyn_admin_clear_notifications(timestamp with time zone,text)|anon, authenticated',
    'public.hyn_admin_clients()|anon, authenticated',
    'public.hyn_admin_delete_node(uuid,text)|anon, authenticated',
    'public.hyn_admin_delivery_dashboard(uuid,text,text,integer)|authenticated',
    'public.hyn_admin_nodes()|anon, authenticated',
    'public.hyn_admin_notifications(integer)|anon, authenticated',
    'public.hyn_admin_overview()|anon, authenticated',
    'public.hyn_admin_promote_by_email(text)|anon, authenticated',
    'public.hyn_admin_remove_relayer(uuid)|authenticated',
    'public.hyn_admin_request_node_command(uuid,text)|anon, authenticated',
    'public.hyn_admin_review_relayer_request(uuid,boolean,text)|authenticated',
    'public.hyn_admin_save_template(text,text)|authenticated',
    'public.hyn_admin_set_dashboard_access(uuid,uuid,boolean)|authenticated',
    'public.hyn_admin_set_delivery_rules(uuid,jsonb)|authenticated',
    'public.hyn_admin_set_digest(uuid,boolean,text,text,boolean,boolean)|authenticated',
    'public.hyn_admin_set_node_config(uuid,jsonb)|anon, authenticated',
    'public.hyn_admin_set_node_relayer(uuid,uuid)|authenticated',
    'public.hyn_admin_set_node_revoked(uuid,boolean,text)|anon, authenticated',
    'public.hyn_admin_set_node_status(uuid,text,integer,text)|anon, authenticated',
    'public.hyn_admin_set_relayer_priority(uuid)|authenticated',
    'public.hyn_admin_set_role(uuid,text)|anon, authenticated',
    'public.hyn_admin_set_server_access(uuid,uuid,boolean)|authenticated',
    'public.hyn_admin_set_user_servers(uuid,uuid[])|authenticated',
    'public.hyn_admin_set_user_status(uuid,text,text)|anon, authenticated',
    'public.hyn_admin_share_server(uuid[],uuid,boolean,boolean)|authenticated',
    'public.hyn_admin_stop_delivery(uuid)|authenticated',
    'public.hyn_admin_templates()|anon, authenticated',
    'public.hyn_bandwidth_report(uuid,integer)|authenticated',
    'public.hyn_can_link()|authenticated',
    'public.hyn_can_monitor()|authenticated',
    'public.hyn_can_view_dashboard(uuid)|authenticated',
    'public.hyn_can_view_fleet()|authenticated',
    'public.hyn_can_view_node(uuid)|authenticated',
    'public.hyn_cancel_relayer_request(uuid)|authenticated',
    'public.hyn_claim_admin_report(uuid)|anon, authenticated',
    'public.hyn_claim_device_linked_email(uuid)|anon, authenticated',
    'public.hyn_claim_env_admin(text)|anon, authenticated',
    'public.hyn_claim_first_telemetry_email(text,text)|anon, authenticated',
    'public.hyn_claim_node_command(text)|anon, authenticated',
    'public.hyn_claim_node_watchdog(text)|anon, authenticated',
    'public.hyn_complete_admin_report(uuid,text,text,text)|anon, authenticated',
    'public.hyn_complete_device_linked_email(uuid,text)|anon, authenticated',
    'public.hyn_complete_first_telemetry_email(text,text)|anon, authenticated',
    'public.hyn_dashboard_accounts()|authenticated',
    'public.hyn_demo_clear()|anon, authenticated',
    'public.hyn_demo_seed()|anon, authenticated',
    'public.hyn_device_approve(text,text)|anon, authenticated',
    'public.hyn_device_lookup(text)|anon, authenticated',
    'public.hyn_device_poll(text)|anon, authenticated',
    'public.hyn_device_start(text,text,text)|anon, authenticated',
    'public.hyn_fetch_config(text)|anon, authenticated',
    'public.hyn_fetch_local_config(text)|anon, authenticated',
    'public.hyn_fleet_bandwidth_report(integer)|authenticated',
    'public.hyn_fleet_metric_history()|authenticated',
    'public.hyn_heartbeat(text,text)|anon, authenticated',
    'public.hyn_ingest(text,jsonb)|anon, authenticated',
    'public.hyn_is_active()|anon, authenticated',
    'public.hyn_is_admin()|anon, authenticated',
    'public.hyn_is_super_admin()|authenticated',
    'public.hyn_local_heartbeat(text,text)|anon, authenticated',
    'public.hyn_maintainer_resolve_alert(bigint,text)|authenticated',
    'public.hyn_metric_history(uuid)|authenticated',
    'public.hyn_node_relayer(uuid)|authenticated',
    'public.hyn_queue_web_notification(text,jsonb)|anon, authenticated',
    'public.hyn_record_bandwidth(text,text,text,numeric,numeric)|anon, authenticated',
    'public.hyn_release_device_linked_email(uuid)|anon, authenticated',
    'public.hyn_release_first_telemetry_email(text)|anon, authenticated',
    'public.hyn_report_node_command(text,uuid,text,text,text,text,text)|anon, authenticated',
    'public.hyn_report_notification(text,jsonb)|anon, authenticated',
    'public.hyn_request_node_command(uuid,text)|anon, authenticated',
    'public.hyn_request_node_update(uuid)|anon, authenticated',
    'public.hyn_request_relayer(integer,text)|authenticated',
    'public.hyn_server_notifications(integer)|authenticated',
    'public.hyn_update_node_config(uuid,jsonb)|anon, authenticated',
    'public.hyn_upsert_email_preferences(uuid,text,text,boolean,boolean,time without time zone,boolean,time without time zone)|authenticated'
  ] loop
    v_sig := split_part(g, '|', 1);
    if to_regprocedure(v_sig) is not null then
      execute format('grant execute on function %s to %s', to_regprocedure(v_sig), split_part(g, '|', 2));
    end if;
  end loop;

  foreach g in array array[
    'public.admin_audit|table|delete, insert, select, update|authenticated',
    'public.admin_audit_id_seq|sequence|select, update, usage|authenticated',
    'public.alert_events|table|delete, insert, select, update|authenticated',
    'public.alert_events_id_seq|sequence|select, update, usage|authenticated',
    'public.bandwidth_counters|table|select|authenticated',
    'public.bandwidth_daily|table|select|authenticated',
    'public.dashboard_access|table|select|authenticated',
    'public.email_preferences|table|delete, insert, select, update|authenticated',
    'public.metrics|table|delete, insert, select, update|authenticated',
    'public.metrics_id_seq|sequence|select, update, usage|authenticated',
    'public.node_commands|table|select|authenticated',
    'public.nodes|table|delete, insert|authenticated',
    'public.notification_log|table|delete, insert, select, update|authenticated',
    'public.notification_log_id_seq|sequence|select, update, usage|authenticated',
    'public.profiles|table|delete, insert, select|authenticated',
    'public.relayer_assignments|table|select|authenticated',
    'public.relayer_requests|table|select|authenticated',
    'public.server_access|table|select|authenticated',
    'public.server_access_events|table|select|authenticated',
    'public.server_access_events_id_seq|sequence|select, update, usage|authenticated',
    'public.speedtests|table|delete, insert, select, update|authenticated',
    'public.speedtests_id_seq|sequence|select, update, usage|authenticated'
  ] loop
    if to_regclass(split_part(g, '|', 1)) is not null then
      execute format('grant %s on %s %s to %s', split_part(g, '|', 3), split_part(g, '|', 2), to_regclass(split_part(g, '|', 1)), split_part(g, '|', 4));
    end if;
  end loop;

  -- Column grants are applied one column at a time so a column this database
  -- does not have yet cannot abort the rest.
  foreach g in array array[
    'public.node_relayer_links|assignment_id|select|authenticated',
    'public.node_relayer_links|linked_at|select|authenticated',
    'public.node_relayer_links|node_id|select|authenticated',
    'public.node_relayer_links|owner|select|authenticated',
    'public.nodes|agent_version|select|authenticated',
    'public.nodes|config|select|authenticated',
    'public.nodes|created_at|select|authenticated',
    'public.nodes|hostname|select|authenticated',
    'public.nodes|id|select|authenticated',
    'public.nodes|is_demo|select|authenticated',
    'public.nodes|last_config_pull_at|select|authenticated',
    'public.nodes|last_heartbeat_at|select|authenticated',
    'public.nodes|last_metric_at|select|authenticated',
    'public.nodes|last_seen_at|select|authenticated',
    'public.nodes|name|select|authenticated',
    'public.nodes|os|select|authenticated',
    'public.nodes|owner|select|authenticated',
    'public.nodes|paused_until|select|authenticated',
    'public.nodes|revoked|select|authenticated',
    'public.nodes|status|select|authenticated',
    'public.nodes|status_reason|select|authenticated',
    'public.nodes|telemetry_mode|select|authenticated',
    'public.nodes|config|update|authenticated',
    'public.nodes|name|update|authenticated',
    'public.nodes|revoked|update|authenticated',
    'public.profiles|full_name|update|authenticated'
  ] loop
    if exists(select 1 from pg_attribute where attrelid = to_regclass(split_part(g, '|', 1))
              and attname = split_part(g, '|', 2) and attnum > 0 and not attisdropped) then
      execute format('grant %s (%I) on table %s to %s', split_part(g, '|', 3), split_part(g, '|', 2),
        to_regclass(split_part(g, '|', 1)), split_part(g, '|', 4));
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';
commit;
