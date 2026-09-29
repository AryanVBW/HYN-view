-- The database schedules its own maintenance whenever pg_cron is installed.
--
-- The schedule was created only if pg_cron already existed at the moment the
-- schema was applied. The self-hosted database restored on 2026-09-20 has
-- pg_cron 1.6.4 preloaded but had no jobs at all, so telemetry cleanup depended
-- on the portal's 10-minute host cron reaching /api/cron/email.
--
-- _hyn_schedule_jobs() creates or updates every HYN job by name, so it is safe to
-- re-run. Run it again after enabling pg_cron on an existing database:
--   select public._hyn_schedule_jobs();
begin;

create or replace function public._hyn_schedule_jobs()
returns text language plpgsql set search_path = public as $$
declare r record; n integer := 0;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    return 'pg_cron is not installed: no database jobs scheduled';
  end if;
  for r in select * from (values
    ('hyn-telemetry-retention', '*/5 * * * *', 'select public.hyn_prune_telemetry(5000)')
  ) j(name, schedule, command) loop
    perform cron.schedule(r.name, r.schedule, r.command);
    n := n + 1;
  end loop;
  return format('pg_cron jobs scheduled: %s', n);
end $$;
revoke all on function public._hyn_schedule_jobs() from public, anon, authenticated;

do $$ begin raise notice '%', public._hyn_schedule_jobs(); end $$;

commit;
