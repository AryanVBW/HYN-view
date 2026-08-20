# Privacy Policy

**Last updated: 19 August 2026**

> Before publishing: replace every `[BRACKETED]` placeholder, decide the items
> marked **DECIDE**, and have a lawyer in your jurisdiction review this. If you
> operate the portal for clients in the EU/UK you are a **data controller** and
> obligations apply to you regardless of what this document says. This draft is
> not legal advice.

---

## 1. Who this applies to, and who is responsible

hyn-view has two parts, and it matters which one you are using.

**The agent** is a shell program that runs on a server you administer. Used on
its own, it reads local counters and prints them to your terminal or emails them
to an address you configure. It **transmits nothing to the Author**, contains no
analytics or telemetry about you, and requires no account.

**The portal** is an optional web dashboard. If you link a server to a portal,
that server begins sending telemetry to the portal's database.

The portal is not operated by the Author as a public service. Whoever deploys it
operates it and is the **data controller** for the data in it. For the deployment
you are using, that is:

- **Controller:** [YOUR LEGAL NAME / COMPANY]
- **Contact:** [CONTACT EMAIL]
- **Address:** [POSTAL ADDRESS]
- **Data protection contact:** [DPO OR CONTACT, if applicable]

If you self-host the portal, you are the controller for your own deployment and
this document is a template you should adapt.

## 2. What the agent reads on the monitored machine

All of the following is read locally from the operating system. Unless you link
the machine to a portal, it stays on the machine.

**System and hardware**
Hostname, operating system and distribution, kernel version, uptime, processor
model, core count, per-core clock speeds, governor and clock limits, and every
temperature sensor the hardware exposes.

**Resource usage**
Processor utilisation split by user/system/iowait/steal, load average, pressure
stall information, memory and swap usage, per-filesystem capacity and free space,
and disk throughput and utilisation.

**Network**
Per-interface throughput, totals, errors and drops; negotiated link speed,
duplex, MTU and MAC address; TCP connection-state counts, retransmit rates,
listen-queue drops and connection-tracking usage; the interface name and its
local IP address; latency and packet loss to the configured probe targets; the
machine's **public IP address** (if `public_ip=on`); and, on wireless links, the
network name (SSID) and gateway.

**Processes**
The process list, and for the highest-consuming processes: process ID, command
name, CPU and memory use, thread and descriptor counts, and **the account name of
the user running the process**.

**Accounts and access — read this part carefully**
The agent reads **who is currently logged in**, including the account name, the
terminal, the **source network address of the remote session**, and the login
time. It also counts **rejected SSH authentication attempts** in the reporting
window. It reads the account it is itself running as, and the account that
invoked it via `sudo`.

**Service state**
systemd unit names and states, failed units, and — only if node tracking is
enabled — the unit states, restart counts, resource use and **counts of error and
warning lines from the last hour of the journal** for the tracked service, plus
the version recorded on disk.

### Why the access data is there

An unrecognised remote login is often the most important line in a daily report
about a server that runs unattended. That is a deliberate design decision, and it
means reports and alerts can contain personal data. If you do not want it, see
§ 8.

## 3. What is sent to the portal, if you link a server

Only when you run `sudo hyn link` and approve it does a server transmit anything.
Each push (by default every five minutes) sends the measurements in § 2 —
including **the account names of the owners of top processes** — plus the node's
name, hostname, operating system, agent version, the alert rules currently
firing, and the last throughput-test result. The complete payload is also stored
verbatim as JSON so the dashboard can add panels later.

The agent additionally reports, after attempting to send a notification: the
channel used, the destination, the message subject, whether it succeeded, and the
error if it failed.

**What is not sent to the portal:** file contents, directory listings, command
arguments, environment variables, keystrokes, journal or log line text, database
contents, application data, or the source addresses of logged-in sessions.

**Note the asymmetry:** session account names and source addresses **are** placed
in the body of alert and daily-report messages delivered to your own notification
channels (your email inbox, your push topic), because that is where they are
useful. They are not written to the portal database.

## 4. What the portal stores about you

- **Account:** your email address, and your name if you provide one. Handled by
  Supabase Auth. If you sign in with Google, Google supplies your email address
  and account identifier to the portal; the portal never receives your Google
  password.
- **Authentication:** a session cookie so you stay signed in. This is strictly
  necessary for the service to function. **The portal sets no advertising,
  profiling or third-party tracking cookies.**
- **Your servers:** for each linked machine, its name, hostname, operating
  system, agent version, when it was paired, when it last reported, its
  administrative status, and its settings.
- **Notification channels:** the channel type, the destination (email address,
  push topic, chat ID or webhook host) and, if you choose to store it centrally,
  the **provider API key or password**. See § 7 on that choice.
- **Notification history:** every delivery attempt, with channel, destination,
  subject, result and failure reason.
- **Telemetry:** everything in § 3.
- **Administrative record:** if an administrator pauses, suspends, revokes or
  changes the role of your account or a machine, that action is recorded with
  the administrator's identity, the reason given and the time.

Pairing codes are stored only as a hash and are deleted after they expire.

## 5. Who can see it

- **You**, for your own account and machines. This is enforced in the database by
  row-level security, not merely by the interface.
- **Administrators of this deployment.** An administrator can read every
  client's machines, telemetry and notification history, and can pause, suspend
  or revoke any machine or account. If you did not deploy the portal yourself,
  assume its operator can see your telemetry. Currently: [WHO HAS ADMIN ACCESS].
- **Sub-processors**, listed in § 6, to the extent needed to run the service.
- **Nobody else.** Your data is **not sold, rented, shared for advertising,
  used to train models, or disclosed to third parties**, except where required
  by law, and then only to the extent required.

## 6. Sub-processors and third-party services

**Always involved when the portal is used**

| Service | Purpose | Data involved |
| --- | --- | --- |
| Supabase | Database, authentication, hosting of the backend | Everything in §§ 3–4 |
| [HOSTING PROVIDER, e.g. Vercel] | Serving the dashboard | Request metadata, IP address |

**DECIDE and state:** the region your Supabase project runs in
(`[REGION]`), and, if data leaves your users' jurisdiction, the transfer
mechanism you rely on.

**Involved only if you configure or enable them**

| Service | When | What it receives |
| --- | --- | --- |
| Google | Only if you sign in with Google | Authentication with Google; Google tells the portal your email address |
| Resend / Brevo / your SMTP provider | Only if configured as a channel | The notification, including its body, and the recipient address |
| ntfy / Telegram | Only if configured | The notification and the topic or chat ID |
| Slack / Discord (webhook) | Only if configured | The notification |
| healthchecks.io or equivalent | Only if a ping URL is set | A signal that the machine is alive or in trouble |

**Contacted by the agent on the monitored machine**

| Endpoint | Purpose | Disable with |
| --- | --- | --- |
| `api.ipify.org`, then `ifconfig.me` | Discover the machine's public IP | `public_ip=off` |
| `1.1.1.1`, `8.8.8.8` (configurable) | Latency and packet-loss probes | `latency_targets=` |
| `cloudflare.com` (configurable) | DNS resolution-time probe | `dns_probe=off` |
| `speed.cloudflare.com` | Throughput tests, when run | `speedtest_per_day=0` |
| `registry.npmjs.org` | Check for a newer release | `auto_update=off` |
| `install.hiwaynetwork.io` | Only if node tracking is on: compares the installed node version against the published one | `highway_update_check=off`, or `highway_track=off` |

These are ordinary network requests, so the operator of each endpoint will see
your machine's IP address. None of them receive your telemetry.

## 7. The choice about credentials

You can store notification provider credentials in **either** place:

- **In the portal.** Convenient — you change them in a browser and every server
  picks them up. The cost: the credential is in the database, so whoever can read
  that database could read it. It is protected by being **write-only from any
  browser session** — the dashboard can replace a key but cannot display one —
  and it is released only to a server presenting its own node token.
- **On the machine**, in `/etc/hyn-view/secrets`, mode `0600`, root only. A
  credential set there overrides the portal, so central storage is entirely
  optional.

Node tokens and pairing codes are stored **only as SHA-256 hashes**; the
plaintext exists only in transit. Tokens are never placed in command-line
arguments, so other local users cannot read them from the process list. The
service-role key that would bypass database access controls is never given to an
agent.

## 8. Reducing what is collected

The agent is configurable, and every one of these is a supported setting:

| To stop collecting | Set |
| --- | --- |
| The public IP address | `public_ip=off` |
| Node/service tracking entirely | `highway_track=off` |
| Latency probes to third parties | `latency_targets=` (empty) |
| DNS probes | `dns_probe=off` |
| Throughput tests | `speedtest_per_day=0` |
| Update checks | `auto_update=off` |
| Sending anything to a portal | never run `hyn link`, or run `sudo hyn unlink` |
| Local metric history | `metrics_keep_days=0` |

To exclude logged-in-session details and rejected-authentication counts from
messages, do not enable the daily report (`report_enabled=off`); that is the
feature which includes them.

## 9. How long it is kept

| Data | Retention |
| --- | --- |
| Telemetry in the portal | **30 days**, then deleted automatically by the database |
| Local metric history on the machine | `metrics_keep_days`, **8 days** by default |
| Notification history | Until you delete the account, unless you ask for removal |
| Administrative audit records | Retained as a security record: [STATE PERIOD] |
| Account details | Until you delete the account |
| Pairing codes | Expire in 15 minutes; purged within the hour |

## 10. Legal bases (UK/EU GDPR)

**DECIDE which apply to your deployment and delete the rest.**

- **Contract** — to provide the dashboard you asked for.
- **Legitimate interests** — keeping the service secure, preventing abuse, and
  the administrative oversight described in § 5. Balanced against your interests;
  ask us for the assessment.
- **Consent** — where you actively choose to store a provider credential
  centrally, or to sign in with Google. Withdrawable at any time.

Where telemetry identifies **your** users rather than you — a colleague's account
name in a process list, for example — **you** are the controller for that data
and you are responsible for informing them. See `DISCLAIMER.md` § 5.

## 11. Your rights

Subject to applicable law you may request access to your data, correction,
deletion, a portable copy, restriction of processing, or object to processing.
Write to [CONTACT EMAIL]; we aim to respond within 30 days.

You can act on most of this yourself:

- **Stop collection now** — `sudo hyn unlink` on the machine.
- **Cut a machine off from the portal** — revoke it in the dashboard. This
  invalidates its token permanently.
- **Delete a machine and all of its telemetry** — delete the node in the
  dashboard; its metrics, speed tests and alerts are removed with it.
- **Delete demo data** — one click, wherever it is shown.
- **Delete your account** — [DESCRIBE THE PROCESS, e.g. email us]. Deleting the
  account removes the profile, machines, channels, telemetry and notification
  history.

If you are in the EEA or UK you may complain to your supervisory authority; in
the UK that is the ICO.

## 12. Security

Access is restricted per account in the database itself, not only in the
interface. Credentials are hashed or held in a column no browser session can
read. Secrets on the machine are `0600` and root-only. Message bodies pass
through restricted-permission temporary files rather than command-line
arguments. Text taken from system journals is escaped before it is placed in
JSON, because it is attacker-influenced input.

No system is perfectly secure and no guarantee is given. If you find a
vulnerability, please report it to [SECURITY CONTACT EMAIL] rather than
disclosing it publicly.

## 13. Children

This is server administration tooling and is not directed at children. It is not
knowingly offered to anyone under [16 / 13 — **DECIDE**].

## 14. Automated decision-making

Alert rules compare measurements against thresholds you configure. No profiling
or automated decision-making producing legal effects is performed.

## 15. Changes

Material changes will be announced by [HOW: email / a notice in the dashboard]
before taking effect, and the date above will be updated.

---

**Contact:** [CONTACT EMAIL]
