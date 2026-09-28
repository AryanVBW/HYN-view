# Email delivery

All HYN-view email is sent from **`hyn-view.info`**. `hyn-view.in` is the website
only — it is not a mail domain, and nothing may send from it.

| Domain | Purpose |
| --- | --- |
| `www.hyn-view.in` | The portal and the agent API (`/api/agent/v1`). The apex `hyn-view.in` is not the portal. |
| `hyn-view.info` | The only sending domain: portal email (`EMAIL_FROM`) and Supabase Auth email (GoTrue SMTP). |

## Configuration

| Where | Setting | Value |
| --- | --- | --- |
| Portal (Heroku config) | `EMAIL_FROM` | `HYN-view <reports@hyn-view.info>` (the code default) |
| Portal (Heroku config) | `RESEND_API_KEY` | a Resend key for the account that holds the verified `hyn-view.info` domain |
| Self-hosted Supabase `.env` | `SMTP_ADMIN_EMAIL` | `reports@hyn-view.info` |
| Self-hosted Supabase `.env` | `SMTP_HOST` / `SMTP_PORT` | `smtp.resend.com` / `587` |
| Self-hosted Supabase `.env` | `SMTP_SENDER_NAME` | `HYN-view` |

The portal refuses to send from any other domain: an `EMAIL_FROM` that is not
an `@hyn-view.info` address is ignored and the default above is used instead,
so a mistyped config variable cannot make every email fail.

## Verifying the sending domain

`hyn-view.info` must be verified in the Resend account whose API key the portal
uses (Resend → Domains: SPF, DKIM and the return-path records must all show
**Verified**). Before 2026-09-20, 468 queued emails failed with *"The
hyn-view.in domain is not verified"* because the sender was an `@hyn-view.in`
address; `@hyn-view.in` must never be verified or used as a sender.

After changing any of the settings above:

1. Sign in to the portal as a Super admin and open **Admin → Email check**. It
   reports whether a provider key is configured and which sender is in effect,
   without revealing the key.
2. Send one test email from the admin fleet table and confirm it arrives from
   `reports@hyn-view.info`.

The monitored servers hold no email configuration at all; they queue events
with the portal using their node token, and the portal sends them.
