# Security incident and breach triage runbook

**Internal use only**<br>
**Owner:** NEXUSV TECHNOLOGIES PRIVATE LIMITED<br>
**Operational and legal escalation:** vivek.aryanvbw@gmail.com<br>
**Effective date:** 21 August 2026

This runbook covers the hosted HYN-view service, its Supabase data plane and Auth,
Vercel hosting, Resend delivery, release pipeline and linked monitoring agents. It is
not a substitute for incident-specific legal advice.

## Pre-incident requirements

Complete these actions before production reliance:

1. Appoint a named incident commander, technical lead, communications lead, privacy
   lead and alternates. Grant individual, MFA-protected emergency access; do not share
   accounts.
2. Designate and register the CERT-In point of contact using the required process and
   keep the designation current. The legal mailbox alone is not proof that this has
   been completed.
3. Maintain current escalation contacts and customer/controller contacts in a
   restricted directory, including Supabase, Vercel and Resend support routes.
4. Enable time synchronisation and decide the applicable CERT-In ICT-log set. Verify
   secure rolling 180-day storage within India where the directions apply.
5. Test revocation/rotation for Supabase keys and sessions, Vercel credentials,
   Resend keys, Google OAuth credentials, HYN-view node tokens and notification
   provider credentials.
6. Prepare restricted evidence storage, write-once or integrity-protected copies,
   forensic export procedures and a communication channel independent of the
   production identity system.
7. Run a tabletop for cross-tenant access, exposed service-role key, compromised
   administrator, malicious package release and leaked node token at least annually
   and after major architecture changes.

## 1. Declare and record

Anyone receiving an alert, report or credible suspicion opens a restricted incident
record and contacts the incident commander. Record immediately:

- incident ID, reporter and detection source;
- detection time and the separate time NexusV became aware of a credible security or
  personal-data breach, in UTC and IST;
- affected production environment, accounts, tenants, nodes, providers and data;
- what is observed, what is inferred, and what remains unknown;
- current containment and every person with access to the case.

Treat suspected cross-tenant access, data exfiltration, service-role/admin compromise,
malicious release, ransomware, material denial of service, or public credential
exposure as critical until scoped. Do not wait for perfect proof before containing
credible active harm or starting regulatory assessment.

## 2. Preserve evidence before it disappears

1. Record system clocks and provider timestamps. Preserve original time zones.
2. Export relevant Supabase Auth, API, database and audit evidence; Vercel request,
   function, deployment and security logs; Resend delivery/security logs; source
   commits, CI artefacts, package versions and configuration history.
3. For affected Ubuntu nodes, preserve relevant systemd, authentication, package and
   HYN-view state evidence with the server owner's authority. Collect only what the
   incident requires.
4. Hash exported files, record who collected them, source, time, storage location and
   every transfer. Keep originals read-only and analyse copies.
5. Preserve volatile evidence when feasible, but do not prolong active compromise to
   collect it.
6. Never paste secrets, full tokens, raw credential stores or unnecessary personal
   data into tickets, chat or email. Store them only in the restricted evidence
   system.

If a legal hold is needed, record its basis, data scope, approver, access list, review
date and disposal trigger. Evidence preservation does not authorise unrelated bulk
collection.

## 3. Contain without destroying the record

Choose the narrowest safe action and record its exact time and operator:

- disable a vulnerable route or deployment, revoke affected sessions, suspend a
  compromised account or node, and block confirmed malicious access;
- rotate exposed keys and tokens from a clean administrative environment, beginning
  with credentials that can mint or read other credentials;
- isolate affected nodes or tenants while preserving unaffected customers;
- stop notification/webhook delivery if it could leak more data;
- preserve old hashes/configuration as evidence before rotation when safe;
- verify that containment works through independent logs and tests.

Do not delete the account, node, database row or log merely to make the incident look
closed. Destructive eradication follows evidence capture and the incident commander's
approval unless immediate deletion is essential to stop harm.

## 4. Regulatory and contractual decision gates

Run all gates in parallel. The shortest applicable deadline governs the work pace.

### CERT-In: assess immediately for the six-hour window

At awareness, the privacy/legal lead and incident commander decide whether the event
is reportable under Annexure I and the 28 April 2022 directions. The CERT-In FAQ
specifically identifies severe incidents affecting public information infrastructure,
data breaches or leaks, large-scale/frequent incidents and incidents affecting human
safety for reporting within **six hours of noticing or being brought to notice**.

If applicable:

1. Record the six-hour deadline in UTC and IST and contact the designated CERT-In
   point of contact immediately.
2. Send the information available within the deadline; do not delay because the full
   incident form or root cause is incomplete. Clearly mark facts, estimates and
   unknowns, then supplement within a reasonable time.
3. Preserve and provide relevant logs when required. Maintain confidentiality and a
   record of exactly what was transmitted.
4. Send through the current official reporting route, including
   `incident@cert-in.org.in` where applicable, and retain delivery acknowledgement.
5. Record a reasoned non-report decision as carefully as a report decision.

Primary sources: [CERT-In directions](https://www.cert-in.org.in/PDF/CERT-In_Directions_70B_28.04.2022.pdf) and
[CERT-In FAQ](https://www.cert-in.org.in/PDF/FAQs_on_CyberSecurityDirections_May2022.pdf).

### EU GDPR: controller/processor and 72-hour assessment

First determine NexusV's role for each affected data set:

- When NexusV is a processor for a customer controller, notify that controller
  **without undue delay** under the data-processing agreement. Provide facts and
  updates; do not wait for the investigation to finish.
- When NexusV is the controller, assess risk to people's rights and freedoms. If the
  breach is not unlikely to create risk, notify the competent supervisory authority
  without undue delay and, where feasible, within **72 hours after awareness**. A late
  notice must explain the delay. Information may be supplied in phases.
- If the controller assessment finds a likely **high risk**, communicate to affected
  people without undue delay unless a documented Article 34 exception applies.

Record the nature and approximate scale, data categories, affected countries,
confidentiality/integrity/availability impact, likely consequences, safeguards such as
effective encryption, containment, residual risk and decision rationale. A conclusion
of "unlikely risk" requires evidence, not the absence of confirmed complaints.

Primary source: [GDPR Articles 33 and 34 on EUR-Lex](https://eur-lex.europa.eu/eli/reg/2016/679/2016-05-04/eng#art_33).

### Other India, customer and provider duties

- The legal owner must assess any privacy/data-protection notice duties effective and
  applicable on the incident date; this runbook does not assume an unverified Indian
  privacy deadline.
- Review customer contracts, data-processing agreements, security addenda, cyber-
  insurance requirements and provider notice terms. Contractual clocks may be shorter
  than statutory ones.
- Notify law enforcement only through an authorised decision, except where immediate
  emergency contact is necessary to protect people.

## 5. Decision log

Maintain one chronological log. Every row records:

| Required field | What to record |
|---|---|
| Time | UTC and IST; distinguish detection, awareness, decision and action |
| Decision | Containment, scope, report/non-report, customer or person notice |
| Basis | Confirmed facts, uncertainty, applicable role/law/contract and risk analysis |
| Authority | Decision maker, reviewer and approval route |
| Action | Owner, deadline, completion time, result and evidence location |
| Follow-up | Missing facts, next update, residual risk and reconsideration trigger |

Revisit notification decisions whenever scope, data sensitivity, exploitability or
affected population changes.

## 6. Notice quality control

Regulator, customer and affected-person notices must be factual and consistent. State:

- incident ID and reliable contact channel;
- when the event and awareness occurred, with time zones;
- known systems, data categories, approximate people/records and countries affected;
- likely consequences and current risk assessment;
- containment and mitigation actually completed, not merely planned;
- actions recipients should take, when genuinely useful;
- known limitations, material unknowns and time of the next update.

Do not say "no data was accessed," "fully contained," "all data is safe," "permanently
deleted," or identify an attacker unless verified evidence supports it. Do not include
credentials, exploitable detail, unrelated personal data or speculation. Legal and
technical reviewers approve external notices, but review must not miss a deadline.

## 7. Eradication, recovery and closure

1. Find the entry point and affected population; patch the root cause and equivalent
   paths, not only the observed symptom.
2. Rotate affected credentials, remove persistence, rebuild from trusted artefacts and
   validate RLS/tenant boundaries and logging before restoring access.
3. Monitor for recurrence and credential reuse. Keep temporary controls until the
   permanent fix is independently verified.
4. Reconcile every regulator, customer, provider and affected-person update; correct
   earlier estimates promptly.
5. Complete a blameless post-incident review with root cause, control failures,
   timeline, impact, evidence, remediation owner and due date.
6. Retest remediation and close only when residual risk is accepted by an authorised
   owner. Track longer work separately without hiding it in a closed incident.
7. Apply the approved evidence retention or legal hold and securely dispose of copies
   when it expires.

An incident is not closed merely because service is available again.
