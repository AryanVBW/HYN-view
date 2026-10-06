\set ON_ERROR_STOP on
-- Subscription billing. now() is fixed inside the transaction, so elapsed time
-- is simulated by moving stored timestamps into the past.
\set QUIET on
\pset tuples_only on
begin;
create function pg_temp.check_billing(ok boolean, label text) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FAIL billing: %', label; end if;
  raise notice 'PASS billing: %', label;
end $$;
create function pg_temp.raises(sql text, expected text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if position(expected in sqlerrm) = 0 then raise exception 'expected "%" from %, got "%"', expected, sql, sqlerrm; end if;
  return true;
end $$;
create function pg_temp.sub(u uuid) returns public.billing_subscriptions language sql as $$
  select * from public.billing_subscriptions where user_id = u order by created_at desc, id limit 1;
$$;
create function pg_temp.open_inv(u uuid) returns public.billing_invoices language sql as $$
  select * from public.billing_invoices where user_id = u and status = 'open';
$$;
create function pg_temp.raise_one(u uuid) returns public.billing_charges language plpgsql as $$
declare t jsonb; c public.billing_charges;
begin
  t := public.hyn_billing_svc_tick((pg_temp.sub(u)).id);
  if jsonb_array_length(t->'raise') <> 1 then raise exception 'expected one charge to raise, got %', t; end if;
  perform public.hyn_billing_svc_charge_raised((t->'raise'->0->>'charge_id')::uuid, true, 'cf-' || (t->'raise'->0->>'payment_id'),
    'PENDING', current_date + 1, null, false);
  select * into c from public.billing_charges where id = (t->'raise'->0->>'charge_id')::uuid;
  return c;
end $$;
create function pg_temp.activate(u uuid, p_phone text default '9876543210') returns void language plpgsql as $$
declare r jsonb; m public.billing_mandates;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('test.uid', u::text, true);
  r := public.hyn_billing_begin_checkout(1, null, p_phone);
  perform set_config('role', 'postgres', true);
  perform public.hyn_billing_svc_mandate_created((r->>'mandate_id')::uuid, true, 'session', 'cf', null);
  perform public.hyn_billing_svc_mandate_status(r->>'cf_subscription_id', 'ACTIVE', 'upi', now());
end $$;

insert into auth.users(id, email) values
 ('b1000000-0000-4000-8000-000000000001', 'super@billing.test'),
 ('b1000000-0000-4000-8000-000000000002', 'legacy@billing.test'),
 ('b1000000-0000-4000-8000-000000000003', 'new@billing.test'),
 ('b1000000-0000-4000-8000-000000000004', 'manual@billing.test'),
 ('b1000000-0000-4000-8000-000000000005', 'admin@billing.test'),
 ('b1000000-0000-4000-8000-000000000006', 'coupon@billing.test');
update public.profiles set status = 'active', full_name = split_part(email, '@', 1),
  role = case right(id::text, 1) when '1' then 'super_admin' when '5' then 'admin' else 'monitor' end
 where email like '%@billing.test';
insert into public.nodes(id, owner, name, token_hash) values
 ('b2000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000002', 'legacy one', public._hyn_sha256('billing-legacy-1')),
 ('b2000000-0000-4000-8000-000000000002', 'b1000000-0000-4000-8000-000000000002', 'legacy two', null),
 ('b2000000-0000-4000-8000-000000000005', 'b1000000-0000-4000-8000-000000000005', 'staff box', null);

-- ---------------------------------------------------------------------------
-- pricing and calendar
-- ---------------------------------------------------------------------------
select pg_temp.check_billing(
  (public._hyn_billing_price(2, 9900, 1, '[]', 1, '[{"id":"00000000-0000-4000-8000-000000000001","kind":"first_month","amount_off":5000,"label":"Welcome"},
    {"id":"00000000-0000-4000-8000-000000000002","kind":"ongoing","percent_off":10,"label":"Loyal"}]')->>'total')::bigint = 12820,
  'ongoing discount comes off first, then the first-month discount (19800 - 10% - 5000)');
select pg_temp.check_billing(
  (public._hyn_billing_price(2, 9900, 1, '[]', 2, '[{"id":"00000000-0000-4000-8000-000000000001","kind":"first_month","amount_off":5000,"label":"Welcome"},
    {"id":"00000000-0000-4000-8000-000000000002","kind":"ongoing","percent_off":10,"label":"Loyal"}]')->>'total')::bigint = 17820,
  'a first-month discount is ignored after cycle 1');
select pg_temp.check_billing(
  (public._hyn_billing_price(1, 9900, 3, '[]', 1, '[{"id":"00000000-0000-4000-8000-000000000002","kind":"ongoing","percent_off":10,"label":"Loyal"}]')->>'total')::bigint = 29700,
  'multi-month invoices are not discounted');
select pg_temp.check_billing(
  (public._hyn_billing_price(1, 9900, 1, '[]', 1, '[{"id":"00000000-0000-4000-8000-000000000001","kind":"first_month","amount_off":9850,"label":"Almost"}]')->>'total')::bigint = 0
  and (public._hyn_billing_price(1, 9900, 1, '[]', 1, '[{"id":"00000000-0000-4000-8000-000000000001","kind":"first_month","amount_off":20000,"label":"Big"}]')->>'discount_total')::bigint = 9900,
  'totals under Rs 1 are not charged and amount discounts are capped');
select pg_temp.check_billing(
  (public._hyn_billing_price(1, 9900, 1, '[{"id":"x","description":"proration","amount":3300}]', 2, '[]')->>'total')::bigint = 13200,
  'pending adjustments are added to the subtotal');
select pg_temp.check_billing(
  public._hyn_billing_add_months('2026-01-31 10:00+05:30', 31, 1) = '2026-02-28 10:00+05:30'
  and public._hyn_billing_add_months('2026-01-31 10:00+05:30', 31, 2) = '2026-03-31 10:00+05:30'
  and public._hyn_billing_add_months('2026-02-28 23:30+05:30', 31, 1) = '2026-03-31 23:30+05:30',
  'monthly periods keep the IST anchor day and fall back to the last day of short months');

-- ---------------------------------------------------------------------------
-- launch: existing customers keep access through a legacy trial
-- ---------------------------------------------------------------------------
select pg_temp.check_billing(public._hyn_billing_owner_access('b1000000-0000-4000-8000-000000000003'),
  'nobody is gated before billing is launched');
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000005';
select pg_temp.check_billing(pg_temp.raises('select public.hyn_admin_billing_launch(14)', 'super administrator role required'),
  'an ordinary admin cannot launch billing');
select pg_temp.check_billing(pg_temp.raises('select public.hyn_admin_billing_set_enforce(true)', 'super administrator role required'),
  'an ordinary admin cannot switch enforcement');
set local "test.uid" = 'b1000000-0000-4000-8000-000000000001';
select pg_temp.check_billing(pg_temp.raises('select public.hyn_admin_billing_set_enforce(true)', 'Launch billing first'),
  'enforcement cannot be switched on before the launch creates legacy trials');
select pg_temp.check_billing((public.hyn_admin_billing_launch(14)->>'legacy_trials')::integer = 1,
  'launch creates one legacy trial (staff and server-less accounts get none)');
reset role;
select pg_temp.check_billing((select enforce from public.billing_settings where id = 1), 'launch switches enforcement on');
select pg_temp.check_billing((select s.status = 'trialing' and s.legacy and s.quantity = 2 and s.trial_ends_at > now() + interval '13 days'
    from public.billing_subscriptions s where s.user_id = 'b1000000-0000-4000-8000-000000000002'),
  'the legacy trial covers every server the customer already had');
select pg_temp.check_billing(not exists(select 1 from public.nodes where owner = 'b1000000-0000-4000-8000-000000000002' and status <> 'active'),
  'legacy servers keep reporting');

-- ---------------------------------------------------------------------------
-- linking is gated
-- ---------------------------------------------------------------------------
select pg_temp.check_billing(pg_temp.raises($$insert into public.nodes(owner, name) values ('b1000000-0000-4000-8000-000000000003', 'x')$$,
  'An active HYN-view subscription is required'), 'linking without a plan is refused');
select pg_temp.check_billing(pg_temp.raises($$insert into public.nodes(owner, name) values ('b1000000-0000-4000-8000-000000000002', 'x')$$,
  'All 2 server slots'), 'linking beyond the plan''s slots is refused');
insert into public.nodes(id, owner, name) values ('b2000000-0000-4000-8000-000000000006', 'b1000000-0000-4000-8000-000000000005', 'staff two');
select pg_temp.check_billing(true, 'staff link without a plan');
insert into public.nodes(id, owner, name, is_demo) values ('b2000000-0000-4000-8000-000000000007', 'b1000000-0000-4000-8000-000000000003', 'demo', true);
select pg_temp.check_billing(true, 'demo servers are not gated');

-- ---------------------------------------------------------------------------
-- checkout -> autopay mandate -> first invoice -> first charge
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000003';
select pg_temp.check_billing(pg_temp.raises($$select public.hyn_billing_begin_checkout(1, null, '12345')$$, '10-digit Indian mobile'),
  'checkout needs a valid Indian mobile number');
select pg_temp.check_billing(pg_temp.raises($$select public.hyn_billing_begin_checkout(0, null, '9876543210')$$, 'between 1 and 1000'),
  'checkout needs at least one server');
select pg_temp.check_billing(pg_temp.raises('select public.hyn_billing_svc_tick()', 'permission denied'),
  'a signed-in user cannot run the billing job');
do $$ declare r jsonb; begin
  r := public.hyn_billing_begin_checkout(1, null, '+91 98765-43210');
  if r->>'phone' <> '9876543210' or (r->>'auth_amount')::bigint <> 200 or r->>'cf_subscription_id' !~ '^hyn_[0-9a-f]{32}$'
     or (r->>'max_amount')::bigint < 19800 then
    raise exception 'unexpected checkout %', r;
  end if;
  perform set_config('test.mandate', r->>'mandate_id', true);
  perform set_config('test.cfsub', r->>'cf_subscription_id', true);
end $$;
select pg_temp.check_billing((public.hyn_billing_summary()->'subscription'->>'status') = 'incomplete'
    and not (public.hyn_billing_summary()->>'has_access')::boolean,
  'an unfinished checkout gives no access');
reset role;
select pg_temp.check_billing((public.hyn_billing_svc_mandate_created(current_setting('test.mandate')::uuid, true, 'sess_1', 'cf_1', null)->>'status') = 'INITIALIZED',
  'the mandate is recorded once Cashfree creates it');
select pg_temp.check_billing((public.hyn_billing_svc_mandate_status(current_setting('test.cfsub'), 'BANK_APPROVAL_PENDING', null, now() - interval '1 minute')->>'status') = 'applied'
    and (pg_temp.sub('b1000000-0000-4000-8000-000000000003')).status = 'incomplete',
  'a pending bank approval keeps the plan incomplete');
select pg_temp.check_billing((public.hyn_billing_svc_mandate_status(current_setting('test.cfsub'), 'ACTIVE', 'upi', now())->>'mandate_status') = 'ACTIVE',
  'mandate activation is applied');
select pg_temp.check_billing((public.hyn_billing_svc_mandate_status(current_setting('test.cfsub'), 'BANK_APPROVAL_PENDING', null, now() - interval '30 seconds')->>'status') = 'stale',
  'an older webhook cannot roll the mandate back');
select pg_temp.check_billing((select s.status = 'active' and s.collection = 'auto' and s.current_mandate_id = current_setting('test.mandate')::uuid
    from public.billing_subscriptions s where s.user_id = 'b1000000-0000-4000-8000-000000000003'),
  'an active mandate starts the plan with provisional access');
select pg_temp.check_billing((select i.kind = 'first' and i.total = 9900 and i.cycle_number = 1 and i.next_attempt_at is not null
    from pg_temp.open_inv('b1000000-0000-4000-8000-000000000003') i),
  'the first invoice is finalised and queued for charging');
insert into public.nodes(id, owner, name, token_hash) values ('b2000000-0000-4000-8000-000000000003', 'b1000000-0000-4000-8000-000000000003', 'new one', public._hyn_sha256('billing-new-1'));
select pg_temp.check_billing(pg_temp.raises($$insert into public.nodes(owner, name) values ('b1000000-0000-4000-8000-000000000003', 'x')$$, 'All 1 server slot on'),
  'a one-server plan links exactly one server');
select set_config('test.charge', (pg_temp.raise_one('b1000000-0000-4000-8000-000000000003')).id::text, true);
select pg_temp.check_billing((select c.status = 'pending' and c.amount = 9900 and c.attempt = 1 from public.billing_charges c where c.id = current_setting('test.charge')::uuid),
  'the billing job hands out exactly one charge for the invoice');
select pg_temp.check_billing(jsonb_array_length(public.hyn_billing_svc_tick((pg_temp.sub('b1000000-0000-4000-8000-000000000003')).id)->'raise') = 0,
  'a charge in flight is never raised twice');
select pg_temp.check_billing((pg_temp.sub('b1000000-0000-4000-8000-000000000003')).status = 'active',
  'the plan stays active while the first charge is in flight');
select pg_temp.check_billing((public.hyn_billing_svc_charge_status((select payment_id from public.billing_charges where id = current_setting('test.charge')::uuid),
    'SUCCESS', 'cfp_1', null, now())->>'status') = 'applied', 'charge success is applied');
select pg_temp.check_billing((public.hyn_billing_svc_charge_status((select payment_id from public.billing_charges where id = current_setting('test.charge')::uuid),
    'FAILED', 'cfp_1', 'late failure', now())->>'status') = 'final', 'a successful charge cannot be failed afterwards');
select pg_temp.check_billing((select s.status = 'active' and s.cycle_count = 1 and s.paid_through > now() + interval '27 days'
      and s.access_ends_at = s.paid_through
    from public.billing_subscriptions s where s.user_id = 'b1000000-0000-4000-8000-000000000003')
  and pg_temp.open_inv('b1000000-0000-4000-8000-000000000003') is null,
  'payment covers one month from the start of the period');

-- A debit for an invoice that is already settled is flagged for a refund.
insert into public.billing_charges(invoice_id, mandate_id, payment_id, attempt, amount, status)
select id, current_setting('test.mandate')::uuid, 'dup-payment', 2, total, 'cancelling'
  from public.billing_invoices where user_id = 'b1000000-0000-4000-8000-000000000003' and status = 'paid';
select public.hyn_billing_svc_charge_status('dup-payment', 'SUCCESS', 'cfp_dup', null, now());
select pg_temp.check_billing((select needs_refund from public.billing_invoices where user_id = 'b1000000-0000-4000-8000-000000000003' and status = 'paid'),
  'a duplicate debit is flagged for a refund');
update public.billing_invoices set needs_refund = false where user_id = 'b1000000-0000-4000-8000-000000000003';

-- ---------------------------------------------------------------------------
-- renewal, failed payments, retries, grace, hold and late payment
-- ---------------------------------------------------------------------------
update public.billing_subscriptions set paid_through = now() + interval '2 days' where user_id = 'b1000000-0000-4000-8000-000000000003';
select set_config('test.charge', (pg_temp.raise_one('b1000000-0000-4000-8000-000000000003')).id::text, true);
select pg_temp.check_billing((select i.kind = 'renewal' and i.cycle_number = 2 and i.due_at = now() + interval '2 days'
    from pg_temp.open_inv('b1000000-0000-4000-8000-000000000003') i),
  'the renewal invoice is finalised renewal_lead_days before the period ends');
select public.hyn_billing_svc_charge_status((select payment_id from public.billing_charges where id = current_setting('test.charge')::uuid),
  'FAILED', null, 'insufficient funds', now());
select pg_temp.check_billing((select i.next_attempt_at = now() + interval '2 days' and i.attempts = 1
    from pg_temp.open_inv('b1000000-0000-4000-8000-000000000003') i),
  'a failed charge is retried after retry_interval_days');
select pg_temp.check_billing((pg_temp.sub('b1000000-0000-4000-8000-000000000003')).status = 'active',
  'a failure before the due date leaves the plan active');
-- Due date passes.
update public.billing_invoices set due_at = now() - interval '1 day 1 minute', period_start = now() - interval '1 day 1 minute'
 where user_id = 'b1000000-0000-4000-8000-000000000003' and status = 'open';
update public.billing_subscriptions set paid_through = now() - interval '1 day 1 minute' where user_id = 'b1000000-0000-4000-8000-000000000003';
select public.hyn_billing_svc_tick((pg_temp.sub('b1000000-0000-4000-8000-000000000003')).id);
select pg_temp.check_billing((pg_temp.sub('b1000000-0000-4000-8000-000000000003')).status = 'past_due'
    and public._hyn_billing_owner_access('b1000000-0000-4000-8000-000000000003')
    and (select status = 'active' from public.nodes where id = 'b2000000-0000-4000-8000-000000000003'),
  'past due keeps service during the grace period');
-- Grace period ends.
update public.billing_invoices set due_at = now() - interval '8 days' where user_id = 'b1000000-0000-4000-8000-000000000003' and status = 'open';
update public.billing_subscriptions set paid_through = now() - interval '8 days' where user_id = 'b1000000-0000-4000-8000-000000000003';
select public.hyn_billing_svc_tick((pg_temp.sub('b1000000-0000-4000-8000-000000000003')).id);
select pg_temp.check_billing((pg_temp.sub('b1000000-0000-4000-8000-000000000003')).status = 'unpaid'
    and not public._hyn_billing_owner_access('b1000000-0000-4000-8000-000000000003'),
  'after the grace period the plan is unpaid and loses access');
select pg_temp.check_billing((select status = 'suspended' and billing_hold and status_reason like 'Billing:%' from public.nodes where id = 'b2000000-0000-4000-8000-000000000003'),
  'an unpaid plan puts its servers on a billing hold');
set local role anon;
select pg_temp.check_billing(pg_temp.raises($$select public.hyn_ingest('billing-new-1', jsonb_build_object('ts', now(), 'cpu', jsonb_build_object('pct', 5)))$$,
  'node suspended: Billing:'), 'a held server''s reports are refused with the billing reason');
reset role;
select pg_temp.check_billing((select status = 'active' from public.nodes where id = 'b2000000-0000-4000-8000-000000000001'),
  'other customers are unaffected');
-- An administrator suspends the held server meanwhile; billing must not undo it.
update public.nodes set status_reason = 'Abuse review' where id = 'b2000000-0000-4000-8000-000000000003';
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000003';
select pg_temp.check_billing((public.hyn_billing_retry_payment()->>'status') = 'queued', 'the customer can retry payment');
select pg_temp.check_billing(pg_temp.raises('select public.hyn_billing_set_quantity(2)', 'Settle the outstanding invoice'),
  'plan changes wait until the outstanding invoice is settled');
reset role;
select set_config('test.charge', (pg_temp.raise_one('b1000000-0000-4000-8000-000000000003')).id::text, true);
select public.hyn_billing_svc_charge_status((select payment_id from public.billing_charges where id = current_setting('test.charge')::uuid),
  'SUCCESS', 'cfp_2', null, now());
select pg_temp.check_billing((select s.status = 'active' and s.paid_through > now() + interval '27 days' and s.current_period_start = now() and s.unpaid_since is null
    from public.billing_subscriptions s where s.user_id = 'b1000000-0000-4000-8000-000000000003'),
  'a late payment restarts the period from the payment, so lost days are not billed');
select pg_temp.check_billing((select status = 'suspended' and not billing_hold and status_reason = 'Abuse review' from public.nodes where id = 'b2000000-0000-4000-8000-000000000003'),
  'payment lifts the billing hold but leaves an administrator''s suspension');
update public.nodes set status = 'active', status_reason = null where id = 'b2000000-0000-4000-8000-000000000003';

-- ---------------------------------------------------------------------------
-- cancellation
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000003';
select pg_temp.check_billing((public.hyn_billing_cancel()->>'status') = 'cancel_at_period_end', 'a paid plan cancels at the period end');
select pg_temp.check_billing((public.hyn_billing_summary()->>'has_access')::boolean, 'access continues until the paid time runs out');
select pg_temp.check_billing((public.hyn_billing_resume()->>'status') = 'resumed', 'a scheduled cancellation can be undone');
select public.hyn_billing_cancel();
reset role;
update public.billing_subscriptions set paid_through = now() + interval '1 day' where user_id = 'b1000000-0000-4000-8000-000000000003';
select public.hyn_billing_svc_tick((pg_temp.sub('b1000000-0000-4000-8000-000000000003')).id);
select pg_temp.check_billing(pg_temp.open_inv('b1000000-0000-4000-8000-000000000003') is null,
  'no renewal is finalised for a plan that is ending');
update public.billing_subscriptions set paid_through = now() - interval '1 minute' where user_id = 'b1000000-0000-4000-8000-000000000003';
do $$ declare t jsonb; begin
  t := public.hyn_billing_svc_tick((pg_temp.sub('b1000000-0000-4000-8000-000000000003')).id);
  if jsonb_array_length(t->'cancel_mandates') <> 1 then raise exception 'mandate not handed out for cancellation: %', t; end if;
  perform public.hyn_billing_svc_mandate_cancel_result((t->'cancel_mandates'->0->>'mandate_id')::uuid, true, null);
end $$;
select pg_temp.check_billing((select s.status = 'canceled' and s.cancel_reason = 'canceled_by_user' from public.billing_subscriptions s
    where s.user_id = 'b1000000-0000-4000-8000-000000000003')
  and (select status = 'CANCELLED' from public.billing_mandates where id = current_setting('test.mandate')::uuid),
  'the plan ends at the period end and its mandate is cancelled');
select pg_temp.check_billing((select status = 'suspended' and billing_hold from public.nodes where id = 'b2000000-0000-4000-8000-000000000003'),
  'servers stop monitoring once a plan has ended');
select pg_temp.check_billing((public.hyn_billing_svc_mandate_status(current_setting('test.cfsub'), 'ACTIVE', 'upi', now() + interval '1 minute')->>'status') = 'final',
  'a cancelled mandate cannot be revived by a late webhook');

-- ---------------------------------------------------------------------------
-- legacy trial -> autopay -> first charge at the trial end; plan changes
-- ---------------------------------------------------------------------------
select pg_temp.activate('b1000000-0000-4000-8000-000000000002');
select pg_temp.check_billing((select s.status = 'trialing' and s.collection = 'auto' and s.current_mandate_id is not null
    from public.billing_subscriptions s where s.user_id = 'b1000000-0000-4000-8000-000000000002')
  and pg_temp.open_inv('b1000000-0000-4000-8000-000000000002') is null,
  'autopay during a legacy trial charges nothing until the trial ends');
update public.billing_subscriptions set trial_ends_at = now() + interval '2 days', access_ends_at = now() + interval '2 days'
 where user_id = 'b1000000-0000-4000-8000-000000000002';
select set_config('test.charge', (pg_temp.raise_one('b1000000-0000-4000-8000-000000000002')).id::text, true);
select pg_temp.check_billing((select i.total = 19800 and i.due_at = now() + interval '2 days' and i.period_start = now() + interval '2 days'
    from pg_temp.open_inv('b1000000-0000-4000-8000-000000000002') i)
  and (pg_temp.sub('b1000000-0000-4000-8000-000000000002')).status = 'trialing',
  'the first charge is for every server and covers the month after the trial');
select public.hyn_billing_svc_charge_status((select payment_id from public.billing_charges where id = current_setting('test.charge')::uuid),
  'SUCCESS', 'cfp_3', null, now());
select pg_temp.check_billing((select s.status = 'active' and s.paid_through > now() + interval '29 days' from public.billing_subscriptions s
    where s.user_id = 'b1000000-0000-4000-8000-000000000002'),
  'paying ahead of the trial end does not shorten the trial');
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000002';
select pg_temp.check_billing((public.hyn_billing_set_quantity(3)->>'proration')::bigint = 9900,
  'adding a server bills the remaining share of every period already billed');
reset role;
insert into public.nodes(id, owner, name) values ('b2000000-0000-4000-8000-000000000004', 'b1000000-0000-4000-8000-000000000002', 'legacy three');
select pg_temp.check_billing(true, 'the added slot can be used at once');
set local role authenticated;
select pg_temp.check_billing(pg_temp.raises('select public.hyn_billing_set_quantity(2)', 'You have 3 linked servers'),
  'a plan cannot drop below the linked servers');
reset role;
delete from public.nodes where id = 'b2000000-0000-4000-8000-000000000004';
set local role authenticated;
select pg_temp.check_billing((select (r->>'quantity')::int = 3 and (r->>'pending_quantity')::int = 2 from public.hyn_billing_set_quantity(2) r),
  'a decrease takes effect at the next renewal');
reset role;
update public.billing_subscriptions set paid_through = now() + interval '1 day' where user_id = 'b1000000-0000-4000-8000-000000000002';
select public.hyn_billing_svc_tick((pg_temp.sub('b1000000-0000-4000-8000-000000000002')).id);
select pg_temp.check_billing((select i.quantity = 2 and i.total = 19800 + 9900 from pg_temp.open_inv('b1000000-0000-4000-8000-000000000002') i)
  and (pg_temp.sub('b1000000-0000-4000-8000-000000000002')).quantity = 2,
  'the renewal applies the lower count and carries the proration');

-- ---------------------------------------------------------------------------
-- admin assigns a plan and settles payment received directly
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000005';
select pg_temp.check_billing(pg_temp.raises($$select public.hyn_admin_billing_assign('b1000000-0000-4000-8000-000000000004', 2, 5000, 3, 'manual', true, 'cash')$$,
  'super administrator role required'), 'an ordinary admin cannot assign plans');
select pg_temp.check_billing(jsonb_array_length(public.hyn_admin_billing_dashboard()->'subscriptions') >= 2, 'an ordinary admin can read the billing dashboard');
set local "test.uid" = 'b1000000-0000-4000-8000-000000000001';
select pg_temp.check_billing(pg_temp.raises($$select public.hyn_admin_billing_assign('b1000000-0000-4000-8000-000000000005', 1, null, 1, 'manual', false)$$,
  'Staff accounts are exempt'), 'staff cannot be put on a plan');
select pg_temp.check_billing(pg_temp.raises($$select public.hyn_admin_billing_assign('b1000000-0000-4000-8000-000000000004', 2, 5000, 3, 'manual', true, null)$$,
  'Choose how the payment was received'), 'a settled assignment records how it was paid');
select pg_temp.check_billing((select r->>'invoice_status' = 'paid' and (r->>'total')::bigint = 30000
    from public.hyn_admin_billing_assign('b1000000-0000-4000-8000-000000000004', 2, 5000, 3, 'manual', true, 'cash', 'R-1', 'paid at the office') r),
  'an admin assigns a three-month plan at a custom price, paid in cash');
reset role;
select pg_temp.check_billing((select s.status = 'active' and s.collection = 'manual' and s.quantity = 2 and s.paid_through > now() + interval '88 days'
    from public.billing_subscriptions s where s.user_id = 'b1000000-0000-4000-8000-000000000004')
  and (select count(*) = 1 from public.billing_manual_payments where user_id = 'b1000000-0000-4000-8000-000000000004'),
  'the assigned plan is active for the paid months');
insert into public.nodes(owner, name) values ('b1000000-0000-4000-8000-000000000004', 'manual a'), ('b1000000-0000-4000-8000-000000000004', 'manual b');
select pg_temp.check_billing(true, 'an assigned plan can link its servers');
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000004';
select pg_temp.check_billing(pg_temp.raises('select public.hyn_billing_cancel()', 'billed manually'), 'a manual plan is cancelled by an administrator');
set local "test.uid" = 'b1000000-0000-4000-8000-000000000001';
select public.hyn_admin_billing_assign('b1000000-0000-4000-8000-000000000004', 2, 5000, 1, 'manual', false);
select pg_temp.check_billing(pg_temp.raises($$select public.hyn_admin_billing_assign('b1000000-0000-4000-8000-000000000004', 2, 5000, 1, 'manual', false)$$,
  'has an open invoice'), 'a second assignment waits for the open invoice');
reset role;
select set_config('test.invoice', (pg_temp.open_inv('b1000000-0000-4000-8000-000000000004')).id::text, true);
set local role authenticated;
select pg_temp.check_billing(pg_temp.raises(format('select public.hyn_admin_billing_record_payment(%L, 9999, %L)', current_setting('test.invoice'), 'upi'),
  'must equal the invoice total'), 'a manual payment must match the invoice');
select public.hyn_admin_billing_record_payment(current_setting('test.invoice')::uuid, 10000, 'bank_transfer', 'UTR123');
reset role;
select pg_temp.check_billing((select s.paid_through > now() + interval '118 days' from public.billing_subscriptions s
    where s.user_id = 'b1000000-0000-4000-8000-000000000004'),
  'a further month is added after the time already paid for');
select pg_temp.check_billing(jsonb_array_length(public.hyn_billing_svc_tick((pg_temp.sub('b1000000-0000-4000-8000-000000000004')).id)->'raise') = 0,
  'manual plans are never charged automatically');
update public.billing_subscriptions set paid_through = now() + interval '1 day' where user_id = 'b1000000-0000-4000-8000-000000000004';
select public.hyn_billing_svc_tick((pg_temp.sub('b1000000-0000-4000-8000-000000000004')).id);
select pg_temp.check_billing((select i.collection = 'manual' and i.total = 10000 and i.next_attempt_at is null
    from pg_temp.open_inv('b1000000-0000-4000-8000-000000000004') i),
  'a manual plan still gets a renewal invoice to settle');

-- ---------------------------------------------------------------------------
-- coupons and discounts
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000001';
select public.hyn_admin_billing_save_coupon('{"code":"welcome50","name":"Welcome 50%","kind":"first_month","percent_off":50}');
select public.hyn_admin_billing_save_coupon('{"code":"LOYAL10","name":"Loyal 10%","kind":"ongoing","percent_off":10,"duration_months":2}');
select public.hyn_admin_billing_save_coupon('{"code":"ONCE","name":"Once","kind":"ongoing","amount_off":1000,"max_redemptions":1}');
select pg_temp.check_billing(pg_temp.raises($$select public.hyn_admin_billing_save_coupon('{"code":"WELCOME50","name":"Again","kind":"first_month","percent_off":5}')$$,
  'already exists'), 'coupon codes are unique');
select pg_temp.check_billing(pg_temp.raises($$select public.hyn_admin_billing_save_coupon('{"code":"BOTH","name":"Both","kind":"ongoing","percent_off":5,"amount_off":100}')$$,
  'Check the coupon'), 'a coupon is either a percentage or an amount');
set local "test.uid" = 'b1000000-0000-4000-8000-000000000006';
select pg_temp.check_billing((select (r->>'total')::bigint = 4950 and (r->'coupon'->>'valid')::boolean from public.hyn_billing_preview(1, 'welcome50') r),
  'the checkout preview applies a first-month code');
select pg_temp.check_billing((select not (r->'coupon'->>'valid')::boolean and (r->>'total')::bigint = 9900 from public.hyn_billing_preview(1, 'NOPE') r),
  'an unknown code is reported without failing the preview');
select public.hyn_billing_begin_checkout(1, 'WELCOME50', '9876543210');
reset role;
select pg_temp.check_billing((select redemptions = 1 from public.billing_coupons where code = 'WELCOME50'), 'a code counts as redeemed at checkout');
set local role authenticated;
select public.hyn_billing_begin_checkout(1, null, '9876543210');
reset role;
select pg_temp.check_billing((select redemptions = 0 from public.billing_coupons where code = 'WELCOME50')
    and not exists(select 1 from public.billing_discounts where user_id = 'b1000000-0000-4000-8000-000000000006' and status = 'active'),
  'a retried checkout without the code gives the redemption back');
set local role authenticated;
select set_config('test.checkout', public.hyn_billing_begin_checkout(1, 'WELCOME50', '9876543210')::text, true);
reset role;
select public.hyn_billing_svc_mandate_created((current_setting('test.checkout')::jsonb->>'mandate_id')::uuid, true, 's', 'c', null);
select public.hyn_billing_svc_mandate_status(current_setting('test.checkout')::jsonb->>'cf_subscription_id', 'ACTIVE', 'card', now());
select pg_temp.check_billing((select i.total = 4950 from pg_temp.open_inv('b1000000-0000-4000-8000-000000000006') i)
  and (select status = 'consumed' and cycles_remaining = 0 from public.billing_discounts where user_id = 'b1000000-0000-4000-8000-000000000006' and code = 'WELCOME50' and status <> 'removed'),
  'the first invoice spends the first-month discount');
select public.hyn_billing_svc_charge_status((pg_temp.raise_one('b1000000-0000-4000-8000-000000000006')).payment_id, 'SUCCESS', 'cfp_4', null, now());
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000006';
select pg_temp.check_billing(pg_temp.raises($$select public.hyn_billing_apply_coupon('WELCOME50')$$, 'already used'), 'a code works once per customer');
select public.hyn_billing_apply_coupon('loyal10');
select pg_temp.check_billing(pg_temp.raises($$select public.hyn_billing_apply_coupon('ONCE')$$, 'already has an ongoing discount'),
  'only one ongoing discount is active at a time');
select pg_temp.check_billing((select (r->'estimate'->>'total')::bigint = 8910 and not (r->>'first_month_available')::boolean from public.hyn_billing_summary() r),
  'the billing page estimates the next renewal with the ongoing discount');
reset role;
update public.billing_subscriptions set paid_through = now() + interval '1 day' where user_id = 'b1000000-0000-4000-8000-000000000006';
select public.hyn_billing_svc_tick((pg_temp.sub('b1000000-0000-4000-8000-000000000006')).id);
select pg_temp.check_billing((select i.total = 8910 from pg_temp.open_inv('b1000000-0000-4000-8000-000000000006') i)
  and (select cycles_remaining = 1 from public.billing_discounts where user_id = 'b1000000-0000-4000-8000-000000000006' and code = 'LOYAL10'),
  'a renewal spends one month of the ongoing discount');
-- Voiding the unpaid renewal gives the discount month back.
update public.billing_charges set status = 'failed' where invoice_id = (pg_temp.open_inv('b1000000-0000-4000-8000-000000000006')).id;
select set_config('test.invoice', (pg_temp.open_inv('b1000000-0000-4000-8000-000000000006')).id::text, true);
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000001';
select pg_temp.check_billing((public.hyn_admin_billing_void_invoice(current_setting('test.invoice')::uuid, 'testing a void')->>'status') = 'void',
  'an admin voids an unpaid invoice');
reset role;
select pg_temp.check_billing((select cycles_remaining = 2 and status = 'active' from public.billing_discounts where user_id = 'b1000000-0000-4000-8000-000000000006' and code = 'LOYAL10'),
  'a voided invoice returns the discount month it used');
-- Date-limited discounts lapse by date.
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000001';
select public.hyn_admin_billing_add_discount('b1000000-0000-4000-8000-000000000006', null, 'Launch offer', 'ongoing', null, 500, null, now() + interval '12 hours');
reset role;
select pg_temp.check_billing((select count(*) = 1 from public.billing_discounts where user_id = 'b1000000-0000-4000-8000-000000000006' and status = 'active')
    and (select status = 'removed' from public.billing_discounts where code = 'LOYAL10'),
  'an admin discount replaces the active one of the same kind');
select public.hyn_billing_svc_tick((pg_temp.sub('b1000000-0000-4000-8000-000000000006')).id);
select pg_temp.check_billing((select i.total = 9900 and i.discount_total = 0 from pg_temp.open_inv('b1000000-0000-4000-8000-000000000006') i)
  and (select status = 'expired' from public.billing_discounts where label = 'Launch offer'),
  'a discount that ends before the next period is retired, not applied');
update public.billing_coupons set redemptions = max_redemptions where code = 'ONCE';
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000003';
select pg_temp.check_billing((select r->'coupon'->>'message' like '%fully redeemed%' from public.hyn_billing_preview(1, 'ONCE') r),
  'a code past its redemption limit is refused');
reset role;

-- ---------------------------------------------------------------------------
-- long-unpaid plans end; staff; webhooks; privileges
-- ---------------------------------------------------------------------------
update public.billing_charges set status = 'failed' where invoice_id = (pg_temp.open_inv('b1000000-0000-4000-8000-000000000006')).id and status in ('raising','pending');
update public.billing_invoices set due_at = now() - interval '9 days', next_attempt_at = null where user_id = 'b1000000-0000-4000-8000-000000000006' and status = 'open';
update public.billing_subscriptions set paid_through = now() - interval '9 days' where user_id = 'b1000000-0000-4000-8000-000000000006';
select public.hyn_billing_svc_tick((pg_temp.sub('b1000000-0000-4000-8000-000000000006')).id);
update public.billing_subscriptions set unpaid_since = now() - interval '31 days' where user_id = 'b1000000-0000-4000-8000-000000000006';
select public.hyn_billing_svc_tick((pg_temp.sub('b1000000-0000-4000-8000-000000000006')).id);
select pg_temp.check_billing((select status = 'canceled' and cancel_reason = 'unpaid' from public.billing_subscriptions where user_id = 'b1000000-0000-4000-8000-000000000006')
  and not exists(select 1 from public.billing_invoices where user_id = 'b1000000-0000-4000-8000-000000000006' and status = 'open'),
  'a plan unpaid for unpaid_cancel_days ends and its invoice is voided');
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000006';
select pg_temp.check_billing((select (r->>'total')::bigint = 9900 from public.hyn_billing_preview(1, null) r)
    and (public.hyn_billing_summary()->'subscription') = 'null'::jsonb,
  'a returning customer can subscribe again');
select pg_temp.check_billing((select not (r->'coupon'->>'valid')::boolean from public.hyn_billing_preview(1, 'WELCOME50') r),
  'a first-month code cannot be reused on a new plan');
set local "test.uid" = 'b1000000-0000-4000-8000-000000000005';
select pg_temp.check_billing((public.hyn_billing_summary()->>'exempt')::boolean and (public.hyn_billing_summary()->>'has_access')::boolean,
  'staff are exempt from billing');
select pg_temp.check_billing(pg_temp.raises($$select public.hyn_billing_begin_checkout(1, null, '9876543210')$$, 'Staff accounts are not billed'),
  'staff cannot start a checkout');
reset role;

select set_config('test.event', public.hyn_billing_svc_record_event('hash-1', 'SUBSCRIPTION_STATUS_CHANGED', '{}')::text, true);
select pg_temp.check_billing(public.hyn_billing_svc_record_event('hash-1', 'SUBSCRIPTION_STATUS_CHANGED', '{}') = current_setting('test.event')::bigint,
  'an unprocessed duplicate webhook is processed again');
select public.hyn_billing_svc_event_done(current_setting('test.event')::bigint, null);
select pg_temp.check_billing(public.hyn_billing_svc_record_event('hash-1', 'SUBSCRIPTION_STATUS_CHANGED', '{}') is null,
  'a processed webhook is ignored when it is redelivered');

select pg_temp.check_billing(not has_table_privilege('authenticated', 'public.billing_invoices', 'SELECT')
    and not has_table_privilege('anon', 'public.billing_subscriptions', 'SELECT')
    and not has_function_privilege('anon', 'public.hyn_billing_summary()', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.hyn_billing_svc_charge_status(text,text,text,text,timestamp with time zone)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public._hyn_billing_mark_paid(uuid,text,timestamp with time zone)', 'EXECUTE'),
  'billing tables and internals are private; the browser reaches billing only through RPCs');
select pg_temp.check_billing(not exists(select 1 from pg_roles where rolname = 'service_role')
    or has_function_privilege('service_role', 'public.hyn_billing_svc_tick(uuid)', 'EXECUTE'),
  'the portal''s server key can run the billing job');

-- Enforcement off releases every billing hold.
set local role authenticated;
set local "test.uid" = 'b1000000-0000-4000-8000-000000000001';
select public.hyn_admin_billing_set_enforce(false);
reset role;
select pg_temp.check_billing(not exists(select 1 from public.nodes where billing_hold) and
    (select status = 'active' from public.nodes where id = 'b2000000-0000-4000-8000-000000000003'),
  'switching enforcement off lifts every billing hold');
rollback;
