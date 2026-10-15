# Subscription billing (Cashfree, per server, monthly)

Status: implemented in `supabase/migrations/20261006120000_subscription_billing.sql`
and the web portal (`/billing`, `/admin/billing`, `/api/billing/*`,
`/api/cron/billing`). Web only: the CLI is unchanged.

## What is sold

One price per server per month (`billing_settings.price_per_server`, paise,
GST inclusive). A subscription buys **server slots** (`quantity`). Billing is in
advance, monthly, anchored to the day the first paid period started (a 31st
anchor renews on the last day of shorter months).

Every amount is an integer number of paise. Rupees appear only at the Cashfree
boundary.

## Who needs a subscription

`billing_settings.enforce` is off until a super admin launches billing, so the
migration changes nothing on its own.

With enforcement on, a server is **entitled** when:

- it is a demo server, or
- its owner is Maintainer, Admin or Super admin (staff are exempt), or
- its owner has a subscription with access (`access_ends_at > now()`) and the
  server is among the owner's oldest `quantity` non-revoked servers.

What happens without entitlement:

- **Linking**: a new server is refused when the owner has no access or every
  slot is in use (trigger on `nodes` insert, so every linking path is covered).
- **Monitoring**: the server is put on a *billing hold*: `status='suspended'`,
  `status_reason='Billing: …'`, `billing_hold=true`. Ingest, bandwidth, alert
  queueing and live snapshots already refuse a suspended server, and the agent
  already prints the reason and retries every interval, so it resumes by itself
  once entitlement returns. The outage sweep ignores suspended servers, so a
  lapsed account gets no offline emails.
- **Dashboard**: existing data stays readable (read only); nothing new arrives.

Holds are applied and lifted by `_hyn_billing_sync_access()`: immediately by
every billing change, every minute by pg_cron, and on every billing cron run.
A hold is lifted only while `status_reason` still carries the billing prefix,
so an administrator's own suspension is never undone by billing.

## Subscription states

| Status | Meaning | Access |
| --- | --- | --- |
| `incomplete` | Checkout started, autopay not yet authorised | none |
| `trialing` | Free period (new-user trial or legacy grace) | until `trial_ends_at` |
| `active` | Paid, or first charge in flight | until `access_ends_at` |
| `past_due` | A charge failed or is overdue, within the grace window | until due + `grace_days` |
| `unpaid` | Grace ran out | none; paying restores it |
| `canceled` | Ended | none |

`access_ends_at` is the single source of truth for access and is time based,
so access ends on time even if no job runs:

- paid period: `access_ends_at = paid_through`
- open invoice (renewal, first charge, manual): `greatest(paid_through, due_at + grace_days)`
- trial: `trial_ends_at` (plus grace once the trial-end invoice is open)

## Autopay (Cashfree on-demand mandate)

1. `/billing`: the user picks slots, an optional coupon and a phone number
   (Cashfree requires it).
2. `POST /api/billing/checkout`: `hyn_billing_begin_checkout` creates the
   subscription (`incomplete`) and a mandate row, then the server creates a
   Cashfree `ON_DEMAND` subscription with:
   - a refundable verification amount (`auth_amount`, default ₹2; eNACH is
     always ₹0)
   - `plan_max_amount = greatest(mandate_max_amount, 2 × monthly subtotal)`
   - payment methods: UPI, card and eNACH, **except** when `plan_max_amount`
     is above ₹15,000: UPI AutoPay and Indian cards then need the customer to
     approve every debit (AFA), which cannot work for unattended renewals, so
     only eNACH is offered.
3. The browser opens Cashfree checkout (JS SDK v3, `subscriptionsCheckout`).
4. Cashfree form-POSTs to `/api/billing/return`, which fetches the real status
   from Cashfree (never trusting the redirect) and applies it. Webhooks report
   the same status independently, and the cron reconciles anything stuck.
5. When the mandate becomes ACTIVE:
   - new subscriber with `trial_days > 0`: becomes `trialing`
   - new subscriber without a trial: the first invoice is finalised at once and
     the subscription becomes `active` with *provisional* access while the
     first charge is in flight. If that charge fails, the normal retry and grace
     rules apply, and access ends at due + grace.
   - existing subscriber (replacement method, legacy user, manual plan
     switching to autopay): the mandate becomes current, the old one is
     cancelled at Cashfree, and an unpaid open invoice gets a fresh attempt.

### Charging rules (Cashfree constraints)

- An on-demand charge must be scheduled 1–14 days ahead. Indian cards need 2
  days; UPI needs 2 days when raised at or after 20:00 IST. Cashfree sends the
  pre-debit notification (at least 24 h before) and the amount cannot change
  after it.
- So renewal invoices are **finalised `renewal_lead_days` (default 3) before
  the period ends**, with amount and discounts frozen. The charge is scheduled
  for the IST date the period ends, never earlier than the earliest allowed date.
- Each attempt is a new Cashfree payment (`payment_id = <invoice>-<attempt>`,
  also used as the idempotency key), so double raising is impossible.
- Failed attempts retry automatically every `retry_interval_days` (2) up to
  `max_auto_attempts` (4 = first + 3 retries). UPI additionally retries hourly
  inside Cashfree. The user can trigger more attempts ("Retry payment"), and
  only one attempt is ever in flight per invoice.
- If an invoice is larger than the mandate limit it is not charged; the user is
  asked to authorise autopay again with a higher limit.
- A charge whose invoice has meanwhile been settled manually, voided or
  cancelled is cancelled at Cashfree. If Cashfree has already debited it, the
  payment is recorded and the invoice is flagged `needs_refund` for an admin.

## Discounts

Two kinds, at most one of each active on a subscription:

| Kind | Applies to | Ends |
| --- | --- | --- |
| `first_month` | Only the subscription's first paid billing cycle (`cycle_number = 1`). Trials and legacy grace are not cycles. | When that invoice is finalised. It can be added only before the first invoice is finalised, and only once per account across all subscriptions. |
| `ongoing` | Every finalised invoice | After `duration_months` invoices (null = forever) or once a period starts on/after `ends_at`, whichever is first. Ends with the subscription. |

How a discount is calculated:

1. `subtotal = quantity × unit_price + pending adjustments` (prorations).
2. The ongoing discount is applied to the subtotal.
3. The first-month discount is applied to what remains.
4. Percentages round half up to the paise. A fixed amount is capped at what
   remains. A total can never be negative.
5. A total below ₹1 is not charged (Cashfree's minimum), so the invoice is free.

What happens over a discount's life:

- **Snapshot**: a discount's terms are copied when it is applied, so editing or
  deactivating a coupon later never changes an existing customer's discount.
- **Consumption**: a cycle is consumed when the invoice is finalised. If that
  invoice is voided unpaid, the cycle is given back.
- **Coupon codes**: a code needs to be active, before `redeem_by`, under
  `max_redemptions`, and not already used by that account. Admins can also
  attach a discount with no code.

## Changing the number of servers

- **Increase**: takes effect immediately. During a paid period the prorated
  difference (`added slots × unit_price × remaining / period length`) is added
  to the next invoice. Trials and unpaid first periods are not prorated.
- **Decrease**: takes effect at the next renewal and is refused while more
  servers are linked than the new number. Nothing is refunded.

## Cancellation

- **User**: cancels at the period end, and access continues until then.
  - An already-finalised renewal invoice is cancelled at Cashfree and voided.
    If the debit is already processing and cannot be stopped, the payment is
    honoured and the plan ends after the period it paid for.
  - A user can resume any time before the end.
  - Cancelling while `incomplete`, `past_due` or `unpaid` ends the plan at once
    and voids the open invoice, since nothing was paid for the remaining time.
- **At the period end**: the status becomes `canceled` and the Cashfree mandate
  is cancelled, so no further debit is possible.
- **Customer cancels or pauses the mandate in their bank or UPI app**: the plan
  continues to the period end. The next renewal cannot be charged, so the
  normal grace rules apply. The billing page asks for autopay again.
- **Admin**: can end a plan at the period end or immediately (optionally
  voiding the open invoice). Refunds are made by hand in the Cashfree
  dashboard.

## Late payment

- An invoice that stays unpaid past due + grace leaves the subscription
  `unpaid` (no access). The invoice stays open, so retrying, new autopay or a
  manual settlement restores it.
- A payment that arrives after access had already ended starts a fresh period
  at the payment time, so nobody pays for time they could not use.
- The same rule applies when a renewal invoice is created after the paid period
  already ended (for example, a lapsed manual plan).
- After `unpaid_cancel_days` (30) the subscription is cancelled, its open
  invoice is voided and its mandate is cancelled.

## Manual billing (admin)

Super admins, at `/admin/billing`:

- **Assign** a plan to any user: slots, price per server (0 = complimentary),
  1–36 months, and collection `manual` or `auto`. They can record the payment
  in the same step (cash, bank transfer, direct UPI, cheque or other, with a
  reference). Switching to manual cancels the user's mandate.
- **Record payment** against any open invoice. The amount must equal the
  invoice total (apply a discount first to settle for less). Any in-flight
  Cashfree charge for that invoice is cancelled.
- **Manual renewals**: an open invoice is created `renewal_lead_days` before
  the period ends, with no charge. Normal grace follows. The user may switch to
  autopay from `/billing` at any time, which charges the open invoice.
- Also: coupons (create and deactivate), discounts on a user, slot changes,
  cancellation, settings, and launch.

Admins (not super) can read the billing dashboard. Every billing write is
recorded in `admin_audit`.

## Launch and existing users

`hyn_admin_billing_launch(grace_days)` turns enforcement on and gives every
non-staff account that already owns servers a **legacy trial**:

- slots = its current server count, at the current price
- `trialing` until now + grace

These users keep full access and are asked to set up autopay (the ₹2
verification). Their first charge is at the end of the trial. Without autopay
by then, the normal grace rules apply.

## Webhooks and reconciliation

- `POST /api/billing/webhook` verifies `x-webhook-signature` =
  Base64(HMAC-SHA256(`x-webhook-timestamp` + raw body, client secret)) with a
  constant-time compare.
- Events are de-duplicated by body hash. Statuses only move forward: a SUCCESS
  is final and a later FAILED is ignored, and an older mandate event never
  overwrites a newer one.
- `GET /api/cron/billing` (Bearer `CRON_SECRET`, every 10 minutes from
  `server02`) moves time-based states, finalises invoices, raises, cancels and
  reconciles charges and mandates against the Cashfree API, and syncs access.
  Work is claimed under row locks, so overlapping runs are safe.

## Not included

- GST invoices / tax lines (prices are GST inclusive).
- Billing emails: Cashfree sends the pre-debit and payment notices (email and
  SMS), and the portal shows banners. The portal's email gate refuses new
  automatic kinds by design.
- Automatic refunds (flagged for an admin instead).
- Annual plans or currencies other than INR.

## Deploying

1. Apply `supabase/migrations/20261006120000_subscription_billing.sql` (also part
   of `supabase/schema.sql`). Enforcement starts off, so nobody's access changes.
2. Set `CASHFREE_CLIENT_ID`, `CASHFREE_CLIENT_SECRET` and `CASHFREE_ENV` on the
   portal, then deploy it. The release gate refuses a portal whose billing
   functions are missing from the database.
3. In Cashfree, register `https://www.hyn-view.in/api/billing/webhook` for the
   Subscriptions events.
4. Add the billing run to `/etc/cron.d/hyn-view` on `server02`, next to the email
   worker:
   `*/10 * * * * root curl -fsS -H "Authorization: Bearer $CRON_SECRET" https://www.hyn-view.in/api/cron/billing >/dev/null`
5. Test one checkout end to end in the sandbox, then switch `CASHFREE_ENV` to
   `production`.
6. A super admin sets the price at `/admin/billing` and launches billing with the
   legacy free period for existing customers.
