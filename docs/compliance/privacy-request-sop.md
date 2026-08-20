# Privacy request SOP

**Internal use only**<br>
**Owner:** NEXUSV TECHNOLOGIES PRIVATE LIMITED<br>
**Request channel:** vivek.aryanvbw@gmail.com<br>
**Effective date:** 21 August 2026

## Objective and service target

Use this procedure for access, export, correction, objection, restriction and
deletion requests concerning the hosted service at `www.hyn-view.in` or
`www.hyn-view.info`.

For a verified deletion request, remove the requester's data from HYN-view active
systems within **seven calendar days**. Record both the received time and verified
time. Verification must be prompt and proportionate; it must not be used to delay a
valid request. Provider backups, mandatory security evidence and legal holds follow
the exceptions below and must not be restored into ordinary use.

## 1. Intake and ownership

1. Open a restricted case and assign a case ID immediately.
2. Record the received timestamp in UTC and IST, source address, requested right,
   stated account email, affected nodes, countries mentioned and exact scope.
3. Preserve the original request as evidence. Do not place it in a public issue,
   source repository or general chat channel.
4. Send an acknowledgement from `vivek.aryanvbw@gmail.com`. State that identity and
   authority must be verified, describe any information still needed, and give the
   case ID. Do not promise an outcome before scope and applicable roles are known.
5. Assign one case owner. Escalate immediately if the request alleges unauthorised
   access, disclosure or loss; use the [incident runbook](incident-response.md) in
   parallel.

## 2. Verify identity and authority

Use the least intrusive reliable method:

- Prefer a fresh authenticated portal session plus confirmation through the account's
  verified email address.
- For a node-only request, confirm the requester controls the portal account that owns
  the node and can identify the node without disclosing its token.
- Never request a password, password verifier, node token, API key, recovery code or
  complete authentication log.
- Request government identity evidence only if impersonation risk cannot be resolved
  another way. If it is exceptionally required, collect the minimum, restrict access,
  and delete the evidence as soon as verification is documented.
- If the requester is a monitored employee, contractor or other person who does not
  control the customer account, identify whether NexusV is acting for the customer as
  a processor. Route the request to the customer controller securely, preserve the
  original received time, and assist under the applicable data-processing agreement.
- If an agent, administrator or representative submits the request, verify both the
  data subject and the representative's authority.

Record the method, time, result and reviewer. A failed verification is not a deletion;
retain the case and explain the safe next step without revealing whether another
person has an account.

## 3. Find the data

Resolve the verified Supabase Auth user ID and every owned node ID. Search by stable
IDs first and email second. Record row counts and evidence locations, not full data,
in the case log.

### Hosted HYN-view checklist

- Supabase Auth user, identities, authentication metadata and legal-acceptance
  metadata.
- `profiles`.
- `nodes`, including configuration, status and token verifier.
- `metrics`, `speedtests` and `alert_events` for each node.
- Pending or approved `device_codes` connected to the user or node.
- `notification_log` delivery records. Provider credentials and destinations
  used for sending remain on the customer-controlled monitored server.
- `admin_audit` rows where the person appears as actor, target, email or in detail.
- `admin_allowlist` entries, if the requester was an authorised administrator.
- Supabase database, Auth, API and project logs; Supabase backups or point-in-time
  recovery copies.
- Vercel request, function, deployment, security and account logs.
- Resend contacts, suppression state, message metadata and retained content.
- Restricted privacy, support, abuse, legal-hold and security cases containing the
  person's identifiers.

### Monitored-server checklist

The customer controls files on its own server. Ask the authorised server owner to
inventory `/etc/hyn-view`, `/var/lib/hyn-view`, the applicable user's XDG config and
state directories, and any HYN-view notification copies. Local uninstallation keeps
configuration, secrets and history unless the owner uses the purge option.

Do not claim NexusV deleted customer-controlled local files without written evidence
from the customer. Do not ask the customer to send secrets or raw local telemetry as
proof.

## 4. Fulfil access, export or correction

1. Export only data attributable to the verified requester and their authorised
   nodes. Use a common, machine-readable format for structured records and a readable
   explanation of field names.
2. Redact other users' data, node tokens and security information
   whose disclosure would create a concrete risk. Record every redaction category and
   its reason.
3. Validate the export against the inventory and scan it for secrets before release.
4. Deliver it through an authenticated, time-limited channel. Do not attach a large or
   sensitive unencrypted archive to ordinary email.
5. For correction, update the authoritative record, confirm downstream copies or
   caches, and record before-and-after evidence without duplicating unnecessary data.

## 5. Fulfil deletion

Perform these steps in order so collection stops before stored data is removed:

1. Check for a documented legal hold, active security investigation, fraud-prevention
   need or other mandatory retention. The privacy owner and legal reviewer must record
   the exact data held, basis, access restriction, review date and disposal trigger.
2. Revoke or suspend affected hosted nodes and rotate any credential that may have
   been exposed. Ask the authorised server owner to unlink the agent and run
   `sudo hyn uninstall --purge` if local HYN-view files must also be erased.
3. Delete affected nodes. Database cascades should remove their `metrics`,
   `speedtests`, `alert_events` and `notification_log`; verify each table rather
   than assuming the cascade succeeded.
4. Delete any remaining `device_codes`, profile data and other user-linked
   application rows.
5. Review `admin_audit`. Remove or pseudonymise requester email and free-text detail
   unless a documented security or legal basis requires a restricted copy. Foreign
   keys becoming null is not enough because email and detail fields can remain.
6. Remove the email from `admin_allowlist` when applicable.
7. Delete the Supabase Auth user through an authorised administrative path. Confirm
   identities and sessions are invalidated and application rows no longer resolve to
   the user ID.
8. Submit provider-side deletion requests for active logs or message metadata where
   the provider supports them. Record provider case IDs and results.
9. Add the deleted stable identifiers to a restricted suppression manifest so a
   backup restore does not silently reactivate the account. Store only the minimum
   identifier needed for this control.
10. Run the verification checks below and have a second authorised person review the
    evidence before closing the case.

Messages already delivered through email, Telegram, ntfy, SMTP or a webhook cannot be
recalled by HYN-view. Explain this clearly. Delete NexusV-controlled delivery records
where required, but do not represent copies in a recipient's inbox, endpoint, logs or
backups as deleted.

## 6. Backups and residual records

- Active-system deletion does not prove immediate physical erasure from provider
  backups or point-in-time recovery media.
- Record the actual Supabase, Vercel and Resend backup/log settings and contractual
  deletion behaviour for the case. If unknown, escalate; do not invent a period.
- Restrict residual copies from ordinary use. If restoration is required, reapply the
  suppression manifest and deletion before reopening service access.
- When a legal hold ends, remove the held copy and record the disposal evidence.

## 7. Verification and closure

Confirm all applicable checks:

- Portal sign-in and active sessions no longer work.
- The user ID and email no longer appear in Auth, profiles, node records,
  administrator allow lists or ordinary application queries.
- Owned node IDs return no nodes, metrics, speed tests, alerts or notification logs.
- Pending pairing rows connected to the user or deleted nodes are gone.
- Audit free text and support/security cases have been deleted, pseudonymised or tied
  to a documented exception.
- Provider actions, local-controller actions, holds and backup limitations are listed
  in the closure record.
- Completion occurred within seven calendar days of verification, or the case records
  the precise lawful reason, approver, affected data and next review date.

Send a plain-language closure message stating what was completed, what remains only in
restricted backups or legal/security evidence, what NexusV could not control, and how
to raise a concern. Do not say "permanently deleted everywhere" unless evidence proves
that statement.

## Evidence log fields

Record at minimum:

| Field | Required evidence |
|---|---|
| Case and request | Case ID, request type, original message location, received time |
| Identity | Method, verified time, reviewer, authority or controller relationship |
| Scope | User ID, node IDs, systems/providers searched, row counts |
| Actions | Timestamp, operator, system, operation, result, provider case ID |
| Exceptions | Data retained, basis, approver, access restriction, review/disposal date |
| Verification | Before/after counts, session test, reviewer and review time |
| Communication | Acknowledgement, clarification, export and closure message locations |

Keep the log pseudonymous where possible. The retention period and repository for
this evidence are unresolved operational decisions listed in the
[retention schedule](retention-schedule.md); the case file must not become an
unbounded copy of the deleted data.
