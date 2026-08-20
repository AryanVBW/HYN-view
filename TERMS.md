# Terms of Use

**Last updated: 19 August 2026**

> Before publishing: replace every `[BRACKETED]` placeholder, choose a governing
> law, and have a lawyer in your jurisdiction review this. Liability caps and
> warranty exclusions are the clauses most often unenforceable if drafted badly
> or if consumer law applies. This draft is not legal advice.

---

## 1. Agreement

These terms govern your use of the hyn-view **portal** operated by
[YOUR LEGAL NAME / COMPANY] ("we", "us") at [PORTAL URL] ("the Service"), and
they accompany the software itself.

Your rights to **the software** are granted by the MIT licence in `LICENSE` and
are not restricted by these terms. Where the two differ about the software, the
licence governs.

By creating an account or linking a server you accept these terms. If you do not
accept them, do not use the Service — the agent works without it.

## 2. What the Service is

The Service displays system measurements — processor, memory, storage,
temperature and network usage — reported by servers you choose to link, and
records the notifications sent about them. That is all it is.

The Service is **not**: a cryptocurrency, financial, investment or payment
product; a wallet or custodian; a mining, staking, validation or bandwidth-sharing
service; a means of earning income; or a safety, industrial-control or
life-critical system. Nothing in it is investment, financial, tax or legal
advice. See `DISCLAIMER.md`.

We are **not affiliated with Highway P2P (`highwayp2p.com`) or any other node,
relay or infrastructure platform**, and we do not act on their behalf. If you run
such software, your relationship is with that platform and is governed by its
terms, to which we are not a party.

## 3. Eligibility and your authority to monitor

You must be able to form a binding contract and be at least [16 / 18 — DECIDE].

**You may only link a machine you own or are authorised by its owner to
monitor.** By linking a machine you confirm that you have that authority, that
monitoring it and transmitting its telemetry to the Service is lawful where you
and the machine are located, and that it does not breach any contract or hosting
policy applying to it.

Where telemetry identifies people — for example the account name of a user
running a process — you confirm you have a lawful basis to collect it and will
inform them as required. For that data you are the controller and we process it
on your behalf. See `PRIVACY.md`.

## 4. Accounts and credentials

You are responsible for your account, for everything done under it, and for the
security of the node tokens issued to your machines. Tell us promptly at
[CONTACT EMAIL] if you believe either has been compromised, and revoke the
affected machine in the dashboard.

Do not share an account, or attempt to reach data belonging to another client.

## 5. Acceptable use

You must not:

- link or monitor a machine you are not authorised to monitor;
- attempt to access another client's data, or to obtain administrative
  privileges you were not granted;
- probe, load-test, scrape or disrupt the Service, or circumvent its rate,
  quota or access controls;
- send unlawful, deceptive or abusive content through the notification features,
  or use them to send unsolicited bulk messages;
- use the Service to build a competing dataset about third parties, or to
  monitor people rather than machines;
- submit deliberately falsified telemetry;
- use the Service where doing so would breach sanctions or export controls
  applying to you.

## 6. Your content

You keep all rights to the telemetry and configuration you submit. You grant us
only the limited permission needed to store, process and display it back to you
and to operate and secure the Service. We claim no ownership, and we do not use
your data for advertising or to train models.

## 7. Availability, and our right to pause or suspend

The Service is provided **without any service-level commitment**. It may be
unavailable for maintenance, and it may change or be discontinued. If we
discontinue it we will give [NOTICE PERIOD] notice where practical and allow you
to export your data.

We may **pause**, **suspend** or **revoke** a machine, or **suspend** an account,
where we reasonably believe it is necessary to protect the Service, to comply with
law, or because these terms have been breached; and for scheduled maintenance.

- A **pause** stops telemetry being accepted, and may be time-limited so that it
  ends by itself.
- A **suspension** stops it until we lift it.
- A **revocation** invalidates a machine's credential permanently; the machine
  must be paired again.

**While a machine is paused, suspended or revoked, no telemetry is recorded and
no alerts are generated for it.** Except where a breach or a legal requirement
makes it impractical, we will tell you and give a reason. These actions are
recorded in an audit log. Where the reason is not urgent we will give notice
first.

## 8. Fees

**DECIDE — pick one and delete the other.**

*If free:* The Service is currently provided free of charge. If we introduce
charges we will give at least [NOTICE PERIOD] notice, and you may stop using it
instead.

*If paid:* Fees, billing period and refund terms are as set out at
[PRICING URL]. Fees are [exclusive/inclusive] of tax. Non-payment may result in
suspension after notice.

## 9. Third-party services

The Service depends on third parties, including Supabase and [HOSTING PROVIDER],
and — only where you configure them — notification providers. Your use of those
services may be governed by their own terms. **We are not responsible for
third-party services, their availability, or their handling of data**, and an
outage or failure at one of them is not a breach of these terms by us.

## 10. Accuracy — the important limitation

Measurements come from counters and sensors reported by your own operating system
and hardware, which are regularly incomplete or wrong. **We do not warrant that
any figure, alert or absence of an alert is accurate, timely or complete.**

In particular, and by design:

- **If a monitored machine goes down, so does the agent on it — and it therefore
  reports nothing. Silence never means "healthy."** Detecting an unreachable host
  requires an independent external service; see `README.md`.
- Notifications depend on third-party providers and may be delayed, throttled,
  filtered as spam, or lost.
- A daily quota exists to prevent a misbehaving rule exhausting your provider's
  limit; once reached, further messages are suppressed.
- The software has not been independently audited or verified.

**Do not rely on the Service as the sole safeguard for any system where failure
carries meaningful cost.** Keep independent monitoring for anything important.

## 11. Disclaimer of warranties

To the fullest extent permitted by law, the Service and the software are provided
**"as is" and "as available", without warranties of any kind**, express, implied
or statutory, including merchantability, fitness for a particular purpose,
accuracy, uninterrupted or error-free operation, and non-infringement.

## 12. Limitation of liability

To the fullest extent permitted by law:

- We are not liable for indirect, incidental, special, consequential, punitive or
  exemplary damages, nor for lost profits, lost revenue, lost or corrupted data,
  business interruption, or damage arising from an undetected fault, a missed or
  false alert, or reliance on any figure the Service displays — even if we were
  advised such damage was possible.
- Our total aggregate liability arising from or in connection with the Service is
  limited to the greater of **[the fees you paid us in the 12 months before the
  claim]** and **[AMOUNT, e.g. USD 100]**.

**Nothing in these terms limits liability which cannot lawfully be limited**,
including for death or personal injury caused by negligence, or for fraud or
fraudulent misrepresentation. If you are a consumer, your statutory rights are
unaffected. Some jurisdictions do not permit some of these exclusions, in which
case they apply to you only to the extent permitted.

## 13. Indemnity

You will indemnify us against claims, losses and reasonable costs arising from
your breach of these terms, from your monitoring of a machine you were not
authorised to monitor, or from telemetry you submitted that identified a person
without a lawful basis.

## 14. Termination

You may stop at any time: `sudo hyn unlink` on each machine, then ask us to
delete your account. We may terminate for material breach, or on
[NOTICE PERIOD] notice if we discontinue the Service.

On termination your data is deleted as described in `PRIVACY.md`. Sections 6, 11,
12, 13 and 16 survive.

## 15. Changes to these terms

We may change these terms. Material changes will be announced by
[HOW: email / a dashboard notice] at least [NOTICE PERIOD] before they take
effect. Continuing to use the Service after that constitutes acceptance; if you
disagree, stop using it and ask us to delete your account.

## 16. Governing law and disputes

These terms are governed by the laws of **[JURISDICTION]**, and the courts of
**[JURISDICTION]** have [exclusive/non-exclusive] jurisdiction, without affecting
any right you have as a consumer to bring proceedings where you live.

**DECIDE:** whether to require informal resolution first — contacting
[CONTACT EMAIL] and allowing 30 days — before formal proceedings.

## 17. General

These terms and the documents they reference are the entire agreement between us
about the Service. If a provision is unenforceable the rest continues to apply.
Our not enforcing a provision is not a waiver of it. You may not assign these
terms without our consent; we may assign them to a successor of our business.
Nothing here creates a partnership, agency or employment relationship.

---

**Contact:** [CONTACT EMAIL]
**Operator:** [YOUR LEGAL NAME / COMPANY], [POSTAL ADDRESS]
