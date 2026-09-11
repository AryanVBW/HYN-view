# Delivery operations

Open `/admin/deliveries`. Active admins can inspect delivery history; active super admins can change policies, schedules, and stop retries. SQL/RLS enforce this boundary independently of the UI.

## Release order

1. Apply `20260911150000_delivery_controls.sql` to the linked HYN Supabase project after the database suites pass.
2. Deploy the matching portal commit. The release gate requires the new RPCs and the service-role environment variable.
3. The GitHub deployment workflow enables `HYN_DELIVERY_CONTROLS_ENABLED=true` after deploying that commit. The existing Resend key, sender, Supabase URL, and service-role key are required. Never expose these keys in the browser.
4. Inspect the dashboard and run read-only release probes. Do not send a production email merely to verify deployment.

The migration leaves combined daily emails unconfigured and disabled. It does not opt shared users into email. A super admin must explicitly save a user schedule or confirm a global default. Explicit user settings override global digest defaults; restoring inheritance removes that override. Existing incident/system preferences are unchanged. Configuring the new digest, even as disabled, replaces legacy per-server daily emails for the affected users.

## Sending budgets and history

Limits are application budgets, not a live Resend plan allowance. A blank limit adds no cap; zero blocks sending. Global all-email, global type, user all-email, and user type rules all apply. Any pause blocks; the strictest cap and attempt count apply, with the longest retry delay. Reservations are serialized in PostgreSQL so concurrent workers cannot overspend the daily cap. Every reserved attempt counts, including failures and retries, using UTC days.

Provider acceptance is recorded as `sent`; it is not evidence of inbox delivery. No delivery/open webhook is implied. Definite failures may retry when the original dispatcher runs again. Timeouts or ambiguous network outcomes become `unknown` and stop automatically to avoid duplicates. Stale in-flight reservations also require provider review. Inspect the provider reference before any manual operational recovery; do not create a new idempotency key just to bypass an uncertain outcome.

Stopping a message prevents future attempts without deleting the ledger. Already accepted or currently sending messages cannot be recalled. Legacy/agent logs are displayed separately and are not double-counted toward the managed ledger. Browser/in-app alerts remain separate and permission-scoped; Supabase Auth emails and external agent/provider sends are outside these caps.

## Combined daily digest

Each enabled active user gets at most one accepted digest per local calendar date, keyed by user and date. It contains the complete set of currently permitted servers, honoring explicit server denial, active account status, and shared-server notification opt-outs. Local-only servers are identified without inventing cloud metrics. Server visibility is rechecked at reservation time, immediately before provider dispatch.

The existing authenticated email cron and telemetry dispatch invoke the digest runner. The configured time is a not-before time; delivery happens on the next invocation, up to 25 users per invocation. Keep the existing cron active for quiet servers and larger fleets. Nothing is sent by opening the dashboard, previewing a template, or saving settings.

## Operational rollback

Pause global all-email rules to stop managed sending while retaining enforcement and history. Disabling the feature flag is a compatibility rollback to legacy sending, not a sending kill switch: caps and combined digests are then bypassed. Do not drop the ledger or roll back the migration to disable a schedule.
