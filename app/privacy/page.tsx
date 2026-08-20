import type { Metadata } from "next";
import Link from "next/link";
import { Important, LegalPage } from "@/components/legal-page";

export const metadata: Metadata = {
  title: "Privacy Policy / HYN-view",
  description:
    "How NexusV handles account data and server telemetry for the HYN-view hosted dashboard.",
};

const contact = "vivek.aryanvbw@gmail.com";

export default function PrivacyPage() {
  return (
    <LegalPage kicker="// privacy" title="Privacy Policy" updated="21 August 2026">
      <Important>
        HYN-view server telemetry can be personal or confidential data when a
        hostname, email, account name, IP address, process name or alert identifies a
        person or reveals operational details. We minimise this data, but do not
        describe it as anonymous or non-personal in every context.
      </Important>

      <h2>1. Operator, scope and roles</h2>
      <p>
        <strong>NEXUSV TECHNOLOGIES PRIVATE LIMITED</strong> operates the HYN-view
        dashboard at <a href="https://www.hyn-view.in">www.hyn-view.in</a> and{" "}
        <a href="https://www.hyn-view.info">www.hyn-view.info</a> (the
        &ldquo;Hosted Service&rdquo;). Privacy, grievance, security and support
        questions may be sent to <a href={`mailto:${contact}`}>{contact}</a>.
      </p>
      <p>
        The open-source <strong>agent</strong> runs on a server owned or administered
        by its installer. It can work locally without an account. NexusV receives no
        server telemetry from an unlinked agent, although the agent can still make
        the built-in and configured outbound requests listed below. Linking and
        approving a server starts submissions to the optional Hosted Service.
      </p>
      <p>
        NexusV is controller or Data Fiduciary for account, authentication, service
        security and operator-administration data. A customer that decides why and
        how to monitor its server is normally controller of that telemetry, and
        NexusV processes it for the customer. A self-hosted portal has a separate
        operator responsible for its own privacy notice and compliance.
      </p>

      <h2>2. What the agent can read</h2>
      <p>Depending on version and settings, local measurements can include:</p>
      <ul>
        <li>
          hostname or node label, OS and kernel, uptime, CPU model and clocks, load,
          temperature sensors and service status;
        </li>
        <li>
          CPU, memory, swap, pressure, filesystem capacity, disk throughput and
          utilisation;
        </li>
        <li>
          interface and connection counters, latency, packet loss, DNS timing and
          throughput tests, plus optional local or public IP, MAC, gateway and Wi-Fi
          name;
        </li>
        <li>
          process names and resource use. Only when an administrator sets{" "}
          <code>notify_access_details=on</code>, local alerts or reports can include
          run-as and session usernames, session source addresses and the source IP
          with the most rejected logins. The default is <code>off</code>; and
        </li>
        <li>
          unit names, states, restarts, versions and diagnostic summaries. Older
          agents or optional diagnostic fields can include a short service-log
          excerpt, so administrators should upgrade and review settings before
          linking a sensitive machine.
        </li>
      </ul>
      <p>
        This information stays on the server unless its administrator links a portal
        or configures an outbound notification or endpoint. Install and use the agent
        only with the machine owner&apos;s authority.
      </p>

      <h3>Built-in and default outbound requests</h3>
      <p>
        An agent can make network requests without being linked. Default settings and
        installed timers can contact:
      </p>
      <ul>
        <li>
          Cloudflare <code>1.1.1.1</code> and Google <code>8.8.8.8</code> for latency
          and packet-loss probes, plus the local gateway;
        </li>
        <li>
          the machine&apos;s configured DNS resolver to resolve{" "}
          <code>cloudflare.com</code> for DNS timing;
        </li>
        <li>
          <code>api.ipify.org</code>, falling back to <code>ifconfig.me</code>, for
          public-IP discovery;
        </li>
        <li>
          an installed Ookla Speedtest or <code>speedtest-cli</code> provider, or{" "}
          <code>speed.cloudflare.com</code> as the curl fallback, for throughput tests;
        </li>
        <li>
          <code>install.hiwaynetwork.io</code> for the optional Highway version
          manifest; and <code>registry.npmjs.org</code> for update checks.
        </li>
      </ul>
      <p>
        A configured notification provider, heartbeat URL or linked portal is also
        contacted. Every external endpoint necessarily receives the server&apos;s
        public or egress source IP and ordinary request metadata; the system resolver
        sees DNS queries. Diagnostic endpoints do not receive the hosted telemetry
        payload, but notification destinations receive their message content and a
        linked portal receives the payload described below. Disable these functions
        with <code>latency_targets=</code>, <code>dns_probe=off</code>,{" "}
        <code>public_ip=off</code>, <code>speedtest_per_day=0</code>,{" "}
        <code>highway_update_check=off</code> or <code>highway_track=off</code>, and{" "}
        <code>auto_update=off</code>, as applicable.
      </p>

      <h2>3. What the Hosted Service handles</h2>
      <h3>Accounts and authentication</h3>
      <ul>
        <li>email address and, if supplied, name;</li>
        <li>
          a protected password verifier and authentication records handled by
          Supabase Auth, or identity information from an enabled OAuth provider;
        </li>
        <li>strictly necessary session cookies and account-security records; and</li>
        <li>
          IP address, user agent, timestamp, error and security metadata generated by
          Vercel, Supabase or the application.
        </li>
      </ul>
      <p>
        NexusV does not receive or display a user&apos;s plaintext password. Supabase
        Auth processes the password and keeps a protected verifier. If Google sign-in
        is enabled, HYN-view does not receive the user&apos;s Google password.
      </p>

      <h3>Servers, telemetry and administration</h3>
      <ul>
        <li>
          node name, hostname, OS and agent versions, pairing and last-seen times,
          settings and administrative status;
        </li>
        <li>
          CPU, memory, load, temperature, storage, network, process-name, service,
          alert and throughput-test fields sent by the installed agent version;
        </li>
        <li>
          notification destination and delivery metadata, including subject, result
          and error details;
        </li>
        <li>
          administrator actions and reasons; and
        </li>
        <li>the selected visual theme stored locally in the browser.</li>
      </ul>
      <p>
        The Hosted Service is not intended to collect file contents, command
        arguments, environment variables, keystrokes, database contents or
        application records. The default <code>notify_access_details=off</code>
        excludes run-as and session usernames, session source addresses and the
        source IP with the most rejected logins from notifications. It does not make
        every notification anonymous: depending on the alert, report and settings, a
        message can still contain hostname, wireless SSID, local or public IP,
        gateway, DNS details, mount paths, and process or service context. Setting it
        to <code>on</code> additionally permits the access identities in messages sent
        directly to the administrator&apos;s configured destinations.
      </p>
      <p>
        Notification destinations and provider credentials are configured on each
        monitored server. API keys, SMTP passwords, tokens and webhook URLs are not
        stored in Supabase or returned by the Hosted Service. They remain in the
        root-only <code>/etc/hyn-view/secrets</code> file until the server
        administrator removes them. The agent contacts the selected provider
        directly and can separately report destination and delivery-result metadata
        to the Hosted Service.
      </p>

      <h2>4. Purposes and legal bases</h2>
      <p>
        We process data to register and authenticate users; link authorised servers;
        show requested health information; apply alert rules; send service messages;
        provide support; maintain security and availability; prevent abuse; enforce
        the <Link href="/terms">Terms</Link>; and meet legal obligations.
      </p>
      <p>
        Where EU/EEA GDPR applies, the legal bases are performance of the service
        contract, legitimate interests in operating and securing the service, legal
        obligation, and consent where applicable law requires it for an optional
        feature. A customer that submits information about other people must provide
        its own lawful basis, notices and rights process.
      </p>
      <Important>
        We do <strong>not</strong> sell or rent personal data, use it for behavioural
        advertising, or use customer telemetry to train AI models.
      </Important>

      <h2>5. Who can access data</h2>
      <p>
        Standard accounts can access only their own tenant data through the normal
        dashboard, enforced by database row-level policies. Authorised NexusV
        deployment administrators have privileged access across tenants where needed
        to operate, secure and support the Hosted Service, investigate abuse or
        comply with law. This access does not transfer ownership of customer data or
        permit unrelated use.
      </p>
      <p>
        Providers receive only what is needed for their function. The primary
        providers are <strong>Vercel</strong> for web hosting and request processing,{" "}
        <strong>Supabase</strong> for database and authentication, and{" "}
        <strong>Resend</strong> for transactional email. Google is involved only if
        enabled and selected for sign-in. Administrator-selected notification
        destinations are contacted directly by a monitored server only when
        configured locally. See the{" "}
        <Link href="/subprocessors">provider and subprocessor list</Link>.
        Information may also be disclosed when law requires it or where reasonably
        necessary to protect users and service security, subject to applicable
        safeguards.
      </p>

      <h2>6. Regions and transfers</h2>
      <p>
        The operator has configured the Supabase project&apos;s primary database
        region as <strong>Mumbai, India</strong>. That does not mean every request,
        copy, log or backup is processed only in Mumbai. Vercel uses distributed
        infrastructure, and Vercel, Supabase, Resend and optional providers may
        process data in other countries.
      </p>
      <p>
        Where EU/EEA transfer restrictions apply, an appropriate transfer mechanism
        and supplementary safeguards must apply before a restricted transfer. A
        business customer can review the public{" "}
        <Link href="/dpa">Data Processing Addendum</Link> and request signed
        data-processing or transfer terms at{" "}
        <a href={`mailto:${contact}`}>{contact}</a>.
      </p>

      <h2>7. Security and credentials</h2>
      <p>
        Safeguards include HTTPS, Supabase authentication, tenant row-level policies,
        restricted administrator roles, hashed node credentials and pairing codes,
        and root-only local secret files where configured. Pairing codes become
        unusable immediately when they expire after 15 minutes; expired database
        records are physically deleted on the next pairing request or a maintenance
        cleanup cycle. No internet service is perfectly secure. Keep node tokens,
        notification credentials and local root access protected.
      </p>
      <p>
        Report suspected security or privacy incidents privately under the{" "}
        <Link href="/security">Security Policy</Link> to{" "}
        <a href={`mailto:${contact}`}>{contact}</a>.
      </p>

      <h2>8. Retention and deletion</h2>
      <ul>
        <li>
          Hosted metrics are ordinarily kept on a rolling 30-day basis and pruned
          during successful ingestion. If a node stops sending, older rows can remain
          until maintenance or deletion.
        </li>
        <li>
          Pairing codes become unusable after 15 minutes; expired records are
          physically deleted on the next pairing request or maintenance cleanup
          cycle.
        </li>
        <li>
          Other configuration, alert, speed-test, notification and administrative
          records are kept while needed for the account, security or law, or until
          the related node or account is deleted.
        </li>
        <li>
          On the server, default local metric history is 8 days, the default alert
          log is 31 days, and speed-test history is limited to the latest 90 records.
          Local configuration remains until removed or purged by the administrator.
        </li>
      </ul>
      <p>
        <code>sudo hyn unlink</code> stops future submissions but does not delete data
        already hosted. To request deletion, email{" "}
        <a href={`mailto:${contact}`}>{contact}</a> from the account email and identify
        the account and nodes. After verification, we will delete requested data from
        active Hosted Service systems within <strong>7 days</strong>. Limited copies
        can remain temporarily in provider backups, security records or where law
        requires retention; they remain isolated from ordinary use and expire under
        the applicable schedule.
      </p>

      <h2>9. Choices and rights</h2>
      <p>
        You may use the open-source agent without linking the Hosted Service. Settings
        can also disable optional public-IP lookups, latency or DNS probes, throughput
        tests, update checks, service tracking and outbound notifications. Keep{" "}
        <code>notify_access_details=off</code> unless a legitimate monitoring need,
        lawful basis and restricted destination justify access identifiers in
        messages. That setting hides those access identities, not the other system
        context an alert or report needs to describe the server.
      </p>
      <p>
        Subject to applicable law, you may request access, correction, deletion,
        restriction, objection, portability or withdrawal of consent at{" "}
        <a href={`mailto:${contact}`}>{contact}</a>. We may verify identity. If NexusV
        processes telemetry only for your organisation, direct the request to that
        organisation first. EEA residents may complain to their competent supervisory
        authority; Indian users may use the grievance contact and available statutory
        complaint process.
      </p>

      <h2>10. Adults, automated decisions and changes</h2>
      <p>
        Registration is for people aged <strong>18 or older</strong>. Alert rules
        compare measurements with administrator-selected thresholds and do not make
        decisions producing legal or similarly significant effects about people.
      </p>
      <p>
        For material policy changes we will provide email or prominent dashboard
        notice at least 30 days in advance where practical. Urgent legal or security
        changes may take effect sooner, with notice as soon as reasonably possible.
      </p>

      <p>
        <strong>Operator:</strong> NEXUSV TECHNOLOGIES PRIVATE LIMITED
        <br />
        <strong>Contact:</strong> <a href={`mailto:${contact}`}>{contact}</a>
      </p>
    </LegalPage>
  );
}
