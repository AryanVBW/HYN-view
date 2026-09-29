-- Web notification jobs end: expiry, opt-outs, stale 'sending' and deferral
-- backoff (migrations/20260929100000_web_jobs_end.sql). Rolled back.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email) values ('4c000000-0000-4000-8000-000000000001','jobs@web-jobs.test');
insert into public.nodes(id,owner,name) values
  ('4c000000-0000-4000-8000-0000000000a1','4c000000-0000-4000-8000-000000000001','opted in'),
  ('4c000000-0000-4000-8000-0000000000a2','4c000000-0000-4000-8000-000000000001','opted out'),
  ('4c000000-0000-4000-8000-0000000000a3','4c000000-0000-4000-8000-000000000001','no recipient');
-- Pairing creates a preferences row per node; set the ones this test needs.
insert into public.email_preferences(node_id,recipient,incident_enabled,daily_enabled) values
  ('4c000000-0000-4000-8000-0000000000a1','owner@web-jobs.test',true,true),
  ('4c000000-0000-4000-8000-0000000000a2','owner@web-jobs.test',false,false)
on conflict (node_id) do update set recipient = excluded.recipient,
  incident_enabled = excluded.incident_enabled, daily_enabled = excluded.daily_enabled;
delete from public.email_preferences where node_id = '4c000000-0000-4000-8000-0000000000a3';
-- Anything already queued would be claimed first; park it for the test.
update public.web_notification_jobs set status='sent' where node_id not in
  ('4c000000-0000-4000-8000-0000000000a1','4c000000-0000-4000-8000-0000000000a2','4c000000-0000-4000-8000-0000000000a3');

create function pg_temp.job(p_node text, p_fp text, p_category text, p_age interval) returns uuid language sql as $$
  insert into public.web_notification_jobs(node_id,fingerprint,category,subject,text_body,created_at,updated_at)
  values (('4c000000-0000-4000-8000-0000000000' || p_node)::uuid, p_fp, p_category, 'subject ' || p_fp, 'body',
          now() - p_age, now() - p_age) returning id;
$$;
create function pg_temp.st(p_fp text) returns text language sql as $$
  select status || '/' || attempts from public.web_notification_jobs where fingerprint = p_fp;
$$;

do $$ declare r json; begin
  perform pg_temp.job('a2', 'opted-out-alert', 'alert', interval '3 hours');
  perform pg_temp.job('a3', 'no-recipient', 'test', interval '2 hours');
  perform pg_temp.job('a2', 'opted-out-report', 'report', interval '90 minutes');
  perform pg_temp.job('a1', 'deliverable', 'alert', interval '1 hour');
  r := public.hyn_claim_web_notification(null);
  if r->>'status' <> 'send' or r->>'fingerprint' <> 'deliverable' or r->>'recipient' <> 'owner@web-jobs.test' then
    raise exception 'undeliverable jobs still block the queue: %', r;
  end if;
  if pg_temp.st('opted-out-alert') <> 'failed/5' or pg_temp.st('no-recipient') <> 'failed/5'
     or pg_temp.st('opted-out-report') <> 'failed/5'
     or (select error from public.web_notification_jobs where fingerprint = 'opted-out-alert') <> 'Incident alerts are switched off for this server'
     or (select error from public.web_notification_jobs where fingerprint = 'no-recipient') <> 'No email recipient is set for this server' then
    raise exception 'jobs that cannot be sent were not closed with their reason';
  end if;
  perform public.hyn_complete_web_notification((r->>'id')::uuid, 'sent', 'owner@web-jobs.test', 'provider-1', null);
  raise notice 'PASS  jobs with no recipient or an opted-out kind end at claim and never block the queue';
end $$;

do $$ declare r json; v uuid; begin
  v := pg_temp.job('a1', 'deferred', 'alert', interval '10 minutes');
  r := public.hyn_claim_web_notification(null);
  perform public.hyn_defer_web_delivery(v, 'Automatic "incident" email is switched off.');
  if pg_temp.st('deferred') <> 'queued/0' then raise exception 'a deferral did not hand the attempt back'; end if;
  r := public.hyn_claim_web_notification(null);
  if r->>'status' <> 'idle' then raise exception 'a deferred job was offered again at once: %', r; end if;
  update public.web_notification_jobs set updated_at = now() - interval '11 minutes' where id = v;
  r := public.hyn_claim_web_notification(null);
  if r->>'fingerprint' is distinct from 'deferred' then raise exception 'a deferred job was not offered after 10 minutes'; end if;
  update public.web_notification_jobs set created_at = now() - interval '25 hours' where id = v;
  perform public.hyn_defer_web_delivery(v, 'still switched off');
  if pg_temp.st('deferred') <> 'failed/5' then raise exception 'a day-old job was deferred again: %', pg_temp.st('deferred'); end if;
  raise notice 'PASS  a deferred job waits 10 minutes, and a day-old job is closed instead of deferred';
end $$;

do $$ declare r json; begin
  perform pg_temp.job('a1', 'expired-queued', 'alert', interval '25 hours');
  perform pg_temp.job('a1', 'expired-retry', 'alert', interval '26 hours');
  update public.web_notification_jobs set status = 'failed', attempts = 2, error = 'provider timeout' where fingerprint = 'expired-retry';
  perform pg_temp.job('a1', 'expired-sending', 'alert', interval '9 days');
  update public.web_notification_jobs set status = 'sending', attempts = 1 where fingerprint = 'expired-sending';
  perform pg_temp.job('a1', 'stale-sending', 'alert', interval '20 minutes');
  update public.web_notification_jobs set status = 'sending', attempts = 1, updated_at = now() - interval '16 minutes'
   where fingerprint = 'stale-sending';
  perform pg_temp.job('a1', 'live-sending', 'alert', interval '5 minutes');
  update public.web_notification_jobs set status = 'sending', attempts = 1, updated_at = now() - interval '1 minute'
   where fingerprint = 'live-sending';
  r := public.hyn_claim_web_notification(null);
  if pg_temp.st('expired-queued') <> 'failed/5' or pg_temp.st('expired-retry') <> 'failed/5'
     or pg_temp.st('expired-sending') <> 'failed/5'
     or (select error from public.web_notification_jobs where fingerprint = 'expired-retry')
          <> 'Not delivered within 24 hours. Last reason: provider timeout' then
    raise exception 'jobs older than a day were not closed';
  end if;
  if r->>'fingerprint' is distinct from 'stale-sending' or pg_temp.st('stale-sending') <> 'sending/2' then
    raise exception 'a job a stopped worker left in sending was not offered again: %', r;
  end if;
  if pg_temp.st('live-sending') <> 'sending/1' then raise exception 'a job still being sent was taken over'; end if;
  if public.hyn_claim_web_notification(null)->>'status' <> 'idle' then raise exception 'the queue did not drain'; end if;
  raise notice 'PASS  day-old jobs close, a stopped worker''s job is retried after 15 minutes, a live send is left alone';
end $$;
rollback;
