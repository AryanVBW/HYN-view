-- Outage detection runs in the database, every minute.
--
-- The portal's watchdog was a Vercel Workflow started from the agent gateway.
-- The portal runs on Heroku, where the workflow runtime does not exist, and it
-- was also switched off (HYN_ENABLE_WORKFLOW_WATCHDOG). So no server was ever
-- reported offline. On production every node_watchdogs row was still
-- 'starting'.
--
-- _hyn_outage_sweep() runs every minute through pg_cron (_hyn_schedule_jobs).
-- It compares each server's last heartbeat with its quiet threshold
-- (_hyn_quiet_after_seconds: three missed beats, never under three minutes) and
-- records the result in node_watchdogs.last_alert_state. On a real transition
-- (online -> offline or offline -> online) it queues one email in
-- web_notification_jobs, but only if the server has a recipient and incident
-- alerts are on. The portal sends queued jobs like any other alert.
-- Servers seen for the first time are recorded without an email, so a server
-- that went quiet long ago is not reported as a new outage. Servers that never
-- sent a heartbeat (agents before 1.7), paused, suspended, revoked and demo
-- servers are left out.
begin;

create or replace function public._hyn_outage_sweep()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_seen integer := 0; v_changed integer := 0; v_queued integer := 0;
begin
  if not pg_try_advisory_xact_lock(1876901121, 60) then return jsonb_build_object('status', 'busy'); end if;

  insert into public.node_watchdogs(node_id, state)
    select n.id, 'running' from public.nodes n
     where n.last_heartbeat_at is not null and not n.is_demo and not n.revoked
  on conflict (node_id) do nothing;

  with cur as (
    select n.id, n.name, n.hostname, n.last_heartbeat_at, w.last_alert_state as prior,
           case when n.last_heartbeat_at > now() - make_interval(secs => public._hyn_quiet_after_seconds(n.config))
                then 'online' else 'offline' end as now_state,
           extract(epoch from now() - n.last_heartbeat_at)::bigint as age
      from public.nodes n join public.node_watchdogs w on w.node_id = n.id
     where n.last_heartbeat_at is not null and not n.is_demo and not n.revoked
       and (n.status = 'active' or (n.status = 'paused' and n.paused_until <= now()))
     for update of w skip locked
  ), upd as (
    update public.node_watchdogs w
       set state = 'running', last_alert_state = c.now_state, updated_at = now()
      from cur c where w.node_id = c.id
    returning c.*
  ), queued as (
    insert into public.web_notification_jobs(node_id, fingerprint, category, severity, subject, text_body)
    select u.id,
           format('outage:%s:%s', u.now_state, extract(epoch from u.last_heartbeat_at)::bigint),
           'alert',
           case u.now_state when 'offline' then 'crit' else 'info' end,
           left(case u.now_state
             when 'offline' then format('[HYN CRIT] %s missed three heartbeats', coalesce(u.name, u.hostname, 'Machine'))
             else format('[HYN RECOVERED] %s is reporting again', coalesce(u.name, u.hostname, 'Machine')) end, 300),
           case u.now_state
             when 'offline' then format(
               'No heartbeat has reached the portal for %s seconds (last at %s UTC). Charts still show the last received values.'
               || E'\n\nOn the server: sudo hyn doctor --fix',
               u.age, to_char(u.last_heartbeat_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS'))
             else format('The machine resumed its heartbeat at %s UTC.',
               to_char(u.last_heartbeat_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS')) end
      from upd u join public.email_preferences e on e.node_id = u.id
     where u.now_state <> u.prior and u.prior in ('online', 'offline')
       and e.recipient is not null and e.incident_enabled
    on conflict (node_id, fingerprint) do nothing
    returning 1
  )
  select (select count(*) from upd), (select count(*) from upd where now_state <> prior), (select count(*) from queued)
    into v_seen, v_changed, v_queued;

  update public.node_watchdogs w set state = 'stopped', updated_at = now()
    from public.nodes n
   where n.id = w.node_id and w.state <> 'stopped'
     and (n.is_demo or n.revoked or n.status not in ('active', 'paused')
          or (n.status = 'paused' and (n.paused_until is null or n.paused_until > now())));

  return jsonb_build_object('status', 'ok', 'servers', v_seen, 'transitions', v_changed, 'emails_queued', v_queued);
end $$;
revoke all on function public._hyn_outage_sweep() from public, anon, authenticated;

create or replace function public._hyn_schedule_jobs()
returns text language plpgsql set search_path = public as $$
declare r record; n integer := 0;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    return 'pg_cron is not installed: no database jobs scheduled';
  end if;
  for r in select * from (values
    ('hyn-telemetry-retention', '*/5 * * * *', 'select public.hyn_prune_telemetry(5000)'),
    ('hyn-delivery-retention', '17 * * * *', 'select public._hyn_prune_delivery_history(5000)'),
    ('hyn-outage-sweep', '* * * * *', 'select public._hyn_outage_sweep()')
  ) j(name, schedule, command) loop
    perform cron.schedule(r.name, r.schedule, r.command);
    n := n + 1;
  end loop;
  return format('pg_cron jobs scheduled: %s', n);
end $$;
revoke all on function public._hyn_schedule_jobs() from public, anon, authenticated;

do $$ begin raise notice '%', public._hyn_schedule_jobs(); end $$;

commit;
