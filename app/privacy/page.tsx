import type { Metadata } from "next";
import { Important, LegalPage, Placeholder } from "@/components/legal-page";

export const metadata: Metadata = {
  title: "Privacy Policy / HYN-view",
  description:
    "What the hyn-view agent reads, what is sent to the dashboard, who can see it, and how to reduce or delete it.",
};

export default function PrivacyPage() {
  return (
    <LegalPage kicker="// privacy" title="Privacy Policy" updated="19 August 2026">
      <Important>
        Placeholders like <Placeholder>[CONTACT EMAIL]</Placeholder> must be filled in
        before this is published, and reviewed by a lawyer in your jurisdiction. If
        you operate this dashboard for other people you are a data controller and
        obligations apply to you regardless of what this page says.
      </Important>

      <h2>1. Two parts, and which one you are using</h2>
      <p>
        The <strong>agent</strong> runs on a server you administer. On its own it reads
        local counters and prints them to your terminal or emails them to an address
        you configure. It sends <strong>nothing to the author of this software</strong>,
        contains no usage analytics, and needs no account.
      </p>
      <p>
        The <strong>dashboard</strong> is optional. Only once you run{" "}
        <code>sudo hyn link</code> and approve it does a server start sending
        telemetry to it.
      </p>
      <p>
        The dashboard is not run by the software&apos;s author as a public service.
        Whoever deploys it operates it and is the controller of the data in it. For
        this deployment that is <Placeholder>[YOUR LEGAL NAME / COMPANY]</Placeholder>,{" "}
        <Placeholder>[POSTAL ADDRESS]</Placeholder>, contactable at{" "}
        <Placeholder>[CONTACT EMAIL]</Placeholder>.
      </p>

      <h2>2. What the agent reads on the machine</h2>
      <p>
        All of it comes from the operating system and stays on the machine unless you
        link it to a dashboard.
      </p>
      <h3>System and resource usage</h3>
      <p>
        Hostname, operating system, kernel, uptime, processor model and core count,
        per-core clock speeds and governor, every temperature sensor the hardware
        exposes, processor utilisation, load, pressure stall information, memory and
        swap, per-filesystem capacity, and disk throughput.
      </p>
      <h3>Network</h3>
      <p>
        Per-interface throughput, errors and drops; link speed, duplex, MTU and MAC
        address; TCP connection states, retransmits and connection-tracking usage;
        the local IP address; latency and packet loss to the configured probe
        targets; the machine&apos;s <strong>public IP address</strong>; and on wireless
        links the network name and gateway.
      </p>
      <h3>Processes and accounts</h3>
      <p>
        The process list, and for the heaviest processes their name, resource use and{" "}
        <strong>the account name of the user running them</strong>. It also reads{" "}
        <strong>who is currently logged in</strong> — account name, terminal,{" "}
        <strong>the source network address of the remote session</strong> and login
        time — and counts <strong>rejected SSH authentication attempts</strong>.
      </p>
      <Important>
        This means reports and alerts can contain personal data. That is deliberate:
        on a server that runs unattended, &ldquo;a login from an address I do not
        recognise&rdquo; is often the most important line in a daily report. Section 6
        explains how to switch it off.
      </Important>

      <h2>3. What reaches the dashboard</h2>
      <p>
        Every push — by default one every five minutes — sends the measurements above,
        including <strong>the account names of the owners of top processes</strong>,
        plus the machine&apos;s name, hostname, operating system, agent version, the
        alert rules currently firing, and the last throughput test. After trying to
        send a notification it also reports the channel, destination, subject, result
        and any error.
      </p>
      <p>
        <strong>Not sent:</strong> file contents, directory listings, command
        arguments, environment variables, keystrokes, log or journal line text,
        database or application data, or the source addresses of logged-in sessions.
      </p>
      <p>
        Note the asymmetry: session account names and source addresses{" "}
        <strong>do</strong> appear in the body of alert and report messages delivered
        to your own channels — your inbox, your push topic — because that is where
        they are useful. They are not stored in the dashboard&apos;s database.
      </p>

      <h2>4. What the dashboard stores about you</h2>
      <ul>
        <li>Your email address, and your name if you give one.</li>
        <li>
          A session cookie so you stay signed in. Strictly necessary.{" "}
          <strong>No advertising, profiling or third-party tracking cookies are
          set.</strong>
        </li>
        <li>
          For each machine: name, hostname, operating system, agent version, when it
          paired, when it last reported, its status and its settings.
        </li>
        <li>
          Notification channels: type, destination, and — only if you choose to store
          it centrally — the provider API key or password. See section 5.
        </li>
        <li>Every notification attempt, with its result and failure reason.</li>
        <li>The telemetry in section 3.</li>
        <li>
          If an administrator pauses, suspends or revokes your machine or account,
          that action with its reason, time and the administrator&apos;s identity.
        </li>
      </ul>
      <p>Pairing codes are stored only as a hash and are deleted after they expire.</p>

      <h3>Who can see it</h3>
      <p>
        You, for your own machines — enforced in the database itself, not just in the
        interface. <strong>Administrators of this deployment can see every
        client&apos;s machines, telemetry and notification history</strong>, and can
        pause, suspend or revoke any of them. If you did not deploy this yourself,
        assume its operator can see your telemetry. Beyond that: the processors in
        section 7, and nobody else. Your data is{" "}
        <strong>not sold, shared for advertising, or used to train models</strong>.
      </p>

      <h2>5. Where credentials live — your choice</h2>
      <p>
        Notification provider credentials can be stored <strong>in the dashboard</strong>,
        which is convenient because every server picks up a change, at the cost of the
        credential being in the database. It is protected by being{" "}
        <strong>write-only from any browser session</strong> — the dashboard can
        replace a key but can never display one — and is released only to a server
        presenting its own token.
      </p>
      <p>
        Or store it <strong>on the machine</strong> in <code>/etc/hyn-view/secrets</code>,
        mode <code>0600</code>, root only. A credential there overrides the dashboard,
        so central storage is entirely optional.
      </p>
      <p>
        Machine tokens and pairing codes are stored <strong>only as SHA-256
        hashes</strong>. Tokens never appear in command-line arguments, so other local
        users cannot read them from the process list. No agent is ever given a key
        that would bypass database access controls.
      </p>

      <h2>6. Reducing what is collected</h2>
      <table>
        <thead>
          <tr><th>To stop collecting</th><th>Set</th></tr>
        </thead>
        <tbody>
          <tr><td>The public IP address</td><td><code>public_ip=off</code></td></tr>
          <tr><td>Node/service tracking</td><td><code>highway_track=off</code></td></tr>
          <tr><td>Latency probes to third parties</td><td><code>latency_targets=</code></td></tr>
          <tr><td>DNS probes</td><td><code>dns_probe=off</code></td></tr>
          <tr><td>Throughput tests</td><td><code>speedtest_per_day=0</code></td></tr>
          <tr><td>Update checks</td><td><code>auto_update=off</code></td></tr>
          <tr><td>Logged-in sessions and rejected logins in messages</td><td><code>report_enabled=off</code></td></tr>
          <tr><td>Sending anything to a dashboard</td><td>never run <code>hyn link</code>, or run <code>sudo hyn unlink</code></td></tr>
        </tbody>
      </table>

      <h2>7. Processors and third-party services</h2>
      <p>
        Running the dashboard involves <strong>Supabase</strong> (database and
        authentication) and <Placeholder>[HOSTING PROVIDER]</Placeholder>. State the
        region your project runs in: <Placeholder>[REGION]</Placeholder>, and, if data
        leaves your users&apos; jurisdiction, the transfer mechanism you rely on.
      </p>
      <p>Only if you enable them: Google (sign-in), your email provider (Resend, Brevo or SMTP), ntfy or Telegram, a Slack or Discord webhook, and an external dead-man&apos;s-switch service.</p>
      <h3>Contacted by the agent</h3>
      <table>
        <thead>
          <tr><th>Endpoint</th><th>Purpose</th><th>Disable</th></tr>
        </thead>
        <tbody>
          <tr><td><code>api.ipify.org</code>, <code>ifconfig.me</code></td><td>Discover the public IP</td><td><code>public_ip=off</code></td></tr>
          <tr><td><code>1.1.1.1</code>, <code>8.8.8.8</code></td><td>Latency probes</td><td><code>latency_targets=</code></td></tr>
          <tr><td><code>cloudflare.com</code></td><td>DNS timing probe</td><td><code>dns_probe=off</code></td></tr>
          <tr><td><code>speed.cloudflare.com</code></td><td>Throughput tests</td><td><code>speedtest_per_day=0</code></td></tr>
          <tr><td><code>registry.npmjs.org</code></td><td>Update check</td><td><code>auto_update=off</code></td></tr>
          <tr><td><code>install.hiwaynetwork.io</code></td><td>Only with node tracking on: compares installed version against published</td><td><code>highway_update_check=off</code></td></tr>
        </tbody>
      </table>
      <p>
        Each is an ordinary network request, so the operator of that endpoint sees your
        machine&apos;s IP address. None of them receive your telemetry. We do not
        control third-party services and are not responsible for them.
      </p>

      <h2>8. How long it is kept</h2>
      <table>
        <thead><tr><th>Data</th><th>Retention</th></tr></thead>
        <tbody>
          <tr><td>Telemetry in the dashboard</td><td><strong>30 days</strong>, then deleted automatically</td></tr>
          <tr><td>Local metric history on the machine</td><td><strong>8 days</strong> by default (<code>metrics_keep_days</code>)</td></tr>
          <tr><td>Notification history</td><td>Until the account is deleted</td></tr>
          <tr><td>Administrative audit records</td><td><Placeholder>[STATE PERIOD]</Placeholder></td></tr>
          <tr><td>Pairing codes</td><td>Expire in 15 minutes, purged within the hour</td></tr>
        </tbody>
      </table>

      <h2>9. Legal bases, if UK/EU GDPR applies</h2>
      <p>
        <Placeholder>[DECIDE which apply and delete the rest]</Placeholder>{" "}
        <strong>Contract</strong> — to provide the dashboard you asked for.{" "}
        <strong>Legitimate interests</strong> — keeping the service secure, preventing
        abuse, and the administrative oversight in section 4.{" "}
        <strong>Consent</strong> — where you choose to store a provider credential
        centrally or to sign in with Google, withdrawable at any time.
      </p>
      <p>
        Where telemetry identifies <em>your</em> colleagues rather than you — an
        account name in a process list — <strong>you</strong> are the controller for
        that data and are responsible for informing them.
      </p>

      <h2>10. Your rights, and doing it yourself</h2>
      <p>
        You may request access, correction, deletion, a portable copy, restriction, or
        object to processing. Write to <Placeholder>[CONTACT EMAIL]</Placeholder>; we
        aim to reply within 30 days. Most of it you can do immediately:
      </p>
      <ul>
        <li><strong>Stop collection now</strong> — <code>sudo hyn unlink</code> on the machine.</li>
        <li><strong>Cut a machine off permanently</strong> — revoke it in the dashboard.</li>
        <li><strong>Delete a machine and all its telemetry</strong> — delete the node; its metrics, speed tests and alerts go with it.</li>
        <li><strong>Delete demo data</strong> — one click wherever it appears.</li>
        <li><strong>Delete your account</strong> — <Placeholder>[DESCRIBE THE PROCESS]</Placeholder>.</li>
      </ul>
      <p>
        In the EEA or UK you may complain to your supervisory authority; in the UK
        that is the ICO.
      </p>

      <h2>11. Security</h2>
      <p>
        Access is restricted per account in the database, not only in the interface.
        Credentials are hashed or held in a column no browser session can read.
        Secrets on the machine are <code>0600</code> and root-only. Message bodies pass
        through restricted temporary files rather than command-line arguments. Text
        from system journals is escaped before being placed in JSON, because it is
        attacker-influenced input. No system is perfectly secure and no guarantee is
        given. Report vulnerabilities to{" "}
        <Placeholder>[SECURITY CONTACT]</Placeholder> rather than publicly.
      </p>

      <h2>12. Children, automated decisions, and changes</h2>
      <p>
        This is server tooling, not directed at children, and not knowingly offered to
        anyone under <Placeholder>[16 / 13]</Placeholder>. Alert rules compare readings
        against thresholds you set; there is no profiling or automated decision-making
        with legal effects. Material changes to this policy will be announced by{" "}
        <Placeholder>[HOW]</Placeholder> before taking effect.
      </p>
    </LegalPage>
  );
}
