# hyn-view

A network-first terminal monitor for Ubuntu Server, for boxes that run 24/7 and
are watched by a human.

It covers what `htop` and `btop` cover, but inverts the priority: the network is
the headline, not the CPU. It also tracks a [Highway](https://highwayp2p.com)
relay node (`hw-os`) if one is installed — strictly read-only.

```
npm install -g hyn-view
sudo hyn setup      # guided: notifications, alerts, daily report, timers
hyn                 # dashboard
```

## First launch

Run `hyn` on a fresh install and it offers a guided setup before it draws
anything. Eight steps, about two minutes, and every question has a default that
is right for a 24/7 relay node — holding Enter through the whole thing produces a
good configuration.

```
Step 1 of 8  What we found          detected hardware, WAN link, filesystems, node
Step 2 of 8  Display mode           best looking, or best performing
Step 3 of 8  Theme                  all six drawn live in your terminal
Step 4 of 8  Units and layout       bits or bytes, refresh rate, rows
Step 5 of 8  Where alerts go        email (Resend recommended) or push
Step 6 of 8  What counts as a problem
Step 7 of 8  Daily report and speed tests
Step 8 of 8  Outage detection and updates
```

It shows what it *detected* before asking for anything — being told "Ubuntu
24.04, 8 cores, 31 GiB RAM, eth0 at 1 Gbps, Highway node v0.1.75 active" earns
the right to ask for an API key. Nothing is written until you confirm a summary,
so abandoning halfway leaves no trace. It ends by sending a real test message,
because a notification setup you have not seen arrive is not configured — it is
hoped for.

Asked once. Declining is remembered, and the dashboard works fine without it
(alerts and reports do not). Re-run any time:

```
hyn onboard               full guided setup again
sudo hyn wizard           just the notification part
sudo hyn setup            just the config and timers, no questions
hyn config set <k> <v>    one setting, scriptable
```

Set `onboarding=off` to suppress the prompt entirely.

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

  Then, every 5 minutes ────────────────── hyn push → Supabase → dashboard
```

```
sudo hyn link          pair this machine (asks for the project URL and anon key)
sudo hyn setup         install the 5-minute push timer
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
3. On the server, `sudo hyn link`, then follow the code.

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

Once a node is paired the dashboard can manage its ordinary monitoring settings.
The box keeps its portal connection details and its notification delivery
configuration locally. Provider destinations and credentials are never pulled
from or stored in the portal.

```
hyn config pull        fetch monitoring settings from the portal
hyn cloud status       what was pulled, when, and the node's administrative state
```

Every scheduled `hyn push` performs that pull before collecting and sending its
reading, so portal changes apply on the next check-in without a second timer.
`hyn config pull` remains useful when an operator wants to apply a change
immediately.

`/account` in the portal shows the client account, node settings and every
delivery attempt with the reason any of them failed. Thresholds, report time and
push interval are edited there per server. Notification channels are configured
on each server with `sudo hyn wizard`.

A pulled setting is written to a cache that `cfg_load` reads **before**
`/etc/hyn-view/config`, so a line set locally on the box still wins. That
ordering is deliberate: central management that silently reverts an operator who
edited a machine at 3am for a reason is worse than no central management, and a
cache that outranked explicit local config would be impossible to debug.

### What the agent sends

One push carries, per node: CPU percent split by user/sys/iowait/**steal**, load,
**per-core clock speeds** with the governor and the hardware's floor and ceiling,
**every temperature sensor the platform exposes** (not just the CPU package — an
NVMe at 70°C is what explains a fan that will not stop), memory and swap, every
real filesystem with its size and projected pressure, WAN throughput with errors,
drops, retransmits, **negotiated link speed and duplex**, TCP state distribution,
conntrack headroom, PSI for cpu/memory/io, first-hop and internet latency, the
last speed test, process count and the **top processes by cpu and rss**, and
every alert currently firing.

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

| Control | Effect |
| --- | --- |
| **Pause** | Stops accepting readings. Optionally for N minutes, after which it resumes by itself. |
| **Suspend** | Stops accepting readings until an administrator lifts it. |
| **Revoke** | Invalidates the node token. Not reversible from the portal — the machine must be paired again. |
| **Suspend client** | Suspends the account and, with it, every machine the client owns. |

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
| Supabase anon key | `/etc/hyn-view/config` (0644) | Public by design — it ships in every browser bundle. RLS is what protects data. |
| Node token | `/etc/hyn-view/secrets` (0600) | The actual credential. Sent in a request body, never in `argv`, so no local user can read it out of `ps`. |
| Service-role key | nowhere | The agent never has one. A monitoring agent on a rented VPS is the wrong place for a key that bypasses RLS. |
| Provider API keys and webhook credentials | `/etc/hyn-view/secrets` (0600) | Configured separately on each monitored server; never stored in or delivered by the portal. |

**Notification delivery is local-only.** Run `sudo hyn wizard` on each monitored
server. Destinations live in `/etc/hyn-view/config`; API keys, passwords, tokens
and webhook URLs live in `/etc/hyn-view/secrets`. The portal receives delivery
outcomes for its history view, but it has no table or RPC for provider
credentials and a config pull never returns a notification channel.

Administrators may edit the non-secret HTML wrappers for incident alerts and
daily reports from the Email templates tab. A wrapper must contain
`{{content}}`; optional placeholders include `{{hostname}}`, `{{version}}`,
`{{severity}}` and `{{subject}}`. The node pulls the wrappers as base64 alongside
ordinary settings and applies them around the locally generated message at send
time. Active HTML is rejected, while the generated incident detail remains
unescaped inside `{{content}}`; credentials and recipients never cross into this
template store.

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

The real fix is a dead man's switch: this host checks in on a schedule and an
outside service alerts *you* when the check-ins stop.
[healthchecks.io](https://healthchecks.io) is free and self-hostable. The wizard
asks for a ping URL, and the alert run pings the `/fail` endpoint when something
is critical, so a box that is up but broken also trips it.

## Daily report

Every message — alert or report — names the account it ran as, the human who set
it up if it was via sudo, and who is logged into the box right now with their
source address and login time. On a server that runs unattended, "an ssh session
from an address I do not recognise" is a more useful line than most performance
numbers. The report also counts rejected SSH authentications for the window,
labelled as a trend rather than an incident, because on an internet-facing host
that number is never zero.

One message a day. Performance with averages, peaks and minutes spent busy;
storage with the 24h change and a projected fill date; network totals, peak
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

## Channels

| Channel | Free tier | Notes |
| --- | --- | --- |
| `resend` | 100/day, 3,000/month | Quickest to set up. Without a verified domain you send from `onboarding@resend.dev` **to your own Resend account address only** — fine for alerting yourself. |
| `brevo` | 300/day | 3× the daily headroom; needs a verified sender. |
| `smtp` | — | Any provider, including a Gmail app password. No third-party account. |
| `ntfy` | free | No account at all. Instant phone push. The topic name is the only access control, so make it long. |
| `telegram` | free | Bot token from @BotFather. |
| `webhook` | free | Slack or Discord incoming webhook. |

Configure several; all are attempted. Email for the daily report and push for
3am alerts is a good pairing.

API keys live in `/etc/hyn-view/secrets` at mode `0600`, never in the
world-readable config. Two further rules are enforced in code: secrets are never
passed in `argv` (where any user could read them out of `ps`) and message bodies
go through a `0600` temp file for the same reason. Everything interpolated into
JSON is escaped first because alert and service text can be attacker-influenced.

`notify_max_per_day` (default 50) is a hard backstop so a flapping rule cannot
burn a provider's quota and drop the one message that mattered.

## Updates

On launch hyn checks the npm registry for a newer release. The check is cached
for 12 hours, runs detached, and never delays startup; a newer version shows as a
badge in the status bar.

```
hyn update --check    just look
sudo hyn update --yes install it
```

`auto_update=install` will apply updates unattended. It is **not** the default,
deliberately: that means this tool running `npm i -g` as root on a production
node, so a bad release or a compromised registry account lands on the box by
itself, and a monitor that breaks itself at 3am is worse than one a version
behind. Your call, and the wizard asks.

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
from the dashboard, so it works whether or not anyone is looking. Email via
Resend, Brevo or plain SMTP; push via ntfy or Telegram; or a Slack/Discord
webhook. Plus one daily report covering performance, throughput, storage trend,
connection details and node status.

## Views

| Key | View |
| --- | --- |
| `1` | dashboard |
| `2` | network detail — all interfaces, kernel tuning snapshot |
| `3` | processes |
| `4` | Highway node detail + recent journal warning counts |
| `h` | keys, paths and about |

Other keys: `t` cycle theme, `p` switch visual profile, `u` bits/bytes, `m` sort
by cpu/mem, `i` cycle interface, `s` run a speed test now, `+`/`-` refresh rate,
`r` redraw, `q` quit.

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
hyn notify status | test  delivery configuration, or send a test message
hyn record                sample metrics once

sudo hyn link             pair with the web portal (device-code flow)
sudo hyn unlink           forget the portal credential
hyn push                  send one reading to the portal
hyn config pull           fetch monitoring settings from the portal
hyn cloud status          node id, last push, and any error

hyn update [--check] [--yes]
hyn about                 author, licence, version
hyn theme list | set <name> | preview <name>
hyn config show | get <k> | set <k> <v> | path | edit
hyn doctor                what works on this machine, and what does not
sudo hyn setup            guided setup: config, secrets, timers, notifications
sudo hyn wizard           re-run just the notification setup
sudo hyn uninstall        remove units (add --purge to drop config and history)
```

Four systemd timers are installed: alert evaluation (every 5 min), metric
sampling (every 5 min), throughput tests (4×/day), and the daily report. A fifth,
the portal push (every 5 min), is installed too but only enabled once the node is
paired. All run as one-shots with `ProtectSystem=strict`, an empty capability set
and a single writable path.

`hyn snapshot --json` is the integration point. It emits one object with the
network counters, latency map, speed test result, and node health, so it can be
piped into whatever alerting you already run.

## Highway node tracking

If `/usr/local/bin/highway` exists, the node panel shows unit states and restart
counts, cgroup memory, process CPU/RSS/threads/fds, the Nebula mesh interface
and its traffic, the qdisc on the WAN interface, congestion control, error and
warning counts from the last hour of journal, and the installed version against
the currently published one.

**It never changes anything.** No `systemctl start/stop/restart/enable`, no
writes under `/etc/highway`, `/var/lib/highway` or `/opt/highway`, no `tc` or
`nft` subcommand other than `show`/`list`. The test suite greps the source to
enforce this, so it cannot regress quietly.

The node binary is **not executed** to read its version. Running a validator's
own binary next to a live instance to ask a question is not something a monitor
should do, so the version is read from on-disk files, systemd unit metadata, and
the journal instead. If none of those answer, the panel says so. Set
`highway_version_probe=exec` to opt into running `highway --version`.

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
| `interval` | `1.0` | seconds. `2.0`–`3.0` is lighter still |
| `net_unit` | `bits` | how links are sold; `bytes` if you prefer |
| `panels` | `net,cpu,mem,node,proc,disk` | **order is priority** — the last ones are dropped first on a short terminal |
| `graph` | `braille` | `block` is ~⅓ cheaper and coarser; `off` drops graphs entirely |
| `wan_iface` | `auto` | follows the default route |
| `latency_targets` | `1.1.1.1,8.8.8.8` | plus the gateway, probed separately |
| `speedtest_per_day` | `4` | drives the systemd timer schedule |
| `speedtest_guard_pct` | `25` | skip a scheduled test if the link is busier than this |
| `speedtest_provider` | `auto` | prefers Ookla `speedtest`, then `speedtest-cli`, then `curl` |
| `highway_track` | `on` | node panel |
| `profile` | `best` | `best` or `performance` |
| `notify_channels` | *(empty)* | comma separated; nothing is sent until set |
| `notify_access_details` | `off` | set `on` only to include run-as/session usernames, session source IPs and the worst rejected-login IP in notifications |
| `alert_min_severity` | `warn` | `crit`, `warn` or `info` |
| `alert_repeat_hours` | `6` | reminder interval while still firing |
| `report_at` | `08:00` | server local time |
| `auto_update` | `check` | `off`, `check` or `install` |
| `onboarding` | `on` | offer guided setup on first interactive launch |
| `cloud_enabled` | `off` | set by `hyn link`; gates the portal push timer |
| `cloud_url` | *(empty)* | Supabase project URL |
| `cloud_anon_key` | *(empty)* | public anon key — see the credentials table above |
| `cloud_portal_url` | *(empty)* | only used to print a complete `/link` URL |
| `cloud_push_min` | `5` | minutes between portal pushes |
| `hide_mount` | `/snap,/var/lib/docker,…` | mount points kept out of the disk panel and alerts |

Themes: `hiway` (default), `nord`, `gruvbox`, `dracula`, `solar`, `mono`. Drop a
`.theme` file in `/etc/hyn-view/themes/` to add your own — they are 15 hex
colours, resolved at load into whatever the terminal supports (truecolor, 256,
16, or none).

## Requirements

Ubuntu 22.04 or 24.04 (anything with Linux `/proc` and bash 4.3+ will work).
Snap mounts are excluded automatically: they are read-only squashfs and therefore
permanently 100% full, so a box with twenty snaps would otherwise show twenty
filesystems and fire twenty disk-full alerts that could never clear.
`curl` for speed tests and the update check; `ping` for latency, falling back to
a TCP handshake when ICMP is filtered; `systemd` for unit tracking and the timer.
`hyn doctor` reports which of these you have.

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
