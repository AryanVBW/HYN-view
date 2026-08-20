import type { Metadata } from "next";
import Link from "next/link";
import { LegalPage } from "@/components/legal-page";

export const metadata: Metadata = {
  title: "Providers & Subprocessors / HYN-view",
  description:
    "Primary infrastructure providers and optional customer-directed endpoints used by HYN-view.",
};

const contact = "vivek.aryanvbw@gmail.com";

export default function SubprocessorsPage() {
  return (
    <LegalPage
      kicker="// providers"
      title="Providers and subprocessors"
      updated="21 August 2026"
    >
      <p>
        The HYN-view Hosted Service operated by{" "}
        <strong>NEXUSV TECHNOLOGIES PRIVATE LIMITED</strong> uses the primary
        providers below. A provider receives only the categories needed for its
        function. Provider regions and practices can change under the provider&apos;s
        own terms.
      </p>

      <table>
        <thead>
          <tr>
            <th>Provider</th>
            <th>Function and information</th>
            <th>Location note</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><strong>Vercel</strong></td>
            <td>
              Hosts and delivers the web application; may process IP address, request
              metadata, application responses and operational or security logs
            </td>
            <td>Distributed/global infrastructure; not limited to India</td>
          </tr>
          <tr>
            <td><strong>Supabase</strong></td>
            <td>
              Database, API and authentication; processes account and auth records,
              server configuration, telemetry, notifications and administrative
              records
            </td>
            <td>
              Primary database region configured as Mumbai, India; support, logs or
              backups may involve other locations under Supabase terms
            </td>
          </tr>
          <tr>
            <td><strong>Resend</strong></td>
            <td>
              Transactional email; may process recipient address, subject, message
              body, delivery and error metadata
            </td>
            <td>Provider infrastructure may process data outside India</td>
          </tr>
        </tbody>
      </table>

      <h2>Optional identity and customer-directed providers</h2>
      <p>
        <strong>Google</strong> is involved only when Google sign-in is enabled and
        selected. Google authenticates the user and returns identity information such
        as an email address; HYN-view does not receive the Google password.
      </p>
      <p>
        An administrator can configure other destinations or endpoints, including
        SMTP, Brevo, Telegram, ntfy, Slack, Discord, webhooks, public-IP services,
        latency and DNS targets, throughput-test providers, update registries and
        dead-man&apos;s-switch services. The monitored server contacts these
        customer-directed recipients or endpoints directly; destinations and
        credentials are configured locally and are not stored in the Hosted Service.
        They are not necessarily NexusV subprocessors. The administrator is
        responsible for selecting them and reviewing their terms, security, regions
        and data use. External endpoints receive the server&apos;s public or egress
        source IP and ordinary request metadata.
      </p>

      <h2>Changes and international transfers</h2>
      <p>
        Where EU/EEA transfer restrictions apply, an appropriate transfer mechanism
        and supplementary safeguards must apply before a restricted transfer. See the{" "}
        <Link href="/privacy">Privacy Policy</Link> and{" "}
        <Link href="/dpa">Data Processing Addendum</Link>, or contact{" "}
        <a href={`mailto:${contact}`}>{contact}</a> for current provider information
        or signed business terms.
      </p>
      <p>
        NexusV will update this list when a primary provider changes and, where
        practical, give customers at least 30 days&apos; notice before adding a new
        primary subprocessor that materially changes processing. Urgent security or
        continuity changes may occur sooner with notice as soon as reasonably
        possible.
      </p>

      <p>
        <strong>Privacy and subprocessor contact:</strong>{" "}
        <a href={`mailto:${contact}`}>{contact}</a>
      </p>
    </LegalPage>
  );
}
