import type { Metadata } from "next";
import Link from "next/link";
import { Important, LegalPage } from "@/components/legal-page";

export const metadata: Metadata = {
  title: "Disclaimer & Licence / HYN-view",
  description:
    "HYN-view is independent, open-source server-health monitoring software under the MIT License.",
};

const contact = "vivek.aryanvbw@gmail.com";

export default function LegalNoticePage() {
  return (
    <LegalPage
      kicker="// disclaimer"
      title="Disclaimer, notices and licence"
      updated="21 August 2026"
    >
      <p>
        HYN-view is developed and maintained by{" "}
        <strong>NEXUSV TECHNOLOGIES PRIVATE LIMITED</strong>.
      </p>

      <h2>1. Independent monitoring software</h2>
      <p>
        HYN-view is an independent, voluntary server-health monitoring tool. It reads
        operating-system and hardware measurements and presents them locally or, when
        an authorised administrator links a server, in an optional dashboard. Its
        intended purpose is to make CPU, memory, storage, temperature, network and
        service-health information easier to understand, particularly for Ubuntu and
        other Linux administrators who do not want to rely only on command-line tools.
      </p>
      <Important>
        HYN-view does not by itself administer, repair, patch, secure or take control
        of a server. It is not a substitute for a qualified administrator,
        independent availability monitoring, access controls, backups, patch
        management or incident response.
      </Important>

      <h2>2. No affiliation</h2>
      <p>
        NexusV and HYN-view are <strong>not affiliated with, endorsed by, sponsored
        by, partnered with or acting for</strong> Highway P2P, Hiway Network or any
        other node, relay, bandwidth-sharing, distributed-computing or infrastructure
        platform, unless a signed agreement expressly says otherwise.
      </p>
      <p>
        Third-party names identify software or services with which HYN-view may
        interoperate or which a server owner may observe. All names, trademarks and
        logos remain their owners&apos; property. Their mention does not imply
        endorsement. Rights holders may write to{" "}
        <a href={`mailto:${contact}`}>{contact}</a>.
      </p>

      <h2>3. What HYN-view is not</h2>
      <p>HYN-view contains no intended functionality for:</p>
      <table>
        <thead>
          <tr>
            <th>Not a HYN-view function</th>
            <th>Meaning</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>Cryptocurrency or custody</td>
            <td>No wallet, seed phrase, private key, signing or transaction function</td>
          </tr>
          <tr>
            <td>Mining, staking or validation</td>
            <td>It does not contribute compute or consensus work to a network</td>
          </tr>
          <tr>
            <td>Token, sale or investment</td>
            <td>It issues and promotes no asset, return, reward or yield</td>
          </tr>
          <tr>
            <td>Payments or trading</td>
            <td>It moves no funds, holds no assets and executes no trades</td>
          </tr>
          <tr>
            <td>Bandwidth relay or resale</td>
            <td>It does not proxy, route or resell third-party traffic</td>
          </tr>
        </tbody>
      </table>
      <p>
        Nothing in HYN-view is financial, investment, tax or legal advice. Optional
        service tracking observes status exposed by software the server owner already
        installed. It does not create a relationship between NexusV and that
        software&apos;s publisher or network.
      </p>

      <h2>4. Lawful, authorised use only</h2>
      <p>
        Install or use HYN-view only on a machine you own or are authorised to
        administer. You are responsible for ensuring that monitoring, telemetry and
        notifications comply with applicable law, workplace requirements, contracts
        and hosting-provider policies, and for informing people when telemetry may
        identify them.
      </p>
      <p>
        HYN-view is designed for legitimate server-health monitoring and does not
        authorise malware, intrusion, credential theft, covert surveillance,
        disruption or unlawful activity. Open-source availability cannot guarantee
        that nobody will ever misuse software. NexusV does not endorse unlawful use,
        but this statement is not a blanket waiver of responsibility that law does not
        allow NexusV to exclude. The{" "}
        <Link href="/acceptable-use">Acceptable Use Policy</Link> and{" "}
        <Link href="/terms">Terms</Link> contain the Hosted Service rules.
      </p>

      <h2>5. Accuracy and availability</h2>
      <p>
        Measurements depend on the monitored operating system, hardware, permissions
        and network. Sensors can be absent, delayed, mislabelled, miscalibrated or
        wrong; counters can reset; virtual hosts can expose synthetic values; and
        notification providers can delay, filter or lose messages. HYN-view may show
        a false positive or fail to report a real problem.
      </p>
      <Important>
        If a monitored machine crashes, loses power or loses connectivity, the agent
        may stop reporting. <strong>The absence of an alert does not establish that a
        server is healthy.</strong> Use independent external monitoring for a machine
        that cannot report for itself.
      </Important>
      <p>
        HYN-view has not been independently certified for high-risk or
        safety-critical use. Do not use it as the sole safeguard where an error,
        outage or missed alert could cause substantial loss, injury or harm.
      </p>

      <h2>6. Privacy and providers</h2>
      <p>
        The optional Hosted Service processes account and server information as
        described in the <Link href="/privacy">Privacy Policy</Link>. The current
        primary providers are Vercel, Supabase and Resend. Optional endpoints selected
        by an administrator operate under their own terms. No provider is guaranteed
        to be continuously available. See the{" "}
        <Link href="/subprocessors">provider and subprocessor list</Link>.
      </p>

      <h2>7. Copyright and MIT License</h2>
      <p>
        Copyright © 2026 <strong>NEXUSV TECHNOLOGIES PRIVATE LIMITED</strong>.
        HYN-view is open source under the MIT License. Subject to the licence
        conditions, the software may be used, copied, modified, merged, published,
        distributed, sublicensed and sold. The copyright and permission notices must
        remain in copies or substantial portions.
      </p>
      <p>
        The MIT License governs copyright permission for the software. The Terms
        separately govern accounts and use of the NexusV-hosted dashboard. Neither
        gives permission to violate applicable law or another person&apos;s rights.
      </p>
      <pre
        style={{
          border: "1px solid var(--border)",
          background: "rgba(0,0,0,0.5)",
          padding: "1rem",
          overflowX: "auto",
          fontSize: "0.72rem",
          lineHeight: 1.7,
          whiteSpace: "pre-wrap",
        }}
      >{`MIT License

Copyright (c) 2026 NEXUSV TECHNOLOGIES PRIVATE LIMITED

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.`}</pre>

      <h2>8. Warranty and liability notice</h2>
      <p>
        The software is provided <strong>&ldquo;as is&rdquo;</strong>, without warranty,
        under the MIT License. The Hosted Service is provided &ldquo;as is&rdquo; and
        &ldquo;as available&rdquo; under the Terms. To the fullest extent permitted by
        law, NexusV disclaims implied warranties and liability for indirect or
        consequential losses, inaccurate readings, missed or false alerts,
        unavailable providers or reliance on HYN-view. Nothing limits a liability,
        remedy or consumer right that cannot lawfully be limited.
      </p>

      <p>
        <strong>Operator and copyright owner:</strong> NEXUSV TECHNOLOGIES PRIVATE
        LIMITED
        <br />
        <strong>Official sites:</strong>{" "}
        <a href="https://www.hyn-view.in">www.hyn-view.in</a> and{" "}
        <a href="https://www.hyn-view.info">www.hyn-view.info</a>
        <br />
        <strong>Contact:</strong> <a href={`mailto:${contact}`}>{contact}</a>
      </p>
    </LegalPage>
  );
}
