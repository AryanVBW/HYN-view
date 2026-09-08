# Local history on Supabase Free + Heroku student credits

The website runs on **Heroku**, funded by the GitHub Student Developer Pack.
Supabase remains the authentication and control database. This is the default
storage design from CLI 1.10.0 onward; older README descriptions of cloud charts,
full reports and 24-second beats describe the opt-in legacy archive.

The live Heroku app `hyn-view` was inspected on 2026-09-08: **one Basic web
dyno**, no add-ons, automatic certificate management enabled. Its dyno type was
not changed. A [Basic dyno costs at most $7/month](https://help.heroku.com/2XZEBC20/how-much-does-a-hobby-or-basic-dyno-cost),
which fits within the published student credit if that credit is active and
other charges do not use it. Credit balance/expiry was not independently verified.

## Data placement

| Data | Location and lifetime |
| --- | --- |
| Detailed sampled readings | Monitored server: `/var/lib/hyn-view/local/snapshots/`, private files; 14 days / 256 MiB shared history budget by default |
| CLI request counts, status codes, body byte totals | Server: `local/usage/`; no tokens, payloads, URLs, response bodies or credentials in these records |
| Alert history, compact report samples, service diagnostics | Existing local `alert-log`, `metrics.tsv`, and systemd journal; these have their own retention settings |
| Generated daily text reports | Private `local/snapshots/*-report-*.txt` files, included in the same age/space limits |
| Pairing verifiers, node token hashes, account roles, permissions, settings, command status | Supabase, using the existing RLS and limited RPC permissions |
| A requested complete reading | Heroku process memory, five-minute lifetime; 256 KiB maximum per reading, 8 MiB total serialized payload budget |
| Email delivery credentials | Heroku server-only environment; never copied to a monitored machine or browser |

There is no offline telemetry upload queue. Failed cloud operations do not stop
local recording or cause a historical upload burst when service returns. Disk
rotation removes the oldest local history when age/space limits are reached;
it is not an unlimited backup. Back up the server's state directory if longer
retention is required. Files are private (0600), directories 0700.

The new archive supplements the existing report and journal logs; it does not
copy the entire operating-system journal or claim to record every moment between
samples. `record_interval_min` controls periodic collection. The default is five
minutes. Requested syncs also save a local snapshot before attempting transfer.

`cloud_storage=local` disables recurring metric ingestion. `hyn push`, first
pairing sync, and requested sync/update commands can share **one current reading**
with the authorized portal. Only token/version metadata reaches Supabase during
that request. A current owner or administrator may view the temporary reading;
paused/revoked nodes and suspended accounts cannot share it. Once expired or
evicted, the UI asks for another reading. Past charts remain on the machine.

Use **one web dyno and one Node process** for the transient view. A restart,
sleep, deployment, or another dyno/process loses or cannot see that memory.
The cache has no database/disk fallback. Heroku's filesystem is ephemeral and
is not a durable log destination. A browser can retain an already rendered
reading; five minutes is the server's retention, not remote erasure of a screen.

## CLI operations and property changes

```sh
sudo hyn autostart enable       # install/repair startup and recovery services once
hyn autostart status            # show boot enablement, sleep prevention and update policy
sudo hyn cloud optimize        # local archive, email sharing off, 60s beats, 5min checks
sudo hyn cloud usage            # actual local POST accounting and reference quotas
sudo hyn cloud usage 20         # configured request baseline for 20 identical nodes
sudo hyn history --local 12    # JSONL for the last 12 local readings
sudo hyn logs 100               # local alert/service diagnostics
sudo hyn config set local_keep_days 30
sudo hyn config set local_max_mb 512
sudo hyn config set record_interval_min 5 report_at 09:00  # one atomic edit
sudo hyn config pull            # fetch current portal properties immediately
sudo hyn push                   # request one transient portal reading immediately
```

Settings reload in the resident agent within five minutes. The portal owns its
allowlist of thresholds, report time, update policy and push interval, plus local
sampling/alert schedules, daily report enablement, speed test frequency and
`keep_awake`. Changed schedules are applied automatically, including stopped or
disabled timers; saved values no longer wait for a manual setup run. CLI `config
set` accepts multiple key/value pairs, validates the complete batch before
writing, and applies schedules immediately. `hyn config apply` applies direct
file edits. A failed service application is retried by local maintenance.
The CLI validates property values and refuses multiline injection. If `config
set` changes a local value that the portal overrides, it now prints the effective
value and explains where to change/clear it. Storage policy, notification sharing,
history limits, endpoints and credentials are local-only permissions; the portal
cannot turn cloud archiving on.

## Unattended startup and updates

On a supported Ubuntu system with systemd, `sudo npm install -g hyn-view`
installs and enables the services automatically. Pair once with `sudo hyn link`.
After that, the owner can change settings or request **Update CLI** in the portal
without opening a terminal or leaving the browser page open. `auto_update=install`
also checks for new releases on its cached schedule (12 hours by default).
An explicit portal update does not wait for that registry cache.

- `hyn-agent.service` starts at boot without a desktop login, restarts after a
  crash, reloads configuration, and reports liveness.
- `hyn-update.service` runs installation in its own process group, so restarting
  the agent does not kill npm. It uses a captured Node/npm PATH for installations
  made through nvm/asdf as well as system packages. Linux advisory locks prevent
  overlapping installers.
- `hyn-update.timer` starts at boot and every five minutes to repair HYN services
  and recover a saved maintenance job. Jobs are published atomically, are never
  overwritten by automatic checks, and survive a missed trigger or interrupted
  worker. Automatic installation failures retry after at least 15 minutes.
  Switching automatic updates off cancels an automatic job. Portal jobs recheck
  current permissions and command state before installing.
- `hyn-awake.service` holds a systemd sleep/idle/lid inhibitor when
  `keep_awake=on` (default). Turning it off releases that inhibitor. HYN does not
  mask OS services or inhibit shutdown/reboot. Sleep prevention requires
  `systemd-inhibit` and a working systemd-logind service; `autostart status` shows
  whether it is actually active.

The keep-awake service uses [systemd inhibition locks](https://systemd.io/INHIBITOR_LOCKS/).
Boot/retry scheduling uses [systemd timers](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html).
Normal updates preserve `/etc/hyn-view` credentials/settings and `/var/lib/hyn-view`
history. Registry failures, disk exhaustion and permission errors are surfaced;
the CLI cannot guarantee recovery if its installed executable/filesystem itself
is destroyed. Keep a host backup for that case. Recovery of an interrupted portal
command can reinstall the same release; command execution is idempotent, not an
exactly-once guarantee.

**Starting the agent is different from powering on the computer.** Enable the
machine's BIOS/UEFI **Restore on AC Power Loss / AC Recovery → Power On** once if
it should boot when electricity returns ([manufacturer example](https://www.intel.com/content/www/us/en/support/articles/000059976/server-products/server-boards.html)).
The exact setting depends on the computer model. Wake-on-LAN or RTC wake requires support
and configuration in the motherboard/network. Disk encryption that needs a
password before boot also prevents unattended startup. A powered-off machine
cannot receive a portal request. The CLI does not change firmware, reboot this
development computer, or claim to configure hardware power recovery remotely.

`cloud_notifications=off` in local mode blocks CLI notification/report content
from the cloud. An operator can explicitly enable that key to use managed email;
then selected email content and bounded delivery records do pass through Supabase
and the email provider. Account/security emails and small command completion
receipts are still portal features. Local mode does not silently revoke a user's
account permissions or erase existing cloud history.

To explicitly restore historical portal telemetry, set `cloud_storage=cloud`.
This enables the previous Supabase ingest contract, including its storage and
egress costs. A local-mode CLI pointed directly at Supabase refuses a reading
upload: transient sharing requires the hosted gateway. There is no automatic
fallback from local storage to permanent cloud ingestion.

## Consumption model

With defaults, each node sends about **60,480 control POSTs per 30 days**:
43,200 one-minute heartbeats plus 17,280 settings/command checks. Previously a
24-second heartbeat, one-minute settings/command checks, and ten-minute telemetry
yielded about 198,720 POSTs. That is about **70% fewer routine requests**, before
pairing, explicit commands, errors and retries. Local settings checks also omit
the email templates, dispatch work and Workflow lease used by the legacy path.
Heartbeat failures back off up to 15 minutes while local supervision stays alive.
Hidden/offline browser tabs skip dashboard refreshes; queued commands poll at
15 seconds, running commands at five seconds.

`cloud usage` measures this CLI's application-body POST traffic, not TLS/HTTP
overhead, domain health probes, browser traffic, Heroku CPU, or the gateway's
Supabase egress. Its 30-day projection uses the last 24 hours; a newly installed
agent has an incomplete observation window. The configured fleet baseline is an
estimate, not provider billing. Check actual Supabase Usage and Heroku Billing
for database size, total egress, resource use, other apps, and credit expiry.

Verified references on 2026-09-08:

- [Supabase Free](https://supabase.com/pricing): 500 MB database, 5 GB uncached
  egress plus a separate 5 GB cached allowance, 1 GB file storage, 50,000 MAU.
  API requests are unlimited; CPU, database size and egress still constrain scale.
- [Heroku student credits](https://help.heroku.com/Z3RHNRHD/how-does-the-heroku-for-github-students-program-work):
  up to $13 per month for 24 months. Charges beyond available credits are payable.
- [Eco dyno hours](https://devcenter.heroku.com/articles/eco-dyno-hours): $5/month,
  1,000 hours shared across the account, with idle web dynos sleeping after 30
  minutes. Regular real heartbeats keep this portal awake: up to 744 hours in a
  31-day month for one process. Reducing API traffic does not reduce that figure
  while check-ins continue. No additional Heroku database, Redis, or worker is
  required for this design.
- [Heroku dynos](https://devcenter.heroku.com/articles/dynos): temporary disk is
  discarded during lifecycle changes. Keep durable diagnostic history on the CLI
  machines, not in a dyno directory.

## Rollout, domains and authentication

Deployment status on 2026-09-08: code and migration are tested locally; neither
has been deployed and CLI 1.10.0 has not been published. Both domains are now
registered on Heroku app `hyn-view`. `www` already has a certificate and points
to `amorphous-mosquito-65cdzk6lub45l5bl3jh67eyk.herokudns.com`. The newly registered
apex has target `amorphous-eel-gniptw2eojdo2caghyaqw2vb.herokudns.com`, but its
current A record is the placeholder `192.0.2.1`; its DNS and certificate remain
pending. These targets are app-specific; always recheck them before editing DNS.

The domain currently uses one.com nameservers. Its [documented record
types](https://help.one.com/hc/en-us/articles/115005595925-Manage-your-DNS-settings)
do not list ALIAS/ANAME/flattening. Its [Web alias](https://help.one.com/hc/en-us/articles/360000855678-How-do-I-create-a-Web-alias)
is a browser feature, not the DNS alias required for the CLI API. Verify support
with the domain account; if absent, use a DNS host supporting apex flattening,
preserving existing mail and verification records. Do not pin a resolved Heroku
IP or substitute browser forwarding for a working second API endpoint. Access
to the one.com account owning this domain is still required.

1. Apply `supabase/migrations/20260908090000_local_telemetry.sql` to the existing
   database, then `supabase/migrations/20260908110000_unattended_settings.sql`
   (or the complete schema for a new project). No existing history is
   deleted by this migration. Export/retain old data deliberately before any
   separate cleanup.
2. Deploy the **web-portal repository** to the existing Heroku app. The Procfile
   starts Next on Heroku's `PORT`, the Node buildpack uses the pinned pnpm lockfile,
   and `heroku-postbuild` builds the app. The GitHub workflow uses the
   `HEROKU_APP_NAME` repository variable and `HEROKU_API_KEY` secret. Keep one web
   process; do not add paid resources as part of the deployment.
3. Configure the server-only Supabase key and any enabled email provider in
   Heroku config vars. `NEXT_PUBLIC_SUPABASE_URL` and the public anon key must be
   available at build time. The example `.env.local` documents the fields.
4. Register **both** `www.hyn-view.in` and `hyn-view.in` on the same Heroku app.
   Use Heroku's returned DNS targets: CNAME for `www`, ALIAS/ANAME or DNS flattening
   at the apex. Enable and verify automated certificates for both domains.
   [Custom domains](https://devcenter.heroku.com/articles/custom-domains),
   [ACM](https://devcenter.heroku.com/articles/automated-certificate-management).
5. Add both `https://www.hyn-view.in/auth/callback` and
   `https://hyn-view.in/auth/callback` to Supabase Auth's redirect allowlist; use
   `https://www.hyn-view.in` as the Site URL. Avoid redirecting agent POST routes
   between hosts. OAuth cookies remain scoped to the domain used for sign-in.
6. Confirm both `/api/agent/v1/health` endpoints return
   `{"service":"hyn-agent-v1",...}` over HTTPS, then release/install CLI 1.10.0
   and run `sudo hyn cloud optimize` on existing machines. Deploy the portal
   **before** upgrading agents: older portals do not support transient readings.

The CLI prefers `www`, tries the apex if the health probe fails, and caches a
verified host for six hours. A transport/5xx failure invalidates that selection
and gives the other host priority on the next operation. It never replays an
ambiguous POST and never sends secrets in a probe or follows a cross-host
redirect. Explicit custom endpoints retain their own configuration.

The previous Vercel Workflow watchdog is disabled unless
`HYN_ENABLE_WORKFLOW_WATCHDOG=true` and a compatible durable runtime is separately
configured. The dashboard still reports missed heartbeats. **Automated outage
emails require an independent watcher** on Heroku; a CLI cannot report that its
own machine is off. Existing cloud-history email schedules require invocation of
the protected `/api/cron/email` endpoint by a configured scheduler. No scheduler,
Workflow service or paid add-on is implicitly provisioned by this change.
