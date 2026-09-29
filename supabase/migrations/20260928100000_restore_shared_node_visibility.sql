-- Restore shared-server visibility lost in 20260921140000_maintainer_role.sql.
--
-- That migration replaced the node and telemetry read policies with
-- `owner = auth.uid() or hyn_can_view_fleet()`. The policies they replaced went
-- through hyn_can_view_node(), so the swap also removed, for every non-fleet
-- user:
--   * servers and dashboards shared through server_access / dashboard_access
--     (Viewers saw no machines at all),
--   * the suspended-account and revoked-node checks, and
--   * the 48-hour read window on metrics, speed tests and alert events.
-- hyn_can_view_node() already grants maintainers fleet-wide visibility (same
-- migration), so routing the policies back through it keeps the maintainer role
-- working while restoring everything else.

drop policy if exists nodes_select_own on public.nodes;
create policy nodes_select_own on public.nodes for select to authenticated
  using(public.hyn_can_view_node(id));

drop policy if exists metrics_select_own on public.metrics;
create policy metrics_select_own on public.metrics for select to authenticated
  using(ts between now()-interval '48 hours' and now()+interval '5 minutes' and public.hyn_can_view_node(node_id));

drop policy if exists speedtests_select_own on public.speedtests;
create policy speedtests_select_own on public.speedtests for select to authenticated
  using(ts between now()-interval '48 hours' and now()+interval '5 minutes' and public.hyn_can_view_node(node_id));

drop policy if exists alert_events_select_own on public.alert_events;
create policy alert_events_select_own on public.alert_events for select to authenticated
  using(ts between now()-interval '48 hours' and now()+interval '5 minutes' and public.hyn_can_view_node(node_id));

drop policy if exists notification_log_select_own on public.notification_log;
create policy notification_log_select_own on public.notification_log for select to authenticated
  using(public.hyn_is_active() and (owner = auth.uid() or public.hyn_can_view_fleet()));
