-- Web notification jobs always end instead of cycling for ever.
--
-- hyn_defer_web_delivery put a job back in the queue and handed back its
-- attempt, and hyn_claim_web_notification always offered the oldest queued job
-- first. A job the portal could never send (automatic email off, no recipient,
-- the owner opted out) was therefore claimed and deferred again every few
-- seconds, and every newer job waited behind it. On production on 2026-09-29,
-- 510 jobs were queued this way (the oldest from 2026-09-13), and two had been
-- stuck in 'sending' since 2026-09-20 and 2026-09-22.
--
-- Each job now ends:
--   * not delivered within 24 hours          -> failed, no further attempts
--   * no recipient, or its kind switched off  -> failed when it is claimed
--   * left 'sending' by a worker that stopped -> offered again after 15 minutes
--   * deferred by the portal                  -> offered again after 10 minutes
-- A retired job keeps its row and the reason; it is not logged as a send.
begin;

create or replace function public.hyn_defer_web_delivery(p_job uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  -- A deferral is not a provider attempt, so the attempt is handed back, but a
  -- job older than a day is closed rather than queued again.
  update public.web_notification_jobs
     set status = case when created_at < now() - interval '24 hours' then 'failed' else 'queued' end,
         attempts = case when created_at < now() - interval '24 hours' then 5 else greatest(0, attempts - 1) end,
         error = left(p_reason, 1000), updated_at = now()
   where id = p_job and status = 'sending';
end $$;

create or replace function public.hyn_claim_web_notification(p_job_id uuid default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_job public.web_notification_jobs; v_node public.nodes; v_pref public.email_preferences; v_end text;
begin
  update public.web_notification_jobs j
     set status = 'failed', attempts = 5, updated_at = now(),
         error = left('Not delivered within 24 hours' || coalesce('. Last reason: ' || j.error, ''), 1000)
    from (select id from public.web_notification_jobs
           where created_at < now() - interval '24 hours'
             and (status in ('queued', 'sending') or (status = 'failed' and attempts < 5))
           for update skip locked) expired
   where j.id = expired.id;
  update public.web_notification_jobs j
     set status = 'queued', updated_at = now(), error = null
    from (select id from public.web_notification_jobs
           where status = 'sending' and updated_at < now() - interval '15 minutes'
           for update skip locked) stale
   where j.id = stale.id;

  loop
    with candidate as (
      select j.id from public.web_notification_jobs j
       where (p_job_id is null or j.id = p_job_id)
         and ((j.status = 'queued' and (j.error is null or j.updated_at < now() - interval '10 minutes'))
              or (j.status = 'failed' and j.attempts < 5))
         and not exists(select 1 from public.delivery_events e where e.source_key = 'web-notification:' || j.id::text
               and ((e.terminal and e.status <> 'sent') or e.status = 'sending' or e.next_retry_at > now()))
       order by j.created_at for update of j skip locked limit 1
    ) update public.web_notification_jobs j
         set status = 'sending', attempts = j.attempts + 1, updated_at = now(), error = null
        from candidate where j.id = candidate.id returning j.* into v_job;
    if not found then return json_build_object('status', 'idle'); end if;
    select * into v_node from public.nodes where id = v_job.node_id;
    select * into v_pref from public.email_preferences where node_id = v_job.node_id;
    v_end := case
      when v_pref.recipient is null then 'No email recipient is set for this server'
      when v_job.category = 'alert' and not v_pref.incident_enabled then 'Incident alerts are switched off for this server'
      when v_job.category = 'report' and not v_pref.daily_enabled then 'Daily email is switched off for this server'
    end;
    exit when v_end is null;
    update public.web_notification_jobs set status = 'failed', attempts = 5, error = v_end, updated_at = now()
     where id = v_job.id;
    if p_job_id is not null then return json_build_object('status', 'idle'); end if;
  end loop;

  return json_build_object('status', 'send', 'id', v_job.id, 'node_id', v_job.node_id, 'node_name', v_node.name,
    'hostname', v_node.hostname, 'owner', v_node.owner, 'recipient', v_pref.recipient,
    'fingerprint', v_job.fingerprint, 'category', v_job.category, 'severity', v_job.severity,
    'subject', v_job.subject, 'text_body', v_job.text_body, 'html_body', v_job.html_body,
    'attempts', v_job.attempts);
end $$;

notify pgrst, 'reload schema';
commit;
