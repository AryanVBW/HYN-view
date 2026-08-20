# Privacy Policy

**Effective date and last updated: 21 August 2026**

**Version: 1.0**

This policy explains how **NEXUSV TECHNOLOGIES PRIVATE LIMITED** ("NexusV",
"we", "us") handles information through the HYN-view hosted dashboard at
<https://www.hyn-view.in> and <https://www.hyn-view.info> (the **Hosted
Service**). It also explains what the open-source HYN-view agent reads on a
server.

Privacy, grievance, security and support contact:
<vivek.aryanvbw@gmail.com>.

## 1. Scope and responsibility

HYN-view has two parts:

- The **agent** is open-source software installed by a server owner or an
  authorised administrator. It can operate locally without a HYN-view account.
  If it is not linked to the Hosted Service, NexusV does not receive its server
  telemetry. An unlinked agent can still make the built-in and configured
  outbound requests listed below.
- The **Hosted Service** is an optional account-based dashboard. A server sends
  telemetry to it only after an administrator links and approves that server.

For account, authentication, service-security and operator-administration data,
NexusV acts as the controller or Data Fiduciary. When a customer decides to
monitor a server and determines the telemetry to send, that customer is normally
the controller of that monitored-server data and NexusV processes it for the
customer. A person or organisation that self-hosts the portal is responsible for
its own deployment and must publish its own accurate privacy information.

## 2. Information handled by the agent

Depending on the installed version and settings, the agent can read:

- **System identity and health:** hostname or node label, operating-system and
  kernel versions, uptime, CPU model and cores, clock information, load,
  temperature sensors and service status.
- **Resource use:** CPU, memory, swap, pressure, filesystem capacity, disk
  throughput and utilisation.
- **Network health:** interface counters, speed, duplex and MTU; connection-state
  counts; latency, packet loss, DNS timing and throughput-test results. Optional
  features can read the server's local or public IP address, MAC address, gateway
  and wireless network name.
- **Processes and access:** process names and resource use. When an administrator
  explicitly sets `notify_access_details=on`, local reports and alerts can include
  run-as and session usernames, session source addresses, failed-authentication
  counts, and the source address with the most rejected logins. These details are
  excluded from notifications by default.
- **Service diagnostics:** unit names, states, restart counts, version and
  diagnostic summaries. Older agent versions or optional diagnostic fields may
  include a short service-log excerpt; administrators should upgrade and review
  settings before linking a machine whose logs may contain confidential content.

This information stays on the monitored machine unless the administrator links
the agent to a portal or configures a notification or other outbound endpoint.
An administrator must not install or use the agent on a machine without the
owner's authority.

### Built-in and default outbound requests

An agent can make network requests even when it is not linked to the Hosted
Service. Default settings and installed timers can contact:

- Cloudflare's `1.1.1.1` and Google's `8.8.8.8` for latency and packet-loss
  probes, plus the local gateway; set `latency_targets=` to remove the public
  targets;
- the machine's configured DNS resolver to resolve `cloudflare.com` for DNS
  timing; set `dns_probe=off` to disable it;
- `api.ipify.org`, falling back to `ifconfig.me`, to discover the public IP;
  set `public_ip=off` to disable it;
- an installed Ookla Speedtest or `speedtest-cli` provider, or
  `speed.cloudflare.com` as the curl fallback, for scheduled or manual
  throughput tests; set `speedtest_per_day=0` to stop scheduled tests and do not
  run the manual command;
- `install.hiwaynetwork.io` for the optional Highway version manifest when
  Highway tracking and its update check are enabled; set
  `highway_update_check=off` or `highway_track=off` to disable it; and
- `registry.npmjs.org` for the default update check; set `auto_update=off` to
  disable it.

A notification provider, heartbeat URL or linked portal is also contacted when
the administrator configures that feature. Every external endpoint necessarily
receives the server's public or egress source IP and ordinary request metadata.
A system DNS resolver sees the DNS query, and an endpoint can keep its own logs
under its policy. These diagnostic endpoints are not sent the Hosted Service
telemetry payload, except that a configured notification destination receives
the message content and a linked portal receives the hosted payload described
below.

## 3. Information handled by the Hosted Service

The Hosted Service may process the following.

### Account and authentication data

- email address and, if supplied, name;
- a protected password verifier and authentication records handled by Supabase
  Auth, or an identity and email returned by an enabled OAuth provider;
- session cookies and security records needed to keep an account signed in and
  prevent abuse; and
- request metadata such as IP address, user agent, timestamps and error or
  security logs generated by Vercel, Supabase or our application.

NexusV does not receive or display a user's plaintext password. A password is
processed by Supabase Auth, which stores a protected verifier needed to
authenticate the account. If Google sign-in is enabled, HYN-view does not
receive the user's Google password.

### Server and telemetry data

- node name, hostname, operating-system and agent versions, link and last-seen
  timestamps, configuration and administrative status;
- CPU, memory, swap, load, temperature, storage, network-counter and service
  health measurements;
- filesystem mount labels, process names and resource summaries, alert states,
  throughput-test results and other diagnostic fields sent by the installed
  agent version; and
- notification-delivery metadata, including channel, destination, subject,
  success or failure and error details.

The Hosted Service is not intended to collect file contents, command arguments,
environment variables, keystrokes, database contents or application records.
Telemetry such as an email address, hostname, account name, IP address, process
name, mount label or alert text can nevertheless identify a person or reveal
confidential operational information. It must therefore be treated as personal
or confidential data when context makes it so.

The default `notify_access_details=off` excludes run-as and session usernames,
session source addresses and the source address with the most rejected logins
from notifications. It does **not** make every notification anonymous. Depending
on the alert, report and settings, a message can still contain the hostname,
wireless SSID, local or public IP, gateway, DNS details, filesystem mount paths,
and process or service context. Setting `notify_access_details=on` additionally
allows those account and access identifiers in messages sent directly to the
administrator's configured destinations, even when they are not stored as
hosted dashboard telemetry.

### Configuration and administration data

- node monitoring settings;
- notification-delivery records reported by a linked agent. These can include
  the provider kind, destination, subject, status and error summary, but not the
  credential used to send the message;
- account, node and administrator actions and their reasons; and
- browser preferences, including the selected visual theme stored locally in
  the browser.

Notification destinations and provider credentials are configured on each
monitored server. API keys, SMTP passwords, tokens and webhook URLs are not
stored in Supabase or returned by the Hosted Service. They remain in the local
root-only `/etc/hyn-view/secrets` file until the server administrator removes
them. The agent sends a notification directly to the selected provider and, if
linked, can separately report the delivery result to the Hosted Service.

Node tokens and pairing codes are stored in the database as cryptographic
hashes. Pairing codes become unusable immediately when they expire after 15
minutes. Their expired database records are physically deleted on the next
pairing request or a maintenance cleanup cycle. Keep node tokens and notification
credentials secret.

## 4. Purposes and legal bases

We use the information above only to:

- create and authenticate accounts;
- link authorised servers and display their health data;
- apply alert rules and deliver requested service messages;
- provide support, maintain availability and diagnose faults;
- prevent abuse, investigate security events and enforce the Terms; and
- comply with applicable legal obligations.

Where the EU/EEA GDPR applies, the legal bases are performance of the service
contract, our legitimate interests in operating and securing the service, and
compliance with law. We use consent where applicable law requires it for an
optional feature. A customer that sends monitored-server data concerning other
people must establish its own lawful basis, give required notices, respect those
people's rights and configure data minimisation appropriately.

We do **not** sell or rent personal data, use it for behavioural advertising, or
use customer telemetry to train machine-learning or generative-AI models.

## 5. Access and disclosure

- A standard account can access only its own tenant data through the normal
  dashboard, enforced by database row-level access policies.
- Authorised NexusV deployment administrators have privileged technical access
  across tenants where needed to operate, secure and support the Hosted Service,
  investigate abuse or comply with law. Administrative access is not the same
  as customer ownership, and does not give NexusV permission to use telemetry
  for unrelated purposes.
- Vendors receive only the data needed to provide their contracted function.
  The main Hosted Service vendors are **Vercel** (web hosting and request
  processing), **Supabase** (database and authentication), and **Resend**
  (transactional email). Google is involved only if its sign-in option is
  enabled. Other notification destinations are contacted directly by a monitored
  server only when its administrator configures them locally. See
  [SUBPROCESSORS.md](SUBPROCESSORS.md).
- We may disclose information where law requires it, or when reasonably
  necessary to protect rights, users or service security, subject to applicable
  safeguards.

## 6. Regions and international transfers

The operator has configured the Supabase project's primary database region as
**Mumbai, India**. This does not mean every copy, log or request is processed
only in Mumbai. Vercel serves the web application through distributed
infrastructure, and Vercel, Supabase, Resend and optional providers may process
data in other countries.

Where EU/EEA transfer restrictions apply, NexusV and its customers must ensure
that an appropriate mechanism applies before a restricted transfer, such as an
adequacy decision or applicable standard contractual clauses, together with
supplementary safeguards where required. Business customers may contact us to
request signed data-processing or transfer terms; the public processing terms
are in [DATA_PROCESSING_ADDENDUM.md](DATA_PROCESSING_ADDENDUM.md).

## 7. Security

Safeguards include HTTPS in transit, Supabase authentication, tenant row-level
access policies, hashed node and pairing credentials, restricted administrative
roles and root-only local secret files where configured. Providers and authorised
administrators may retain narrowly scoped access needed to operate the service.

No internet service is perfectly secure. Customers remain responsible for their
server access controls, local secret files, notification endpoints, staff
permissions, backups and incident response. Report a suspected vulnerability or
data incident privately to <vivek.aryanvbw@gmail.com>. See
[SECURITY.md](SECURITY.md).

## 8. Retention and deletion

- Hosted metric rows are ordinarily kept on a rolling **30-day** basis and are
  pruned during successful ingestion. If a node stops sending, older rows may
  remain until scheduled maintenance or deletion of the node or account.
- Pairing codes become unusable after **15 minutes**; their expired records are
  physically deleted on the next pairing request or maintenance cleanup cycle.
- Other hosted configuration, alert, speed-test, notification and administrative
  records are retained while needed to provide or secure the account, or until
  the associated node or account is deleted, unless law requires longer.
- On the monitored server, the default local metric history is **8 days**, the
  default local alert log is **31 days**, and speed-test history is limited to
  the latest **90 records**. Configuration and local secret files remain until
  the administrator removes them or uses the purge option.

Running `sudo hyn unlink` stops future portal submissions from that agent, but it
does not by itself delete information already held by the Hosted Service.

To request deletion, email <vivek.aryanvbw@gmail.com> from the account email and
identify the account and nodes concerned. After verifying the request, we will
delete the requested data from active Hosted Service systems within **7 days**.
Deletion is intended to be permanent and cannot be undone. Limited copies may
remain temporarily in provider backups, fraud or security records, or where
retention is required by law; they will be isolated from ordinary use and
removed or allowed to expire under the applicable retention schedule.

## 9. Your choices and rights

You can avoid hosted processing by using the open-source agent without linking
it. Depending on configuration, you can also disable public-IP lookup, latency
or DNS probes, throughput tests, update checks, service tracking and outbound
notifications. Keep `notify_access_details=off` unless a legitimate monitoring
need, lawful basis and suitably restricted destination justify including access
identifiers in messages. That setting hides the access identities listed above,
not other system context that an alert or report needs to describe the server.

Subject to applicable law, you may request access, correction, deletion,
restriction, objection, a portable copy or withdrawal of consent by emailing
<vivek.aryanvbw@gmail.com>. We may verify identity before acting. We aim to
acknowledge requests promptly and will complete verified deletion requests from
active systems within 7 days; other rights requests will be handled within the
period required by applicable law.

If NexusV processes monitored-server data only on behalf of an organisation,
requests concerning that data should normally be directed to that organisation.
We will provide reasonable assistance to the organisation. People in the EEA
may also complain to the data-protection supervisory authority where they live,
work or believe an infringement occurred. Indian users may use the grievance
contact above and any statutory complaint route available to them.

## 10. Children and automated decisions

The Hosted Service is server-management tooling for adults. Registration is not
offered to anyone under **18 years old**. Alert rules compare measurements with
administrator-selected thresholds; HYN-view does not make automated decisions
that produce legal or similarly significant effects about people.

## 11. Changes and contact

We may update this policy as the software, providers or law changes. For a
material change, we will provide email or prominent dashboard notice at least
30 days in advance where practical. A change required urgently for security,
fraud prevention or law may take effect sooner, with notice as soon as
reasonably possible.

- **Operator:** NEXUSV TECHNOLOGIES PRIVATE LIMITED
- **Hosted Service:** <https://www.hyn-view.in> and <https://www.hyn-view.info>
- **Privacy, grievance and security contact:** <vivek.aryanvbw@gmail.com>
