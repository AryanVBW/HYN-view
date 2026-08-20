import type { Metadata } from "next";
import Link from "next/link";
import { Important, LegalPage, Placeholder } from "@/components/legal-page";

export const metadata: Metadata = {
  title: "Terms of Use / HYN-view",
  description:
    "Terms governing use of the hyn-view dashboard, including accuracy limits, suspension rights and liability.",
};

export default function TermsPage() {
  return (
    <LegalPage kicker="// terms" title="Terms of Use" updated="19 August 2026">
      <Important>
        Placeholders must be filled in and this reviewed by a lawyer before you rely
        on it. Liability caps and warranty exclusions are the clauses most often
        unenforceable if drafted badly or where consumer law applies.
      </Important>

      <h2>1. Agreement</h2>
      <p>
        These terms govern the hyn-view dashboard operated by{" "}
        <Placeholder>[YOUR LEGAL NAME / COMPANY]</Placeholder> at{" "}
        <Placeholder>[PORTAL URL]</Placeholder> (&ldquo;the Service&rdquo;). Your
        rights to <strong>the software itself</strong> come from its MIT licence and
        are not restricted by these terms; where the two differ about the software,
        the licence governs.
      </p>
      <p>
        By creating an account or linking a server you accept these terms. If you do
        not, do not use the Service — the agent works perfectly well without it.
      </p>

      <h2>2. What the Service is, and is not</h2>
      <p>
        It displays system measurements — processor, memory, storage, temperature and
        network usage — reported by servers you link, and records the notifications
        sent about them. That is all.
      </p>
      <p>
        It is <strong>not</strong> a cryptocurrency, financial, investment or payment
        product; not a wallet or custodian; not a mining, staking, validation or
        bandwidth-sharing service; not a way to earn income; and not a safety,
        industrial-control or life-critical system. Nothing in it is investment,
        financial, tax or legal advice.
      </p>
      <p>
        We are <strong>not affiliated with Highway P2P (highwayp2p.com) or any other
        node, relay or infrastructure platform</strong> and do not act on their
        behalf. If you run such software, that relationship is between you and that
        platform under its terms, to which we are not a party. See the{" "}
        <Link href="/legal">disclaimer</Link>.
      </p>

      <h2>3. Your authority to monitor</h2>
      <Important>
        You may only link a machine you own or are authorised by its owner to monitor.
      </Important>
      <p>
        By linking a machine you confirm you have that authority; that monitoring it
        and sending its telemetry here is lawful where you and the machine are; and
        that it breaches no contract or hosting policy applying to it. Where telemetry
        identifies people — an account name in a process list, for instance — you
        confirm you have a lawful basis and will inform them. For that data you are
        the controller and we process it for you.
      </p>
      <p>
        You must be able to form a binding contract and be at least{" "}
        <Placeholder>[16 / 18]</Placeholder>.
      </p>

      <h2>4. Accounts and credentials</h2>
      <p>
        You are responsible for your account, everything done under it, and the
        security of the tokens issued to your machines. Tell us at{" "}
        <Placeholder>[CONTACT EMAIL]</Placeholder> if either is compromised, and
        revoke the affected machine in the dashboard. Do not share an account or try
        to reach another client&apos;s data.
      </p>

      <h2>5. Acceptable use</h2>
      <p>You must not:</p>
      <ul>
        <li>link or monitor a machine you are not authorised to monitor;</li>
        <li>attempt to reach another client&apos;s data, or obtain privileges you were not granted;</li>
        <li>probe, load-test, scrape or disrupt the Service, or circumvent its rate or access controls;</li>
        <li>send unlawful, deceptive, abusive or unsolicited bulk messages through the notification features;</li>
        <li>use the Service to monitor people rather than machines;</li>
        <li>submit deliberately falsified telemetry;</li>
        <li>use the Service where that would breach sanctions or export controls applying to you.</li>
      </ul>

      <h2>6. Your content</h2>
      <p>
        You keep all rights to the telemetry and configuration you submit. You grant
        us only the permission needed to store, process and display it back to you and
        to operate and secure the Service. We claim no ownership and do not use your
        data for advertising or to train models.
      </p>

      <h2>7. Availability, and our right to pause or suspend</h2>
      <p>
        The Service comes with <strong>no service-level commitment</strong>. It may be
        unavailable for maintenance, and may change or be discontinued — with{" "}
        <Placeholder>[NOTICE PERIOD]</Placeholder> notice where practical, and a
        chance to export your data.
      </p>
      <p>
        We may <strong>pause</strong>, <strong>suspend</strong> or{" "}
        <strong>revoke</strong> a machine, or suspend an account, where we reasonably
        believe it necessary to protect the Service, to comply with law, or because
        these terms have been breached, and for scheduled maintenance. A pause stops
        telemetry being accepted and may expire by itself; a suspension lasts until we
        lift it; a revocation invalidates a machine&apos;s credential permanently and
        it must be paired again.
      </p>
      <Important>
        While a machine is paused, suspended or revoked, no telemetry is recorded and
        no alerts are generated for it.
      </Important>
      <p>
        Except where a breach or legal requirement makes it impractical we will tell
        you and give a reason, and where the reason is not urgent we will give notice
        first. Every such action is recorded in an audit log.
      </p>

      <h2>8. Fees</h2>
      <p>
        <Placeholder>[DECIDE]</Placeholder> Either: the Service is currently free, and
        if we introduce charges we will give at least{" "}
        <Placeholder>[NOTICE PERIOD]</Placeholder> notice. Or: fees, billing period
        and refunds are as set out at <Placeholder>[PRICING URL]</Placeholder>.
      </p>

      <h2>9. Third-party services</h2>
      <p>
        The Service depends on third parties including Supabase and{" "}
        <Placeholder>[HOSTING PROVIDER]</Placeholder>, and on any notification
        providers you configure. Their own terms may apply to you.{" "}
        <strong>We are not responsible for third-party services or their handling of
        data</strong>, and an outage at one of them is not a breach of these terms by
        us.
      </p>

      <h2>10. Accuracy — the limitation that matters most</h2>
      <p>
        Measurements come from counters and sensors reported by your own operating
        system and hardware, which are regularly incomplete or wrong.{" "}
        <strong>We do not warrant that any figure, any alert, or the absence of an
        alert is accurate, timely or complete.</strong>
      </p>
      <Important>
        If a monitored machine goes down, the agent on it goes down too — and reports
        nothing. <strong>Silence never means healthy.</strong> Detecting an
        unreachable host needs an independent external service.
      </Important>
      <p>
        Notifications depend on third-party providers and may be delayed, throttled,
        filtered as spam, or lost. A daily cap exists to stop a misbehaving rule
        exhausting your provider&apos;s quota; once reached, further messages are
        suppressed. The software has not been independently audited or verified.
      </p>
      <p>
        <strong>Do not rely on the Service as the sole safeguard for any system where
        failure carries meaningful cost.</strong>
      </p>

      <h2>11. Disclaimer of warranties</h2>
      <p>
        To the fullest extent permitted by law the Service and software are provided{" "}
        <strong>&ldquo;as is&rdquo; and &ldquo;as available&rdquo;, without warranties
        of any kind</strong>, express, implied or statutory, including
        merchantability, fitness for a particular purpose, accuracy, uninterrupted or
        error-free operation, and non-infringement.
      </p>

      <h2>12. Limitation of liability</h2>
      <p>
        To the fullest extent permitted by law we are not liable for indirect,
        incidental, special, consequential, punitive or exemplary damages, nor for lost
        profits, revenue, or corrupted data, business interruption, or damage arising
        from an undetected fault, a missed or false alert, or reliance on any figure
        the Service displays — even if we were told such damage was possible. Our
        total aggregate liability is limited to the greater of the fees you paid us in
        the preceding 12 months and <Placeholder>[AMOUNT]</Placeholder>.
      </p>
      <p>
        <strong>Nothing here limits liability that cannot lawfully be limited</strong>,
        including for death or personal injury caused by negligence, or for fraud. If
        you are a consumer your statutory rights are unaffected.
      </p>

      <h2>13. Indemnity</h2>
      <p>
        You will indemnify us against claims, losses and reasonable costs arising from
        your breach of these terms, from monitoring a machine you were not authorised
        to monitor, or from telemetry you submitted that identified a person without a
        lawful basis.
      </p>

      <h2>14. Termination</h2>
      <p>
        Stop at any time: <code>sudo hyn unlink</code> on each machine, then ask us to
        delete your account. We may terminate for material breach, or on{" "}
        <Placeholder>[NOTICE PERIOD]</Placeholder> notice if we discontinue the
        Service. Data is then deleted as described in the{" "}
        <Link href="/privacy">privacy policy</Link>. Sections 6 and 11 to 13 survive.
      </p>

      <h2>15. Changes, law and general</h2>
      <p>
        Material changes will be announced by <Placeholder>[HOW]</Placeholder> at
        least <Placeholder>[NOTICE PERIOD]</Placeholder> before taking effect. These
        terms are governed by the laws of{" "}
        <Placeholder>[JURISDICTION]</Placeholder>, whose courts have jurisdiction,
        without affecting any right you have as a consumer to bring proceedings where
        you live. If a provision is unenforceable the rest continues to apply. Not
        enforcing a provision is not a waiver. Nothing here creates a partnership,
        agency or employment relationship.
      </p>
    </LegalPage>
  );
}
