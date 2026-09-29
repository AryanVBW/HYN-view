-- Database maintenance is scheduled with pg_cron when it is installed
-- (_hyn_schedule_jobs). The harness has no pg_cron, so a stand-in with the same
-- signature and upsert-by-name behaviour records what would be scheduled, and
-- each scheduled command is then run once. Rolled back.
\set ON_ERROR_STOP on
begin;
do $$ begin
  if public._hyn_schedule_jobs() not like 'pg_cron is not installed%' then
    raise exception 'jobs were reported scheduled without pg_cron';
  end if;
end $$;
create schema cron;
create table cron.job(jobid bigserial primary key, jobname text unique, schedule text, command text);
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as $$
  insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command
  returning jobid;
$$;

do $$ declare r record; v_first text; begin
  v_first := public._hyn_schedule_jobs();
  if public._hyn_schedule_jobs() <> v_first or (select count(*) from cron.job) <> substring(v_first from '[0-9]+$')::integer
     or (select count(distinct jobname) from cron.job) <> (select count(*) from cron.job) then
    raise exception 'scheduling twice changed the job list: % / %', v_first, (select count(*) from cron.job);
  end if;
  if not exists(select 1 from cron.job where jobname = 'hyn-telemetry-retention' and schedule = '*/5 * * * *'
                and command = 'select public.hyn_prune_telemetry(5000)') then
    raise exception 'telemetry retention is not scheduled every five minutes';
  end if;
  for r in select jobname, command from cron.job order by jobname loop
    execute r.command;
  end loop;
  raise notice 'PASS  database maintenance is scheduled once per job by name, and every scheduled command runs';
end $$;

do $$ declare v_node uuid := '4d000000-0000-4000-8000-0000000000a1'; v_owner uuid := '4d000000-0000-4000-8000-000000000001';
  v_log bigint := (select count(*) from public.notification_log); v_audit bigint := (select count(*) from public.admin_audit);
  r jsonb;
begin
  if not exists(select 1 from cron.job where jobname = 'hyn-delivery-retention' and schedule = '17 * * * *') then
    raise exception 'delivery history retention is not scheduled hourly';
  end if;
  if not exists(select 1 from cron.job where jobname = 'hyn-outage-sweep' and schedule = '* * * * *') then
    raise exception 'the outage sweep is not scheduled every minute';
  end if;
  insert into auth.users(id,email) values (v_owner,'retention@maintenance.test');
  insert into public.nodes(id,owner,name) values (v_node, v_owner, 'retention node');
  insert into public.web_notification_jobs(node_id,fingerprint,status,attempts,subject,text_body,created_at,updated_at) values
    (v_node,'sent-old','sent',1,'s','b',now()-interval '40 days',now()-interval '31 days'),
    (v_node,'sent-recent','sent',1,'s','b',now()-interval '40 days',now()-interval '29 days'),
    (v_node,'failed-final-old','failed',5,'s','b',now()-interval '40 days',now()-interval '31 days'),
    (v_node,'failed-retry-old','failed',2,'s','b',now()-interval '40 days',now()-interval '31 days'),
    (v_node,'queued-old','queued',0,'s','b',now()-interval '40 days',now()-interval '31 days');
  insert into public.delivery_events(id,source_key,owner,node_id,kind,recipient,subject,status,terminal,updated_at) values
    ('4d000000-0000-4000-8000-0000000000e1','retention:old',v_owner,v_node,'incident','r@maintenance.test','s','sent',true,now()-interval '91 days'),
    ('4d000000-0000-4000-8000-0000000000e2','retention:recent',v_owner,v_node,'incident','r@maintenance.test','s','sent',true,now()-interval '89 days');
  insert into public.delivery_attempts(event_id,status) values ('4d000000-0000-4000-8000-0000000000e1','sent'),('4d000000-0000-4000-8000-0000000000e2','sent');
  insert into public.cloud_email_dispatches(idempotency_key,node_id,kind,created_at) values
    ('retention:dispatch-old',v_node,'report',now()-interval '31 days'),('retention:dispatch-recent',v_node,'report',now()-interval '1 day'),
    ('first-system:' || v_node,v_node,'system',now()-interval '400 days'),('device-linked:' || v_node,v_node,'system',now()-interval '400 days');
  r := public._hyn_prune_delivery_history(5000);
  if (select string_agg(fingerprint, ',' order by fingerprint) from public.web_notification_jobs where node_id = v_node)
       <> 'failed-retry-old,queued-old,sent-recent' then
    raise exception 'finished-job retention removed the wrong jobs: %', r;
  end if;
  if (select string_agg(source_key, ',') from public.delivery_events where owner = v_owner) <> 'retention:recent'
     or (select count(*) from public.delivery_attempts where event_id in ('4d000000-0000-4000-8000-0000000000e1','4d000000-0000-4000-8000-0000000000e2')) <> 1
     or (select string_agg(split_part(idempotency_key, ':', 1) || ':' || case when idempotency_key like 'retention:%' then split_part(idempotency_key, ':', 2) else 'node' end, ',' order by idempotency_key)
           from public.cloud_email_dispatches where node_id = v_node) <> 'device-linked:node,first-system:node,retention:dispatch-recent' then
    raise exception 'delivery ledger retention removed the wrong rows: %', r;
  end if;
  if (select count(*) from public.notification_log) <> v_log or (select count(*) from public.admin_audit) <> v_audit then
    raise exception 'delivery retention touched the delivery log or the audit trail';
  end if;
  raise notice 'PASS  finished jobs go after 30 days, the delivery ledger after 90, one-time email keys, the log and audit trail stay';
end $$;
rollback;
