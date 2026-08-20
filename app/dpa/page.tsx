import type { Metadata } from "next";
import Link from "next/link";
import { Important, LegalPage } from "@/components/legal-page";

export const metadata: Metadata = {
  title: "Data Processing Addendum / HYN-view",
  description:
    "Processor terms for customer personal data handled through the HYN-view Hosted Service.",
};

const contact = "vivek.aryanvbw@gmail.com";

export default function DataProcessingAddendumPage() {
  return (
    <LegalPage
      kicker="// data processing"
      title="Data Processing Addendum"
      updated="21 August 2026"
    >
      <p>
        This Data Processing Addendum (&ldquo;DPA&rdquo;) supplements the HYN-view{" "}
        <Link href="/terms">Terms of Use</Link> when{" "}
        <strong>NEXUSV TECHNOLOGIES PRIVATE LIMITED</strong> (&ldquo;NexusV&rdquo;)
        processes Customer Personal Data on behalf of a customer through the Hosted
        Service and data-protection law requires processor terms. The customer is the
        person or organisation identified by the applicable HYN-view account and
        instructions.
      </p>
      <Important>
        This public DPA does not itself complete a required international-transfer
        instrument whose annexes demand additional party details. An EEA business
        customer that requires signed terms or standard contractual clauses must
        contact <a href={`mailto:${contact}`}>{contact}</a> before making a restricted
        transfer.
      </Important>

      <h2>1. Roles and scope</h2>
      <p>
        The customer is controller of Customer Personal Data contained in telemetry
        or configuration that it chooses to send. NexusV is processor for that data.
        NexusV remains an independent controller or Data Fiduciary for account,
        authentication, fraud-prevention, security and legal-compliance information,
        as described in the <Link href="/privacy">Privacy Policy</Link>.
      </p>
      <p>
        &ldquo;Customer Personal Data&rdquo; means personal data processed by NexusV
        on the customer&apos;s behalf through the Hosted Service. &ldquo;Data
        Protection Law&rdquo; means law applicable to that processing, including the
        EU/EEA GDPR where applicable.
      </p>

      <h2>2. Documented instructions</h2>
      <p>
        NexusV will process Customer Personal Data only to provide, secure and support
        the Hosted Service; receive notification-delivery records from linked agents;
        perform configuration and deletion requests; comply with the Terms; and meet
        legal obligations. Notification messages are sent directly by each monitored
        server to destinations configured locally by its administrator, not routed
        through central portal credentials. The Terms, this DPA, account settings and
        lawful support requests are the customer&apos;s documented instructions.
      </p>
      <p>
        NexusV will inform the customer if an instruction appears to infringe
        applicable Data Protection Law, unless law prohibits notice. The customer is
        responsible for the lawfulness, accuracy and minimisation of its instructions
        and for giving required notices and obtaining required permissions.
      </p>

      <h2>3. Confidentiality and security</h2>
      <p>
        NexusV will limit access to personnel and providers who need it for their work
        and are subject to appropriate confidentiality duties. Safeguards include
        HTTPS, Supabase authentication, tenant row-level policies, restricted
        privileged roles, hashed node and pairing credentials, administrative action
        logging and local root-only secret-file permissions where configured. No
        measure eliminates all risk.
      </p>
      <p>
        The customer is responsible for account access, monitored servers, local
        configuration, destination providers, staff permissions, backups and incident
        response. See the <Link href="/security">Security Policy</Link>.
      </p>

      <h2>4. Subprocessors</h2>
      <p>
        The customer gives general authorisation for the providers in the{" "}
        <Link href="/subprocessors">provider and subprocessor list</Link>. NexusV will
        impose data-protection obligations appropriate to each provider&apos;s
        function and remains responsible for its processor obligations to the extent
        required by law.
      </p>
      <p>
        NexusV will give at least 30 days&apos; notice of a new primary subprocessor
        where practical. A customer with a reasonable data-protection objection
        should contact NexusV during that period. The parties will try in good faith
        to find an alternative; if none is available, the customer may stop the
        affected processing and request deletion. Urgent security or continuity
        changes may occur sooner.
      </p>

      <h2>5. Assistance and incidents</h2>
      <p>
        Taking account of the processing and available information, NexusV will
        provide reasonable assistance with data-subject requests, security
        obligations, personal-data-breach notifications, impact assessments and
        regulator consultations required by law. If NexusV becomes aware of a
        confirmed personal-data breach affecting Customer Personal Data, it will
        notify the customer without undue delay and provide information reasonably
        needed for the customer&apos;s obligations. Notice is not an admission of
        fault.
      </p>
      <p>
        The customer must promptly forward any request NexusV should handle as its
        processor and must not send unnecessary personal data in support
        correspondence.
      </p>

      <h2>6. Return and deletion</h2>
      <p>
        During an active account, the customer may request an available export by
        email. On a verified deletion request or termination, NexusV will delete
        requested Customer Personal Data from active Hosted Service systems within{" "}
        <strong>7 days</strong>, as described in the Privacy Policy. Limited copies
        may remain temporarily in provider backups or security records, or where law
        requires retention; they remain protected, are not used for ordinary service
        purposes and are removed or allowed to expire under the applicable schedule.
      </p>

      <h2>7. Information and audits</h2>
      <p>
        NexusV will provide information reasonably necessary to demonstrate
        compliance with processor obligations. If that is insufficient, a business
        customer may request an audit no more than once per year, unless a regulator
        or confirmed incident reasonably requires more. Audits must be proportionate,
        protect other customers and confidential information, avoid disruption and
        use an independent qualified auditor. The customer bears reasonable audit
        costs unless the audit identifies a material NexusV breach.
      </p>

      <h2>8. International transfers</h2>
      <p>
        The Supabase project&apos;s primary database region is configured as Mumbai,
        India. Vercel, Supabase, Resend and optional providers may process data
        elsewhere. The parties will use an applicable transfer mechanism before a
        restricted transfer, such as an adequacy decision or applicable standard
        contractual clauses with required supplementary safeguards. This DPA does not
        claim all processing occurs in India.
      </p>

      <h2>9. Processing details</h2>
      <ul>
        <li>
          <strong>Subject matter and purpose:</strong> hosting and displaying
          server-health telemetry, authenticating users, recording notification
          delivery outcomes, support and security.
        </li>
        <li>
          <strong>Duration:</strong> the account term and retention period in the
          Privacy Policy.
        </li>
        <li>
          <strong>Nature and frequency:</strong> automated collection from linked
          agents, storage, organisation, display, retrieval and deletion, ordinarily
          on the configured interval. A monitored server separately transmits
          notification messages to destinations configured locally by its
          administrator.
        </li>
        <li>
          <strong>People concerned:</strong> customer personnel, authorised users,
          administrators and people whose identifiers may appear in authorised
          telemetry or alerts.
        </li>
        <li>
          <strong>Data categories:</strong> account, host and node identifiers;
          system, resource, network, process, service and alert data; notification
          destinations and records; and request or security metadata.
        </li>
        <li>
          <strong>Sensitive data:</strong> not intentionally required. Customers must
          not send special-category data, passwords, private keys, or message content
          unrelated or unnecessary to an authorised server-health notification unless
          NexusV expressly agrees in writing and lawful safeguards are in place.
        </li>
      </ul>

      <h2>10. Precedence and liability</h2>
      <p>
        For processor obligations, this DPA controls over a conflicting Terms
        provision. A separately signed data-processing or transfer agreement controls
        over this public DPA. Liability is subject to lawful limitations in the Terms,
        without limiting rights or liabilities that cannot lawfully be limited.
      </p>

      <p>
        <strong>Processor:</strong> NEXUSV TECHNOLOGIES PRIVATE LIMITED
        <br />
        <strong>Privacy contact:</strong>{" "}
        <a href={`mailto:${contact}`}>{contact}</a>
        <br />
        <strong>Hosted Service:</strong>{" "}
        <a href="https://www.hyn-view.in">www.hyn-view.in</a> and{" "}
        <a href="https://www.hyn-view.info">www.hyn-view.info</a>
      </p>
    </LegalPage>
  );
}
