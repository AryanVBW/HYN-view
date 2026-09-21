-- ===========================================================================
-- daily and system-info email are off until somebody asks for it
-- ===========================================================================
-- The incident-alert opt-in migration (20260902050000) deliberately left these
-- two on, reasoning that a health digest is not what actually paged anyone. That
-- was true at product-decision time; the account since then is the same shape
-- as before: a freshly linked node with nobody having chosen anything starts
-- mailing its owner twice a day by default, and the per-user combined digest
-- (lib/user-digest.ts, gated by HYN_DELIVERY_CONTROLS_ENABLED) already exists to
-- replace both per-node emails with one admin-schedulable message per user. A
-- default nobody chose competing with a feature built to replace it is not a
-- default worth keeping.
--
-- As with incident alerts: the column default governs nodes linked from now on,
-- the backfill switches off the existing fleet's un-chosen sends. An account that
-- wants either digest still gets it in one click on /account, or an admin can
-- turn the combined per-user digest on fleet-wide from /admin/deliveries.
alter table public.email_preferences alter column daily_enabled set default false;
alter table public.email_preferences alter column system_enabled set default false;

do $$
declare v_daily bigint; v_system bigint;
begin
  update public.email_preferences set daily_enabled = false, updated_at = now() where daily_enabled;
  get diagnostics v_daily = row_count;
  update public.email_preferences set system_enabled = false, updated_at = now() where system_enabled;
  get diagnostics v_system = row_count;
  raise notice 'daily health email switched off for % existing node preference row(s)', v_daily;
  raise notice 'system information email switched off for % existing node preference row(s)', v_system;
end;
$$;
