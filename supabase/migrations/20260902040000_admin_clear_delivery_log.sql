-- ===========================================================================
-- an administrator can clear the delivery log
-- ===========================================================================
-- notification_log only ever grew. Rows leave it when a node or an Auth user is
-- deleted and never otherwise -- docs/compliance/retention-schedule.md records it
-- as the one table with no age purge -- so a fleet that has been mailing for a
-- year keeps every long-resolved failure from every machine it has ever owned.
-- The admin panel is where that log is actually read, and a wall of history is
-- what stops it being read.
--
-- Deleting rather than hiding: `target` and `error` are the most personal columns
-- in the schema (a recipient address, and a provider's verbatim reason for
-- refusing it), so keeping them out of sight but on disk is the wrong answer to
-- "we no longer need these".
--
-- p_before makes it a retention purge as well as a wipe -- null clears
-- everything, a timestamp keeps what is recent -- because an administrator
-- tidying up months of resolved failures and one destroying this morning's
-- evidence are not the same action, and only one of them is routine.
create or replace function public.hyn_admin_clear_notifications(
  p_before timestamptz default null,
  p_reason text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_deleted bigint;
begin
  perform public._hyn_require_admin();

  with gone as (
    delete from public.notification_log
     where p_before is null or ts < p_before
    returning 1
  )
  select count(*) into v_deleted from gone;

  -- Audited after the fact so the count is the real one, and audited even when it
  -- removed nothing: who cleared the log is the one thing the log can no longer
  -- say about itself.
  perform public._hyn_audit('notification_log.clear', null, null,
    jsonb_build_object('reason', p_reason, 'deleted', v_deleted, 'before', p_before));

  return json_build_object('status', 'ok', 'deleted', v_deleted);
end;
$$;

revoke all on function public.hyn_admin_clear_notifications(timestamptz, text) from public;
grant execute on function public.hyn_admin_clear_notifications(timestamptz, text) to authenticated;
