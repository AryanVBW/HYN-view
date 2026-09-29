-- One-time email keys survive delivery-history retention.
--
-- cloud_email_dispatches is also where the portal records that a server's
-- one-time messages were sent: 'first-system:<node>' (the first system report,
-- claimed after every upload) and 'device-linked:<node>' (the linking
-- confirmation). _hyn_prune_delivery_history deleted every key older than 30
-- days, including these, so 30 days after linking each server would have been
-- sent its "first" system report again. These keys are kept for the life of the
-- server; they are removed with it (on delete cascade).
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
    select idempotency_key from public.cloud_email_dispatches
     where created_at < now() - interval '30 days'
       and idempotency_key not like 'first-system:%'
       and idempotency_key not like 'device-linked:%'
     order by created_at for update skip locked limit v_batch
  ) delete from public.cloud_email_dispatches d using expired e where d.idempotency_key = e.idempotency_key;
  get diagnostics v_dispatches = row_count;
  return jsonb_build_object('status', 'ok', 'jobs_deleted', v_jobs, 'delivery_events_deleted', v_events,
    'dispatches_deleted', v_dispatches);
end $$;
revoke all on function public._hyn_prune_delivery_history(integer) from public, anon, authenticated;

commit;
