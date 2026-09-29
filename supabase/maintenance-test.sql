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
rollback;
