import type { Metadata } from "next";
import { Important, LegalPage, Placeholder } from "@/components/legal-page";

export const metadata: Metadata = {
  title: "Disclaimer & Licence / HYN-view",
  description:
    "hyn-view is an independent monitoring tool with no affiliation to any node platform, and contains no cryptocurrency functionality.",
};

export default function LegalNoticePage() {
  return (
    <LegalPage
      kicker="// disclaimer"
      title="Disclaimer, notices and licence"
      updated="19 August 2026"
    >
      <h2>1. No affiliation with any node platform</h2>
      <p>
        hyn-view is an independent system-monitoring tool developed and maintained by{" "}
        <Placeholder>[YOUR LEGAL NAME]</Placeholder> (&ldquo;the Author&rdquo;).
      </p>
      <Important>
        The Author is <strong>not affiliated with, endorsed by, sponsored by,
        partnered with, or acting as an agent of</strong> Highway P2P
        (highwayp2p.com), Hiway Network, or any other network, node, relay,
        bandwidth-sharing, distributed-computing or infrastructure platform, nor any
        operator, foundation, issuer or vendor associated with them.
      </Important>
      <p>
        No such organisation has reviewed, approved, certified or supported this
        software. No business relationship, joint venture, agency, licence or
        partnership exists or is implied.
      </p>

      <h3>Why other products are named at all</h3>
      <p>
        This tool can optionally read the state of node software that a machine&apos;s
        owner has already installed, in order to display it. Naming that software is
        necessary to describe what is being observed. Such references are{" "}
        <strong>nominative</strong> — they identify a product to describe
        interoperability, nothing more. All product names, trademarks and logos are
        the property of their respective owners, and their use here implies no
        endorsement or association. Rights holders with an objection can write to{" "}
        <Placeholder>[CONTACT EMAIL]</Placeholder>.
      </p>

      <h2>2. What this software does — and does not — do</h2>
      <p>
        <strong>It observes. It does not participate.</strong> It reads operating-system
        counters any local user can already read — <code>/proc</code>,{" "}
        <code>/sys</code>, <code>df</code>, <code>ping</code>, systemd unit metadata —
        and presents them. Its purpose is measuring <strong>computer resource
        usage</strong> on machines the operator already administers.
      </p>
      <p>It contains no functionality for, and performs none of:</p>
      <table>
        <thead>
          <tr><th>Not present</th><th>Meaning</th></tr>
        </thead>
        <tbody>
          <tr><td>Cryptocurrency of any kind</td><td>No wallet, no private keys, no seed phrases, no addresses, no transactions, no signing</td></tr>
          <tr><td>Mining or proof-of-work</td><td>It does not mine, stake, validate, or contribute compute to any network</td></tr>
          <tr><td>Token, coin, sale or offering</td><td>Nothing is issued, sold, distributed or promoted</td></tr>
          <tr><td>Trading, exchange, custody, payments</td><td>It moves no funds and holds no assets</td></tr>
          <tr><td>Earnings, rewards or yield</td><td>No representation that any activity produces income</td></tr>
          <tr><td>Bandwidth resale or relaying</td><td>It routes, proxies and relays nothing</td></tr>
          <tr><td>Recruitment or referral</td><td>It enrols nobody in any programme or network</td></tr>
        </tbody>
      </table>
      <Important>
        This is not a cryptocurrency product, an investment product, or a financial
        product, and nothing in it or its documentation is investment, financial, tax
        or legal advice.
      </Important>

      <h3>Read-only with respect to third-party software</h3>
      <p>
        Where optional node tracking is enabled, this tool is strictly read-only. It
        does not start, stop, restart, enable, disable, install, update, configure or
        modify any third-party software or its data, and does not execute a node binary
        to inspect it unless an operator explicitly opts in. This is enforced
        mechanically rather than merely promised: the test suite inspects the source
        for mutating commands and fails if one appears. Tracking can be switched off
        entirely with <code>highway_track=off</code>.
      </p>

      <h2>3. Not independently verified</h2>
      <p>
        This software was written to the requirements of a single client and has{" "}
        <strong>not</strong> been independently audited, certified, benchmarked or
        verified. No representation is made that any measurement is accurate or
        complete, that any alert will identify a real problem or avoid reporting one
        that does not exist, that any notification will be delivered in time to be
        useful, or that it is compatible with any version of any third-party software
        it can observe.
      </p>
      <p>
        Measurements derive from counters and sensors reported by the host system,
        which are themselves frequently wrong — a sensor may be absent, mislabelled or
        miscalibrated, a virtualised host may report fabricated values, and a counter
        may reset or wrap. Where a value cannot be read this software reports it as
        unavailable rather than as zero, but it cannot detect a value that is merely
        incorrect.
      </p>
      <Important>
        Do not rely on this tool as the sole safeguard for any system where failure
        carries meaningful cost. It is an aid to a human operator, not a substitute for
        one. If the monitored machine goes down, so does the software on it — so it
        reports nothing, and <strong>absence of an alert never means
        healthy</strong>.
      </Important>

      <h2>4. Operator responsibility</h2>
      <p>
        You are responsible for the machines you monitor. You must own the machine or
        be authorised by its owner; monitoring it must be lawful where you and it are
        located and must breach no contract or hosting policy; and where telemetry
        identifies people you must have a lawful basis and inform them. You must also
        comply with the terms of any third-party platform whose software you choose to
        observe — those terms are between you and that platform.
      </p>
      <p>
        Using this tool against a system you are not authorised to monitor may be
        unlawful. The Author does not endorse or support such use.
      </p>

      <h2>5. No warranty</h2>
      <p>
        This software is provided <strong>&ldquo;as is&rdquo;, without warranty of any
        kind</strong>, express or implied, including merchantability, fitness for a
        particular purpose, accuracy and non-infringement. To the maximum extent
        permitted by law the Author is not liable for any claim, damage or loss —
        including lost profits, lost data, business interruption, or damage from an
        undetected fault, a missed alert, a false alert, or reliance on any figure
        displayed — whether in contract, tort or otherwise. Some jurisdictions do not
        allow such exclusions, so parts may not apply to you, and nothing here limits
        liability that cannot lawfully be limited.
      </p>

      <h2>6. Licence</h2>
      <p>
        The software is released under the <strong>MIT Licence</strong>.
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

Copyright (c) 2026 Vivek W (AryanVBW)

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

      <p>
        Contact: <Placeholder>[CONTACT EMAIL]</Placeholder>
      </p>
    </LegalPage>
  );
}
