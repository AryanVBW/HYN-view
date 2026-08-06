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

`sudo hyn setup` asks the questions rather than leaving you to reverse-engineer a
config file: where alerts should go, what should trigger them, when the daily
report should arrive, and whether to watch for updates. It ends by sending a real
test message, because a notification setup you have not seen arrive is not
configured — it is hoped for.

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

One message a day. Performance with averages, peaks and minutes spent busy;
storage with the 24h change and a projected fill date; network totals, peak
rates, retransmit share and latency; every LAN and WAN interface with its type,
address, state and traffic, plus SSID, gateway and DNS; throughput tests against
your all-time best; full Highway node status; and everything that fired.

It leads with a one-line verdict — `HEALTHY`, `MOSTLY HEALTHY`, `PLAN AHEAD`,
`DEGRADED` or `ATTENTION` — because that is what a phone notification shows.

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
JSON is escaped first — journal lines are attacker-influenced text.

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
| `4` | Highway node detail + recent journal warnings |
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
sampling (every 5 min), throughput tests (4×/day), and the daily report. All run
as one-shots with `ProtectSystem=strict`, an empty capability set and a single
writable path.

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
| `alert_min_severity` | `warn` | `crit`, `warn` or `info` |
| `alert_repeat_hours` | `6` | reminder interval while still firing |
| `report_at` | `08:00` | server local time |
| `auto_update` | `check` | `off`, `check` or `install` |

Themes: `hiway` (default), `nord`, `gruvbox`, `dracula`, `solar`, `mono`. Drop a
`.theme` file in `/etc/hyn-view/themes/` to add your own — they are 15 hex
colours, resolved at load into whatever the terminal supports (truecolor, 256,
16, or none).

## Requirements

Ubuntu 22.04 or 24.04 (anything with Linux `/proc` and bash 4.3+ will work).
`curl` for speed tests and the update check; `ping` for latency, falling back to
a TCP handshake when ICMP is filtered; `systemd` for unit tracking and the timer.
`hyn doctor` reports which of these you have.

Terminals down to 80×24 are supported — the layout drops panels rather than
wrapping, and the network graph and node health badge are the last things to go.
Without a UTF-8 locale it falls back to ASCII glyphs automatically.

## Development

```
bash test/selfcheck.sh
```

The self-check builds a synthetic `/proc` and `/sys` with hand-computed counters
and asserts the exact values the collectors should produce — that a counter delta
over 1000 ms is the rate claimed, that field 24 of `/proc/<pid>/stat` is RSS,
that a comm containing `)` doesn't shift every field after it, that a counter
going backwards reports zero instead of a fabricated spike, and that no rendered
row exceeds the terminal width at 140, 80, or 40 columns. It needs no framework
and no network.

## Author

**Vivek W (AryanVBW)** — [github.com/AryanVBW](https://github.com/AryanVBW)

Attribution appears on the dashboard status bar, in the `ABOUT` panel (`h`), in
`hyn about`, and in the footer of every alert and daily report.

## Licence

MIT © 2026 Vivek W (AryanVBW)
