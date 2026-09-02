-- ===========================================================================
-- incident alert email is off until somebody asks for it
-- ===========================================================================
-- It shipped on. Every paired machine therefore started mailing its owner the
-- moment a rule fired, on an account that had never chosen to receive mail, and a
-- fleet with a real problem produced thousands of attempts a day -- the admin
-- panel's own attention banner read `4501 notifications failed in the last 24h`.
-- A default nobody chose, that fails four and a half thousand times a day, is not
-- a default: it is the loudest possible way to be ignored.
--
-- So the two per-node digests keep their defaults and this one is opt-in. Both
-- halves matter: the column default changes what a machine paired from now on
-- does, and the backfill changes what the existing fleet does, because a default
-- only ever governed rows that did not exist yet.
--
-- Note what this also switches off, since it is not obvious from the name: the
-- portal's dead-server watchdog (workflows/heartbeat-watchdog.ts) sends its
-- outage mail through the same `incident_enabled` gate. An account that wants to
-- hear about a machine going quiet has to turn Incident alerts on -- one switch on
-- /account, and the panel's own note now says so rather than leaving somebody to
-- discover it during an outage.
alter table public.email_preferences alter column incident_enabled set default false;

-- Reported rather than assumed: this runs once, against a fleet whose size the
-- next person reading the log cannot recover, and "how many accounts were mailing
-- without having asked to" is the whole justification for the change.
do $$
declare v_disabled bigint;
begin
  update public.email_preferences
     set incident_enabled = false,
         updated_at = now()
   where incident_enabled;
  get diagnostics v_disabled = row_count;
  raise notice 'incident alert email switched off for % existing node preference row(s)', v_disabled;
end;
$$;
