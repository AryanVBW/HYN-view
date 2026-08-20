# HYN-view compliance operations

**Internal use only**<br>
**Owner:** NEXUSV TECHNOLOGIES PRIVATE LIMITED<br>
**Operational contact:** vivek.aryanvbw@gmail.com<br>
**Effective date:** 21 August 2026<br>
**Review cycle:** Quarterly and after any material product, provider or legal change

These runbooks turn the hosted HYN-view commitments into repeatable operations.
They are control procedures, not a legal opinion. The operator must keep them aligned
with the deployed code, the Supabase, Vercel and Resend configurations, customer
contracts, and applicable Indian and EU requirements.

## Runbooks

1. [Privacy request SOP](privacy-request-sop.md) — verify and complete access,
   export, correction and deletion requests, including the seven-day active-system
   deletion target.
2. [Retention schedule](retention-schedule.md) — what the code currently removes,
   what merely cascades on account or node deletion, and what still needs an owner
   or provider decision.
3. [Security incident and breach triage](incident-response.md) — containment,
   evidence preservation, CERT-In six-hour assessment and EU GDPR breach decisions.

## Operating rules

- Create a restricted case record for every request or incident; never manage one
  only through an email thread.
- Record facts, timestamps, decisions, approvers and evidence locations. Do not copy
  passwords, node tokens, API keys or unnecessary telemetry into the case record.
- A legal hold or security-preservation need may narrow a deletion, but it must have
  a documented basis, scope, approver, review date and eventual disposal action.
- Provider dashboards and contracts are evidence. Marketing pages are not evidence
  of actual region, backup, log or deletion settings.
- If the deployed system differs from these runbooks, treat the difference as a
  control failure: contain the risk, record it, correct either the implementation or
  the commitment, and retest.

## Pre-production control actions

These decisions are not implemented merely by publishing the runbooks:

1. Name a privacy-request owner and backup who can administer Supabase, Vercel and
   Resend without sharing credentials.
2. Name the CERT-In point of contact and alternate, submit the required point-of-
   contact information to CERT-In, and test the escalation path.
3. Approve the unresolved retention periods identified in the retention schedule,
   configure provider settings, and automate deletion wherever the provider allows.
4. Decide where the restricted request, legal-hold and incident evidence logs live,
   who may access them, and how long they are kept.
5. Obtain Indian and EU counsel review before treating these procedures as proof of
   legal compliance, including the interaction between privacy minimisation and the
   CERT-In ICT-log requirements.
