# Disclaimer and Notices

**Last updated: 19 August 2026**

> Before publishing: replace every `[BRACKETED]` placeholder below, and have a
> lawyer in your jurisdiction review this document together with `PRIVACY.md`
> and `TERMS.md`. These documents were drafted to describe this software
> accurately; they are not legal advice and do not by themselves create legal
> protection.

---

## 1. No affiliation with any node platform or operator

hyn-view is an independent system-monitoring tool developed and maintained by
[YOUR LEGAL NAME] ("the Author").

The Author is **not affiliated with, endorsed by, sponsored by, partnered with,
or acting as an agent of** Highway P2P (`highwayp2p.com`), Hiway Network, or any
other network, node, relay, bandwidth-sharing, distributed-computing or
infrastructure platform, nor any operator, foundation, issuer or vendor
associated with them.

No such organisation has reviewed, approved, certified or supported this
software. No business relationship, joint venture, agency, licence or
partnership exists or is implied.

## 2. Why other products are named at all

This software can optionally read the state of node software already installed
on a machine by its owner, in order to display it. Naming that software is
necessary to describe what this tool observes and to let an operator find the
relevant feature. Such references are **nominative** — they identify a product
in order to describe interoperability, and nothing more.

All product names, trademarks, service marks and logos are the property of their
respective owners. Their use here does not imply any endorsement, affiliation or
association, and no claim of ownership is made over them.

If you are a rights holder and object to a reference in this project, contact
[CONTACT EMAIL] and it will be reviewed promptly.

## 3. What this software does — and does not — do

**It observes. It does not participate.**

hyn-view reads operating-system counters that the kernel already exposes to any
local user — `/proc`, `/sys`, `df`, `ping`, and `systemd` unit metadata — and
presents them. Its purpose is measuring **computer resource usage** (processor,
memory, storage, temperature, network throughput and latency) on machines the
operator already administers.

It contains **no** functionality for, and performs **no**:

| Not present | Meaning |
| --- | --- |
| Cryptocurrency of any kind | No wallet, no private keys, no seed phrases, no addresses, no transactions, no signing |
| Mining or proof-of-work | It does not mine, stake, validate, or contribute compute to any network |
| Token, coin, sale or offering | Nothing is issued, sold, distributed, or promoted |
| Trading, exchange, custody or payments | It moves no funds and holds no assets |
| Earnings, rewards or yield | It makes no representation that any activity produces income |
| Bandwidth resale or traffic relaying | It routes, proxies and relays nothing |
| Recruitment or referral | It does not enrol anyone in any programme or network |

**This software is not a cryptocurrency product, an investment product, or a
financial product, and nothing in it or its documentation is investment,
financial, tax or legal advice.**

### Read-only with respect to third-party software

Where optional node tracking is enabled, this tool is strictly read-only. It does
not start, stop, restart, enable, disable, install, update, configure or modify
any third-party software or its data. It does not execute a node binary in order
to inspect it, unless an operator explicitly opts in by setting
`highway_version_probe=exec`.

This is enforced mechanically, not merely promised: the test suite inspects the
source for mutating commands and fails the build if one appears
(`bash test/selfcheck.sh`, "read-only guarantee"). Tracking can be switched off
entirely with `highway_track=off`.

## 4. Not independently verified

This software was written to the requirements of a single client and has **not**
been independently audited, certified, benchmarked or verified by any third
party. No representation is made that:

- any measurement it reports is accurate, complete or fit for any purpose;
- any detection, threshold or alert will identify a real problem, or will not
  report a problem that does not exist;
- any notification will be delivered, or delivered in time to be useful;
- it is compatible with, or will continue to be compatible with, any version of
  any third-party software it can observe.

Measurements are derived from counters and sensors reported by the host operating
system and hardware. Those sources are themselves frequently wrong — a sensor
may be absent, mislabelled or miscalibrated, a virtualised host may report
fabricated values, and a counter may reset or wrap. Where a value cannot be read
this software reports it as unavailable rather than as zero, but it cannot detect
a value that is merely incorrect.

**Do not rely on this tool as the sole safeguard for any system where failure
carries meaningful cost.** It is an aid to a human operator, not a substitute for
one, and not a safety, medical, industrial-control or life-critical system.

### It cannot tell you a machine is down

If the monitored machine loses power, crashes or loses connectivity, the software
on it stops running too, and therefore reports nothing. Absence of an alert never
means a system is healthy. Detecting an unreachable host requires an independent
external service; see the "Detecting a dead server" section of `README.md`.

## 5. Operator responsibility

You are responsible for the machines you monitor and for how you use what you
learn from them. In particular you must ensure that:

- you own the monitored machine, or are authorised by its owner to monitor it;
- monitoring it, and transmitting its telemetry to wherever you send it,
  complies with the law applicable to you and to that machine, with any contract
  governing it, and with the policies of its hosting provider;
- where telemetry identifies people — for example the account names of logged-in
  users, the source addresses of remote sessions, or the owners of running
  processes — you have a lawful basis to collect it and you tell those people as
  required. See `PRIVACY.md` for exactly which fields are involved;
- you comply with any applicable terms of any third-party platform whose
  software you choose to observe with this tool. Those terms are between you and
  that platform; the Author is not a party to them.

Using this tool against a system you are not authorised to monitor may be
unlawful. The Author does not endorse or support such use.

## 6. No warranty

This software is provided **"as is", without warranty of any kind**, express or
implied, including but not limited to the warranties of merchantability, fitness
for a particular purpose, accuracy and non-infringement. See `LICENSE` for the
full text, which governs.

To the maximum extent permitted by law, the Author is not liable for any claim,
damage, loss or other liability — including lost profits, lost data, business
interruption, or damage arising from an undetected fault, a missed alert, a false
alert, or reliance on any figure this software displays — whether in contract,
tort or otherwise, arising from or in connection with this software or its use.

Some jurisdictions do not allow the exclusion of certain warranties or
liabilities, so parts of the above may not apply to you. Nothing here limits
liability that cannot lawfully be limited.

## 7. Third parties this software can contact

Running this tool causes network requests. Each is listed in `PRIVACY.md`
§ "Third-party services", with its purpose and how to disable it. In summary,
depending on configuration, it may contact: a public IP reflector, public DNS
resolvers for latency probes, a throughput-test endpoint, the npm registry for
update checks, your configured notification providers, your own portal backend,
and — only if node tracking is enabled — a version-manifest URL belonging to the
node software's distributor.

The Author does not control third-party services and is not responsible for
them. Their handling of any data is governed by their own terms and policies.

## 8. Independence of this document

If any provision here is found unenforceable, the remainder continues to apply.
This document describes the Author's position; it does not override `LICENSE`,
which governs your rights to use the software.

---

**Contact:** [CONTACT EMAIL]
**Author:** [YOUR LEGAL NAME] — <https://github.com/AryanVBW>
