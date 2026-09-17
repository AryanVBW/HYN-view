# HYN-view portal

Next.js customer and fleet dashboard for the HYN Ubuntu monitoring agent.

## Automatic Heroku deployment

Every push to this repository's `main` branch runs validation and deploys to
Heroku once the database checks pass. See the
[Heroku setup guide](docs/heroku-deployment.md) for the GitHub secret, optional
app settings, Heroku config vars, and manual retry instructions.

## Local development

```bash
cp .env.local.example .env.local
pnpm install
pnpm dev
```

The public URL and anon key are **Auth only**. Application data is stored in
Cloudflare D1. See [cloudflare/README.md](cloudflare/README.md).

Set `HYN_DATA_API_URL` to the Worker origin so `/api/agent/v1` and dashboard
queries stop calling PostgREST.

## Hosted agent API

The CLI calls `/api/agent/v1/[action]`; customers do not enter a Supabase URL
or anon key. The gateway exposes only pairing, ingest, config-pull, and delivery
reporting RPCs, caps request bodies at 1 MB, and keeps the database contract out
of the CLI-facing URL.

## Managed email

One deployment-level Resend key serves all accounts. Each linked node receives
a tenant-private default schedule using the account email. In Account, a client
can change the recipient, IANA timezone, incident alerts, daily health time, and
daily system-information time. Administrators control all three HTML wrappers.

Set these server-only deployment variables:

```text
HYN_DATA_API_URL
HYN_DATA_SERVICE_KEY
RESEND_API_KEY
EMAIL_FROM
CRON_SECRET
```

`vercel.json` invokes `/api/cron/email` once daily at 12:00 UTC so the portal
can deploy on Vercel Hobby. The worker checks each account's local send-time
threshold, claims an idempotency key before sending, writes the delivery result
to `notification_log`, and never exposes provider credentials to a browser or
monitored server. Minute-accurate delivery requires Vercel Pro or an external
scheduler calling the same protected route.

## Verification

```bash
pnpm test
pnpm lint
pnpm build
```
