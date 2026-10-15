# Billing: $150 price display, and Full or Split payment

Status: design, awaiting review. Extends
`2026-10-06-subscription-billing-design.md`; nothing here replaces it except
where a section says so. Web portal and database only; the CLI is unchanged.

## What the owner asked for

1. The price per server per month becomes **$150**.
2. The customer chooses how to pay each month:
   - **Full**: 100% on the 1st.
   - **Split**: 50% on the 1st and 50% on the 25th.
3. Both are autopay subscriptions. Everything else in billing (coupons,
   trials, grace, retries, cancellation, admin tools) keeps working.
4. The Cashfree integration and its documentation are checked and correct.

## Decisions taken

| Question | Decision |
| --- | --- |
| Currency | Show **$150**. Charge a **fixed INR amount an admin sets** (`price_per_server`, paise). Cashfree only ever sees INR, so UPI, cards and eNACH keep working. |
| Billing calendar | **Calendar months for both modes**, in IST. |
| Joining mid-month | The first period runs from now to the next boundary and is **prorated by time**. |
| Existing subscriptions | Unchanged: they keep their price and renewal day. |

Assumption to confirm: billing has not launched with paying customers. If it
has, the migration still changes nothing for them (see Compatibility).

## Why not charge in USD

Verified in Cashfree's documentation (links at the end):

- Plans accept `plan_currency` other than INR, including USD.
- A non-INR subscription can only be authorised with an **international
  Visa or Mastercard**. UPI AutoPay and eNACH are INR-only.
- Cashfree states that **Indian-issued cards paying in a foreign currency are
  not supported for subscriptions**.

So USD billing would lock out every Indian customer. Showing USD and charging
a fixed INR amount avoids that. The cost is that the INR amount is a number an
admin keeps in step with the exchange rate by hand; there is no live rate.

## Price

`billing_settings` gains `display_price_usd_cents integer` (default 15000,
shown as `$150`). `price_per_server` stays the amount charged, in paise. Its
default for a fresh database becomes 1,250,000 (₹12,500, a placeholder: the
owner sets the real figure at `/admin/billing`).

Rules:

- The portal shows `$150 / server / month` and, beside it, what is charged:
  "Billed in INR: ₹12,500 per server per month".
- Invoices, receipts and the payment page show INR only. USD is never an
  amount on any invoice.
- A subscription snapshots `unit_price` when it is created, as today, so a
  later price change affects new subscriptions only.

## Pay modes and the calendar

`billing_subscriptions` gains:

- `pay_mode` `'full' | 'split'` (default `'full'`).
- `pending_pay_mode` `'full' | 'split' | null`: a switch the customer has
  asked for, applied when the next period starts on the 1st.
- `calendar` `'calendar' | 'anchor'`. New rows default to `'calendar'`; the
  migration sets every existing row to `'anchor'`, which keeps the current
  renewal-day behaviour exactly.

All times are IST. A **boundary** is 00:00 IST on the 1st or the 25th.

| Mode | Periods in a month | Each pays |
| --- | --- | --- |
| Full | 1st to next 1st | 100% |
| Split | 1st to 25th, then 25th to next 1st | 50% each |

The 25th boundary exists only for Split. The second Split period is 6 or 7
days long (3 or 4 in February) but costs the same 50%. That is what "50% at the
start, 50% at month end" means here, and it has a consequence the owner should
know: a Split customer who cancels at the period end after paying the first
half has paid 50% for 24 days of access. See Open points.

A single function, `_hyn_billing_next_boundary(ts, pay_mode)`, returns the end
of the period that starts at `ts`: the next 25th (Split, if before the 25th) or
the next 1st. It is the only place the calendar is encoded.

### Invoice periods

The existing engine already issues one open invoice at a time, charges it on
its due date, and moves `paid_through` forward when it is paid. Each Split
installment is therefore **its own invoice and its own period**:

- Full month, Full: one invoice, period 1st to 1st.
- Full month, Split: installment 1 (1st to 25th) and installment 2 (25th to
  1st).
- A renewal invoice is finalised `renewal_lead_days` (3) before its period
  starts, so Cashfree's pre-debit notice is sent in time and the debit lands on
  the boundary date. Installment 2 is therefore raised around the 22nd, and the
  next 1st invoice around the 28th to 30th.

`billing_invoices` gains `installment smallint`, `installments smallint` (1 of
1, 1 of 2, 2 of 2) and `share_bps integer` (the share of one month's price the
period stands for before proration: 10000 for Full, 5000 for a Split half).
Existing invoices default to 1 of 1 and 10000.

### Joining mid-month, late starts, trial ends

Every period that starts off a boundary is a **stub**: it ends at the next
boundary and is prorated by time.

```
subtotal = round(quantity x unit_price x share_bps/10000 x (end - start) / (window_end - window_start))
```

`window` is the calendar period that contains `start`. At a boundary the ratio
is 1. This one rule covers a first charge, the first paid period after a trial,
and a renewal that starts late because the customer paid late.

Examples with ₹12,500 per server, one server:

| Joins | Mode | First charge | Covers |
| --- | --- | --- | --- |
| 1st | Full | ₹12,500 | 1st to next 1st |
| 12th (30-day month) | Full | 19 of 30 days = ₹7,917 | 12th to next 1st |
| 12th | Split | 50% x 13 of 24 days = ₹3,385 | 12th to 25th |
| 27th | Split | 50% x 4 of 6 days (June) = ₹4,167 | 27th to next 1st |

A subtotal that rounds below ₹1 is not charged, as today.

## Pricing a Split month

Rules, so that the two halves always add up and discounts stay fair:

1. A Split half is `quantity x unit_price x 50%`. Where an amount does not
   divide evenly, the **second half takes the extra paisa**, so the two halves
   sum to the monthly price.
2. A **percentage** discount applies to every invoice of the month.
3. A **fixed-amount** discount applies in full to the first invoice of the
   month it covers, capped at what that invoice costs.
4. A coupon **cycle is one calendar month**, spent when the month's first
   invoice is finalised. The second installment applies the same percentage
   discounts without spending another cycle. If the first invoice is voided
   unpaid the cycle is given back; voiding only the second gives nothing back.
5. Pending adjustments (see below) are never split: they ride on whichever
   invoice is finalised next.
6. `cycle_number` becomes the **month ordinal** rather than an invoice count:
   both installments of a month carry the same number. This is what makes a
   `first_month` discount (which applies to cycle 1) reach both halves of a
   Split first month, and keeps `duration_months` counting months. A stub
   period counts as its month.

## Changing quantity or mode

- **More servers**: immediate, as today. The prorated difference for the
  remaining time of every invoice that still covers future time is added to the
  next invoice. The proration uses each invoice's own `share_bps`, so a Split
  half is prorated against 50%, not 100%.
- **Fewer servers**: at the next renewal, unchanged.
- **Switching Full and Split**: recorded as `pending_pay_mode` and applied to
  the period that starts on the next 1st, never mid-month. Nothing is refunded
  or re-billed. The customer sees the change and its effective date.
- If a switch to a larger single debit would exceed the autopay limit, the
  existing "above your limit, set up autopay again" path asks for fresh
  authorisation, and the screen warns before the switch is confirmed.

## Late payment, grace, cancellation

Unchanged in principle, with these calendar-specific points:

- Access still comes from `access_ends_at`; grace, retries and the
  unpaid-to-cancelled rule apply per invoice. A missed **second** installment
  ends access at the 25th plus grace; a missed first one, at the 1st plus
  grace.
- A payment after access had fully lapsed starts a period at the payment time
  and keeps the invoice's original length. The next renewal then starts
  off-boundary and realigns to the calendar through a prorated stub, so the
  schedule repairs itself.
- Cancel at period end ends access after the period already paid for. For
  Split that can be the 25th.
- `anchor` subscriptions, and admin `manual` invoices of 1 to 36 months, keep
  using `_hyn_billing_add_months`; they are not split. After a manual invoice
  ends, a `calendar` subscription's next renewal is a prorated stub.

## Autopay mandate sizing

The mandate (`ON_DEMAND`) limit is currently
`greatest(mandate_max_amount, 2 x monthly subtotal)`. At ₹12,500 that is
₹25,000 for one server, which is above ₹15,000, the point where UPI AutoPay and
cards ask the customer to approve **every** charge, which cannot work for
unattended debits. Every plan would silently become eNACH-only.

New rule: `max_amount = greatest(mandate_max_amount, ceil(1.10 x largest single
debit the chosen mode can produce))`, and `mandate_max_amount` defaults to
₹14,999 (not ₹15,000, because Cashfree says these methods are disabled "at
₹15,000 and above"). The existing check that sends mandates above the limit to
eNACH is changed from `>` to `>=` accordingly.

Effect, at ₹12,500 per server:

| Plan | Largest debit | Methods offered |
| --- | --- | --- |
| 1 server, Full | ₹12,500 | UPI, card, eNACH |
| 2 servers, Full | ₹25,000 | eNACH |
| 2 servers, Split | ₹12,500 | UPI, card, eNACH |
| 3 servers, Split | ₹18,750 | eNACH |

This is a real benefit of Split and the checkout says so.

## Cashfree

- Flow is unchanged: create an `ON_DEMAND` mandate, then raise each charge with
  `POST /pg/subscriptions/pay`, scheduled 1 to 14 days ahead. The existing
  `chargeScheduleDate` already picks the boundary's IST date, never earlier
  than Cashfree allows (2 days for cards and eNACH, 1 for UPI before 20:00).
- API version stays `2025-01-01`. Cashfree lists `2026-01-01` (v6) as latest and
  `2025-01-01` as still supported. Moving versions changes payload and webhook
  shapes and is a separate change with its own sandbox run.
- Cashfree's MCP server covers Payment Gateway, Payouts and SecureID and
  **exposes no Subscriptions tools**, so it cannot be used for this work.
  Behaviour is taken from the REST documentation instead.
- GST: prices remain GST-inclusive, as before. A USD display does not change
  that.

## Interface

**`/billing` plan chooser** (and the pricing card):

- Price block: `$150 / server / month`, with "Billed in INR: ₹12,500".
- A two-option control: **Pay in full on the 1st** and **Split: 50% on the 1st,
  50% on the 25th**. The live total and the **dated schedule** update with the
  server count, coupon and mode, for example (Split, joining on the 12th, one
  server) "Today ₹3,385 · 25 Jun ₹6,250 · 1 Jul ₹6,250".
- A note when the choice decides which payment methods are available.

**Billing page**: shows the pay mode, the next two debit dates and amounts, and
a "Switch to Split / Full" action with its effective date. Invoice rows say
"Installment 1 of 2" where relevant.

**`/admin/billing`**: settings gain the USD display price and keep the INR
charge; the assign form gains a pay mode; invoices show their installment.

## Compatibility and migration

One additive migration, `20261015120000_billing_pay_modes.sql`, also folded into
`supabase/schema.sql`:

- New columns only, plus `_hyn_billing_next_boundary` and replacements of the
  functions listed under Code.
- Every existing subscription is set to `calendar = 'anchor'`,
  `pay_mode = 'full'`, so its next renewal is computed exactly as before.
- `price_per_server` and `mandate_max_amount` are updated only where they still
  hold the old untouched defaults (9900 and 1500000), so an admin's own values
  are never overwritten.
- Safe to run twice.

## Code that changes

Database: `_hyn_billing_next_boundary` (new), `_hyn_billing_price`,
`_hyn_billing_create_invoice`, `_hyn_billing_advance`, `_hyn_billing_mark_paid`,
`_hyn_billing_summary_json`, `hyn_billing_preview`, `hyn_billing_begin_checkout`,
`hyn_billing_set_quantity`, `hyn_billing_set_pay_mode` (new),
`hyn_admin_billing_save_settings`, `hyn_admin_billing_assign`,
`hyn_admin_billing_launch`.

Portal: `lib/billing.ts` (types and schedule helpers), `lib/cashfree.ts`
(mandate limit rule), `app/billing/actions.ts`, `components/billing/billing-panel.tsx`,
`components/billing/plan-features.tsx`, `components/admin/billing-admin.tsx`,
`app/terms/page.tsx` if it states a price.

## Documentation to update

- `2026-10-06-subscription-billing-design.md`: "What is sold", the invoice and
  charging sections, and "Not included" (currency).
- The portal README billing section and deploy steps (new settings, the INR
  amount to set before launch).
- The Terms page, if it names a price or a billing day.
- The in-app copy.

## Testing

- **Database** (`supabase/billing-test.sql`): boundaries across month ends and
  February; the halves summing to the month; stubs on each window; discounts
  (percentage on both halves, fixed on the first, cycle spent once, give-back);
  proration against `share_bps`; switching applied on the next 1st only;
  late-payment realignment; `anchor` subscriptions behaving exactly as before.
- **Portal** (`lib/*.test.ts`, `tests/*`): schedule helper, mandate limit and
  methods at the ₹15,000 boundary, the plan chooser and schedule preview.
- **Sandbox end to end**: one checkout in each mode against Cashfree's sandbox
  (Cashfree credentials are needed; I cannot do this without them).
- The existing test suites must still pass.

## Open points

1. **Split economics.** The second installment buys 6 to 7 days of access for
   50% of the month's price, and a customer who stops at the 25th has paid 50%
   for 24 days. If the owner wants the second half to be owed for the whole
   month, or wants the first half to cover the whole month's access, the model
   changes to a single invoice with two charges, which is the riskier design
   that was rejected.
2. **The INR amount** for $150 must be set by the owner before launch.
3. **Cashfree sandbox**: eNACH and UPI limits (`>= ₹15,000`) should be
   confirmed on a real sandbox mandate.

## Sources (Cashfree)

- Subscription payment methods and limits:
  https://www.cashfree.com/docs/payments/subscription/payment-modes
- Subscriptions FAQ: https://www.cashfree.com/docs/payments/subscription/faq
- Create a plan (`plan_currency`):
  https://www.cashfree.com/docs/api-reference/payments/latest/subscription/create-a-plan
- International payments, foreign-currency cards not supported for
  subscriptions: https://www.cashfree.com/docs/payments/international-payments/ipg/overview
- API versions and endpoints:
  https://www.cashfree.com/docs/api-reference/payments/latest/subscription/endpoints
- MCP server tools: https://www.cashfree.com/docs/tools-ai/mcp-server
