import type { Metadata } from "next";
import Link from "next/link";
import { Important, LegalPage } from "@/components/legal-page";

export const metadata: Metadata = {
  title: "Security Policy / HYN-view",
  description:
    "How to report a HYN-view vulnerability and the security responsibilities of administrators.",
};

const contact = "vivek.aryanvbw@gmail.com";

export default function SecurityPage() {
  return (
    <LegalPage kicker="// security" title="Security Policy" updated="21 August 2026">
      <h2>1. Supported versions</h2>
      <p>
        Security fixes are made for the latest released HYN-view agent and the
        current Hosted Service. Upgrade to the latest official release before
        reporting an issue that may already have been corrected. Older or modified
        deployments may not receive fixes.
      </p>

      <h2>2. Reporting a vulnerability</h2>
      <Important>
        Email <a href={`mailto:${contact}`}>{contact}</a> with the subject
        &ldquo;HYN-view security report&rdquo;. Do not open a public issue for an
        unpatched vulnerability.
      </Important>
      <p>Include:</p>
      <ul>
        <li>the affected agent version, URL or component;</li>
        <li>a concise description and the security impact;</li>
        <li>steps to reproduce using your own account or test system;</li>
        <li>logs or screenshots with secrets and personal data removed; and</li>
        <li>a safe way to contact you about the report.</li>
      </ul>
      <p>
        Do not include a password, node token, API key, cookie, private key, full
        webhook URL or unnecessary personal data in a report. We will review reports
        in good faith, but this policy does not promise a particular response or
        remediation time, payment, reward or legal safe harbour. Testing must comply
        with the <Link href="/acceptable-use">Acceptable Use Policy</Link> and
        applicable law.
      </p>

      <h2>3. Security design and limitations</h2>
      <p>
        The Hosted Service uses HTTPS, Supabase authentication, tenant row-level
        access policies, restricted administrative roles and hashed node and pairing
        credentials. Supabase Auth processes account passwords and stores protected
        password verifiers; NexusV administrators cannot view a user&apos;s plaintext
        password. Local secret files are intended to be root-only with mode{" "}
        <code>0600</code>.
      </p>
      <p>
        Authorised deployment administrators and infrastructure providers retain
        privileged access needed to operate, secure, back up and investigate the
        Hosted Service. No system is perfectly secure, and these controls are not a
        warranty against every intrusion, misconfiguration or data loss.
      </p>

      <h2>4. Administrator responsibilities</h2>
      <p>Server and self-hosting administrators should:</p>
      <ul>
        <li>install only from an official source and review changes before upgrading;</li>
        <li>
          restrict root access and protect <code>/etc/hyn-view</code> and notification
          secrets;
        </li>
        <li>revoke a node promptly if its token or machine is compromised;</li>
        <li>minimise diagnostic, public-IP and access-detail collection;</li>
        <li>keep the operating system, browser and dependencies patched;</li>
        <li>use independent availability monitoring and tested backups; and</li>
        <li>
          remove local configuration with the documented purge option when retiring a
          server.
        </li>
      </ul>
      <p>
        Report a security or privacy incident affecting a Hosted Service account
        promptly to <a href={`mailto:${contact}`}>{contact}</a>.
      </p>

      <p>
        <strong>Security contact:</strong> NEXUSV TECHNOLOGIES PRIVATE LIMITED —{" "}
        <a href={`mailto:${contact}`}>{contact}</a>
      </p>
    </LegalPage>
  );
}
