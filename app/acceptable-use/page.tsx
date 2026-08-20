import type { Metadata } from "next";
import Link from "next/link";
import { Important, LegalPage } from "@/components/legal-page";

export const metadata: Metadata = {
  title: "Acceptable Use Policy / HYN-view",
  description:
    "Rules requiring lawful, authorised server monitoring through HYN-view.",
};

const contact = "vivek.aryanvbw@gmail.com";

export default function AcceptableUsePage() {
  return (
    <LegalPage
      kicker="// acceptable use"
      title="Acceptable Use Policy"
      updated="21 August 2026"
    >
      <p>
        This policy forms part of the HYN-view <Link href="/terms">Terms of Use</Link>{" "}
        for the Hosted Service operated by{" "}
        <strong>NEXUSV TECHNOLOGIES PRIVATE LIMITED</strong>. It also states the uses
        of the open-source agent that NexusV supports. Copyright permission under the
        MIT License does not make an otherwise unlawful activity lawful.
      </p>

      <h2>1. Required authorisation</h2>
      <Important>
        Use HYN-view only on systems that you own or have express authority to
        administer.
      </Important>
      <p>
        Follow all laws, workplace rules, contracts and hosting-provider policies that
        apply. Give notices and obtain permissions required for monitoring employees,
        contractors, customers or other users.
      </p>

      <h2>2. Prohibited conduct</h2>
      <p>Do not use HYN-view or the Hosted Service to:</p>
      <ul>
        <li>
          access, link, scan or monitor any machine, account, network or tenant
          without authority;
        </li>
        <li>
          develop, deploy, conceal or support malware, ransomware, botnets,
          credential theft, data exfiltration, phishing, exploitation or persistence;
        </li>
        <li>stalk, covertly surveil, harass, intimidate or profile a person;</li>
        <li>
          collect passwords, private keys, authentication tokens, message contents or
          other data unnecessary for authorised server-health monitoring;
        </li>
        <li>
          access another customer&apos;s data or evade authentication, tenant
          isolation, rate limits, quotas, suspension or other security controls;
        </li>
        <li>
          overload, disrupt, scrape, benchmark or security-test the Hosted Service
          without prior written permission;
        </li>
        <li>
          upload malicious input, falsified telemetry or content intended to exploit
          a dashboard, log processor, notification destination or another user;
        </li>
        <li>
          send spam, abusive, deceptive or unlawful messages through notification
          features;
        </li>
        <li>
          infringe privacy, intellectual-property or other rights, or violate
          sanctions, export controls or other applicable law; or
        </li>
        <li>
          represent that NexusV endorses, certifies or guarantees your system or use.
        </li>
      </ul>
      <p>
        Do not rely on HYN-view as the sole control for a safety-critical or high-risk
        system. Use independent monitoring and qualified human administration.
      </p>

      <h2>3. Security research</h2>
      <p>
        Test only accounts and machines you own, unless you have written permission
        that specifically covers the test. Do not access or retain another
        person&apos;s data, impair availability, send unsolicited traffic, use social
        engineering or publish a vulnerability before NexusV has had a reasonable
        opportunity to investigate. Report findings privately under the{" "}
        <Link href="/security">Security Policy</Link>.
      </p>
      <p>
        This policy does not create a bug-bounty programme, promise payment or grant
        permission to violate law or a third party&apos;s terms.
      </p>

      <h2>4. Enforcement</h2>
      <p>
        NexusV may investigate suspected violations and may rate-limit, pause,
        suspend, revoke or terminate Hosted Service access. Immediate action may be
        taken where reasonably necessary to protect users, providers, the public or
        the service, or to comply with law. Where appropriate and lawful, NexusV will
        give notice and a reason.
      </p>
      <p>
        Report abuse to <a href={`mailto:${contact}`}>{contact}</a> with the relevant
        account, node, timestamps and supporting details. Do not email passwords,
        node tokens or unredacted personal data.
      </p>

      <p>
        <strong>Operator:</strong> NEXUSV TECHNOLOGIES PRIVATE LIMITED
        <br />
        <strong>Official sites:</strong>{" "}
        <a href="https://www.hyn-view.in">www.hyn-view.in</a> and{" "}
        <a href="https://www.hyn-view.info">www.hyn-view.info</a>
        <br />
        <strong>Abuse contact:</strong> <a href={`mailto:${contact}`}>{contact}</a>
      </p>
    </LegalPage>
  );
}
