# Security Policy

**Last updated: 21 August 2026**

## Supported versions

Security fixes are made for the latest released HYN-view agent and the current
Hosted Service. Upgrade to the latest official release before reporting an issue
that may already have been corrected. Older or modified deployments may not
receive fixes.

## Reporting a vulnerability

Email <vivek.aryanvbw@gmail.com> with the subject **HYN-view security report**.
Include:

- the affected agent version, URL or component;
- a concise description and the security impact;
- steps to reproduce using your own account or test system;
- relevant logs or screenshots with secrets and personal data removed; and
- a safe way to contact you about the report.

Do not open a public issue for an unpatched vulnerability. Do not include a
password, node token, API key, cookie, private key, full webhook URL or
unnecessary personal data in the report.

We will review reports in good faith, but this policy does not promise a
particular response or remediation time, payment, reward or legal safe harbour.
Testing must comply with the [Acceptable Use Policy](ACCEPTABLE_USE.md) and
applicable law.

## Security design and limitations

The Hosted Service uses HTTPS, Supabase authentication, tenant row-level access
policies, restricted administrative roles and hashed node and pairing
credentials. Supabase Auth processes account passwords and stores protected
password verifiers; NexusV administrators cannot view a user's plaintext
password. Local secret files are intended to be root-only with mode `0600`.

Authorised deployment administrators and infrastructure providers retain
privileged access needed to operate, secure, back up and investigate the Hosted
Service. No system is perfectly secure, and these controls are not a warranty
against every intrusion, misconfiguration or data loss.

## Administrator responsibilities

Server and self-hosting administrators should:

- install only from an official source and review changes before upgrading;
- restrict root access and protect `/etc/hyn-view` and notification secrets;
- revoke a node promptly if its token or machine is compromised;
- minimise diagnostic, public-IP and access-detail collection;
- keep the operating system, browser and dependencies patched;
- use independent availability monitoring and tested backups; and
- remove local configuration with the documented purge option when retiring a
  server.

Security or privacy incidents affecting a Hosted Service account should be
reported promptly to <vivek.aryanvbw@gmail.com>.

**Security contact:** NEXUSV TECHNOLOGIES PRIVATE LIMITED —
<vivek.aryanvbw@gmail.com>
