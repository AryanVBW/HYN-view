import type { Metadata } from "next";
import Link from "next/link";
import { Important, LegalPage } from "@/components/legal-page";

export const metadata: Metadata = {
  title: "Terms of Use / HYN-view",
  description:
    "Terms for the free HYN-view hosted server-health dashboard operated by NexusV.",
};

const contact = "vivek.aryanvbw@gmail.com";

export default function TermsPage() {
  return (
    <LegalPage kicker="// terms" title="Terms of Use" updated="21 August 2026">
      <p>
        These Terms govern the HYN-view dashboard at{" "}
        <a href="https://www.hyn-view.in">www.hyn-view.in</a> and{" "}
        <a href="https://www.hyn-view.info">www.hyn-view.info</a> (the
        &ldquo;Hosted Service&rdquo;), operated by{" "}
        <strong>NEXUSV TECHNOLOGIES PRIVATE LIMITED</strong> (&ldquo;NexusV&rdquo;,
        &ldquo;we&rdquo;, &ldquo;us&rdquo;).
      </p>

      <h2>1. Acceptance and the separate MIT licence</h2>
      <p>
        By registering, signing in, linking a server or otherwise using the Hosted
        Service, you agree to these Terms and the{" "}
        <Link href="/privacy">Privacy Policy</Link>. If you do not agree, do not use
        the Hosted Service.
      </p>
      <p>
        HYN-view&apos;s source code is separately licensed under the{" "}
        <strong>MIT License</strong>, which permits copying, modification,
        distribution, sublicensing and sale subject to its conditions. These Terms do
        not take away those copyright-licence rights; they govern NexusV&apos;s hosted
        accounts and infrastructure. Applicable law still governs every use of the
        software.
      </p>

      <h2>2. What HYN-view is</h2>
      <p>
        HYN-view is a voluntary, informational server-health tool for authorised
        administrators. It displays operating-system and hardware measurements such
        as CPU, memory, storage, temperature, network and service health, and can send
        configured alerts and reports. It is intended to make server health easier to
        understand without relying only on command-line tools.
      </p>
      <Important>
        HYN-view is not an autonomous administration, remediation, access-control,
        security-response or malware-detection system. It does not guarantee that a
        server is healthy, secure or available, and is not designed for safety-critical
        or other high-risk use.
      </Important>
      <p>
        It is not a cryptocurrency, wallet, payment, trading, mining, staking,
        validation, investment, yield, bandwidth-resale or income product. Nothing in
        it is financial, investment, tax or legal advice. See the{" "}
        <Link href="/legal">disclaimer</Link>.
      </p>

      <h2>3. Eligibility, accounts and registration</h2>
      <p>
        You must be at least <strong>18 years old</strong>, have capacity to accept
        these Terms and provide accurate registration information. Registration is
        publicly available and currently free, but it does not create a right to
        perpetual access, a service level or support at a particular time.
      </p>
      <p>
        You are responsible for account activity and for protecting sessions, node
        tokens and notification credentials. Promptly revoke a compromised node and
        report suspected account compromise to{" "}
        <a href={`mailto:${contact}`}>{contact}</a>. Do not share an account in a way
        that defeats access controls or try to access another customer&apos;s data.
      </p>

      <h2>4. Authority to monitor</h2>
      <Important>
        Install, link or monitor HYN-view only on a server you own or are expressly
        authorised to administer.
      </Important>
      <p>By linking a server, you confirm that:</p>
      <ul>
        <li>the owner authorised the monitoring and selected telemetry transfer;</li>
        <li>
          your use complies with applicable law, workplace requirements, contracts
          and hosting-provider policies;
        </li>
        <li>
          you gave required notices and obtained required permissions from people
          whose information may appear in telemetry or notifications; and
        </li>
        <li>you will configure appropriate data minimisation and security.</li>
      </ul>
      <p>
        When you decide why and how monitored-server data about other people is
        processed, you are controller of that data and NexusV processes it for you.
      </p>

      <h2>5. Acceptable use</h2>
      <p>
        The <Link href="/acceptable-use">Acceptable Use Policy</Link> forms part of
        these Terms. You must not use HYN-view or the Hosted Service to:
      </p>
      <ul>
        <li>access or monitor a machine, account, network or tenant without authority;</li>
        <li>
          create malware, conceal unauthorised activity, stalk or surveil people,
          steal credentials or facilitate an attack;
        </li>
        <li>evade authentication, tenant isolation, rate limits or suspension;</li>
        <li>
          disrupt, overload, probe or scrape the Hosted Service without written
          permission;
        </li>
        <li>
          submit malicious or falsified telemetry, or send unlawful, deceptive,
          abusive or unsolicited bulk messages; or
        </li>
        <li>violate sanctions, export controls or any applicable law.</li>
      </ul>
      <p>
        HYN-view is designed for benign server-health monitoring, but no publisher
        can guarantee that open-source software will never be misused. You are
        responsible for your conduct. NexusV&apos;s rejection of unlawful use is not
        a blanket exclusion of responsibility that applicable law does not permit.
      </p>

      <h2>6. Your data</h2>
      <p>
        You retain your rights in submitted telemetry and configuration. You instruct
        NexusV to host, organise, display and transmit it to your configured
        destinations only as needed to provide, support and secure the Hosted Service,
        comply with law and enforce these Terms. We claim no ownership of your
        telemetry, do not sell it, do not use it for behavioural advertising and do
        not use it to train AI models.
      </p>
      <p>
        You are responsible for the legality, accuracy and content of submitted data
        and notification destinations. The Privacy Policy explains deletion and the
        controller/processor roles. The public{" "}
        <Link href="/dpa">Data Processing Addendum</Link> applies within its stated
        scope; business customers may request signed data-processing and transfer
        terms at{" "}
        <a href={`mailto:${contact}`}>{contact}</a>.
      </p>

      <h2>7. Free service and availability</h2>
      <p>
        The Hosted Service is currently <strong>free of charge</strong>. There are no
        subscription fees, refunds or billing commitments. Any future paid plan will
        be optional and have separately disclosed terms; we will provide at least 30
        days&apos; notice before a new charge applies to an existing service.
      </p>
      <p>
        The free Hosted Service has no SLA, uptime, support-response or data-recovery
        guarantee. It may change, be rate-limited, become unavailable or be
        discontinued. We will give at least 30 days&apos; notice of a material
        discontinuation where practical and a reasonable opportunity to request an
        export. Urgent security or legal changes may occur immediately.
      </p>

      <h2>8. Suspension and termination</h2>
      <p>
        We may pause ingestion, suspend an account or node, revoke a token or
        terminate access to protect users and service security, investigate abuse,
        comply with law or provider requirements, address a breach, perform
        maintenance or discontinue the Hosted Service. Where reasonable, we will give
        notice and a reason; urgent action may be immediate.
      </p>
      <Important>
        Pausing or revoking hosted ingestion does not necessarily stop an installed
        agent from collecting local measurements or sending locally configured
        notifications. The server administrator must disable those functions
        separately.
      </Important>
      <p>
        You may stop at any time. <code>sudo hyn unlink</code> stops future Hosted
        Service submissions but does not delete existing data. Request verified
        account or node deletion at <a href={`mailto:${contact}`}>{contact}</a>; active
        Hosted Service data is deleted within 7 days as described in the Privacy
        Policy.
      </p>

      <h2>9. Third parties and independence</h2>
      <p>
        The Hosted Service depends on Vercel, Supabase and Resend, and may interact
        with Google or administrator-selected notification and network-test
        endpoints. We do not control or warrant those providers&apos; availability.
        See the <Link href="/subprocessors">provider and subprocessor list</Link>.
      </p>
      <p>
        Third-party names describe interoperability only. NexusV is not affiliated
        with or endorsed by Highway P2P, Hiway Network or another node, relay,
        distributed-computing or infrastructure platform unless a signed agreement
        says otherwise.
      </p>

      <h2>10. Measurement and alert limits</h2>
      <p>
        Readings come from the monitored operating system, hardware and network.
        Sensors may be absent or wrong, counters may reset, permissions may hide data,
        and notification providers may delay or lose messages. Rules and quotas can
        suppress alerts.
      </p>
      <Important>
        If a monitored server crashes, loses power or loses connectivity, its agent
        may be unable to report. <strong>Silence does not mean healthy.</strong> Use
        independent external availability monitoring and backups for important
        systems.
      </Important>

      <h2>11. Warranty disclaimer</h2>
      <p>
        To the fullest extent permitted by law, the Hosted Service is provided{" "}
        <strong>&ldquo;as is&rdquo; and &ldquo;as available&rdquo;</strong> without
        express, implied or statutory warranties, including accuracy, availability,
        fitness for a purpose, merchantability, non-infringement, security or
        error-free operation. The MIT License contains the warranty disclaimer for
        the open-source software. Statutory rights that cannot lawfully be excluded
        remain unaffected.
      </p>

      <h2>12. Limitation of liability</h2>
      <p>
        To the fullest extent permitted by law, NexusV and its personnel are not
        liable for indirect, incidental, special, consequential, exemplary or
        punitive damages; loss of profit, revenue, goodwill, opportunity, use or data;
        business interruption; or loss arising from an inaccurate reading, delayed or
        missed alert, unavailable server, third-party service or unauthorised use
        outside NexusV&apos;s reasonable control.
      </p>
      <p>
        NexusV&apos;s total aggregate liability concerning the free Hosted Service
        will not exceed the fees actually paid to NexusV for that service in the 12
        months before the event. Because the current Hosted Service is free, that
        amount is currently zero. Nothing limits liability that cannot lawfully be
        limited, including fraud or fraudulent misrepresentation and, where
        applicable, death or personal injury caused by negligence. Consumer statutory
        rights remain unaffected.
      </p>

      <h2>13. Business indemnity</h2>
      <p>
        If you use the Hosted Service for a business or organisation, you will defend
        and indemnify NexusV against third-party claims and reasonable losses arising
        from your unauthorised monitoring, unlawful submitted data, infringement of
        another person&apos;s rights or material acceptable-use breach, to the extent
        permitted by law. NexusV will give reasonable notice and let you control the
        defence, subject to its right to participate. This does not apply where
        prohibited by consumer law or to the extent NexusV caused the claim.
      </p>

      <h2>14. Changes, law and disputes</h2>
      <p>
        Material changes will be announced by email or prominent dashboard notice at
        least 30 days in advance where practical. Urgent legal or security changes may
        take effect sooner. If you disagree, stop using the Hosted Service and request
        deletion.
      </p>
      <p>
        These Terms are governed by the laws of <strong>India</strong>. Subject to
        mandatory consumer rights, competent Indian courts have non-exclusive
        jurisdiction. Before formal proceedings, send a written description to{" "}
        <a href={`mailto:${contact}`}>{contact}</a> and allow 30 days for good-faith
        informal resolution, unless urgent relief is needed. This does not remove an
        EEA or other consumer&apos;s mandatory local rights.
      </p>

      <h2>15. General</h2>
      <p>
        These Terms and incorporated policies are the agreement about the Hosted
        Service. If a provision is unenforceable, it is limited to the minimum extent
        necessary and the rest continues. Failure to enforce is not a waiver. Nothing
        creates a partnership, agency, employment or fiduciary relationship. Terms
        that by nature should survive termination do so.
      </p>

      <p>
        <strong>Operator:</strong> NEXUSV TECHNOLOGIES PRIVATE LIMITED
        <br />
        <strong>Contact:</strong> <a href={`mailto:${contact}`}>{contact}</a>
      </p>
    </LegalPage>
  );
}
