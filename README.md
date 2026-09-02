# hyn-view

A network-first terminal monitor for Ubuntu Server, for boxes that run 24/7 and
are watched by a human.

It covers what `htop` and `btop` cover, but inverts the priority: the network is
the headline, not the CPU. It also tracks a [Highway](https://highwayp2p.com)
relay node (`hw-os`) if one is installed — strictly read-only.

```
curl -fsSL https://www.hyn-view.in/install.sh | sudo bash
```

One command, one password prompt, nothing to answer. It installs node if the box
has none, installs the CLI globally from npm, writes `/etc/hyn-view/config`,
installs and starts the systemd units — including the resident agent that beats
every 24 seconds and updates itself — and then *verifies* that the agent is
actually running rather than trusting that it must be.

If you would rather do it by hand, npm is the same installation:

```
sudo npm install -g hyn-view   # installs, configures and schedules itself
sudo hyn link                  # pair with the web portal (only if you want it)
hyn                            # dashboard
```

## There is no setup step

`npm install -g hyn-view` is the installation. Its postinstall writes
`/etc/hyn-view/config`, creates the state directory and installs and enables the
systemd timers, so metric sampling and alert evaluation are running before you
type anything. No questions, no wizard, no `sudo hyn setup`.

That is a reversal. This used to be a deliberate manual step, on the reasoning
that a postinstall writing systemd units does something the user did not ask for.
Fair for a library; wrong for a monitoring agent whose whole value is being
installed on a box nobody logs into. An operator who runs `npm install -g`, sees
it succeed and walks away has every reason to believe monitoring is running — and
it was not, and nothing said so.

Four rules keep it honest:

| Rule | Why |
| --- | --- |
| It can never fail the install | every path exits 0. A monitor that could not configure itself is degraded, not a broken package. |
| Global installs as root only | `npm i hyn-view` in your project touches nothing. |
| It never overwrites an existing config | a reinstall keeps your settings. |
| `HYN_NO_POSTINSTALL=1` opts out | for image builders and CI. |

It does not pair with the portal, because pairing needs a human with a browser,
and it asks nothing, because there is no terminal to ask on. Every default is
already the right answer for a 24/7 relay node, which is what makes doing this
unattended defensible at all.

**To change something, edit one file.** `/etc/hyn-view/config` is written with
every key and a comment explaining it. `hyn config edit` opens it, `hyn config set
<key> <value>` changes one line, and `hyn config show` prints the current value of
everything. For a linked machine the portal's `/settings` page owns the managed
subset — thresholds, severity, report time, push interval, update policy — and
those changes arrive on the next check-in.

## Guided setup, if you want it

Nothing needs it, so nothing offers it. `hyn onboard` runs the guided setup on
demand: eight steps, about two minutes, and every question has a default that is
right for a 24/7 relay node — holding Enter through the whole thing produces the
same configuration the install already wrote.

```
Step 1 of 8  What we found          detected hardware, WAN link, filesystems, node
Step 2 of 8  Display mode           best looking, or best performing
Step 3 of 8  Theme                  all six drawn live in your terminal
Step 4 of 8  Units and layout       bits or bytes, refresh rate, rows
Step 5 of 8  Email and alerts       managed by the portal; no server API key
Step 6 of 8  What counts as a problem
Step 7 of 8  Cloud reports and speed tests
Step 8 of 8  Outage detection
```

The first decision is how the CLI should update, defaulting to automatic. It then
shows what it detected before asking about display and monitoring preferences. No
email-provider credential is requested. Nothing is written until you confirm the
summary.

```
hyn onboard               the full guided setup
sudo hyn setup            re-apply the config and timers, no questions
hyn config edit           open /etc/hyn-view/config
hyn config set <k> <v>    one setting, scriptable
```

Set `onboarding=on` if you would rather be offered the guided setup on first
launch.

## Why it is not just another htop

**Pure bash, zero dependencies, no runtime.** npm is only the delivery channel.
Nothing is installed but shell scripts — no Node process, no compiled binary, no
Python. It reads `/proc` and `/sys` directly with shell builtins.

**Actually cheap, and measured.** The render loop does no `fork`. No `awk`,
`grep`, `cut`, `ps`, or `sort` per tick, no command substitution in any widget or
formatter, and one `write` per frame carrying only the lines that changed.

Measured on a 150×45 terminal at the default 1 s refresh (macOS, bash 5.3 —
numbers on Linux should be better, bash arithmetic is faster there):

| Configuration | CPU | Per tick | Terminal output |
| --- | --- | --- | --- |
| `profile=best` — gradient braille, time axis, 1s | ~4.2% of one core | ~42 ms | ~1.8 KB/s |
| `profile=performance` — block graphs, 2s | ~1.7% of one core | ~17 ms | ~1.2 KB/s |

RSS is ~11 MiB, which is the bash interpreter itself. Getting here took real
work: the first version cost **1216 ms per frame**, almost all of it in one
innocuous-looking line — measuring a string's visible width with an extglob
pattern substitution. Peeling escape sequences off with plain prefix expansions
instead was 39× faster. There are comments at each of those places explaining why
the slower, more obvious form was rejected; please read them before tidying.

## Two visual profiles

Press `p` to switch live, or set `profile=` in the config.

**`best`** — braille plots where each row is coloured by height, so a graph reads
as a vertical gradient rather than a flat block. A labelled time ruler under the
graph, so "there was a spike" becomes "there was a spike four minutes ago". A
rolling average alongside the peak. 1s refresh.

**`performance`** — block-glyph graphs, no time axis, 2s refresh. Visibly
simpler, and **2.5× cheaper** (1.7% of a core against 4.2%).

Both share one scale between the download and upload plots, so a given dot
height means the same rate in each and the two are directly comparable —
independent scales would make a 10 Mbps upload look like a 900 Mbps one. The
upload plot's *height* shrinks to its share of that scale, so rows that could
only ever be blank go back to the layout instead of being drawn empty.

A profile only fills in keys you have not set yourself, so an explicit `graph=`
or `interval=` line always wins.

## Web portal

The dashboard in `web-portal/` shows the same telemetry in a browser. The server
pushes; the portal reads. Nothing is scraped and no port is opened on the
monitored box.

Pairing works like `gh auth login`, because an Ubuntu server has no browser:

```
                                        ┌─ 1. sudo hyn link
  Ubuntu server (no browser) ───────────┤   prints  QKB8-D6VQ  and polls
                                        └─ 4. receives its node token

  Your phone or laptop ─────────────────── 2. open /link, sign in, type the code
                                           3. approve "web-01"

  Then, on your chosen cadence ─────────── hyn push → hosted API → Supabase → dashboard
```

```
sudo hyn link          pair this machine; no project URL, API key, or manual timer setup
hyn cloud status       node id, and when the last push happened or why it failed
hyn push               send one reading now
sudo hyn unlink        forget the credential locally
```

### Setting it up

1. Create a Supabase project and apply `supabase/schema.sql` in the SQL editor.
   It creates the tables, the row level security policies and the pairing RPCs.
2. In the portal, copy `web-portal/.env.local.example` to `.env.local` and fill
   in the project URL and anon key. For Google sign-in, enable the Google
   provider in Supabase and add `<your-site>/auth/callback` as a redirect URL.
3. Set the server-only portal variables (`SUPABASE_SERVICE_ROLE_KEY`,
   `RESEND_API_KEY`, `EMAIL_FROM`, and `CRON_SECRET`) in the deployment.
4. On the server, run `sudo hyn link`, then follow the code. The CLI talks to
   the hosted `/api/agent/v1` gateway and installs its systemd schedule itself.

### What the dashboard shows

**The Highway node comes first.** The section above the processor charts lists
every tracked unit with its state, restart count, cgroup memory and time active,
then the node process, the mesh tunnel, the WAN qdisc and congestion control, the
journal's error and warning counts for the last hour, and the installed version against the
published one — the terminal's node view (`4`), for someone who is not at the
terminal. It is placed first deliberately: on a relay box a failed unit matters
more than a busy CPU, since a node that is not running earns nothing however cool
it is. An agent older than the section says so and prints the upgrade command,
rather than reporting a machine with no services.

**Everything the agent sends is on the page.** Not a summary of it. Every
filesystem with its type, size, used share and free headroom; the top processes
by CPU and memory with pid and thread count; the link's negotiated speed and
duplex, driver, MTU, local address, gateway and DNS, interface errors and drops,
TCP retransmit share, socket state distribution, listen-queue drops and conntrack
headroom; first-hop latency separately from internet latency; PSI for cpu, memory
and io; per-core clock speeds with the governor and the hardware's floor and
ceiling; **what the machine is drawing and whether it is drawing it from the
wall**, with every power rail the platform exposes. The person watching the portal is the person who cannot reach the
machine, so a dashboard that makes them ask for ssh has failed at its only job.
An administrator sees the same panels inside the per-client view at `/admin`.

**Real data only.** With no node linked it says so and tells you how to link
one; with a node linked but no metrics yet it says that instead, because the fix
is different. A missing sensor renders as `—` or as an explicit "no thermal
sensor" panel rather than as a zero, since a plotted 0°C is a lie about a healthy
machine.

**Demo data is opt-in.** The empty state has a *Load demo data* button that
seeds one synthetic node so the dashboard can be evaluated without a server to
pair. It is flagged `is_demo` in the database, badged `demo data · not a real
server` wherever it appears, and removable in one click. Nothing seeds it
automatically.

## Central management

Once a node is paired the dashboard manages its monitoring settings, update
policy, email recipient, timezone, delivery types, and schedule. Customers do
not configure provider credentials: the portal uses one deployment-level email
key for every account.

```
hyn config pull        fetch monitoring settings from the portal
hyn cloud status       what was pulled, when, and the node's administrative state
```

Every scheduled `hyn push` performs that pull before collecting and sending its
reading, so portal changes apply on the next check-in without a second timer.
**A pull that actually changes something also sends a reading immediately**, rather
than waiting up to `cloud_push_min` — someone who edits a threshold and watches the
page would otherwise reasonably conclude it had not worked.

`/account` shows node settings and every delivery attempt with the reason any
failed. **Clear on that panel hides the history from your own view and deletes
nothing** — the rows stay in the database for the 30-day counters above it and for
the administrator's fleet-wide log, anything sent afterwards appears as usual, and
*show all again* brings the rest back. The cutoff is a cookie, so it is a
per-browser preference rather than a change to anyone's data; clearing for real is
an administrator action. Thresholds, CLI update policy and push interval are
edited per server.
The Email automation section controls immediate incident alerts, the daily
health digest and the daily system-information message. **Incident alerts are off
until you turn them on**, and the two digests are not: a machine that pairs itself
should not start mailing an account that never asked to be mailed, and a default
nobody chose is the one that ends up failing thousands of times a day and being
ignored. The same switch gates the portal's outage email — see "Detecting a dead
server". No customer configures a
provider credential: the portal uses one deployment-level email key for every
account, and the monitored machine holds none.

The set of settings the portal may manage is declared three times — in the agent,
in the database as a `CHECK` constraint, and in the portal form — and a test
compares all three, because drift there does not fail loudly. It presents as "I
changed it in the portal and the server ignored me".

A pulled setting is written to a cache that `cfg_load` applies **after**
`/etc/hyn-view/config`, so the dashboard wins for the small set of keys it is
allowed to manage — thresholds, severity, report time, push interval and update
policy. Everything else is refused outright: endpoints, credentials, privacy
options and the local-only settings are read from the root-owned files and the
portal cannot reach them. That split is deliberate. Central management that
cannot actually change a threshold is not management, and a portal that could
rewrite `cloud_url` or `notify_access_details` would be a much larger trust
boundary than a settings page needs.

The cache is rewritten whole on every pull, never merged, so **clearing a field in
the portal hands the setting back to the CLI default** instead of pinning it to
whatever it was last set to. Central management that can take a setting but not
give it back is a trap, and `cfg_load` reloads from the shipped defaults each time
for the same reason — layering onto the previous result meant a withdrawn value
survived for the life of the process, which on the dashboard is days.

### What the agent sends

One push carries, per node: CPU percent split by user/sys/iowait/**steal**, load,
**per-core clock speeds** with the governor and the hardware's floor and ceiling,
**every temperature sensor the platform exposes** (not just the CPU package — an
NVMe at 70°C is what explains a fan that will not stop), memory and swap, every
real filesystem with its size and projected pressure, WAN throughput with errors,
drops, retransmits, **negotiated link speed and duplex**, TCP state distribution,
conntrack headroom, PSI for cpu/memory/io, first-hop and internet latency, the
last speed test, process count and the **top processes by cpu and rss**,
**power draw with the measurement it came from** — a PSU rail read over hwmon, a
platform or CPU+DRAM figure derived from RAPL energy counters, plus mains presence
and any battery or UPS — and every alert currently firing.

Highway goes over the wire in full, not as a verdict: **every tracked unit with
its state, sub-state, restart count, cgroup memory and how long it has been
active**, the node process (pid, cpu, rss, threads, open files, uptime), the
Nebula mesh interface with its rates, totals and drops, the WAN qdisc and
congestion control, error and warning counts from the last hour of journal with
no journal text, and the installed version — with where that version was
read from — against the currently published one. That is what the portal's
Highway section is drawn from, so it says the same thing the terminal does.

Sensors that do not exist serialise as `null`, never `0`. A VM with no thermal
passthrough is a normal outcome, and a graphed 0°C would be an invented reading.
An unset systemd `MemoryCurrent` (reported as the 64-bit sentinel) is `null` too,
rather than a unit apparently using 16 EiB.

### Administration

An administrator sees every client and every machine at `/admin`: animated fleet
totals, 24-hour CPU and network trends, node-state distribution, which boxes have
gone quiet, open alerts, notification volume and failures per client, the
fleet-wide delivery log, and an audit trail. Client and machine rows open an
embedded per-client dashboard, so an administrator can inspect that client's
live stat cards and telemetry charts without leaving the control panel.

**The delivery log can be cleared, and defaults to a purge rather than a wipe.**
It is the one table nothing prunes, so a fleet that has been mailing for a year
reads as a wall of long-resolved failures — which is what stops it being read.
The control offers older than 30 days, older than 7 days, or everything, and the
first is preselected: clearing months of settled history is routine, deleting
this morning's failures is not. It is fleet-wide and irreversible, so the audit
trail records who cleared it, with what cutoff, and how many rows went.

| Control | Effect |
| --- | --- |
| **Pause** | Stops accepting readings. Optionally for N minutes, after which it resumes by itself. |
| **Suspend** | Stops accepting readings until an administrator lifts it. |
| **Revoke** | Invalidates the node token. Not reversible from the portal — the machine must be paired again. |
| **Delete** | Removes the machine and every reading, alert and delivery recorded for it, from the client's dashboard as well as the admin's. Not reversible, so it asks for the machine name to be typed, and the audit entry outlives the row. |
| **Suspend client** | Suspends the account and, with it, every machine the client owns. |

**A machine can exist without ever having linked, and only an administrator can
remove it.** Approving a pairing code creates the node row immediately, so a
client who approves a code and never finishes `sudo hyn link` — wrong box, a
typo, a changed mind — keeps a machine on their dashboard that will never report
anything. Nothing removed it: the pairing-expiry sweep only reaches one while the
pairing row survives, and pause, suspend and revoke all deliberately leave the
row in place because a revoked box is history worth keeping. So the fleet table
labels those machines `never linked`, filters to just them, and counts them per
client next to the linked total — `2/3 · 1 never linked` — and Delete is the
control for them. It works on any machine, not only a phantom; the never-linked
ones are simply the case where it is the *only* right answer.

A timed pause is preferred over an open-ended one because monitoring you forgot
to switch back on is worse than none: you believe you still have it. The agent
treats a pause as an administrative decision rather than a fault and exits zero,
so a maintenance window does not fill the journal with what looks like a broken
agent.

Two guard rails are enforced in the database: an admin cannot suspend their own
account, and the last remaining administrator cannot be demoted.

The first administrator is made by hand, once:

```sql
update public.profiles set role = 'admin' where email = 'you@example.com';
```

After that, an admin can promote others from `/admin`. The third route is an
allow list — addresses that are promoted automatically the next time they sign
in:

```sql
insert into public.admin_allowlist (email) values ('you@example.com');
```

`admin_allowlist` has row level security on and **no policies**, and is revoked
from both session roles, so no browser session — not even an administrator's —
can read or change who is eligible. It is edited in the SQL editor on purpose:
deciding who may become an admin should need the same access as the schema.

That table replaced an `ADMIN_EMAILS` environment variable checked in the portal's
server code, which was not a boundary at all: the promotion RPC is granted to
`authenticated`, so any signed-in user could skip the app, call it directly with
the public anon key and their own address, and be promoted. The check now happens
inside the function, against the table.

**Authorisation lives in the database, not the UI.** Every admin RPC re-checks the
caller's role, because anyone can call these endpoints directly with the public
anon key — the dashboard hiding a button is a courtesy, not a boundary.

### Credentials

| Value | Where it lives | Why |
| --- | --- | --- |
| Hosted API URL | built into the CLI, overridable in `/etc/hyn-view/config` | Normal customers link without knowing the Supabase project or public key. |
| Node token | `/etc/hyn-view/secrets` (0600) | The actual credential. Sent in a request body, never in `argv`, so no local user can read it out of `ps`. |
| Service-role key | portal server environment only | Used by the scheduled email worker; never sent to a browser or monitored server. |
| Shared Resend key | portal server environment only | One centrally managed provider account serves all portal users. |

**Portal email delivery is centrally managed.** Recipients and schedules are
tenant-private rows protected by RLS; the provider key remains a server-only
deployment secret. The cron worker sends through Resend, records every outcome,
and uses an idempotency ledger so overlapping invocations do not duplicate mail.

Administrators may edit the non-secret HTML wrappers for incident alerts, daily
health digests, and system-information messages from the Email templates tab. A wrapper must contain
`{{content}}`; optional placeholders include `{{hostname}}`, `{{version}}`,
`{{severity}}` and `{{subject}}`. The cloud email worker applies them at send
time. Active HTML is rejected, while generated detail remains unescaped inside
`{{content}}`; provider credentials never cross into the template store.

A node token authorises writes for that one node and nothing else. Revoking a
node from the portal stops it, and `hyn unlink` deliberately does *not* revoke
server-side — a compromised agent revoking its own node would be a denial of
service. The agent refuses to send it to a non-`https` endpoint at all, loopback
excepted, so a mistyped `cloud_url` cannot put a long-lived credential on the
wire in clear text.

The browser is not given even the token's *verifier*: `nodes.token_hash` is left
out of the column grant, so `select *` on `nodes` is refused for a session and the
portal names the columns it wants. The hash cannot be used to write telemetry —
ingest needs the preimage — but there is no page that needs it either, and a value
the browser never receives cannot leak from the browser.

The database tests cover the parts worth being sure about: a token is released
exactly once, a replayed poll is refused, an unknown token cannot write, a paused
node is refused and resumes by itself, a suspended one stays refused, one account
cannot read another's telemetry, a browser session cannot forge a metric row or
read a node's token hash, no central notification-credential tables or directory
RPC exist, a signed-in user
cannot promote themselves by calling the admin-claim RPC directly, the admin allow
list is unreachable from any session, and a non-admin is refused every privileged
endpoint. They also prove that only an administrator can edit a template, that
unsafe HTML is rejected, and that a saved wrapper reaches the node config pull.

```
bash supabase/run-tests.sh     # applies the schema to a throwaway cluster
bash test/cloud-integration.sh # agent against a mock endpoint
```

## Alerts

Rules cover memory, swap, per-mount disk (with a fill-date projection),
read-only root, load per core, CPU steal, iowait, temperature, interface down,
error and drop rates, TCP retransmit share, listen-queue drops, conntrack
headroom, latency, packet loss, throughput regression against your own recorded
best, OOM kills, failed units, file descriptor exhaustion, and — for a Highway
node — failed units, crash loops, an inactive node, a missing mesh tunnel and
journal errors.

Three behaviours matter more than the rule list, because the naive version of
this feature is worse than no feature:

- **Hysteresis.** A rule fires at its threshold and clears at a lower one. With a
  single threshold, a disk sitting at exactly 85% mails you every cycle.
- **Cooldown.** A condition that is still true is repeated at most once per
  `alert_repeat_hours` (default 6), not once per run.
- **Digest.** One run sends *one* message listing everything. A full disk trips
  several rules at once, and six emails about one incident teaches you to ignore
  them.

```
hyn alerts check      evaluate everything now (what the timer runs)
hyn alerts list       every rule, its current value, whether it is firing
hyn alerts test       send a test alert through the real channels
hyn alerts state      firing state and when each was last notified
hyn alerts log [N]    what has fired recently
```

Set any threshold to `0` to switch that rule off.

### Detecting a dead server

**hyn cannot tell you the server went down.** If the box is off, so is hyn. Any
tool claiming otherwise from inside the machine is lying to you.

So the check that matters is made from outside it, and the portal makes it. Pairing
starts a watchdog for that node. `hyn-agent.service` beats every 24 seconds; after
three minutes of silence — seven missed beats — the owner gets a `[HYN CRIT]`
email, and another when the beats resume. Nothing to install and nothing to
configure but the one switch: the outage email goes out through **Incident
alerts** on `/account`, which is off until you turn it on. The watchdog itself
runs regardless, so the portal always knows a machine has gone quiet and shows it;
the switch decides whether you are emailed about it.

Seven missed beats rather than three is deliberate. The threshold is what makes
the difference between "reports an outage" and "cries wolf": at a one-minute
cadence a single dropped packet spent a third of the budget, and on a domestic
link that happens. A 24-second beat buys the same three-minute detection time with
seven independent chances to be heard.

That replaced a healthchecks.io ping URL entered on every machine. It was a second
third-party account, configured per box, to detect exactly what the portal already
sees — and it could only ever notice silence, which is what the portal watchdog
notices too. One fewer account, one fewer thing to get wrong on the fifth server.

An unpaired machine has no outage detection at all, and `hyn doctor` says so rather
than implying otherwise.

## Daily report

Every message — alert or report — names the account it ran as, the human who set
it up if it was via sudo, and who is logged into the box right now with their
source address and login time. On a server that runs unattended, "an ssh session
from an address I do not recognise" is a more useful line than most performance
numbers. The report also counts rejected SSH authentications for the window,
labelled as a trend rather than an incident, because on an internet-facing host
that number is never zero.

One message a day. Performance with averages, peaks and minutes spent busy;
power draw averaged over the window with its peak and an energy estimate in watt
hours; storage with the 24h change and a projected fill date; network totals, peak
rates, retransmit share and latency; every LAN and WAN interface with its type,
address, state and traffic, plus SSID, gateway and DNS; throughput tests against
your all-time best; full Highway node status; and everything that fired.

It leads with a one-line verdict — `HEALTHY`, `MOSTLY HEALTHY`, `PLAN AHEAD`,
`DEGRADED`, `ATTENTION` or `NO HISTORY YET` — because that is what a phone
notification shows.

The HTML version is built for mail clients, not browsers: inline styles only,
tables for structure, bars drawn as coloured table cells, no external images and
no `<style>` block, since Gmail strips it and Outlook renders through Word. A
hidden preheader sets the inbox snippet. Headline figures sit in KPI cells at the
top, trends are block-glyph sparklines in a monospace span, and severities are
coloured pills. Alerts use the same components, so the two look like one product.

```
hyn report            print it
hyn report --send     email it
hyn record            sample metrics once (what the record timer runs)
```

The report needs history, so `hyn-record.timer` samples every 5 minutes into a
TSV. It reports *change* as well as level: "disk at 71%" is not actionable,
"disk at 71%, up 4 points in 24h, full in about 7 days" is.

## Delivery

**There is one delivery path and no configuration for it on the server.**

```
alert fires  ──►  hyn queues an event  ──►  portal resolves the recipient,
                  (node token only)         applies the template, sends,
                                            and records the outcome
```

The agent holds no provider account, no API key, no sender address, no recipient
list and no ping URL. It queues an event with the hosted API using its node token
and stops caring. The portal owns the provider account, the recipients, the
schedules, the templates and the delivery log, and its Account page is the only
place any of it is configured.

Six local channels used to live here — Resend, Brevo, SMTP, Telegram, ntfy and a
generic webhook — each with its own credential in `/etc/hyn-view/secrets`, its own
recipient and sender keys, its own failure modes and its own wizard page. Every one
of them was in the wrong place:

| What was on the box | Why that was wrong |
| --- | --- |
| A provider API key | a credential to rotate on every machine you own, sitting on the machine most exposed to the internet. |
| A recipient address | it changes when someone leaves the team, and changing it meant ssh to N servers. |
| A sender domain | verified once per provider, then re-entered per box and wrong on half of them. |
| A healthchecks.io ping URL | a second third-party account, configured per machine, to detect the thing the portal already detects. |
| The delivery outcome | the agent reported "sent" when it had handed the message to a provider, which is not the same as delivered. |

None of that is knowable or fixable by the person actually looking at the
dashboard, which is the person who cannot reach the machine. So it moved.

What stays on the box is the node token, in `/etc/hyn-view/secrets` at mode `0600`,
never in the world-readable config. It is never passed in `argv` — a token in a
`curl -H` argument lands in `/proc/<pid>/cmdline` where any local user can read it
out of `ps` — and message bodies go the same way. Everything interpolated into JSON
is escaped first, because alert and service text can be attacker-influenced.

`notify_max_per_day` (default 50) is kept as a local backstop: it is the portal's
provider quota a flapping rule would burn, and the cheapest place to stop that is
before the request goes out. The cap itself is set from the portal.

**What you configure, and where.** Two files, one of them not on the server:

| Setting | Where |
| --- | --- |
| Recipient, timezone, send times, which message types | portal → Account |
| Email templates for alerts, digests and system info | portal → Email templates (admin) |
| Thresholds, severity, report time, push interval, update policy | portal → Account, or `/etc/hyn-view/config` |
| Display, theme, panels, refresh rate, node tracking | `/etc/hyn-view/config` only |
| Endpoints, the node token, privacy opt-ins | `/etc/hyn-view/config` and `secrets` only — the portal cannot touch these |

```
hyn notify status     what delivery is configured, and whether this box can reach it
hyn notify test       queue one test event with the portal
```

## Updates

On launch hyn checks the npm registry for a newer release. The check is cached
for 12 hours, runs detached, and never delays startup; a newer version shows as a
badge in the status bar.

```
hyn update --check    just look
sudo hyn update --yes install it
```

`auto_update=install` applies updates unattended and refreshes the systemd units
after npm succeeds, so the agent is not reinstalled or manually reconfigured.
The first-run wizard asks for the policy before anything else, and it can later
be changed from Account in the portal.

The portal also shows the installed and available agent versions. Choosing
**Update machine** creates an owner-scoped, one-time command that the agent picks
up on its next one-minute check-in. The page shows registry check, installation,
HYN service restart, verification, and final synchronization progress. A
successful update restarts and verifies every enabled HYN timer, then immediately
sends fresh telemetry instead of waiting for the configured reporting interval.
If a machine is offline, the command safely waits for it to check in; run
`sudo hyn doctor --fix` on the server, which rewrites the units, re-enables the
timers and pushes a reading immediately.

**A machine that is paused, suspended, revoked or demo says so instead of
failing.** These requests used to be refused with one message — `active node not
found` — under a fixed "recovery on the server" block telling the operator to run
`hyn doctor` and restart the push timer. That is the fix for none of those states:
nothing on the machine can lift a pause, reinstate a suspended node or restore a
revoked credential, so an operator who ssh'd in found a perfectly healthy agent
and concluded the portal was lying. The refusal now names the state and the reason
recorded with it, the control is disabled with that reason rather than offered,
and the recovery shown is the one that applies — the portal for a pause or a
suspension, `sudo hyn link` for a revoked credential, `hyn doctor` only for a
machine that genuinely did not complete the job. `hyn doctor` reports the same
state on the box, since a pause is invisible to every local check. A timed pause
that has already expired is treated as active, exactly as ingest and the heartbeat
already treated it, so a command is never refused by a deadline that has passed.

**The agent has full write access, and that is a deliberate reversal.** These
units used to run under `ProtectSystem=strict` with `ReadWritePaths` limited to
one state directory. It read well and it was wrong: `npm install -g` writes under
`/usr`, `hyn setup` rewrites `/etc`, and node's JIT needs writable-executable
pages, so the agent could not install its own updates, could not rewrite its own
units and could not repair itself. On an unattended box a monitor that cannot fix
itself is worse than one with a wide mount namespace.

What replaced it is the part that was actually protecting the node, which was
never the mount namespace:

| Setting | Why |
| --- | --- |
| `CPUWeight=20`, `IOWeight=20`, `Nice=15`, idle I/O | the node always wins a contended scheduler. Monitoring must never be why a validator misses a block. |
| `MemoryMax=256M` | bash needs ~12 MiB. A relayer holding 1.5 GiB must never feel this process. |
| `OOMScoreAdjust=500` | if the kernel has to choose a victim, it chooses hyn. |
| `TimeoutStartSec` on every unit | a wedged collector is reaped, not accumulated. |

**It cannot stop another service, and that is enforced in code, not by a
sandbox.** Stopping a unit takes a `systemctl` call; no mount namespace ever
prevented one. So the guarantee lives in `test/selfcheck.sh`, which reads every
source file and fails the build if a state-changing `systemctl` verb — `start`,
`stop`, `restart`, `enable`, `disable`, `mask`, `reset-failed` and the rest — is
aimed at anything other than one of hyn's own six units. `hyn` clears the failed
latch on its own services by name and never with a glob: another failed unit on
the same box is information the operator needs, not litter for a monitor to tidy.

The install runs in its own unit for a plainer reason: a check-in that fires every
sixty seconds must not be the process holding an `npm install` open, and a 256 MiB
cap that is right for bash is too tight for node.

**Network detail that matters on a server.** Throughput and packet rates, but
also interface errors and drops, TCP retransmits as a share of segments sent,
listen-queue drops, socket state distribution, conntrack headroom, UDP receive
buffer errors, and first-hop latency measured separately from internet latency —
which is what tells you whether a problem is yours or your provider's.

**Numbers other tools bury.** `steal%` is a first-class field: on a rented VPS it
distinguishes "my node is slow" from "my host is oversold". PSI
(`/proc/pressure`) sits next to load average, because load counts runnable tasks
while PSI measures time actually lost to contention.

**Scheduled speed tests, safely.** Bounded by bytes and by wall clock, skipped
automatically when the link is already busy, and scheduled with a randomised
delay so a fleet of operators running the same installer don't all test at once.

**It tells you when something breaks.** Alerting runs from a systemd timer, not
from the dashboard, so it works whether or not anyone is looking. The message goes
to the portal, which owns the provider account and the recipient — so there is no
API key on the monitored box and no per-machine mailing list. Plus one daily report
covering performance, throughput, storage trend, connection details and node
status.

## Views

| Key | View |
| --- | --- |
| `0` | simple — node status, internet speed now + today's high, CPU temp, essentials |
| `1` | dashboard |
| `2` | network detail — all interfaces, kernel tuning snapshot |
| `3` | processes |
| `4` | Highway node detail + recent journal warning counts |
| `h` | keys, paths and about |

Other keys: `t` cycle theme, `p` switch visual profile, `u` bits/bytes, `m` sort
by cpu/mem, `i` cycle interface, `s` run a speed test now, `+`/`-` refresh rate,
`r` redraw, `q` quit.

The processes view sequences rows rather than sorting flat by cpu or mem: every
process is grouped active (green, on a CPU right now), paused (yellow, sleeping
or waiting on I/O), stopped (red, job-control stopped), then inactive (dim,
zombie) — cpu/mem only breaks ties inside a group, so the panel always reads as
"what's actually running" first.

The simple view (`0`) is the one to leave on a screen nobody is actively working
at: a single glanceable verdict for the node (running / degraded / not running),
current throughput next to today's fastest recorded speed test with a braille
sparkline of the day's tests, CPU temperature against fixed thresholds, what the
machine is drawing and whether it is on mains or battery, and one line each for
memory, the tightest disk and load. Set `dashboard_view=simple` to
open there by default; `hyn net`/`hyn proc`/`hyn node` still override it. On a
linked machine an administrator can set this from the portal instead.

The network panel header names the connection the way you do — Wi-Fi SSID or
NetworkManager connection name, not just `enp3s0` — alongside the link speed,
local address and public address. A connection row carries gateway, DNS, MAC and
interface type, and the full network view (`2`) lists every interface with its
type, state and address.

## Commands

```
hyn                       dashboard
hyn net | proc | node     open on a specific view

hyn snapshot              one-shot reading for ssh, cron and alerting
hyn snapshot --json       same, machine readable
hyn speedtest [--json]    measure now and record it
hyn history [N] [--json]  recorded results

hyn alerts check | list | test | state | log
hyn report [--send]       daily report: print it, or email it
hyn notify status | test  portal delivery state, or queue a test message
hyn record                sample metrics once

sudo hyn link             pair with the web portal (device-code flow)
sudo hyn unlink           forget the portal credential
hyn push                  send one reading to the portal
hyn heartbeat             send one liveness beat now
hyn agent                 run the resident loop in the foreground (debugging)
hyn config pull           fetch monitoring settings from the portal
hyn cloud status          node id, last push, and any error

hyn update [--check] [--yes]
hyn about                 author, licence, version
hyn theme list | set <name> | preview <name>
hyn config show | get <k> | set <k> <v> | path | edit
hyn doctor                what works on this machine, and what does not
sudo hyn doctor --fix     rewrite the units, re-enable the timers, push now
sudo hyn setup            re-apply config, secrets and timers (no questions)
sudo hyn uninstall        remove units (add --purge to drop config and history)
```

**One resident service and five timers** are installed by the postinstall.

`hyn-agent.service` is the only thing here that stays running. It sleeps, wakes
every `heartbeat_sec` (24 by default), sends one small POST that says this machine
is alive, and goes back to sleep. Every five minutes it also reloads the config,
looks for a newer release, and re-arms any timer that has drifted.

It is a resident process rather than a sixth timer for a reason. A heartbeat is
what the portal reads as proof of life, so it has to be the most reliable thing
the agent does — and a timer is not that: the minimum useful cadence still pays a
whole process start per beat, and `AccuracySec` plus `RandomizedDelaySec`
coalescing turns a "24 second" timer into a 24-to-50 second one. Three of those in
a row and a healthy machine is reported as gone.

| Property | Why |
| --- | --- |
| `Restart=always`, `RestartSec=5s` | systemd is the supervisor. "Keep it running" is not code we have to write. |
| `StartLimitIntervalSec=0` | the default gives up after five restarts in ten seconds. A heartbeat must never be permanently abandoned over a bad ten seconds. |
| a liveness stamp every tick | a loop that is *running and not beating* is the one failure a restart policy cannot see. A stale stamp gets the unit restarted — see `setup_heal_agent`. |
| it exits when the version on disk changes | a resident process otherwise runs last week's code for ever. Exiting **is** the upgrade: systemd starts the new one. |
| `MemoryMax=128M`, `CPUWeight=20`, `OOMScoreAdjust=500` | it lives beside a relayer for months. ~11 MiB of bash, one `curl` per beat, and the node wins every contended scheduler. |

It is enabled whether or not the machine is paired. Without a token it does not
beat, but it is still the only thing on an unpaired box that looks for a release
or repairs a stopped timer — and an unpaired box is precisely the one nobody logs
into. Telemetry deliberately stays out of it: an expensive collector that leaks or
wedges must not be able to take the heartbeat down with it.

The five timers follow one rule: **a timer is enabled if its job can ever do
something useful.**

| Timer | On when |
| --- | --- |
| `hyn-record` | always — the report's trend lines come from it |
| `hyn-speedtest` | always |
| `hyn-alerts` | `alert_enabled` (default on) |
| `hyn-report` | `report_enabled` (default on) |
| `hyn-push` | the machine is paired |

Only the push is conditional, because without a node token every run is a
guaranteed failure and an enabled push timer on an unpaired box would write one to
the journal every sixty seconds. Nothing is gated on having somewhere to *send*:
every job treats "no delivery channel" as a no-op and exits 0, so the report timer
runs from the moment you install and prints a line saying where it would have sent
to. `hyn doctor` states the reason for any timer that is off and does not count it
as a warning — a correctly installed machine should not look broken. Portal sync checks
configuration every minute and collects only when the dashboard-selected push
interval is due. All five are one-shots that yield to the node — low CPU and I/O
weight, `MemoryMax=256M`, `OOMScoreAdjust=500` — with full filesystem write
access so the agent can update and repair itself. There is no Node.js process at
any point, and an npm update refreshes the units automatically.

A seventh unit, `hyn-update.service`, is installed but never enabled. It has no
timer and no `[Install]` section: it exists only to be started by name when an
update is due, so neither a sixty-second check-in nor the heartbeat loop is ever
the process holding an `npm install` open. It also has its own cgroup, which is
what lets an update restart the resident agent without killing the install doing
it. See "Updates".

`hyn snapshot --json` is the integration point. It emits one object with the
network counters, latency map, speed test result, and node health, so it can be
piped into whatever alerting you already run.

## Highway node tracking

If `/usr/local/bin/highway` exists, the node panel shows unit states and restart
counts, cgroup memory, process CPU/RSS/threads/fds, the Nebula mesh interface
and its traffic, the qdisc on the WAN interface, congestion control, error and
warning counts from the last hour of journal, and the installed version against
the currently published one.

**Unit discovery is by name pattern, and the default list is
`highway*,hway*,hw-*,nebula*,mosaic*`.** `hway*` is not redundant. Highway
Relayer OS names its units `hway-relayer.service`, `hway-monitor.service`,
`hway-otel-agent.service` and so on — `highway*` needs an "i" and `hw-*` needs the
hyphen straight after "hw", so without `hway*` the only units that matched on a
production relay node were the Nebula ones. The panel reported "ok, 3 units
active" while the relayer itself was untracked and `hway-logrotate.service` sat in
`failed`. Add your own patterns to `highway_units` if your node names units
differently.

The node process is identified from the relayer unit's own `MainPID` rather than
by scanning `/proc` for a command name. `/proc/<pid>/comm` is capped at 15
characters by the kernel, so `hway-relayer-supervise` appears as
`hway-relayer-su`; matching on fixed names picked up a 10 MiB sidecar and reported
its memory for a process actually holding 1.5 GiB.

**It never changes anything.** No `systemctl start/stop/restart/enable`, no
writes under `/etc/highway`, `/var/lib/highway` or `/opt/highway`, no `tc` or
`nft` subcommand other than `show`/`list`. The test suite greps every source file
to enforce this, so it cannot regress quietly. That check is the *only* thing
enforcing it — the units have full filesystem write access — which is why it
covers every file rather than just `highway.sh`.

The node binary is **not executed** to read its version. Running a validator's
own binary next to a live instance to ask a question is not something a monitor
should do, so the version is read from on-disk files, systemd unit metadata, and
the journal instead — `/opt/hway-agent/current/VERSION` first, because scraping a
version out of unit metadata found `v0.3.1` on a box whose agent was `v0.1.95`.
If none of those answer, the panel says so. Set `highway_version_probe=exec` to
opt into running `highway --version`.

Turn the whole thing off with `highway_track=off`.

## Configuration

`/etc/hyn-view/config`, or `~/.config/hyn-view/config` for a single user. Run
`hyn config show` for every key and its current value; `sudo hyn setup` writes a
commented file with all of them.

The config file is parsed, not sourced — a monitoring tool should not become an
arbitrary code loader because someone can write to `/etc`.

Keys worth knowing:

| Key | Default | Notes |
| --- | --- | --- |
| `dashboard_view` | `dash` | `simple` opens the premium glance view (`0`) instead of the full dashboard (`1`) |
| `interval` | `1.0` | seconds. `2.0`–`3.0` is lighter still |
| `net_unit` | `bits` | how links are sold; `bytes` if you prefer |
| `panels` | `net,cpu,mem,node,proc,disk` | **order is priority** — the last ones are dropped first on a short terminal |
| `graph` | `braille` | `block` is ~⅓ cheaper and coarser; `off` drops graphs entirely |
| `wan_iface` | `auto` | follows the default route |
| `latency_targets` | `1.1.1.1,8.8.8.8` | plus the gateway, probed separately |
| `speedtest_per_day` | `4` | drives the systemd timer schedule |
| `speedtest_guard_pct` | `25` | skip a scheduled test if the link is busier than this |
| `speedtest_provider` | `auto` | prefers Ookla `speedtest`, then `speedtest-cli`, then `curl` |
| `power_track` | `on` | RAPL, hwmon power rails and mains/battery state |
| `highway_track` | `on` | node panel |
| `profile` | `best` | `best` or `performance` |
| `notify_access_details` | `off` | set `on` only to include run-as/session usernames, session source IPs and the worst rejected-login IP in notifications |
| `alert_min_severity` | `warn` | `crit`, `warn` or `info` |
| `alert_repeat_hours` | `6` | reminder interval while still firing |
| `report_at` | `08:00` | server local time |
| `auto_update` | `install` | `off`, `check` or `install`; linked installs stay synchronized by default |
| `onboarding` | `off` | the install configures itself, so nothing is offered; `on` restores the first-launch prompt |
| `cloud_enabled` | `off` | set by `hyn link`; gates the portal push timer |
| `cloud_api_url` | `https://www.hyn-view.in/api/agent/v1` | hosted agent API; no customer key required |
| `cloud_url` | *(empty)* | optional direct-Supabase URL for self-hosters |
| `cloud_anon_key` | *(empty)* | optional public anon key for direct-Supabase mode |
| `cloud_portal_url` | `https://www.hyn-view.in` | prints the complete pairing URL |
| `cloud_push_min` | `10` | minutes between full portal readings; heartbeat/config checks remain one minute |
| `heartbeat_sec` | `24` | seconds between liveness beats from `hyn-agent.service`; clamped to 5–3600, local-only |
| `hide_mount` | `/snap,/var/lib/docker,…` | mount points kept out of the disk panel and alerts |

Themes: `hiway` (default), `nord`, `gruvbox`, `dracula`, `solar`, `mono`. Drop a
`.theme` file in `/etc/hyn-view/themes/` to add your own — they are 15 hex
colours, resolved at load into whatever the terminal supports (truecolor, 256,
16, or none).

## Requirements

Ubuntu 22.04 or 24.04, including Highway Relayer OS, which is 24.04 underneath
(anything with Linux `/proc` and bash 5.0+ will work).
Snap mounts are excluded automatically: they are read-only squashfs and therefore
permanently 100% full, so a box with twenty snaps would otherwise show twenty
filesystems and fire twenty disk-full alerts that could never clear.
`curl` for speed tests and the update check; `ping` for latency, falling back to
a TCP handshake when ICMP is filtered; `systemd` for unit tracking and the timer.
`hyn doctor` reports which of these you have.

**The package has no npm dependencies, and that is not an accident.** `dependencies`
in `package.json` is empty and stays empty: nothing here runs on node, so a
dependency would be a supply-chain risk taken on behalf of a root process for no
functional gain. What the agent actually needs is a handful of system packages, and
those are declared where they can be acted on — the one-line installer installs
them, and `hyn doctor` reports any that are missing:

| Dependency | Needed for | If absent |
| --- | --- | --- |
| `bash` 5.0+ | everything — `EPOCHSECONDS` underpins every rate, cooldown and the heartbeat stamp | nothing runs; Ubuntu 22.04 ships 5.1, 24.04 ships 5.2 |
| `systemd` | the resident agent and the five timers | the CLI still works, nothing is scheduled, no heartbeat |
| `curl` | the portal, the npm registry, speed tests | no beat, no update check, no throughput test |
| `ca-certificates` | verifying every https endpoint above | every request fails certificate verification |
| `iputils-ping` | first-hop and internet latency | latency falls back to a TCP handshake |
| `node` 18+ and `npm` | delivery and self-update only — never at runtime | the package cannot install or update itself |
| `python3`, `postgresql` | `test/` and `supabase/` only | the test suites skip |

Terminals down to 80×24 are supported — the layout drops panels rather than
wrapping, and the network graph and node health badge are the last things to go.
Without a UTF-8 locale it falls back to ASCII glyphs automatically.

## Development

```
bash test/selfcheck.sh          # collectors, rendering, alerts, reports
bash test/cloud-integration.sh  # pairing and push against a mock endpoint
bash supabase/run-tests.sh      # schema and RPCs on a throwaway postgres
```

The self-check builds a synthetic `/proc` and `/sys` with hand-computed counters
and asserts the exact values the collectors should produce — that a counter delta
over 1000 ms is the rate claimed, that field 24 of `/proc/<pid>/stat` is RSS,
that a comm containing `)` doesn't shift every field after it, that a counter
going backwards reports zero instead of a fabricated spike, and that no rendered
row exceeds the terminal width at 140, 80, or 40 columns. It needs no framework
and no network.

The cloud checks need `python3` (mock HTTP endpoint) and `postgresql` (a
temporary cluster, created and destroyed by the script). Neither touches a real
Supabase project or the network.

## Legal and scope

**Independent tool, no affiliation.** hyn-view is an independent system monitor.
It is **not affiliated with, endorsed by, sponsored by or partnered with**
Highway P2P (`highwayp2p.com`), Hiway Network, or any other node, relay,
bandwidth-sharing or infrastructure platform. Where such software is named, it is
named only to describe what this tool can *observe* — trademarks belong to their
owners and no endorsement is implied.

**It observes; it does not participate.** Its purpose is measuring computer
resource usage — processor, memory, storage, temperature, throughput, latency.
It contains **no** wallet, keys, addresses or transactions; does **no** mining,
staking or validating; issues no token; relays no traffic; and makes no
representation that any activity earns anything. It is not a cryptocurrency,
investment or financial product, and nothing here is financial advice.

**Not independently verified.** Written to one client's requirements, not audited
or certified by anyone. No warranty — see `LICENSE`. Readings come from sensors
and counters that are themselves often wrong, and a value that cannot be read is
reported as unavailable rather than as zero. Don't make it the only safeguard for
anything expensive.

**It cannot tell you a machine is down.** If the box stops, so does the agent, so
it reports nothing. Silence never means healthy — see "Detecting a dead server".

**Your responsibility.** Only monitor machines you own or are authorised to
monitor. Server identifiers and telemetry can be personal or confidential in
context. Access details are excluded from notifications by default; setting
`notify_access_details=on` includes run-as/session usernames, session source IPs
and the worst rejected-login IP. If you enable it, make sure you have a lawful
basis, minimise destinations and notify affected people as required.

Full documents: [`DISCLAIMER.md`](DISCLAIMER.md) ·
[`PRIVACY.md`](PRIVACY.md) · [`TERMS.md`](TERMS.md) ·
[`ACCEPTABLE_USE.md`](ACCEPTABLE_USE.md) · [`SECURITY.md`](SECURITY.md) ·
[`SUBPROCESSORS.md`](SUBPROCESSORS.md) ·
[`DATA_PROCESSING_ADDENDUM.md`](DATA_PROCESSING_ADDENDUM.md) ·
[`LICENSE`](LICENSE). The portal source includes corresponding routes at
`/legal`, `/privacy`, `/terms`, `/acceptable-use`, `/security`, `/subprocessors`
and `/dpa`; a deployment is required before local policy changes appear on the
hosted domains.

## Author

Developed and maintained by **NEXUSV TECHNOLOGIES PRIVATE LIMITED**.

Official sites: [www.hyn-view.in](https://www.hyn-view.in) ·
[www.hyn-view.info](https://www.hyn-view.info) ·
Contact: [vivek.aryanvbw@gmail.com](mailto:vivek.aryanvbw@gmail.com)

Attribution appears on the dashboard status bar, in the `ABOUT` panel (`h`), in
`hyn about`, and in the footer of every alert and daily report.

## Licence

MIT © 2026 NEXUSV TECHNOLOGIES PRIVATE LIMITED
