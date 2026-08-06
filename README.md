# hyn-view

A network-first terminal monitor for Ubuntu Server, for boxes that run 24/7 and
are watched by a human.

It covers what `htop` and `btop` cover, but inverts the priority: the network is
the headline, not the CPU. It also tracks a [Highway](https://highwayp2p.com)
relay node (`hw-os`) if one is installed — strictly read-only.

```
npm install -g hyn-view
sudo hyn setup      # /etc config, state dir, scheduled speed tests
hyn                 # dashboard
```

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
| default (braille graphs, all probes) | ~4.9% of one core | ~50 ms | ~2 KB/s |
| `graph=block` | ~3.2% | ~33 ms | ~1.4 KB/s |
| `graph=braille`, `interval=2.0` | ~2.8% | ~28 ms | ~1.7 KB/s |

RSS is ~11 MiB, which is the bash interpreter itself. Getting here took real
work: the first version cost **1216 ms per frame**, almost all of it in one
innocuous-looking line — measuring a string's visible width with an extglob
pattern substitution. Peeling escape sequences off with plain prefix expansions
instead was 39× faster. There are comments at each of those places explaining why
the slower, more obvious form was rejected; please read them before tidying.

If you want it cheaper still: `graph=block` (coarser graphs, ~⅓ less work),
`interval=2.0` or `3.0`, or drop panels from `panels=`.

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

## Views

| Key | View |
| --- | --- |
| `1` | dashboard |
| `2` | network detail — all interfaces, kernel tuning snapshot |
| `3` | processes |
| `4` | Highway node detail + recent journal warnings |
| `h` | keys and paths |

Other keys: `t` cycle theme, `u` bits/bytes, `m` sort by cpu/mem, `i` cycle
interface, `s` run a speed test now, `+`/`-` refresh rate, `r` redraw, `q` quit.

## Commands

```
hyn                       dashboard
hyn net | proc | node     open on a specific view

hyn snapshot              one-shot reading for ssh, cron and alerting
hyn snapshot --json       same, machine readable
hyn speedtest [--json]    measure now and record it
hyn history [N] [--json]  recorded results

hyn theme list | set <name> | preview <name>
hyn config show | get <k> | set <k> <v> | path | edit
hyn doctor                what works on this machine, and what does not
sudo hyn setup            install /etc config + speed test timer
sudo hyn uninstall        remove them (add --purge to drop config and history)
```

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

## Licence

MIT
