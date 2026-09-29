-- Delivery history is pruned instead of growing for ever.
--
-- Nothing deleted finished email jobs, the delivery ledger or the scheduled-mail
-- idempotency keys; each only ever grew. Their rows are only needed while a send
-- can still be retried or duplicated, and for the admin delivery view:
--   * web_notification_jobs  finished (sent, or failed with no attempts left)
--                            for 30 days
--   * delivery_events        not updated for 90 days (attempts cascade)
--   * cloud_email_dispatches older than 30 days (keys are per day or per event)
-- notification_log (cleared by administrators from /admin) and admin_audit (the
-- audit trail must outlive what it records) keep their existing policies.
-- Runs hourly through pg_cron (_hyn_schedule_jobs); each run deletes at most
-- p_batch rows per table.
begin;

create or replace function public._hyn_prune_delivery_history(p_batch integer default 5000)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_batch integer := greatest(1, least(coalesce(p_batch, 5000), 5000));
  v_jobs integer := 0; v_events integer := 0; v_dispatches integer := 0;
begin
  if not pg_try_advisory_xact_lock(1876901121, 90) then return jsonb_build_object('status', 'busy'); end if;
  with expired as (
    select id from public.web_notification_jobs
     where (status = 'sent' or (status = 'failed' and attempts >= 5)) and updated_at < now() - interval '30 days'
     order by updated_at for update skip locked limit v_batch
  ) delete from public.web_notification_jobs j using expired e where j.id = e.id;
  get diagnostics v_jobs = row_count;
  with expired as (
    select id from public.delivery_events where updated_at < now() - interval '90 days'
     order by updated_at for update skip locked limit v_batch
  ) delete from public.delivery_events d using expired e where d.id = e.id;
  get diagnostics v_events = row_count;
  with expired as (
    select idempotency_key from public.cloud_email_dispatches where created_at < now() - interval '30 days'
     order by created_at for update skip locked limit v_batch
  ) delete from public.cloud_email_dispatches d using expired e where d.idempotency_key = e.idempotency_key;
  get diagnostics v_dispatches = row_count;
  return jsonb_build_object('status', 'ok', 'jobs_deleted', v_jobs, 'delivery_events_deleted', v_events,
    'dispatches_deleted', v_dispatches);
end $$;
revoke all on function public._hyn_prune_delivery_history(integer) from public, anon, authenticated;

create or replace function public._hyn_schedule_jobs()
returns text language plpgsql set search_path = public as $$
declare r record; n integer := 0;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    return 'pg_cron is not installed: no database jobs scheduled';
  end if;
  for r in select * from (values
    ('hyn-telemetry-retention', '*/5 * * * *', 'select public.hyn_prune_telemetry(5000)'),
    ('hyn-delivery-retention', '17 * * * *', 'select public._hyn_prune_delivery_history(5000)')
  ) j(name, schedule, command) loop
    perform cron.schedule(r.name, r.schedule, r.command);
    n := n + 1;
  end loop;
  return format('pg_cron jobs scheduled: %s', n);
end $$;
revoke all on function public._hyn_schedule_jobs() from public, anon, authenticated;

do $$ begin raise notice '%', public._hyn_schedule_jobs(); end $$;

commit;
