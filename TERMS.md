# Terms of Use

**Effective date and last updated: 21 August 2026**

**Version: 1.0**

These Terms govern the HYN-view hosted dashboard available at
<https://www.hyn-view.in> and <https://www.hyn-view.info> (the **Hosted
Service**), operated by **NEXUSV TECHNOLOGIES PRIVATE LIMITED** ("NexusV",
"we", "us"). Contact: <vivek.aryanvbw@gmail.com>.

## 1. Acceptance and separate open-source licence

By registering, signing in, linking a server or otherwise using the Hosted
Service, you agree to these Terms and the [Privacy Policy](PRIVACY.md). If you do
not agree, do not use the Hosted Service.

The HYN-view software source code is separately licensed under the
[MIT License](LICENSE). The MIT License grants rights to copy, modify,
distribute, sublicense and sell copies of the software subject to its conditions.
These Terms do not take away those software-licence rights. They govern NexusV's
hosted accounts, infrastructure and services. Applicable law continues to apply
to every use of the software, even where the MIT License permits the use as a
matter of copyright.

## 2. What HYN-view is

HYN-view is a voluntary, informational server-health tool. It helps authorised
administrators view operating-system and hardware measurements such as CPU,
memory, storage, temperature, network and service health without relying only on
command-line tools. It can send configured alerts and reports.

HYN-view is not an autonomous administration, remediation, access-control,
security-response or malware-detection system. It does not guarantee that a
server is healthy, secure or available. It is not designed for medical,
emergency, nuclear, aviation, industrial-control, life-safety or other
high-risk use where an error or missed alert could cause death, injury or major
damage.

It is not a cryptocurrency, wallet, payment, trading, mining, staking,
validation, investment, yield, bandwidth-resale or income product. Nothing in
HYN-view is financial, investment, tax or legal advice.

## 3. Eligibility and registration

You must be at least **18 years old**, have legal capacity to accept these Terms
and provide accurate registration information. Registration is publicly
available and the Hosted Service is currently free, but registration does not
create a right to perpetual access, a service level or support at any particular
time.

You are responsible for activity under your account, for keeping session and
node credentials confidential, and for promptly revoking a compromised node.
Do not share an account in a way that defeats access controls. Report suspected
compromise to <vivek.aryanvbw@gmail.com>.

## 4. Authority to monitor

You may install, link or monitor HYN-view only on a server that you own or are
expressly authorised to administer. By linking a server, you represent that:

- you have the owner's authority to monitor it and transmit its selected
  telemetry;
- your use complies with law, employment or workplace requirements, contracts
  and hosting-provider policies that apply to you and the server;
- you have given any notice and obtained any permission required from people
  whose information may appear in telemetry, logs, process names, account names
  or notifications; and
- you will use appropriate configuration and data minimisation for the server.

When you determine why and how monitored-server data concerning other people is
processed, you are the controller of that data and NexusV processes it for you
in providing the Hosted Service.

## 5. Acceptable use

You must comply with [ACCEPTABLE_USE.md](ACCEPTABLE_USE.md). In particular, you
must not use HYN-view to:

- access or monitor a machine, account, tenant or data without authority;
- create malware, conceal unauthorised activity, stalk or surveil people, steal
  credentials or data, or facilitate an attack;
- evade access, rate, security or tenant-isolation controls;
- disrupt, overload, probe or scrape the Hosted Service without written
  permission;
- transmit malicious code or unlawful, deceptive, abusive or unsolicited bulk
  messages;
- falsify telemetry, impersonate another person or misrepresent authority; or
- violate sanctions, export controls or any applicable law.

HYN-view is designed for benign server-health monitoring, but no software
publisher can guarantee that software will never be misused. You are responsible
for your conduct. A statement that NexusV does not authorise unlawful use is not
a blanket exemption from any responsibility NexusV cannot lawfully exclude.

## 6. Your data and instructions

You retain your rights in telemetry and configuration you submit. You instruct
NexusV to host, organise, display, transmit to your configured destinations and
otherwise process that data only as needed to provide, secure and support the
Hosted Service, comply with law and enforce these Terms. You give us the limited
licence needed to do so. We do not acquire ownership of your telemetry, sell it,
use it for behavioural advertising or use it to train AI models.

You are responsible for the legality, accuracy and contents of submitted data,
and for your notification destinations. See the [Privacy Policy](PRIVACY.md) for
the controller/processor roles and deletion procedure. Where processor terms
are required, [DATA_PROCESSING_ADDENDUM.md](DATA_PROCESSING_ADDENDUM.md)
applies subject to its scope and transfer-instrument limitation.

## 7. Free service; no service level

The Hosted Service is currently provided **free of charge**. There are no
subscription fees, refunds or billing commitments. If we later offer a paid
plan, it will be optional and governed by separately disclosed price and payment
terms. We will give at least 30 days' notice before a new charge applies to an
existing service, and you may stop using it instead.

The free Hosted Service has no service-level agreement, uptime guarantee,
support-response guarantee, data-recovery guarantee or commitment to retain any
feature. It may be changed, rate-limited, unavailable or discontinued. We will
give at least 30 days' notice of a material discontinuation where practical and
will provide a reasonable opportunity to request an export. Urgent security or
legal changes may occur immediately.

## 8. Administration, suspension and termination

We may pause ingestion, suspend an account or node, revoke a node token or
terminate access where reasonably necessary to:

- protect users, providers or Hosted Service security;
- investigate suspected unauthorised or unlawful use;
- comply with law or a binding provider requirement;
- address a material or repeated breach of these Terms; or
- perform maintenance or discontinue the Hosted Service.

Where reasonable, we will give notice and a reason. Immediate action may be
necessary for security, abuse or legal compliance. Pausing or revoking hosted
ingestion does **not** necessarily stop an agent already installed on a server
from collecting local measurements or sending locally configured notifications;
the server administrator must disable or uninstall those functions separately.

You may stop using the Hosted Service at any time. `sudo hyn unlink` stops future
submissions from that agent, but it does not delete hosted data. Request account
or node deletion from <vivek.aryanvbw@gmail.com>; verified requests are handled
as described in the Privacy Policy, including deletion from active systems
within 7 days.

## 9. Third-party and open-source services

The Hosted Service depends on providers including Vercel, Supabase and Resend,
and may interact with Google or administrator-selected notification and network
test endpoints. Those services are controlled by their respective providers and
may have separate terms and privacy policies. We do not warrant their continued
availability or performance. See [SUBPROCESSORS.md](SUBPROCESSORS.md).

References to third-party platforms or software describe compatibility or
monitoring only. NexusV is not affiliated with or endorsed by Highway P2P,
Hiway Network or any other node, relay, distributed-computing or infrastructure
platform unless NexusV states otherwise in a signed agreement.

## 10. Measurement and alert limitations

Measurements come from the monitored operating system, hardware and network.
Sensors can be absent, mislabelled, delayed or wrong; counters can reset or wrap;
permissions can hide information; and virtual machines may expose synthetic
values. Rules, quotas and provider failures can suppress or delay alerts.

If a monitored server loses power, crashes or loses connectivity, its agent may
be unable to report. **Silence does not mean healthy.** Use independent external
availability monitoring and backup controls for important systems. You remain
responsible for administration, security, access review, patching, backups and
incident response.

## 11. Disclaimer of warranties

To the fullest extent permitted by applicable law, the Hosted Service is
provided **"as is" and "as available"** without express, implied or statutory
warranties, including warranties of accuracy, availability, fitness for a
particular purpose, merchantability, non-infringement, security or error-free
operation. The MIT License contains the warranty disclaimer governing the
open-source software.

Nothing in these Terms excludes a statutory warranty, remedy or consumer right
that cannot lawfully be excluded.

## 12. Limitation of liability

To the fullest extent permitted by applicable law, NexusV and its directors,
officers, employees and contributors will not be liable for indirect,
incidental, special, consequential, exemplary or punitive damages; loss of
profit, revenue, goodwill, opportunity, use or data; business interruption; or
damage arising from an inaccurate reading, delayed or missed alert, unavailable
server, third-party service or unauthorised use outside NexusV's reasonable
control.

To the fullest extent permitted by law, NexusV's total aggregate liability
arising out of or relating to the free Hosted Service will not exceed the fees
you actually paid NexusV for that Hosted Service in the 12 months before the
event giving rise to the claim. Because the current Hosted Service is free, that
amount is currently zero.

Nothing limits liability that cannot lawfully be limited, including liability
for fraud or fraudulent misrepresentation, or death or personal injury caused by
negligence where applicable. Consumer statutory rights remain unaffected, and
an exclusion applies only to the extent lawful in the user's jurisdiction.

## 13. Indemnity

If you use the Hosted Service for a business or organisation, you will defend
and indemnify NexusV against third-party claims and reasonable losses arising
from your unauthorised monitoring, unlawful submitted data, infringement of
another person's rights, or material breach of sections 4 or 5, to the extent
permitted by law. NexusV will give reasonable notice and allow you to control
the defence, subject to NexusV's right to participate. This section does not
apply where prohibited by consumer law or to the extent a claim was caused by
NexusV.

## 14. Changes

We may update these Terms. For a material change we will provide email or
prominent dashboard notice at least 30 days before it takes effect where
practical. Urgent security, abuse-prevention or legal changes may take effect
sooner with notice as soon as reasonably possible. Continued use after the
effective date means acceptance; if you do not agree, stop using the Hosted
Service and request deletion.

## 15. Governing law and disputes

These Terms are governed by the laws of **India**, without regard to
conflict-of-law rules. Subject to mandatory consumer rights, the competent
courts in India have non-exclusive jurisdiction. Before starting formal
proceedings, each party should send a written description of the dispute to
<vivek.aryanvbw@gmail.com> and allow 30 days for good-faith informal resolution,
unless urgent injunctive relief is reasonably necessary.

This section does not deprive an EEA or other consumer of a mandatory right to
bring proceedings or receive protections in the place where the consumer lives.

## 16. General

These Terms, the Privacy Policy and documents expressly incorporated into them
are the agreement about the Hosted Service. If a provision is unenforceable, it
will be limited to the minimum extent necessary and the remainder continues. A
failure to enforce a term is not a waiver. You may not assign a Hosted Service
account without consent; NexusV may assign these Terms in connection with a
merger, reorganisation or transfer of the Hosted Service, subject to applicable
law. Nothing creates a partnership, agency, employment or fiduciary relationship.

Sections that by their nature should survive termination do so, including
sections 6 and 9 to 16.

- **Operator:** NEXUSV TECHNOLOGIES PRIVATE LIMITED
- **Hosted Service:** <https://www.hyn-view.in> and <https://www.hyn-view.info>
- **Legal and support contact:** <vivek.aryanvbw@gmail.com>
