-- Subscription billing: per-server monthly plans collected through Cashfree
-- on-demand mandates, first-month and ongoing discounts, manual (admin)
-- collection, and database-enforced service access.
--
-- Rules: docs/superpowers/specs/2026-10-06-subscription-billing-design.md
--
-- billing_settings.enforce starts off, so applying this changes nobody's access
-- until a super admin runs hyn_admin_billing_launch(). Money is integer paise.
-- Cashfree calls happen in the portal; it reports every result back through the
-- hyn_billing_svc_* functions, which only the service role may execute.
begin;

-- ===========================================================================
-- tables
-- ===========================================================================
alter table public.nodes add column if not exists billing_hold boolean not null default false;

create table if not exists public.billing_settings (
  id smallint primary key default 1 check (id = 1),
  enforce boolean not null default false,
  launched_at timestamptz,
  price_per_server bigint not null default 9900 check (price_per_server between 0 and 10000000),
  auth_amount bigint not null default 200 check (auth_amount between 100 and 10000),
  mandate_max_amount bigint not null default 1500000 check (mandate_max_amount between 10000 and 100000000),
  trial_days integer not null default 0 check (trial_days between 0 and 90),
  renewal_lead_days integer not null default 3 check (renewal_lead_days between 2 and 10),
  grace_days integer not null default 7 check (grace_days between 1 and 30),
  retry_interval_days integer not null default 2 check (retry_interval_days between 1 and 7),
  max_auto_attempts integer not null default 4 check (max_auto_attempts between 1 and 4),
  unpaid_cancel_days integer not null default 30 check (unpaid_cancel_days between 1 and 365),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  -- Every automatic retry must fall inside the grace window, or the last ones
  -- would be charged after access had already ended.
  constraint billing_settings_retries_within_grace
    check (retry_interval_days * (max_auto_attempts - 1) < grace_days)
);
insert into public.billing_settings (id) values (1) on conflict (id) do nothing;

create table if not exists public.billing_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('incomplete','trialing','active','past_due','unpaid','canceled')),
  collection text not null default 'auto' check (collection in ('auto','manual')),
  quantity integer not null check (quantity between 1 and 1000),
  pending_quantity integer check (pending_quantity between 1 and 1000),
  unit_price bigint not null check (unit_price between 0 and 10000000),
  anchor_day smallint check (anchor_day between 1 and 31),
  trial_ends_at timestamptz,
  paid_through timestamptz,
  current_period_start timestamptz,
  current_period_end timestamptz,
  access_ends_at timestamptz,
  cancel_at_period_end boolean not null default false,
  cancel_requested_at timestamptz,
  canceled_at timestamptz,
  cancel_reason text,
  unpaid_since timestamptz,
  cycle_count integer not null default 0,
  current_mandate_id uuid,
  legacy boolean not null default false,
  note text check (length(note) <= 500),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists billing_subscriptions_one_live
  on public.billing_subscriptions (user_id) where status <> 'canceled';
create index if not exists billing_subscriptions_user_idx on public.billing_subscriptions (user_id, created_at desc);

create table if not exists public.billing_mandates (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references public.billing_subscriptions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  cf_subscription_id text not null unique,
  cf_ref text,
  session_id text,
  status text not null default 'CREATING' check (status in (
    'CREATING','INITIALIZED','BANK_APPROVAL_PENDING','ACTIVE','ON_HOLD','PAUSED',
    'CUSTOMER_PAUSED','CUSTOMER_CANCELLED','CANCELLED','EXPIRED','LINK_EXPIRED',
    'CARD_EXPIRED','COMPLETED','FAILED')),
  payment_group text,
  max_amount bigint not null check (max_amount > 0),
  auth_amount bigint not null check (auth_amount >= 0),
  phone text not null,
  error text,
  last_event_at timestamptz,
  checked_at timestamptz,
  cancel_claimed_at timestamptz,
  activated_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists billing_mandates_subscription_idx on public.billing_mandates (subscription_id, created_at desc);
create index if not exists billing_mandates_user_recent_idx on public.billing_mandates (user_id, created_at desc);

do $$ begin
  alter table public.billing_subscriptions add constraint billing_subscriptions_current_mandate_fkey
    foreign key (current_mandate_id) references public.billing_mandates(id) on delete set null;
exception when duplicate_object then null; end $$;

create sequence if not exists public.billing_invoice_seq;

create table if not exists public.billing_invoices (
  id uuid primary key default gen_random_uuid(),
  number text not null unique,
  subscription_id uuid not null references public.billing_subscriptions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('first','renewal','manual')),
  cycle_number integer not null check (cycle_number >= 1),
  months integer not null default 1 check (months between 1 and 36),
  period_start timestamptz not null,
  period_end timestamptz not null,
  quantity integer not null,
  unit_price bigint not null,
  subtotal bigint not null check (subtotal >= 0),
  discount_total bigint not null check (discount_total >= 0),
  total bigint not null check (total >= 0),
  lines jsonb not null default '[]'::jsonb,
  applied_discounts uuid[] not null default '{}',
  collection text not null check (collection in ('auto','manual')),
  status text not null check (status in ('open','paid','void')),
  due_at timestamptz not null,
  attempts integer not null default 0,
  next_attempt_at timestamptz,
  blocked_reason text check (blocked_reason in ('no_mandate','exceeds_mandate_limit')),
  void_pending_reason text,
  paid_at timestamptz,
  paid_via text check (paid_via in ('cashfree','manual','free')),
  needs_refund boolean not null default false,
  voided_at timestamptz,
  void_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (period_end > period_start),
  check (subtotal - discount_total = total)
);
create unique index if not exists billing_invoices_one_open
  on public.billing_invoices (subscription_id) where status = 'open';
create index if not exists billing_invoices_subscription_idx on public.billing_invoices (subscription_id, created_at desc);
create index if not exists billing_invoices_attempt_idx on public.billing_invoices (next_attempt_at) where status = 'open';

create table if not exists public.billing_charges (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.billing_invoices(id) on delete cascade,
  mandate_id uuid not null references public.billing_mandates(id) on delete cascade,
  payment_id text not null unique,
  cf_payment_id text,
  attempt integer not null,
  amount bigint not null check (amount > 0),
  scheduled_for date,
  status text not null check (status in ('raising','pending','success','failed','cancelling','cancelled')),
  failure_reason text,
  claimed_at timestamptz,
  last_event_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists billing_charges_invoice_idx on public.billing_charges (invoice_id, created_at desc);
create index if not exists billing_charges_open_idx on public.billing_charges (status) where status in ('raising','pending','cancelling');

create table if not exists public.billing_manual_payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.billing_invoices(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount bigint not null check (amount >= 0),
  method text not null check (method in ('cash','bank_transfer','upi','cheque','other')),
  reference text check (length(reference) <= 120),
  note text check (length(note) <= 500),
  received_at timestamptz not null,
  recorded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists billing_manual_payments_user_idx on public.billing_manual_payments (user_id, created_at desc);

create table if not exists public.billing_pending_items (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references public.billing_subscriptions(id) on delete cascade,
  description text not null,
  amount bigint not null check (amount >= 0),
  invoice_id uuid references public.billing_invoices(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists billing_pending_items_subscription_idx on public.billing_pending_items (subscription_id) where invoice_id is null;

create table if not exists public.billing_coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9_-]{3,32}$'),
  name text not null check (length(name) between 1 and 80),
  kind text not null check (kind in ('first_month','ongoing')),
  percent_off integer check (percent_off between 1 and 100),
  amount_off bigint check (amount_off between 1 and 10000000),
  duration_months integer check (duration_months between 1 and 120),
  redeem_by timestamptz,
  max_redemptions integer check (max_redemptions > 0),
  redemptions integer not null default 0,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check ((percent_off is null) <> (amount_off is null)),
  check (kind = 'ongoing' or duration_months is null)
);

create table if not exists public.billing_discounts (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references public.billing_subscriptions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  coupon_id uuid references public.billing_coupons(id) on delete set null,
  code text,
  label text not null check (length(label) between 1 and 120),
  kind text not null check (kind in ('first_month','ongoing')),
  percent_off integer check (percent_off between 1 and 100),
  amount_off bigint check (amount_off between 1 and 10000000),
  -- Invoices left to discount; null is forever. A first-month discount is 1.
  cycles_remaining integer check (cycles_remaining >= 0),
  ends_at timestamptz,
  status text not null default 'active' check (status in ('active','consumed','expired','removed')),
  source text not null check (source in ('code','admin')),
  applied_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((percent_off is null) <> (amount_off is null))
);
create unique index if not exists billing_discounts_one_active_kind
  on public.billing_discounts (subscription_id, kind) where status = 'active';
create unique index if not exists billing_discounts_coupon_once_per_user
  on public.billing_discounts (user_id, coupon_id) where coupon_id is not null and status <> 'removed';

create table if not exists public.billing_events (
  id bigserial primary key,
  body_sha256 text not null unique,
  event_type text,
  payload jsonb,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  error text
);

do $$
declare t text;
begin
  foreach t in array array['billing_settings','billing_subscriptions','billing_mandates','billing_invoices',
    'billing_charges','billing_manual_payments','billing_pending_items','billing_coupons','billing_discounts','billing_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;
revoke all on sequence public.billing_invoice_seq from public, anon, authenticated;
revoke all on sequence public.billing_events_id_seq from public, anon, authenticated;

-- ===========================================================================
-- small helpers
-- ===========================================================================
create or replace function public._hyn_billing_money(p_paise bigint)
returns text language sql stable set search_path = public as $$
  select '₹' || to_char(p_paise / 100.0, 'FM9,999,999,990.00');
$$;

-- Staff are never billed: they run the service rather than buy it.
create or replace function public._hyn_billing_exempt(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = p_user and role in ('maintainer','admin','super_admin'));
$$;

-- Adds months on the IST calendar, keeping the anchor day where the month has
-- it (a 31st renews on the last day of shorter months) and the time of day.
create or replace function public._hyn_billing_add_months(p_ts timestamptz, p_anchor integer, p_months integer)
returns timestamptz language plpgsql stable set search_path = public as $$
declare
  v_local timestamp := p_ts at time zone 'Asia/Kolkata';
  v_month timestamp := date_trunc('month', v_local) + make_interval(months => p_months);
  v_last integer := extract(day from v_month + interval '1 month' - interval '1 day')::integer;
begin
  return (v_month + make_interval(days => least(coalesce(p_anchor, extract(day from v_local)::integer), v_last) - 1)
          + (v_local - date_trunc('day', v_local))) at time zone 'Asia/Kolkata';
end $$;

create or replace function public._hyn_billing_live_sub(p_user uuid)
returns public.billing_subscriptions language sql stable security definer set search_path = public as $$
  select * from public.billing_subscriptions where user_id = p_user and status <> 'canceled' limit 1;
$$;

-- Price of one invoice. Pure: the same function previews a checkout, estimates
-- the next renewal and finalises the real invoice, so they cannot disagree.
--   1. subtotal = quantity x unit price x months + pending adjustments
--   2. the ongoing discount comes off the subtotal
--   3. the first-month discount (cycle 1 only) comes off what remains
--   4. percentages round half up to the paise, fixed amounts are capped
--   5. a total under Rs 1 is not charged
-- Discounts apply to one-month invoices only; a multi-month manual invoice is
-- priced by the administrator who creates it.
create or replace function public._hyn_billing_price(
  p_quantity integer, p_unit_price bigint, p_months integer, p_items jsonb, p_cycle integer, p_discounts jsonb)
returns jsonb language plpgsql stable set search_path = public as $$
declare
  v_subtotal bigint := p_quantity::bigint * p_unit_price * p_months;
  v_remaining bigint;
  v_amount bigint;
  v_lines jsonb;
  v_applied jsonb := '[]'::jsonb;
  i jsonb;
  d jsonb;
begin
  v_lines := jsonb_build_array(jsonb_build_object(
    'type', 'servers', 'quantity', p_quantity, 'unit_price', p_unit_price, 'months', p_months,
    'description', format('%s server%s × %s per month%s', p_quantity, case when p_quantity = 1 then '' else 's' end,
      public._hyn_billing_money(p_unit_price), case when p_months > 1 then format(' × %s months', p_months) else '' end),
    'amount', v_subtotal));
  for i in select value from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_subtotal := v_subtotal + (i->>'amount')::bigint;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'type', 'adjustment', 'item_id', i->'id', 'description', i->>'description', 'amount', (i->>'amount')::bigint));
  end loop;
  v_remaining := v_subtotal;
  for d in select value from jsonb_array_elements(coalesce(p_discounts, '[]'::jsonb))
           order by case value->>'kind' when 'ongoing' then 0 else 1 end loop
    continue when p_months <> 1;
    continue when d->>'kind' = 'first_month' and p_cycle <> 1;
    if d->>'percent_off' is not null then
      v_amount := round(v_remaining * (d->>'percent_off')::numeric / 100);
    else
      v_amount := (d->>'amount_off')::bigint;
    end if;
    v_amount := least(greatest(v_amount, 0), v_remaining);
    v_applied := v_applied || jsonb_build_array(d->'id');
    if v_amount > 0 then
      v_remaining := v_remaining - v_amount;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'type', 'discount', 'discount_id', d->'id', 'kind', d->>'kind', 'description', d->>'label', 'amount', -v_amount));
    end if;
  end loop;
  if v_remaining between 1 and 99 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'type', 'minimum', 'description', 'Amounts under ₹1 are not charged', 'amount', -v_remaining));
    v_remaining := 0;
  end if;
  return jsonb_build_object('subtotal', v_subtotal, 'discount_total', v_subtotal - v_remaining,
    'total', v_remaining, 'lines', v_lines, 'applied', v_applied);
end $$;

-- Discounts that would apply to a period starting at p_start. With p_expire,
-- date-limited discounts whose end has passed are retired on the way.
create or replace function public._hyn_billing_discounts_for(p_sub uuid, p_start timestamptz, p_expire boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if p_expire then
    update public.billing_discounts set status = 'expired', updated_at = now()
     where subscription_id = p_sub and status = 'active' and ends_at is not null and ends_at <= p_start;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'percent_off', percent_off,
           'amount_off', amount_off, 'label', label) order by created_at), '[]'::jsonb)
    into v
    from public.billing_discounts
   where subscription_id = p_sub and status = 'active'
     and (cycles_remaining is null or cycles_remaining > 0)
     and (ends_at is null or ends_at > p_start);
  return v;
end $$;

-- ===========================================================================
-- access: who may link and report
-- ===========================================================================
create or replace function public._hyn_billing_owner_access(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select not coalesce((select enforce from public.billing_settings where id = 1), false)
      or public._hyn_billing_exempt(p_user)
      or exists(select 1 from public.billing_subscriptions s where s.user_id = p_user
                 and s.status in ('trialing','active','past_due') and s.access_ends_at > now());
$$;

-- Puts servers without entitlement on a billing hold and lifts holds that are
-- no longer needed. A hold is status 'suspended' with a 'Billing:' reason: every
-- reporting RPC already refuses a suspended server, and the agent prints the
-- reason and keeps retrying, so it resumes by itself once the hold lifts. A hold
-- is lifted only while the reason is still billing's own, so an administrator's
-- suspension is never undone here. Within an account the oldest servers keep
-- the slots.
create or replace function public._hyn_billing_sync_access(p_user uuid default null)
returns integer language plpgsql security definer set search_path = public as $$
declare v_enforce boolean := coalesce((select enforce from public.billing_settings where id = 1), false);
  v_held integer; v_released integer;
begin
  with ranked as (
    select n.id, n.owner,
           row_number() over (partition by n.owner order by n.created_at, n.id) as rn
      from public.nodes n
     where not n.revoked and not n.is_demo and (p_user is null or n.owner = p_user)
  ), ent as (
    select r.id,
           s.quantity,
           (not v_enforce or public._hyn_billing_exempt(r.owner)
             or (s.id is not null and r.rn <= s.quantity)) as ok
      from ranked r
      left join public.billing_subscriptions s
        on s.user_id = r.owner and s.status in ('trialing','active','past_due') and s.access_ends_at > now()
  ), held as (
    update public.nodes n
       set billing_hold = true, status = 'suspended', paused_until = null,
           status_reason = case when e.quantity is null
             then 'Billing: this account has no active HYN-view subscription. Renew at https://www.hyn-view.in/billing'
             else format('Billing: this server is beyond the %s server slot%s on the plan. Add a slot at https://www.hyn-view.in/billing',
                         e.quantity, case when e.quantity = 1 then '' else 's' end) end
      from ent e
     where n.id = e.id and not e.ok
       and (n.status = 'active' or (n.status = 'paused' and n.paused_until is not null and n.paused_until <= now()))
    returning 1
  ), released as (
    update public.nodes n
       set billing_hold = false,
           status = case when n.status = 'suspended' and n.status_reason like 'Billing:%' then 'active' else n.status end,
           status_reason = case when n.status_reason like 'Billing:%' then null else n.status_reason end
      from ent e
     where n.id = e.id and e.ok and n.billing_hold
    returning 1
  )
  select (select count(*) from held), (select count(*) from released) into v_held, v_released;
  return v_held + v_released;
end $$;

-- Linking a server: refused without an active plan or with every slot in use.
-- A trigger rather than a check in hyn_device_approve, so no insert path can
-- skip it.
create or replace function public._hyn_billing_guard_node_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_sub public.billing_subscriptions; v_count integer;
begin
  if new.is_demo or new.revoked
     or not coalesce((select enforce from public.billing_settings where id = 1), false)
     or public._hyn_billing_exempt(new.owner) then
    return new;
  end if;
  -- Concurrent approvals for one owner must not both take the last slot.
  perform pg_advisory_xact_lock(hashtext('hyn-billing-link:' || new.owner::text));
  select * into v_sub from public.billing_subscriptions
   where user_id = new.owner and status in ('trialing','active','past_due') and access_ends_at > now();
  if v_sub.id is null then
    raise exception 'An active HYN-view subscription is required to link a server. Subscribe at /billing.';
  end if;
  select count(*) into v_count from public.nodes where owner = new.owner and not revoked and not is_demo;
  if v_count >= v_sub.quantity then
    raise exception 'All % server slot% on your plan are in use. Add a slot at /billing to link another server.',
      v_sub.quantity, case when v_sub.quantity = 1 then '' else 's' end;
  end if;
  return new;
end $$;
drop trigger if exists hyn_billing_guard_node_insert on public.nodes;
create trigger hyn_billing_guard_node_insert before insert on public.nodes
  for each row execute function public._hyn_billing_guard_node_insert();

-- ===========================================================================
-- the subscription state machine
-- ===========================================================================
-- Recomputes status and access_ends_at from the facts: what is paid, the trial,
-- and the open invoice. Access is time based, so it ends on time even if no job
-- runs; this only keeps the stored labels honest.
create or replace function public._hyn_billing_refresh(p_sub uuid)
returns void language plpgsql security definer set search_path = public as $$
declare s public.billing_subscriptions; st public.billing_settings; inv public.billing_invoices;
  v_access timestamptz; v_status text; v_grace interval;
begin
  select * into s from public.billing_subscriptions where id = p_sub for update;
  if s.id is null or s.status = 'canceled' then return; end if;
  select * into st from public.billing_settings where id = 1;
  v_grace := make_interval(days => st.grace_days);
  select * into inv from public.billing_invoices where subscription_id = s.id and status = 'open';

  if s.status = 'incomplete' then
    v_status := 'incomplete';
    v_access := null;
  else
    v_access := greatest(s.paid_through, s.trial_ends_at,
                         case when inv.id is not null and inv.void_pending_reason is null then inv.due_at + v_grace end);
    if inv.id is not null and inv.void_pending_reason is null and inv.due_at <= now() then
      if now() >= inv.due_at + v_grace and coalesce(s.paid_through, '-infinity') <= now() then
        v_status := 'unpaid';
      elsif exists(select 1 from public.billing_charges c where c.invoice_id = inv.id and c.status in ('failed','cancelled'))
         or (not exists(select 1 from public.billing_charges c where c.invoice_id = inv.id and c.status in ('raising','pending'))
             and now() > inv.due_at + interval '1 day') then
        v_status := 'past_due';
      else
        v_status := 'active';
      end if;
    elsif s.trial_ends_at > now() and coalesce(s.paid_through, '-infinity') < s.trial_ends_at then
      v_status := 'trialing';
    elsif coalesce(v_access, '-infinity') > now() then
      v_status := 'active';
    else
      v_status := 'unpaid';
    end if;
  end if;

  update public.billing_subscriptions
     set status = v_status, access_ends_at = v_access,
         unpaid_since = case when v_status = 'unpaid' then coalesce(unpaid_since, now()) end,
         updated_at = now()
   where id = s.id and (status, access_ends_at, unpaid_since is not null)
         is distinct from (v_status, v_access, v_status = 'unpaid');
  perform public._hyn_billing_sync_access(s.user_id);
end $$;

create or replace function public._hyn_billing_create_invoice(
  p_sub uuid, p_kind text, p_start timestamptz, p_months integer, p_due timestamptz)
returns public.billing_invoices language plpgsql security definer set search_path = public as $$
declare s public.billing_subscriptions; v_items jsonb; v_price jsonb; v_end timestamptz;
  inv public.billing_invoices; v_applied uuid[];
begin
  select * into s from public.billing_subscriptions where id = p_sub for update;
  if s.anchor_day is null then
    s.anchor_day := extract(day from p_start at time zone 'Asia/Kolkata')::smallint;
  end if;
  update public.billing_subscriptions
     set anchor_day = s.anchor_day, quantity = coalesce(pending_quantity, quantity),
         pending_quantity = null, updated_at = now()
   where id = s.id returning * into s;
  v_end := public._hyn_billing_add_months(p_start, s.anchor_day, p_months);

  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'description', description, 'amount', amount)
           order by created_at), '[]'::jsonb)
    into v_items from public.billing_pending_items where subscription_id = s.id and invoice_id is null;
  v_price := public._hyn_billing_price(s.quantity, s.unit_price, p_months, v_items, s.cycle_count + 1,
               public._hyn_billing_discounts_for(s.id, p_start, true));
  select coalesce(array_agg((value #>> '{}')::uuid), '{}') into v_applied
    from jsonb_array_elements(v_price->'applied');

  insert into public.billing_invoices (
    number, subscription_id, user_id, kind, cycle_number, months, period_start, period_end,
    quantity, unit_price, subtotal, discount_total, total, lines, applied_discounts,
    collection, status, due_at, next_attempt_at)
  values (
    'HYN-' || to_char(now() at time zone 'Asia/Kolkata', 'YYYY') || '-' || lpad(nextval('public.billing_invoice_seq')::text, 6, '0'),
    s.id, s.user_id, p_kind, s.cycle_count + 1, p_months, p_start, v_end,
    s.quantity, s.unit_price, (v_price->>'subtotal')::bigint, (v_price->>'discount_total')::bigint,
    (v_price->>'total')::bigint, v_price->'lines', v_applied,
    s.collection, 'open', p_due, case when s.collection = 'auto' then now() end)
  returning * into inv;

  update public.billing_pending_items set invoice_id = inv.id where subscription_id = s.id and invoice_id is null;
  -- A discount cycle is spent when the invoice is finalised, given back if it is voided unpaid.
  update public.billing_discounts
     set cycles_remaining = case when cycles_remaining is null then null else cycles_remaining - 1 end,
         status = case when cycles_remaining = 1 then 'consumed' else status end,
         updated_at = now()
   where id = any(v_applied);

  if inv.total = 0 then
    perform public._hyn_billing_mark_paid(inv.id, 'free', now());
    select * into inv from public.billing_invoices where id = inv.id;
  end if;
  return inv;
end $$;

create or replace function public._hyn_billing_mark_paid(p_invoice uuid, p_via text, p_at timestamptz)
returns void language plpgsql security definer set search_path = public as $$
declare inv public.billing_invoices; s public.billing_subscriptions; st public.billing_settings;
  v_start timestamptz; v_end timestamptz;
begin
  select * into inv from public.billing_invoices where id = p_invoice for update;
  if inv.id is null or inv.status = 'paid' then return; end if;
  select * into s from public.billing_subscriptions where id = inv.subscription_id for update;
  select * into st from public.billing_settings where id = 1;
  v_start := inv.period_start;
  v_end := inv.period_end;
  -- Paid after access had already ended: the period starts now, so nobody pays
  -- for time they could not use.
  if s.status <> 'canceled' and p_at > inv.due_at + make_interval(days => st.grace_days)
     and p_at > coalesce(s.paid_through, '-infinity') then
    s.anchor_day := extract(day from p_at at time zone 'Asia/Kolkata')::smallint;
    v_start := p_at;
    v_end := public._hyn_billing_add_months(p_at, s.anchor_day, inv.months);
  end if;
  update public.billing_invoices
     set status = 'paid', paid_at = p_at, paid_via = p_via, period_start = v_start, period_end = v_end,
         next_attempt_at = null, blocked_reason = null, void_pending_reason = null,
         needs_refund = (s.status = 'canceled'), updated_at = now()
   where id = inv.id;
  -- Any other attempt still in flight is stopped at Cashfree.
  update public.billing_charges set status = 'cancelling', claimed_at = null, updated_at = now()
   where invoice_id = inv.id and status in ('raising','pending');
  if s.status = 'canceled' then
    -- Money for a plan that already ended is kept on record for a refund.
    perform public._hyn_audit('billing.payment.after_cancel', s.user_id, null,
      jsonb_build_object('invoice', inv.number, 'amount', inv.total, 'via', p_via));
    return;
  end if;
  update public.billing_subscriptions
     set paid_through = greatest(paid_through, v_end), current_period_start = v_start, current_period_end = v_end,
         cycle_count = greatest(cycle_count, inv.cycle_number), anchor_day = s.anchor_day,
         status = 'active', unpaid_since = null, updated_at = now()
   where id = s.id;
  perform public._hyn_billing_refresh(s.id);
end $$;

create or replace function public._hyn_billing_void_invoice(p_invoice uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare inv public.billing_invoices; d public.billing_discounts;
begin
  update public.billing_invoices
     set status = 'void', voided_at = now(), void_reason = left(p_reason, 200), void_pending_reason = null,
         next_attempt_at = null, updated_at = now()
   where id = p_invoice and status = 'open' returning * into inv;
  if inv.id is null then return; end if;
  for d in select * from public.billing_discounts where id = any(inv.applied_discounts)
           and status in ('active','consumed') for update loop
    if d.status = 'consumed' and exists(select 1 from public.billing_discounts o
         where o.subscription_id = d.subscription_id and o.kind = d.kind and o.status = 'active') then
      continue;
    end if;
    update public.billing_discounts
       set cycles_remaining = case when cycles_remaining is null then null else cycles_remaining + 1 end,
           status = 'active', updated_at = now()
     where id = d.id;
  end loop;
  update public.billing_pending_items set invoice_id = null where invoice_id = inv.id;
  perform public._hyn_billing_refresh(inv.subscription_id);
end $$;

create or replace function public._hyn_billing_charge_failed(p_charge uuid, p_reason text, p_status text default 'failed')
returns void language plpgsql security definer set search_path = public as $$
declare c public.billing_charges; inv public.billing_invoices; st public.billing_settings;
begin
  update public.billing_charges set status = p_status, failure_reason = left(coalesce(p_reason, 'payment failed'), 500),
         claimed_at = null, updated_at = now()
   where id = p_charge and status <> 'success' returning * into c;
  if c.id is null then return; end if;
  select * into st from public.billing_settings where id = 1;
  select * into inv from public.billing_invoices where id = c.invoice_id for update;
  if inv.status = 'open' and inv.void_pending_reason is null then
    update public.billing_invoices
       set next_attempt_at = case when attempts < st.max_auto_attempts
                                  then now() + make_interval(days => st.retry_interval_days) end,
           updated_at = now()
     where id = inv.id;
  end if;
  perform public._hyn_billing_refresh(inv.subscription_id);
end $$;

-- Ends a subscription. Access stops at p_at; an open invoice is voided once any
-- charge for it has been stopped at Cashfree, and the mandate is cancelled by
-- the next billing run.
create or replace function public._hyn_billing_end(p_sub uuid, p_reason text, p_at timestamptz)
returns void language plpgsql security definer set search_path = public as $$
declare s public.billing_subscriptions;
begin
  update public.billing_subscriptions
     set status = 'canceled', canceled_at = now(), cancel_reason = left(p_reason, 100),
         access_ends_at = least(coalesce(access_ends_at, p_at), p_at), cancel_at_period_end = false,
         updated_at = now()
   where id = p_sub and status <> 'canceled' returning * into s;
  if s.id is null then return; end if;
  update public.billing_invoices set void_pending_reason = 'subscription_canceled', next_attempt_at = null, updated_at = now()
   where subscription_id = s.id and status = 'open';
  update public.billing_discounts set status = 'expired', updated_at = now()
   where subscription_id = s.id and status = 'active';
  perform public._hyn_billing_sync_access(s.user_id);
end $$;

-- Time-based progress for one subscription: abandoned checkouts, scheduled
-- cancellations, long-unpaid plans, and renewal invoices finalised
-- renewal_lead_days ahead (Cashfree freezes the amount at its pre-debit notice).
create or replace function public._hyn_billing_advance(p_sub uuid)
returns void language plpgsql security definer set search_path = public as $$
declare s public.billing_subscriptions; st public.billing_settings; inv public.billing_invoices;
  v_boundary timestamptz;
begin
  perform public._hyn_billing_refresh(p_sub);
  select * into s from public.billing_subscriptions where id = p_sub for update;
  if s.id is null or s.status = 'canceled' then return; end if;
  select * into st from public.billing_settings where id = 1;
  select * into inv from public.billing_invoices where subscription_id = s.id and status = 'open';

  if s.status = 'incomplete' then
    if s.created_at < now() - interval '7 days' and not exists(select 1 from public.billing_mandates m
         where m.subscription_id = s.id and m.status in ('ACTIVE','ON_HOLD','BANK_APPROVAL_PENDING')) then
      perform public._hyn_billing_end(s.id, 'checkout_abandoned', now());
    end if;
    return;
  end if;

  if s.cancel_at_period_end then
    v_boundary := greatest(s.paid_through, s.trial_ends_at);
    if coalesce(v_boundary, '-infinity') <= now()
       and (inv.id is null or inv.void_pending_reason is not null
            or now() >= inv.due_at + make_interval(days => st.grace_days)) then
      perform public._hyn_billing_end(s.id, coalesce(s.cancel_reason, 'canceled'), coalesce(v_boundary, now()));
    end if;
    return;
  end if;

  if s.status = 'unpaid' and s.unpaid_since <= now() - make_interval(days => st.unpaid_cancel_days) then
    perform public._hyn_billing_end(s.id, 'unpaid', now());
    return;
  end if;

  if inv.id is null and exists(select 1 from public.profiles where id = s.user_id and status = 'active') then
    v_boundary := coalesce(s.paid_through, s.trial_ends_at);
    if v_boundary is not null and v_boundary - make_interval(days => st.renewal_lead_days) <= now() then
      perform public._hyn_billing_create_invoice(s.id, 'renewal', greatest(v_boundary, now()), 1, greatest(v_boundary, now()));
    end if;
  end if;
  perform public._hyn_billing_refresh(s.id);
end $$;

-- A mandate became ACTIVE for the first time.
create or replace function public._hyn_billing_mandate_activated(p_mandate uuid)
returns void language plpgsql security definer set search_path = public as $$
declare m public.billing_mandates; s public.billing_subscriptions; st public.billing_settings;
  v_current_created timestamptz;
begin
  select * into m from public.billing_mandates where id = p_mandate;
  select * into s from public.billing_subscriptions where id = m.subscription_id for update;
  if s.id is null or s.status = 'canceled' then return; end if;
  select * into st from public.billing_settings where id = 1;
  select created_at into v_current_created from public.billing_mandates where id = s.current_mandate_id;
  if v_current_created is null or v_current_created <= m.created_at then
    update public.billing_subscriptions set current_mandate_id = m.id, collection = 'auto', updated_at = now()
     where id = s.id returning * into s;
    update public.billing_invoices set collection = 'auto', updated_at = now()
     where subscription_id = s.id and status = 'open';
  end if;

  if s.status = 'incomplete' then
    if st.trial_days > 0 and not exists(select 1 from public.billing_subscriptions o
         where o.user_id = s.user_id and o.id <> s.id and o.trial_ends_at is not null) then
      update public.billing_subscriptions
         set status = 'trialing', trial_ends_at = now() + make_interval(days => st.trial_days), updated_at = now()
       where id = s.id;
    else
      -- Provisional access while the first charge is in flight; a failed first
      -- charge follows the same retry and grace rules as any other.
      update public.billing_subscriptions set status = 'active', updated_at = now() where id = s.id;
      perform public._hyn_billing_create_invoice(s.id, 'first', now(), 1, now());
    end if;
  else
    update public.billing_invoices
       set next_attempt_at = now(), blocked_reason = null, updated_at = now()
     where subscription_id = s.id and status = 'open' and void_pending_reason is null
       and total > 0 and attempts < 8
       and not exists(select 1 from public.billing_charges c where c.invoice_id = billing_invoices.id
                       and c.status in ('raising','pending','cancelling'));
  end if;
  perform public._hyn_billing_refresh(s.id);
end $$;

-- ===========================================================================
-- coupons and discounts
-- ===========================================================================
create or replace function public._hyn_billing_check_coupon(p_code text, p_user uuid, p_sub uuid)
returns public.billing_coupons language plpgsql security definer set search_path = public as $$
declare c public.billing_coupons; s public.billing_subscriptions;
begin
  select * into c from public.billing_coupons where code = upper(trim(p_code));
  if c.id is null or not c.active then raise exception 'That discount code is not valid.'; end if;
  if c.redeem_by is not null and c.redeem_by <= now() then raise exception 'That discount code has expired.'; end if;
  if c.max_redemptions is not null and c.redemptions >= c.max_redemptions then
    raise exception 'That discount code has been fully redeemed.';
  end if;
  if exists(select 1 from public.billing_discounts where user_id = p_user and coupon_id = c.id and status <> 'removed') then
    raise exception 'You have already used that discount code.';
  end if;
  if c.kind = 'first_month' then
    if exists(select 1 from public.billing_discounts where user_id = p_user and kind = 'first_month'
                and status in ('active','consumed') and (p_sub is null or subscription_id <> p_sub or status = 'consumed')) then
      raise exception 'A first-month discount has already been used on this account.';
    end if;
    select * into s from public.billing_subscriptions where id = p_sub;
    if s.id is not null and (s.cycle_count > 0 or exists(select 1 from public.billing_invoices
         where subscription_id = s.id and status <> 'void' and cycle_number = 1)) then
      raise exception 'First-month codes can only be used before the first payment.';
    end if;
  end if;
  return c;
end $$;

create or replace function public._hyn_billing_attach_discount(
  p_sub uuid, p_coupon uuid, p_kind text, p_percent integer, p_amount bigint, p_months integer,
  p_ends_at timestamptz, p_label text, p_source text, p_replace boolean)
returns public.billing_discounts language plpgsql security definer set search_path = public as $$
declare s public.billing_subscriptions; c public.billing_coupons; d public.billing_discounts; v_existing public.billing_discounts;
begin
  select * into s from public.billing_subscriptions where id = p_sub for update;
  if p_coupon is not null then
    select * into c from public.billing_coupons where id = p_coupon for update;
    if c.max_redemptions is not null and c.redemptions >= c.max_redemptions then
      raise exception 'That discount code has been fully redeemed.';
    end if;
    p_kind := c.kind; p_percent := c.percent_off; p_amount := c.amount_off;
    p_months := case when c.kind = 'first_month' then 1 else c.duration_months end;
    p_label := c.name;
  elsif p_kind = 'first_month' then
    p_months := 1;
  end if;
  select * into v_existing from public.billing_discounts where subscription_id = s.id and kind = p_kind and status = 'active';
  if v_existing.id is not null then
    if not p_replace then
      raise exception 'This plan already has % discount (%). Only one of each kind can be active.',
        case p_kind when 'ongoing' then 'an ongoing' else 'a first-month' end, v_existing.label;
    end if;
    update public.billing_discounts set status = 'removed', updated_at = now() where id = v_existing.id;
  end if;
  insert into public.billing_discounts (subscription_id, user_id, coupon_id, code, label, kind, percent_off,
    amount_off, cycles_remaining, ends_at, status, source, applied_by)
  values (s.id, s.user_id, c.id, c.code, left(trim(p_label), 120), p_kind, p_percent, p_amount, p_months,
    p_ends_at, 'active', p_source, auth.uid())
  returning * into d;
  if c.id is not null then
    update public.billing_coupons set redemptions = redemptions + 1 where id = c.id;
  end if;
  return d;
end $$;

-- ===========================================================================
-- what the billing page shows
-- ===========================================================================
create or replace function public._hyn_billing_summary_json(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare st public.billing_settings; s public.billing_subscriptions; inv public.billing_invoices;
  m public.billing_mandates; pm public.billing_mandates; v_estimate jsonb; v_boundary timestamptz;
  v_items jsonb; v_servers integer; v_held integer;
begin
  select * into st from public.billing_settings where id = 1;
  s := public._hyn_billing_live_sub(p_user);
  if s.id is not null then
    select * into inv from public.billing_invoices where subscription_id = s.id and status = 'open';
    select * into m from public.billing_mandates where id = s.current_mandate_id;
    select * into pm from public.billing_mandates where subscription_id = s.id
       and status in ('CREATING','INITIALIZED','BANK_APPROVAL_PENDING') and id is distinct from s.current_mandate_id
     order by created_at desc limit 1;
    if inv.id is null and s.status in ('trialing','active') and not s.cancel_at_period_end then
      v_boundary := coalesce(s.paid_through, s.trial_ends_at);
      select coalesce(jsonb_agg(jsonb_build_object('id', id, 'description', description, 'amount', amount)), '[]'::jsonb)
        into v_items from public.billing_pending_items where subscription_id = s.id and invoice_id is null;
      v_estimate := public._hyn_billing_price(coalesce(s.pending_quantity, s.quantity), s.unit_price, 1, v_items,
                      s.cycle_count + 1, public._hyn_billing_discounts_for(s.id, coalesce(v_boundary, now()), false))
                    || jsonb_build_object('due_at', v_boundary);
    end if;
  end if;
  select count(*) filter (where true), count(*) filter (where billing_hold and status = 'suspended')
    into v_servers, v_held
    from public.nodes where owner = p_user and not revoked and not is_demo;
  return jsonb_build_object(
    'enforced', st.enforce,
    'exempt', public._hyn_billing_exempt(p_user),
    'has_access', public._hyn_billing_owner_access(p_user),
    'price_per_server', st.price_per_server,
    'trial_days', st.trial_days,
    'auth_amount', st.auth_amount,
    'grace_days', st.grace_days,
    'renewal_lead_days', st.renewal_lead_days,
    'servers', v_servers,
    'held_servers', v_held,
    'first_month_available', not exists(select 1 from public.billing_discounts
        where user_id = p_user and kind = 'first_month' and status = 'consumed'),
    'subscription', case when s.id is null then null else jsonb_build_object(
      'id', s.id, 'status', s.status, 'collection', s.collection, 'quantity', s.quantity,
      'pending_quantity', s.pending_quantity, 'unit_price', s.unit_price, 'trial_ends_at', s.trial_ends_at,
      'paid_through', s.paid_through, 'current_period_start', s.current_period_start,
      'current_period_end', s.current_period_end, 'access_ends_at', s.access_ends_at,
      'cancel_at_period_end', s.cancel_at_period_end, 'legacy', s.legacy, 'cycle_count', s.cycle_count,
      'created_at', s.created_at) end,
    'mandate', case when m.id is null then null else jsonb_build_object(
      'id', m.id, 'status', m.status, 'payment_group', m.payment_group, 'max_amount', m.max_amount,
      'activated_at', m.activated_at) end,
    'pending_mandate', case when pm.id is null then null else jsonb_build_object(
      'id', pm.id, 'status', pm.status, 'created_at', pm.created_at) end,
    'open_invoice', case when inv.id is null then null else jsonb_build_object(
      'id', inv.id, 'number', inv.number, 'kind', inv.kind, 'period_start', inv.period_start,
      'period_end', inv.period_end, 'total', inv.total, 'subtotal', inv.subtotal, 'lines', inv.lines,
      'due_at', inv.due_at, 'attempts', inv.attempts, 'next_attempt_at', inv.next_attempt_at,
      'blocked_reason', inv.blocked_reason, 'collection', inv.collection,
      'grace_ends_at', inv.due_at + make_interval(days => st.grace_days),
      'void_pending', inv.void_pending_reason is not null,
      'charge', (select jsonb_build_object('status', c.status, 'scheduled_for', c.scheduled_for,
                  'failure_reason', c.failure_reason, 'attempt', c.attempt)
                   from public.billing_charges c where c.invoice_id = inv.id order by c.created_at desc limit 1)) end,
    'estimate', v_estimate,
    'discounts', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'label', d.label, 'kind', d.kind,
        'percent_off', d.percent_off, 'amount_off', d.amount_off, 'cycles_remaining', d.cycles_remaining,
        'ends_at', d.ends_at, 'code', d.code) order by d.created_at)
      from public.billing_discounts d where d.subscription_id = s.id and d.status = 'active'), '[]'::jsonb),
    'invoices', coalesce((select jsonb_agg(x order by x->>'created_at' desc) from (
        select jsonb_build_object('id', i.id, 'number', i.number, 'kind', i.kind, 'period_start', i.period_start,
          'period_end', i.period_end, 'total', i.total, 'subtotal', i.subtotal, 'status', i.status,
          'paid_at', i.paid_at, 'paid_via', i.paid_via, 'lines', i.lines, 'due_at', i.due_at,
          'created_at', i.created_at) as x
          from public.billing_invoices i where i.user_id = p_user order by i.created_at desc limit 24) q), '[]'::jsonb)
  );
end $$;

-- ===========================================================================
-- user RPCs
-- ===========================================================================
create or replace function public._hyn_billing_require_user()
returns uuid language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.hyn_is_active() then raise exception 'active account required'; end if;
  return auth.uid();
end $$;

create or replace function public.hyn_billing_summary()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return public._hyn_billing_summary_json(public._hyn_billing_require_user());
end $$;

create or replace function public.hyn_billing_preview(p_quantity integer, p_coupon text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := public._hyn_billing_require_user(); st public.billing_settings; s public.billing_subscriptions;
  c public.billing_coupons; v_discounts jsonb := '[]'::jsonb; v_coupon jsonb := null;
begin
  if p_quantity is null or p_quantity not between 1 and 1000 then raise exception 'Choose between 1 and 1000 servers.'; end if;
  select * into st from public.billing_settings where id = 1;
  s := public._hyn_billing_live_sub(v_uid);
  if nullif(trim(coalesce(p_coupon, '')), '') is not null then
    begin
      c := public._hyn_billing_check_coupon(p_coupon, v_uid, s.id);
      v_discounts := jsonb_build_array(jsonb_build_object('id', c.id, 'kind', c.kind, 'percent_off', c.percent_off,
        'amount_off', c.amount_off, 'label', c.name));
      v_coupon := jsonb_build_object('valid', true, 'code', c.code, 'label', c.name, 'kind', c.kind,
        'duration_months', c.duration_months);
    exception when raise_exception then
      v_coupon := jsonb_build_object('valid', false, 'message', sqlerrm);
    end;
  end if;
  return public._hyn_billing_price(p_quantity, st.price_per_server, 1, '[]'::jsonb, 1, v_discounts)
      || jsonb_build_object('coupon', v_coupon, 'trial_days', st.trial_days, 'auth_amount', st.auth_amount);
end $$;

-- Starts autopay: a new subscription, or a new payment method for an existing one.
create or replace function public.hyn_billing_begin_checkout(p_quantity integer, p_coupon text, p_phone text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := public._hyn_billing_require_user(); st public.billing_settings; s public.billing_subscriptions;
  c public.billing_coupons; m public.billing_mandates; v_phone text; v_email text; v_name text; v_d public.billing_discounts;
begin
  if public._hyn_billing_exempt(v_uid) then raise exception 'Staff accounts are not billed.'; end if;
  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  if length(v_phone) = 12 and left(v_phone, 2) = '91' then v_phone := right(v_phone, 10); end if;
  if v_phone !~ '^[6-9][0-9]{9}$' then raise exception 'Enter a 10-digit Indian mobile number for payment alerts.'; end if;
  perform pg_advisory_xact_lock(hashtext('hyn-billing-user:' || v_uid::text));
  if (select count(*) from public.billing_mandates where user_id = v_uid and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'Too many autopay attempts. Try again in an hour.';
  end if;
  select * into st from public.billing_settings where id = 1;
  select u.email, coalesce(nullif(p.full_name, ''), split_part(u.email, '@', 1)) into v_email, v_name
    from auth.users u join public.profiles p on p.id = u.id where u.id = v_uid;
  if v_email is null then raise exception 'Your account needs an email address before it can be billed.'; end if;

  s := public._hyn_billing_live_sub(v_uid);
  if s.id is null or s.status = 'incomplete' then
    if p_quantity is null or p_quantity not between 1 and 1000 then raise exception 'Choose between 1 and 1000 servers.'; end if;
    if s.id is null then
      insert into public.billing_subscriptions (user_id, status, collection, quantity, unit_price, created_by)
      values (v_uid, 'incomplete', 'auto', p_quantity, st.price_per_server, v_uid) returning * into s;
    else
      update public.billing_subscriptions set quantity = p_quantity, unit_price = st.price_per_server, updated_at = now()
       where id = s.id returning * into s;
    end if;
    -- A retried checkout replaces the code chosen last time.
    for v_d in select * from public.billing_discounts where subscription_id = s.id and source = 'code' and status = 'active' loop
      update public.billing_discounts set status = 'removed', updated_at = now() where id = v_d.id;
      update public.billing_coupons set redemptions = greatest(redemptions - 1, 0) where id = v_d.coupon_id;
    end loop;
    if nullif(trim(coalesce(p_coupon, '')), '') is not null then
      c := public._hyn_billing_check_coupon(p_coupon, v_uid, s.id);
      perform public._hyn_billing_attach_discount(s.id, c.id, null, null, null, null, null, null, 'code', false);
    end if;
  end if;

  insert into public.billing_mandates (subscription_id, user_id, cf_subscription_id, max_amount, auth_amount, phone)
  values (s.id, v_uid, 'hyn_' || replace(gen_random_uuid()::text, '-', ''),
          greatest(st.mandate_max_amount, 2 * s.quantity::bigint * s.unit_price), st.auth_amount, v_phone)
  returning * into m;
  return jsonb_build_object('mandate_id', m.id, 'cf_subscription_id', m.cf_subscription_id,
    'max_amount', m.max_amount, 'auth_amount', m.auth_amount, 'phone', v_phone, 'email', v_email,
    'name', left(v_name, 100), 'subscription_id', s.id);
end $$;

create or replace function public.hyn_billing_set_quantity(p_quantity integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := public._hyn_billing_require_user(); s public.billing_subscriptions; inv public.billing_invoices;
  v_servers integer; v_amount numeric := 0; v_added integer;
begin
  if p_quantity is null or p_quantity not between 1 and 1000 then raise exception 'Choose between 1 and 1000 servers.'; end if;
  perform pg_advisory_xact_lock(hashtext('hyn-billing-user:' || v_uid::text));
  s := public._hyn_billing_live_sub(v_uid);
  if s.id is null then raise exception 'You do not have a plan yet.'; end if;
  select * into s from public.billing_subscriptions where id = s.id for update;
  if s.status = 'unpaid' then raise exception 'Settle the outstanding invoice before changing your plan.'; end if;
  if s.collection = 'manual' then raise exception 'Your plan is billed manually. Contact your administrator to change it.'; end if;
  select count(*) into v_servers from public.nodes where owner = v_uid and not revoked and not is_demo;

  if p_quantity > s.quantity then
    v_added := p_quantity - s.quantity;
    -- Every finalised invoice that still covers time from now on billed fewer
    -- servers; the difference for that remaining time goes on the next invoice.
    for inv in select * from public.billing_invoices where subscription_id = s.id and status <> 'void'
                and period_end > now() and quantity < p_quantity loop
      v_amount := v_amount + (p_quantity - inv.quantity) * inv.unit_price * inv.months
        * extract(epoch from inv.period_end - greatest(now(), inv.period_start))
        / extract(epoch from inv.period_end - inv.period_start);
    end loop;
    if round(v_amount) > 0 then
      insert into public.billing_pending_items (subscription_id, description, amount)
      values (s.id, format('%s added server%s, %s to the end of the billed period', v_added,
        case when v_added = 1 then '' else 's' end, to_char(now() at time zone 'Asia/Kolkata', 'DD Mon YYYY')), round(v_amount));
    end if;
    update public.billing_subscriptions set quantity = p_quantity, pending_quantity = null, updated_at = now() where id = s.id;
  elsif p_quantity < s.quantity then
    if p_quantity < v_servers then
      raise exception 'You have % linked servers. Remove servers before lowering your plan to %.', v_servers, p_quantity;
    end if;
    if s.status = 'incomplete' or not exists(select 1 from public.billing_invoices where subscription_id = s.id
         and status <> 'void' and period_end > now()) then
      update public.billing_subscriptions set quantity = p_quantity, pending_quantity = null, updated_at = now() where id = s.id;
    else
      update public.billing_subscriptions set pending_quantity = p_quantity, updated_at = now() where id = s.id;
    end if;
  else
    update public.billing_subscriptions set pending_quantity = null, updated_at = now() where id = s.id;
  end if;
  perform public._hyn_billing_sync_access(v_uid);
  select * into s from public.billing_subscriptions where id = s.id;
  return jsonb_build_object('quantity', s.quantity, 'pending_quantity', s.pending_quantity, 'proration', round(v_amount));
end $$;

create or replace function public.hyn_billing_apply_coupon(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := public._hyn_billing_require_user(); s public.billing_subscriptions; c public.billing_coupons;
  d public.billing_discounts;
begin
  perform pg_advisory_xact_lock(hashtext('hyn-billing-user:' || v_uid::text));
  s := public._hyn_billing_live_sub(v_uid);
  if s.id is null then raise exception 'Start a plan before adding a discount code.'; end if;
  if s.status = 'unpaid' then raise exception 'Settle the outstanding invoice before adding a discount code.'; end if;
  c := public._hyn_billing_check_coupon(p_code, v_uid, s.id);
  d := public._hyn_billing_attach_discount(s.id, c.id, null, null, null, null, null, null, 'code', false);
  perform public._hyn_audit('billing.discount.code', v_uid, null, jsonb_build_object('code', c.code));
  return jsonb_build_object('id', d.id, 'label', d.label, 'kind', d.kind);
end $$;

create or replace function public.hyn_billing_cancel()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := public._hyn_billing_require_user(); s public.billing_subscriptions;
begin
  perform pg_advisory_xact_lock(hashtext('hyn-billing-user:' || v_uid::text));
  s := public._hyn_billing_live_sub(v_uid);
  if s.id is null then raise exception 'You do not have a plan to cancel.'; end if;
  select * into s from public.billing_subscriptions where id = s.id for update;
  if s.collection = 'manual' then raise exception 'Your plan is billed manually. Contact your administrator to cancel it.'; end if;
  perform public._hyn_audit('billing.cancel', v_uid, null, jsonb_build_object('status', s.status));
  -- Nothing paid for the time ahead: end now.
  if s.status in ('incomplete','past_due','unpaid') or (s.status = 'active' and s.paid_through is null) then
    perform public._hyn_billing_end(s.id, 'canceled_by_user', now());
    return jsonb_build_object('status', 'canceled', 'ends_at', now());
  end if;
  update public.billing_subscriptions
     set cancel_at_period_end = true, cancel_requested_at = now(), cancel_reason = 'canceled_by_user', updated_at = now()
   where id = s.id;
  update public.billing_invoices set void_pending_reason = 'canceled', next_attempt_at = null, updated_at = now()
   where subscription_id = s.id and status = 'open';
  perform public._hyn_billing_refresh(s.id);
  return jsonb_build_object('status', 'cancel_at_period_end',
    'ends_at', greatest(s.paid_through, s.trial_ends_at));
end $$;

create or replace function public.hyn_billing_resume()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := public._hyn_billing_require_user(); s public.billing_subscriptions;
begin
  perform pg_advisory_xact_lock(hashtext('hyn-billing-user:' || v_uid::text));
  s := public._hyn_billing_live_sub(v_uid);
  if s.id is null or not s.cancel_at_period_end or s.status not in ('trialing','active') or s.access_ends_at <= now() then
    raise exception 'There is no scheduled cancellation to undo.';
  end if;
  update public.billing_subscriptions set cancel_at_period_end = false, cancel_requested_at = null, cancel_reason = null,
         updated_at = now() where id = s.id;
  update public.billing_invoices set void_pending_reason = null,
         next_attempt_at = case when collection = 'auto' and total > 0 then now() end, updated_at = now()
   where subscription_id = s.id and status = 'open' and void_pending_reason = 'canceled'
     and not exists(select 1 from public.billing_charges c where c.invoice_id = billing_invoices.id
                     and c.status in ('raising','pending','cancelling'));
  perform public._hyn_audit('billing.resume', v_uid, null, '{}'::jsonb);
  perform public._hyn_billing_refresh(s.id);
  return jsonb_build_object('status', 'resumed');
end $$;

create or replace function public.hyn_billing_retry_payment()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := public._hyn_billing_require_user(); s public.billing_subscriptions; inv public.billing_invoices;
begin
  perform pg_advisory_xact_lock(hashtext('hyn-billing-user:' || v_uid::text));
  s := public._hyn_billing_live_sub(v_uid);
  select * into inv from public.billing_invoices where subscription_id = s.id and status = 'open' for update;
  if inv.id is null or inv.void_pending_reason is not null then raise exception 'There is no payment to retry.'; end if;
  if s.collection <> 'auto' then raise exception 'This invoice is settled manually with your administrator.'; end if;
  if not exists(select 1 from public.billing_mandates where id = s.current_mandate_id and status in ('ACTIVE','ON_HOLD')) then
    raise exception 'Set up autopay first; it will charge this invoice once it is active.';
  end if;
  if exists(select 1 from public.billing_charges where invoice_id = inv.id and status in ('raising','pending','cancelling')) then
    raise exception 'A payment for this invoice is already in progress.';
  end if;
  if inv.attempts >= 8 then raise exception 'This invoice has been attempted too many times. Contact support.'; end if;
  update public.billing_invoices set next_attempt_at = now(), blocked_reason = null, updated_at = now() where id = inv.id;
  return jsonb_build_object('status', 'queued', 'invoice', inv.number);
end $$;

-- ===========================================================================
-- admin RPCs (reads: Admin and Super admin; writes: Super admin)
-- ===========================================================================
create or replace function public.hyn_admin_billing_dashboard(p_search text default null, p_status text default 'all', p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path = public as $$
declare st public.billing_settings; v_search text := nullif(lower(trim(coalesce(p_search, ''))), '');
begin
  perform public._hyn_require_staff();
  if p_status not in ('all','incomplete','trialing','active','past_due','unpaid','canceled','attention') then
    raise exception 'unknown status filter';
  end if;
  select * into st from public.billing_settings where id = 1;
  return jsonb_build_object(
    'as_of', now(),
    'settings', to_jsonb(st),
    'stats', jsonb_build_object(
      'by_status', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n
                    from public.billing_subscriptions group by status) q), '{}'::jsonb),
      'monthly_recurring', coalesce((select sum(quantity::bigint * unit_price) from public.billing_subscriptions
                    where status in ('active','past_due') and not cancel_at_period_end), 0),
      'open_total', coalesce((select sum(total) from public.billing_invoices where status = 'open'), 0),
      'needs_refund', (select count(*) from public.billing_invoices where needs_refund),
      'legacy_trials', (select count(*) from public.billing_subscriptions where legacy and status = 'trialing'),
      'held_servers', (select count(*) from public.nodes where billing_hold and status = 'suspended' and not revoked)),
    'subscriptions', coalesce((select jsonb_agg(row_to_json(q)::jsonb) from (
      select s.id, s.user_id, p.email, p.full_name, s.status, s.collection, s.quantity, s.pending_quantity,
             s.unit_price, s.trial_ends_at, s.paid_through, s.access_ends_at, s.cancel_at_period_end, s.legacy,
             s.created_at, s.cancel_reason,
             (select count(*) from public.nodes n where n.owner = s.user_id and not n.revoked and not n.is_demo) as servers,
             (select m.status from public.billing_mandates m where m.id = s.current_mandate_id) as mandate_status,
             (select jsonb_build_object('number', i.number, 'total', i.total, 'due_at', i.due_at,
                     'blocked_reason', i.blocked_reason, 'attempts', i.attempts)
                from public.billing_invoices i where i.subscription_id = s.id and i.status = 'open') as open_invoice
        from public.billing_subscriptions s join public.profiles p on p.id = s.user_id
       where (v_search is null or lower(coalesce(p.email, '')) like '%' || v_search || '%'
              or lower(coalesce(p.full_name, '')) like '%' || v_search || '%')
         and (p_status = 'all' or s.status = p_status
              or (p_status = 'attention' and (s.status in ('past_due','unpaid') or exists(select 1 from public.billing_invoices i
                    where i.subscription_id = s.id and (i.needs_refund or (i.status = 'open' and i.blocked_reason is not null))))))
       order by (s.status = 'canceled'), s.updated_at desc
       limit 50 offset greatest(coalesce(p_offset, 0), 0)) q), '[]'::jsonb),
    'unbilled', coalesce((select jsonb_agg(row_to_json(q)::jsonb) from (
      select p.id as user_id, p.email, p.full_name, count(n.id) as servers
        from public.profiles p join public.nodes n on n.owner = p.id and not n.revoked and not n.is_demo
       where p.role not in ('maintainer','admin','super_admin')
         and not exists(select 1 from public.billing_subscriptions s where s.user_id = p.id and s.status <> 'canceled')
       group by p.id order by count(n.id) desc limit 50) q), '[]'::jsonb),
    'refunds', coalesce((select jsonb_agg(row_to_json(q)::jsonb) from (
      select i.id, i.number, i.total, i.paid_at, i.paid_via, p.email
        from public.billing_invoices i join public.profiles p on p.id = i.user_id
       where i.needs_refund order by i.updated_at desc limit 50) q), '[]'::jsonb),
    'coupons', coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from public.billing_coupons c), '[]'::jsonb)
  );
end $$;

create or replace function public.hyn_admin_billing_user(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.billing_subscriptions;
begin
  perform public._hyn_require_staff();
  if not exists(select 1 from public.profiles where id = p_user) then raise exception 'no such client'; end if;
  s := public._hyn_billing_live_sub(p_user);
  return public._hyn_billing_summary_json(p_user) || jsonb_build_object(
    'profile', (select jsonb_build_object('id', p.id, 'email', p.email, 'full_name', p.full_name, 'role', p.role,
                  'status', p.status) from public.profiles p where p.id = p_user),
    'all_discounts', coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc)
        from public.billing_discounts d where d.user_id = p_user), '[]'::jsonb),
    'all_invoices', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'number', i.number, 'kind', i.kind,
        'status', i.status, 'total', i.total, 'period_start', i.period_start, 'period_end', i.period_end,
        'due_at', i.due_at, 'paid_at', i.paid_at, 'paid_via', i.paid_via, 'needs_refund', i.needs_refund,
        'attempts', i.attempts, 'blocked_reason', i.blocked_reason, 'void_reason', i.void_reason, 'lines', i.lines)
        order by i.created_at desc) from public.billing_invoices i where i.user_id = p_user), '[]'::jsonb),
    'charges', coalesce((select jsonb_agg(jsonb_build_object('payment_id', c.payment_id, 'status', c.status,
        'amount', c.amount, 'attempt', c.attempt, 'scheduled_for', c.scheduled_for, 'failure_reason', c.failure_reason,
        'created_at', c.created_at) order by c.created_at desc)
        from public.billing_charges c join public.billing_invoices i on i.id = c.invoice_id where i.user_id = p_user), '[]'::jsonb),
    'mandates', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'status', m.status, 'payment_group', m.payment_group,
        'max_amount', m.max_amount, 'created_at', m.created_at, 'activated_at', m.activated_at, 'ended_at', m.ended_at,
        'current', m.id = s.current_mandate_id, 'error', m.error) order by m.created_at desc)
        from public.billing_mandates m where m.user_id = p_user), '[]'::jsonb),
    'manual_payments', coalesce((select jsonb_agg(jsonb_build_object('amount', mp.amount, 'method', mp.method,
        'reference', mp.reference, 'note', mp.note, 'received_at', mp.received_at,
        'invoice', (select number from public.billing_invoices where id = mp.invoice_id)) order by mp.created_at desc)
        from public.billing_manual_payments mp where mp.user_id = p_user), '[]'::jsonb)
  );
end $$;

create or replace function public.hyn_admin_billing_save_settings(p_settings jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public._hyn_require_admin(); v_old public.billing_settings; v_new public.billing_settings;
  k text;
begin
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then raise exception 'settings must be an object'; end if;
  for k in select jsonb_object_keys(p_settings) loop
    if k not in ('price_per_server','auth_amount','mandate_max_amount','trial_days','renewal_lead_days','grace_days',
                 'retry_interval_days','max_auto_attempts','unpaid_cancel_days') then
      raise exception 'unknown billing setting %', k;
    end if;
  end loop;
  select * into v_old from public.billing_settings where id = 1 for update;
  update public.billing_settings set
    price_per_server = coalesce((p_settings->>'price_per_server')::bigint, price_per_server),
    auth_amount = coalesce((p_settings->>'auth_amount')::bigint, auth_amount),
    mandate_max_amount = coalesce((p_settings->>'mandate_max_amount')::bigint, mandate_max_amount),
    trial_days = coalesce((p_settings->>'trial_days')::integer, trial_days),
    renewal_lead_days = coalesce((p_settings->>'renewal_lead_days')::integer, renewal_lead_days),
    grace_days = coalesce((p_settings->>'grace_days')::integer, grace_days),
    retry_interval_days = coalesce((p_settings->>'retry_interval_days')::integer, retry_interval_days),
    max_auto_attempts = coalesce((p_settings->>'max_auto_attempts')::integer, max_auto_attempts),
    unpaid_cancel_days = coalesce((p_settings->>'unpaid_cancel_days')::integer, unpaid_cancel_days),
    updated_at = now(), updated_by = v_actor
  where id = 1 returning * into v_new;
  perform public._hyn_audit('billing.settings', null, null,
    jsonb_build_object('before', to_jsonb(v_old) - 'updated_at' - 'updated_by', 'after', to_jsonb(v_new) - 'updated_at' - 'updated_by'));
  return to_jsonb(v_new);
end $$;

-- Turns enforcement on. Every non-staff account that already owns servers gets
-- a legacy trial for its current server count, so nobody loses access at launch;
-- they set up autopay during the trial and are first charged when it ends.
create or replace function public.hyn_admin_billing_launch(p_grace_days integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public._hyn_require_admin(); st public.billing_settings; v_created integer;
begin
  if p_grace_days is null or p_grace_days not between 1 and 90 then raise exception 'Choose a grace period of 1 to 90 days.'; end if;
  select * into st from public.billing_settings where id = 1 for update;
  with owners as (
    select p.id, count(n.id)::integer as servers
      from public.profiles p join public.nodes n on n.owner = p.id and not n.revoked and not n.is_demo
     where p.status = 'active' and p.role not in ('maintainer','admin','super_admin')
       and not exists(select 1 from public.billing_subscriptions s where s.user_id = p.id and s.status <> 'canceled')
     group by p.id
  ), ins as (
    insert into public.billing_subscriptions (user_id, status, collection, quantity, unit_price, trial_ends_at,
      access_ends_at, legacy, created_by, note)
    select id, 'trialing', 'auto', least(servers, 1000), st.price_per_server, now() + make_interval(days => p_grace_days),
           now() + make_interval(days => p_grace_days), true, v_actor, 'Existing customer at billing launch'
      from owners
    returning 1
  )
  select count(*) into v_created from ins;
  update public.billing_settings set enforce = true, launched_at = coalesce(launched_at, now()), updated_at = now(),
         updated_by = v_actor where id = 1;
  perform public._hyn_audit('billing.launch', null, null, jsonb_build_object('grace_days', p_grace_days, 'legacy_trials', v_created));
  perform public._hyn_billing_sync_access(null);
  return jsonb_build_object('status', 'ok', 'legacy_trials', v_created);
end $$;

create or replace function public.hyn_admin_billing_set_enforce(p_enforce boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public._hyn_require_admin();
begin
  if p_enforce is null then raise exception 'choose on or off'; end if;
  if p_enforce and (select launched_at from public.billing_settings where id = 1) is null then
    raise exception 'Launch billing first, so existing customers receive their trial.';
  end if;
  update public.billing_settings set enforce = p_enforce, updated_at = now(), updated_by = v_actor where id = 1;
  perform public._hyn_audit('billing.enforce', null, null, jsonb_build_object('enforce', p_enforce));
  return jsonb_build_object('enforce', p_enforce, 'changed', public._hyn_billing_sync_access(null));
end $$;

create or replace function public.hyn_admin_billing_assign(
  p_user uuid, p_quantity integer, p_unit_price bigint, p_months integer, p_collection text,
  p_mark_paid boolean, p_method text default null, p_reference text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public._hyn_require_admin(); st public.billing_settings; s public.billing_subscriptions;
  inv public.billing_invoices; v_start timestamptz;
begin
  if not exists(select 1 from public.profiles where id = p_user) then raise exception 'no such client'; end if;
  if public._hyn_billing_exempt(p_user) then raise exception 'Staff accounts are exempt from billing.'; end if;
  if p_quantity is null or p_quantity not between 1 and 1000 then raise exception 'Choose between 1 and 1000 servers.'; end if;
  if p_months is null or p_months not between 1 and 36 then raise exception 'Choose 1 to 36 months.'; end if;
  if p_collection not in ('auto','manual') then raise exception 'Collection must be auto or manual.'; end if;
  if p_unit_price is not null and p_unit_price not between 0 and 10000000 then raise exception 'Enter a valid price.'; end if;
  if coalesce(p_mark_paid, false) and coalesce(p_method, '') not in ('cash','bank_transfer','upi','cheque','other') then
    raise exception 'Choose how the payment was received.';
  end if;
  perform pg_advisory_xact_lock(hashtext('hyn-billing-user:' || p_user::text));
  select * into st from public.billing_settings where id = 1;
  s := public._hyn_billing_live_sub(p_user);
  if s.status = 'incomplete' then
    perform public._hyn_billing_end(s.id, 'replaced_by_admin', now());
    s := null;
  end if;
  if s.id is not null and exists(select 1 from public.billing_invoices where subscription_id = s.id and status = 'open') then
    raise exception 'This user has an open invoice. Record its payment or void it first.';
  end if;
  if s.id is null then
    insert into public.billing_subscriptions (user_id, status, collection, quantity, unit_price, created_by, note)
    values (p_user, 'active', p_collection, p_quantity, coalesce(p_unit_price, st.price_per_server), v_actor, left(p_note, 500))
    returning * into s;
  else
    update public.billing_subscriptions
       set collection = p_collection, quantity = p_quantity, pending_quantity = null,
           unit_price = coalesce(p_unit_price, unit_price), cancel_at_period_end = false, cancel_reason = null,
           current_mandate_id = case when p_collection = 'manual' then null else current_mandate_id end,
           note = coalesce(left(p_note, 500), note), updated_at = now()
     where id = s.id returning * into s;
  end if;
  -- The paid time follows any time already paid for or still in trial.
  v_start := greatest(s.paid_through, case when s.status = 'trialing' then s.trial_ends_at end, now());
  inv := public._hyn_billing_create_invoice(s.id, 'manual', v_start, p_months, v_start);
  if coalesce(p_mark_paid, false) and inv.status = 'open' then
    insert into public.billing_manual_payments (invoice_id, user_id, amount, method, reference, note, received_at, recorded_by)
    values (inv.id, p_user, inv.total, p_method, left(p_reference, 120), left(p_note, 500), now(), v_actor);
    perform public._hyn_billing_mark_paid(inv.id, 'manual', now());
  end if;
  perform public._hyn_billing_refresh(s.id);
  perform public._hyn_audit('billing.assign', p_user, null, jsonb_build_object('quantity', p_quantity,
    'unit_price', s.unit_price, 'months', p_months, 'collection', p_collection, 'paid', coalesce(p_mark_paid, false),
    'invoice', inv.number, 'total', inv.total));
  select * into inv from public.billing_invoices where id = inv.id;
  return jsonb_build_object('subscription_id', s.id, 'invoice', inv.number, 'total', inv.total, 'invoice_status', inv.status);
end $$;

create or replace function public.hyn_admin_billing_record_payment(
  p_invoice uuid, p_amount bigint, p_method text, p_reference text default null, p_note text default null,
  p_received_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public._hyn_require_admin(); inv public.billing_invoices; v_at timestamptz;
begin
  select * into inv from public.billing_invoices where id = p_invoice for update;
  if inv.id is null then raise exception 'no such invoice'; end if;
  if inv.status <> 'open' then raise exception 'Invoice % is already %.', inv.number, inv.status; end if;
  if p_amount is distinct from inv.total then
    raise exception 'The amount must equal the invoice total of %. Apply a discount or void the invoice to settle a different amount.',
      public._hyn_billing_money(inv.total);
  end if;
  if coalesce(p_method, '') not in ('cash','bank_transfer','upi','cheque','other') then
    raise exception 'Choose how the payment was received.';
  end if;
  v_at := coalesce(p_received_at, now());
  if v_at > now() + interval '1 day' then raise exception 'The received date cannot be in the future.'; end if;
  insert into public.billing_manual_payments (invoice_id, user_id, amount, method, reference, note, received_at, recorded_by)
  values (inv.id, inv.user_id, p_amount, p_method, left(p_reference, 120), left(p_note, 500), v_at, v_actor);
  perform public._hyn_billing_mark_paid(inv.id, 'manual', least(v_at, now()));
  perform public._hyn_audit('billing.payment.manual', inv.user_id, null, jsonb_build_object('invoice', inv.number,
    'amount', p_amount, 'method', p_method, 'reference', left(p_reference, 120)));
  return jsonb_build_object('status', 'paid', 'invoice', inv.number);
end $$;

create or replace function public.hyn_admin_billing_void_invoice(p_invoice uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public._hyn_require_admin(); inv public.billing_invoices;
begin
  if length(trim(coalesce(p_reason, ''))) not between 3 and 200 then raise exception 'Give a reason (3 to 200 characters).'; end if;
  select * into inv from public.billing_invoices where id = p_invoice for update;
  if inv.id is null or inv.status <> 'open' then raise exception 'Only an open invoice can be voided.'; end if;
  perform public._hyn_audit('billing.invoice.void', inv.user_id, null, jsonb_build_object('invoice', inv.number, 'reason', trim(p_reason)));
  if exists(select 1 from public.billing_charges where invoice_id = inv.id and status in ('raising','pending','cancelling')) then
    update public.billing_invoices set void_pending_reason = 'admin: ' || trim(p_reason), next_attempt_at = null, updated_at = now()
     where id = inv.id;
    update public.billing_charges set status = 'cancelling', claimed_at = null, updated_at = now()
     where invoice_id = inv.id and status = 'pending';
    return jsonb_build_object('status', 'void_pending');
  end if;
  perform public._hyn_billing_void_invoice(inv.id, 'admin: ' || trim(p_reason));
  return jsonb_build_object('status', 'void');
end $$;

create or replace function public.hyn_admin_billing_set_quantity(p_user uuid, p_quantity integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public._hyn_require_admin(); s public.billing_subscriptions;
begin
  if p_quantity is null or p_quantity not between 1 and 1000 then raise exception 'Choose between 1 and 1000 servers.'; end if;
  s := public._hyn_billing_live_sub(p_user);
  if s.id is null then raise exception 'This user has no plan.'; end if;
  update public.billing_subscriptions set quantity = p_quantity, pending_quantity = null, updated_at = now() where id = s.id;
  perform public._hyn_audit('billing.quantity', p_user, null, jsonb_build_object('from', s.quantity, 'to', p_quantity));
  perform public._hyn_billing_sync_access(p_user);
  return jsonb_build_object('quantity', p_quantity);
end $$;

create or replace function public.hyn_admin_billing_cancel(p_user uuid, p_immediate boolean, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public._hyn_require_admin(); s public.billing_subscriptions;
begin
  s := public._hyn_billing_live_sub(p_user);
  if s.id is null then raise exception 'This user has no plan.'; end if;
  perform public._hyn_audit('billing.cancel.admin', p_user, null,
    jsonb_build_object('immediate', coalesce(p_immediate, false), 'reason', left(p_reason, 200)));
  if coalesce(p_immediate, false) or s.status in ('incomplete','past_due','unpaid') then
    perform public._hyn_billing_end(s.id, 'canceled_by_admin', now());
    return jsonb_build_object('status', 'canceled');
  end if;
  update public.billing_subscriptions set cancel_at_period_end = true, cancel_requested_at = now(),
         cancel_reason = 'canceled_by_admin', updated_at = now() where id = s.id;
  update public.billing_invoices set void_pending_reason = 'canceled', next_attempt_at = null, updated_at = now()
   where subscription_id = s.id and status = 'open';
  perform public._hyn_billing_refresh(s.id);
  return jsonb_build_object('status', 'cancel_at_period_end');
end $$;

create or replace function public.hyn_admin_billing_add_discount(
  p_user uuid, p_code text, p_label text, p_kind text, p_percent integer, p_amount bigint,
  p_months integer, p_ends_at timestamptz)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public._hyn_require_admin(); s public.billing_subscriptions; c public.billing_coupons;
  d public.billing_discounts;
begin
  s := public._hyn_billing_live_sub(p_user);
  if s.id is null then raise exception 'This user has no plan.'; end if;
  if nullif(trim(coalesce(p_code, '')), '') is not null then
    c := public._hyn_billing_check_coupon(p_code, p_user, s.id);
    d := public._hyn_billing_attach_discount(s.id, c.id, null, null, null, null, null, null, 'admin', true);
  else
    if p_kind not in ('first_month','ongoing') then raise exception 'Choose first month or ongoing.'; end if;
    if (p_percent is null) = (p_amount is null) then raise exception 'Enter either a percentage or an amount.'; end if;
    if p_percent is not null and p_percent not between 1 and 100 then raise exception 'A percentage is 1 to 100.'; end if;
    if p_amount is not null and p_amount not between 1 and 10000000 then raise exception 'Enter a valid amount.'; end if;
    if p_kind = 'ongoing' and p_months is not null and p_months not between 1 and 120 then
      raise exception 'Duration is 1 to 120 months, or empty for forever.';
    end if;
    if length(trim(coalesce(p_label, ''))) not between 1 and 120 then raise exception 'Give the discount a label.'; end if;
    if p_kind = 'first_month' and (s.cycle_count > 0 or exists(select 1 from public.billing_invoices
         where subscription_id = s.id and status <> 'void' and cycle_number = 1)) then
      raise exception 'The first billing cycle is already finalised; use an ongoing discount for one month instead.';
    end if;
    if p_ends_at is not null and p_ends_at <= now() then raise exception 'The end date must be in the future.'; end if;
    d := public._hyn_billing_attach_discount(s.id, null, p_kind, p_percent, p_amount,
      case when p_kind = 'ongoing' then p_months end, p_ends_at, p_label, 'admin', true);
  end if;
  perform public._hyn_audit('billing.discount.add', p_user, null, to_jsonb(d) - 'subscription_id' - 'user_id');
  return jsonb_build_object('id', d.id, 'label', d.label);
end $$;

create or replace function public.hyn_admin_billing_remove_discount(p_discount uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public._hyn_require_admin(); d public.billing_discounts;
begin
  update public.billing_discounts set status = 'removed', updated_at = now()
   where id = p_discount and status = 'active' returning * into d;
  if d.id is null then raise exception 'No active discount with that id.'; end if;
  perform public._hyn_audit('billing.discount.remove', d.user_id, null, jsonb_build_object('label', d.label));
  return jsonb_build_object('status', 'removed');
end $$;

create or replace function public.hyn_admin_billing_save_coupon(p_coupon jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public._hyn_require_admin(); c public.billing_coupons;
begin
  begin
    insert into public.billing_coupons (code, name, kind, percent_off, amount_off, duration_months, redeem_by,
      max_redemptions, created_by)
    values (upper(trim(p_coupon->>'code')), trim(p_coupon->>'name'), p_coupon->>'kind',
      (p_coupon->>'percent_off')::integer, (p_coupon->>'amount_off')::bigint,
      case when p_coupon->>'kind' = 'ongoing' then (p_coupon->>'duration_months')::integer end,
      (p_coupon->>'redeem_by')::timestamptz, (p_coupon->>'max_redemptions')::integer, v_actor)
    returning * into c;
  exception
    when unique_violation then raise exception 'A coupon with that code already exists.';
    when check_violation then raise exception 'Check the coupon: code is 3-32 letters, digits, - or _; one of percent (1-100) or amount; duration only for ongoing.';
  end;
  perform public._hyn_audit('billing.coupon.create', null, null, to_jsonb(c));
  return to_jsonb(c);
end $$;

create or replace function public.hyn_admin_billing_set_coupon_active(p_coupon uuid, p_active boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public._hyn_require_admin(); c public.billing_coupons;
begin
  update public.billing_coupons set active = coalesce(p_active, false) where id = p_coupon returning * into c;
  if c.id is null then raise exception 'no such coupon'; end if;
  perform public._hyn_audit('billing.coupon.active', null, null, jsonb_build_object('code', c.code, 'active', c.active));
  return to_jsonb(c);
end $$;

create or replace function public.hyn_admin_billing_resolve_refund(p_invoice uuid, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public._hyn_require_admin(); inv public.billing_invoices;
begin
  if length(trim(coalesce(p_note, ''))) not between 3 and 300 then raise exception 'Describe how it was resolved.'; end if;
  update public.billing_invoices set needs_refund = false, updated_at = now() where id = p_invoice and needs_refund
  returning * into inv;
  if inv.id is null then raise exception 'That invoice is not waiting for a refund.'; end if;
  perform public._hyn_audit('billing.refund.resolved', inv.user_id, null, jsonb_build_object('invoice', inv.number, 'note', trim(p_note)));
  return jsonb_build_object('status', 'resolved');
end $$;

-- ===========================================================================
-- service RPCs: the portal reports what Cashfree said (service role only)
-- ===========================================================================
create or replace function public.hyn_billing_svc_mandate_created(
  p_mandate uuid, p_ok boolean, p_session text, p_cf_ref text, p_error text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m public.billing_mandates;
begin
  update public.billing_mandates
     set status = case when p_ok then 'INITIALIZED' else 'FAILED' end,
         session_id = case when p_ok then left(p_session, 500) end, cf_ref = left(p_cf_ref, 100),
         error = case when p_ok then null else left(p_error, 500) end,
         ended_at = case when p_ok then null else now() end, updated_at = now()
   where id = p_mandate and status = 'CREATING' returning * into m;
  return jsonb_build_object('status', coalesce(m.status, 'unchanged'));
end $$;

create or replace function public.hyn_billing_svc_mandate_lookup(p_mandate uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('mandate_id', id, 'cf_subscription_id', cf_subscription_id, 'user_id', user_id, 'status', status)
    from public.billing_mandates where id = p_mandate;
$$;

create or replace function public.hyn_billing_svc_mandate_status(
  p_cf_subscription_id text, p_status text, p_payment_group text, p_event_at timestamptz)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m public.billing_mandates; v_status text := upper(trim(coalesce(p_status, '')));
begin
  select * into m from public.billing_mandates where cf_subscription_id = p_cf_subscription_id for update;
  if m.id is null then return jsonb_build_object('status', 'unknown'); end if;
  if v_status not in ('INITIALIZED','BANK_APPROVAL_PENDING','ACTIVE','ON_HOLD','PAUSED','CUSTOMER_PAUSED',
       'CUSTOMER_CANCELLED','CANCELLED','EXPIRED','LINK_EXPIRED','CARD_EXPIRED','COMPLETED') then
    return jsonb_build_object('status', 'ignored');
  end if;
  if p_event_at is not null and m.last_event_at is not null and p_event_at < m.last_event_at then
    return jsonb_build_object('status', 'stale');
  end if;
  -- A cancelled mandate stays cancelled whatever arrives late.
  if m.status in ('CANCELLED','CUSTOMER_CANCELLED','EXPIRED','COMPLETED','CARD_EXPIRED') and v_status <> m.status then
    return jsonb_build_object('status', 'final');
  end if;
  update public.billing_mandates
     set status = v_status, payment_group = coalesce(nullif(lower(p_payment_group), ''), payment_group),
         last_event_at = greatest(last_event_at, p_event_at), checked_at = now(),
         activated_at = case when v_status = 'ACTIVE' then coalesce(activated_at, now()) else activated_at end,
         ended_at = case when v_status in ('CUSTOMER_CANCELLED','CANCELLED','EXPIRED','LINK_EXPIRED','CARD_EXPIRED','COMPLETED')
                         then coalesce(ended_at, now()) end,
         updated_at = now()
   where id = m.id;
  if v_status = 'ACTIVE' and m.activated_at is null then
    perform public._hyn_billing_mandate_activated(m.id);
  else
    perform public._hyn_billing_refresh(m.subscription_id);
  end if;
  return jsonb_build_object('status', 'applied', 'mandate_status', v_status, 'subscription_id', m.subscription_id);
end $$;

create or replace function public.hyn_billing_svc_mandate_cancel_result(p_mandate uuid, p_ok boolean, p_error text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if p_ok then
    update public.billing_mandates set status = 'CANCELLED', ended_at = coalesce(ended_at, now()), updated_at = now()
     where id = p_mandate and status not in ('CANCELLED','CUSTOMER_CANCELLED','EXPIRED','COMPLETED','CARD_EXPIRED');
  else
    update public.billing_mandates set error = left(p_error, 500), updated_at = now() where id = p_mandate;
  end if;
  return jsonb_build_object('status', 'ok');
end $$;

create or replace function public.hyn_billing_svc_charge_status(
  p_payment_id text, p_status text, p_cf_payment_id text, p_failure text, p_event_at timestamptz)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c public.billing_charges; inv public.billing_invoices; v text := upper(trim(coalesce(p_status, '')));
begin
  select * into c from public.billing_charges where payment_id = p_payment_id for update;
  if c.id is null then return jsonb_build_object('status', 'unknown'); end if;
  if c.status = 'success' then return jsonb_build_object('status', 'final'); end if;
  if v <> 'SUCCESS' and p_event_at is not null and c.last_event_at is not null and p_event_at < c.last_event_at then
    return jsonb_build_object('status', 'stale');
  end if;
  update public.billing_charges set cf_payment_id = coalesce(nullif(p_cf_payment_id, ''), cf_payment_id),
         last_event_at = greatest(last_event_at, p_event_at), updated_at = now()
   where id = c.id;
  if v = 'SUCCESS' then
    update public.billing_charges set status = 'success', failure_reason = null, claimed_at = null where id = c.id;
    select * into inv from public.billing_invoices where id = c.invoice_id for update;
    if inv.status = 'open' then
      perform public._hyn_billing_mark_paid(inv.id, 'cashfree', now());
    else
      -- Debited although the invoice was already settled or voided.
      update public.billing_invoices set needs_refund = true, updated_at = now() where id = inv.id;
      perform public._hyn_audit('billing.payment.duplicate', inv.user_id, null,
        jsonb_build_object('invoice', inv.number, 'payment_id', c.payment_id, 'amount', c.amount));
    end if;
  elsif v = 'FAILED' then
    if c.status <> 'failed' then perform public._hyn_billing_charge_failed(c.id, p_failure, 'failed'); end if;
  elsif v = 'CANCELLED' then
    if c.status = 'cancelling' then
      update public.billing_charges set status = 'cancelled', claimed_at = null where id = c.id;
      perform public._hyn_billing_refresh((select subscription_id from public.billing_invoices where id = c.invoice_id));
    elsif c.status <> 'cancelled' then
      perform public._hyn_billing_charge_failed(c.id, coalesce(p_failure, 'cancelled by the bank or customer'), 'cancelled');
    end if;
  elsif v in ('PENDING','INITIALIZED','ACTIVE','BANK_APPROVAL_PENDING','NOTIFICATION_INITIATED') then
    if c.status = 'raising' then
      update public.billing_charges set status = 'pending', claimed_at = null where id = c.id;
    end if;
  else
    return jsonb_build_object('status', 'ignored');
  end if;
  return jsonb_build_object('status', 'applied');
end $$;

-- p_definite: Cashfree answered and refused the charge (counts as a failed
-- attempt). Otherwise the outcome is unknown and the charge is reconciled later.
create or replace function public.hyn_billing_svc_charge_raised(
  p_charge uuid, p_ok boolean, p_cf_payment_id text, p_status text, p_scheduled_for date, p_error text, p_definite boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c public.billing_charges;
begin
  select * into c from public.billing_charges where id = p_charge for update;
  if c.id is null then return jsonb_build_object('status', 'unknown'); end if;
  -- Stopped while the raise was in flight: keep the reference so the cancel can find it.
  if c.status = 'cancelling' and p_ok then
    update public.billing_charges set cf_payment_id = coalesce(nullif(p_cf_payment_id, ''), cf_payment_id),
           scheduled_for = coalesce(p_scheduled_for, scheduled_for) where id = c.id;
    return jsonb_build_object('status', 'cancelling');
  end if;
  if c.status <> 'raising' then return jsonb_build_object('status', 'unchanged'); end if;
  if p_ok then
    update public.billing_charges set status = 'pending', cf_payment_id = nullif(p_cf_payment_id, ''),
           scheduled_for = p_scheduled_for, claimed_at = null, updated_at = now() where id = c.id;
    if upper(coalesce(p_status, '')) in ('SUCCESS','FAILED','CANCELLED') then
      return public.hyn_billing_svc_charge_status(c.payment_id, p_status, p_cf_payment_id, p_error, null);
    end if;
  elsif p_definite then
    perform public._hyn_billing_charge_failed(c.id, p_error, 'failed');
  else
    update public.billing_charges set failure_reason = left(p_error, 500), updated_at = now() where id = c.id;
  end if;
  return jsonb_build_object('status', 'applied');
end $$;

-- Webhook de-duplication. Returns the event id to process, or null when this
-- exact body was already processed.
create or replace function public.hyn_billing_svc_record_event(p_hash text, p_type text, p_payload jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  insert into public.billing_events (body_sha256, event_type, payload) values (p_hash, left(p_type, 100), p_payload)
  on conflict (body_sha256) do nothing returning id into v_id;
  if v_id is null then
    select id into v_id from public.billing_events where body_sha256 = p_hash and processed_at is null;
  end if;
  return v_id;
end $$;

create or replace function public.hyn_billing_svc_event_done(p_event bigint, p_error text)
returns void language sql security definer set search_path = public as $$
  update public.billing_events
     set processed_at = case when p_error is null then now() end, error = left(p_error, 1000)
   where id = p_event;
$$;

-- One billing run: time-based transitions, renewals, and the Cashfree work the
-- portal must do next. Rows are claimed under SKIP LOCKED, so overlapping runs
-- never hand out the same work; every Cashfree call is idempotent besides.
create or replace function public.hyn_billing_svc_tick(p_sub uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; inv public.billing_invoices; m public.billing_mandates; c public.billing_charges;
  v_raise jsonb := '[]'::jsonb; v_cancel_charges jsonb := '[]'::jsonb; v_check_charges jsonb := '[]'::jsonb;
  v_cancel_mandates jsonb := '[]'::jsonb; v_check_mandates jsonb := '[]'::jsonb;
begin
  -- One run at a time: a full run and a single-subscription run lock rows in
  -- different orders.
  perform pg_advisory_xact_lock(74821977);
  update public.billing_mandates set status = 'FAILED', error = coalesce(error, 'never created at Cashfree'),
         ended_at = now(), updated_at = now()
   where status = 'CREATING' and created_at < now() - interval '15 minutes' and (p_sub is null or subscription_id = p_sub);

  for r in select s.id from public.billing_subscriptions s
            where s.status <> 'canceled' and (p_sub is null or s.id = p_sub)
            order by s.id for update skip locked loop
    perform public._hyn_billing_advance(r.id);
  end loop;

  -- Invoices to void once nothing for them is in flight at Cashfree.
  for inv in select * from public.billing_invoices
              where status = 'open' and void_pending_reason is not null and (p_sub is null or subscription_id = p_sub)
              for update skip locked loop
    update public.billing_charges set status = 'cancelling', claimed_at = null, updated_at = now()
     where invoice_id = inv.id and status = 'pending';
    if not exists(select 1 from public.billing_charges where invoice_id = inv.id and status in ('raising','pending','cancelling')) then
      perform public._hyn_billing_void_invoice(inv.id, inv.void_pending_reason);
    end if;
  end loop;

  -- Charges to raise.
  for inv in select i.* from public.billing_invoices i
               join public.billing_subscriptions s on s.id = i.subscription_id
               join public.profiles p on p.id = i.user_id
              where i.status = 'open' and s.collection = 'auto' and s.status <> 'canceled' and i.total > 0
                and i.void_pending_reason is null and i.next_attempt_at <= now() and p.status = 'active'
                and not exists(select 1 from public.billing_charges x where x.invoice_id = i.id
                                and x.status in ('raising','pending','cancelling'))
                and (p_sub is null or i.subscription_id = p_sub)
              order by i.next_attempt_at limit 100 for update of i skip locked loop
    select m2.* into m from public.billing_mandates m2 join public.billing_subscriptions s2 on s2.current_mandate_id = m2.id
     where s2.id = inv.subscription_id and m2.status in ('ACTIVE','ON_HOLD');
    if m.id is null then
      update public.billing_invoices set blocked_reason = 'no_mandate', next_attempt_at = null, updated_at = now() where id = inv.id;
    elsif inv.total > m.max_amount then
      update public.billing_invoices set blocked_reason = 'exceeds_mandate_limit', next_attempt_at = null, updated_at = now() where id = inv.id;
    else
      insert into public.billing_charges (invoice_id, mandate_id, payment_id, attempt, amount, status, claimed_at)
      values (inv.id, m.id, inv.number || '-' || (inv.attempts + 1) || '-' || substr(md5(gen_random_uuid()::text), 1, 6),
              inv.attempts + 1, inv.total, 'raising', now())
      returning * into c;
      update public.billing_invoices set attempts = attempts + 1, next_attempt_at = null, blocked_reason = null, updated_at = now()
       where id = inv.id;
      v_raise := v_raise || jsonb_build_array(jsonb_build_object('charge_id', c.id, 'payment_id', c.payment_id,
        'cf_subscription_id', m.cf_subscription_id, 'amount', c.amount, 'due_at', inv.due_at,
        'payment_group', m.payment_group, 'invoice', inv.number));
    end if;
    perform public._hyn_billing_refresh(inv.subscription_id);
  end loop;

  for c in select x.* from public.billing_charges x join public.billing_invoices i on i.id = x.invoice_id
            where x.status = 'cancelling' and x.updated_at < now() - interval '2 minutes'
              and (x.claimed_at is null or x.claimed_at < now() - interval '30 minutes')
              and (p_sub is null or i.subscription_id = p_sub)
            limit 100 for update of x skip locked loop
    update public.billing_charges set claimed_at = now() where id = c.id;
    v_cancel_charges := v_cancel_charges || jsonb_build_array(jsonb_build_object('charge_id', c.id, 'payment_id', c.payment_id,
      'cf_subscription_id', (select cf_subscription_id from public.billing_mandates where id = c.mandate_id)));
  end loop;

  -- Outcomes that should have arrived by webhook but did not.
  for c in select x.* from public.billing_charges x join public.billing_invoices i on i.id = x.invoice_id
            where ((x.status = 'raising' and x.claimed_at < now() - interval '10 minutes')
                   or (x.status = 'pending' and coalesce(x.claimed_at, x.created_at) < now() - interval '6 hours'
                       and coalesce(x.scheduled_for, (now() at time zone 'Asia/Kolkata')::date) <= (now() at time zone 'Asia/Kolkata')::date))
              and (p_sub is null or i.subscription_id = p_sub)
            limit 100 for update of x skip locked loop
    update public.billing_charges set claimed_at = now() where id = c.id;
    v_check_charges := v_check_charges || jsonb_build_array(jsonb_build_object('charge_id', c.id, 'payment_id', c.payment_id,
      'status', c.status, 'amount', c.amount,
      'cf_subscription_id', (select cf_subscription_id from public.billing_mandates where id = c.mandate_id),
      'due_at', (select due_at from public.billing_invoices where id = c.invoice_id),
      'payment_group', (select payment_group from public.billing_mandates where id = c.mandate_id),
      'invoice', (select number from public.billing_invoices where id = c.invoice_id)));
  end loop;

  -- Mandates nobody should be able to charge any more.
  for m in select m2.* from public.billing_mandates m2 join public.billing_subscriptions s on s.id = m2.subscription_id
            where m2.status in ('INITIALIZED','BANK_APPROVAL_PENDING','ACTIVE','ON_HOLD','PAUSED','CUSTOMER_PAUSED')
              and (s.status = 'canceled'
                   or (m2.status in ('ACTIVE','ON_HOLD','PAUSED','CUSTOMER_PAUSED')
                       and (s.collection = 'manual' or s.current_mandate_id is distinct from m2.id))
                   or (m2.status = 'INITIALIZED' and m2.created_at < now() - interval '2 days')
                   or (m2.status in ('INITIALIZED','BANK_APPROVAL_PENDING') and exists(select 1 from public.billing_mandates n
                         where n.subscription_id = m2.subscription_id and n.created_at > m2.created_at and n.status <> 'FAILED')))
              and not exists(select 1 from public.billing_charges x where x.mandate_id = m2.id
                              and x.status in ('raising','pending','cancelling'))
              and (m2.cancel_claimed_at is null or m2.cancel_claimed_at < now() - interval '1 hour')
              and (p_sub is null or m2.subscription_id = p_sub)
            limit 100 for update of m2 skip locked loop
    update public.billing_mandates set cancel_claimed_at = now() where id = m.id;
    v_cancel_mandates := v_cancel_mandates || jsonb_build_array(jsonb_build_object('mandate_id', m.id,
      'cf_subscription_id', m.cf_subscription_id));
  end loop;

  -- Mandates whose status may have changed without a webhook reaching us.
  for m in select m2.* from public.billing_mandates m2 join public.billing_subscriptions s on s.id = m2.subscription_id
            where ((m2.status in ('INITIALIZED','BANK_APPROVAL_PENDING') and m2.created_at > now() - interval '35 days'
                    and coalesce(m2.checked_at, m2.created_at) < now() - interval '20 minutes')
                   or (m2.status in ('ACTIVE','ON_HOLD') and s.current_mandate_id = m2.id
                       and coalesce(m2.checked_at, m2.created_at) < now() - interval '1 day'))
              and (p_sub is null or m2.subscription_id = p_sub)
            limit 200 for update of m2 skip locked loop
    update public.billing_mandates set checked_at = now() where id = m.id;
    v_check_mandates := v_check_mandates || jsonb_build_array(jsonb_build_object('mandate_id', m.id,
      'cf_subscription_id', m.cf_subscription_id));
  end loop;

  delete from public.billing_events where received_at < now() - interval '90 days';
  if p_sub is null then perform public._hyn_billing_sync_access(null); end if;
  return jsonb_build_object('raise', v_raise, 'cancel_charges', v_cancel_charges, 'check_charges', v_check_charges,
    'cancel_mandates', v_cancel_mandates, 'check_mandates', v_check_mandates);
end $$;

-- ===========================================================================
-- the database job: holds follow access to the minute
-- ===========================================================================
create or replace function public._hyn_schedule_jobs()
returns text language plpgsql set search_path = public as $$
declare r record; n integer := 0;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    return 'pg_cron is not installed: no database jobs scheduled';
  end if;
  for r in select * from (values
    ('hyn-telemetry-retention', '*/5 * * * *', 'select public.hyn_prune_telemetry(5000)'),
    ('hyn-delivery-retention', '17 * * * *', 'select public._hyn_prune_delivery_history(5000)'),
    ('hyn-outage-sweep', '* * * * *', 'select public._hyn_outage_sweep()'),
    ('hyn-billing-access', '* * * * *', 'select public._hyn_billing_sync_access(null)')
  ) j(name, schedule, command) loop
    perform cron.schedule(r.name, r.schedule, r.command);
    n := n + 1;
  end loop;
  return format('pg_cron jobs scheduled: %s', n);
end $$;
revoke all on function public._hyn_schedule_jobs() from public, anon, authenticated;
do $$ begin raise notice '%', public._hyn_schedule_jobs(); end $$;

-- ===========================================================================
-- privileges
-- ===========================================================================
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like '\_hyn\_billing\_%' or p.proname like 'hyn\_billing\_%'
                  or p.proname like 'hyn\_admin\_billing\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
  if exists(select 1 from pg_roles where rolname = 'service_role') then
    for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname like 'hyn\_billing\_svc\_%' loop
      execute format('grant execute on function %s to service_role', r.sig);
    end loop;
  end if;
end $$;

grant execute on function public.hyn_billing_summary() to authenticated;
grant execute on function public.hyn_billing_preview(integer, text) to authenticated;
grant execute on function public.hyn_billing_begin_checkout(integer, text, text) to authenticated;
grant execute on function public.hyn_billing_set_quantity(integer) to authenticated;
grant execute on function public.hyn_billing_apply_coupon(text) to authenticated;
grant execute on function public.hyn_billing_cancel() to authenticated;
grant execute on function public.hyn_billing_resume() to authenticated;
grant execute on function public.hyn_billing_retry_payment() to authenticated;
grant execute on function public.hyn_admin_billing_dashboard(text, text, integer) to authenticated;
grant execute on function public.hyn_admin_billing_user(uuid) to authenticated;
grant execute on function public.hyn_admin_billing_save_settings(jsonb) to authenticated;
grant execute on function public.hyn_admin_billing_launch(integer) to authenticated;
grant execute on function public.hyn_admin_billing_set_enforce(boolean) to authenticated;
grant execute on function public.hyn_admin_billing_assign(uuid, integer, bigint, integer, text, boolean, text, text, text) to authenticated;
grant execute on function public.hyn_admin_billing_record_payment(uuid, bigint, text, text, text, timestamptz) to authenticated;
grant execute on function public.hyn_admin_billing_void_invoice(uuid, text) to authenticated;
grant execute on function public.hyn_admin_billing_set_quantity(uuid, integer) to authenticated;
grant execute on function public.hyn_admin_billing_cancel(uuid, boolean, text) to authenticated;
grant execute on function public.hyn_admin_billing_add_discount(uuid, text, text, text, integer, bigint, integer, timestamptz) to authenticated;
grant execute on function public.hyn_admin_billing_remove_discount(uuid) to authenticated;
grant execute on function public.hyn_admin_billing_save_coupon(jsonb) to authenticated;
grant execute on function public.hyn_admin_billing_set_coupon_active(uuid, boolean) to authenticated;
grant execute on function public.hyn_admin_billing_resolve_refund(uuid, text) to authenticated;

notify pgrst, 'reload schema';
commit;
