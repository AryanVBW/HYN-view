import {
  buildDailyDigestContent,
  buildDeviceLinkedContent,
  buildIncidentContent,
  buildSignInContent,
  buildSystemSummaryContent,
  emailPalette,
} from "./cloud-email.ts";
import type { NotificationTemplateKey } from "./types.ts";

// The footer line differs per message because "why did I get this" is the most
// useful sentence in a notification, and after this release the answer is not the
// same for every kind: the sign-in notice still sends itself, everything else is
// sent because a person pressed a button.
const footerNote: Record<NotificationTemplateKey, string> = {
  alert: "Sent from the HYN-view portal when an administrator or maintainer requested it.",
  report: "Sent from the HYN-view portal when an administrator or maintainer requested it.",
  system: "Sent from the HYN-view portal when an administrator or maintainer requested it.",
  signin: "Automatic security notice. If this sign-in was not you, secure the account immediately.",
  device: "Sent once when a machine finishes pairing with your account.",
  first_report: "Sent once, after a newly linked machine uploads its first complete reading.",
};

// The wrapper an administrator actually edits.
//
// It used to be the single string "{{content}}", which is why the editor looked
// empty: a passthrough wrapper is correct behaviour and completely unhelpful as a
// starting point -- there was nothing on screen to change, and no way to tell what
// editing it would even affect. This is the real current format instead, so the
// panel opens on the markup that is in use and every placeholder is visible in
// context.
//
// Constraints this must respect (enforced by applyEmailTemplate and the save RPC):
// no script/iframe/object/embed/form/link/meta, no inline event handlers, no
// http(s)/data src or href, no url(...) in styles. Inline styles and tables only,
// because Gmail strips <style> and Outlook renders through Word.
export function defaultTemplateHtml(key: NotificationTemplateKey): string {
  return `<!-- HYN-view email wrapper. {{content}} is replaced by the generated message
     body; everything around it is yours. Placeholders: {{subject}} {{hostname}}
     {{severity}} {{version}}. Inline styles only - no <style> block, no scripts. -->
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse">
  <tr>
    <td style="padding:0 0 18px">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;background:${emailPalette.codeBg};border:1px solid ${emailPalette.border};border-radius:6px">
        <tr>
          <td style="padding:12px 16px;font:600 11px -apple-system,Segoe UI,Arial,sans-serif;letter-spacing:.06em;text-transform:uppercase;color:${emailPalette.brand}">{{severity}}</td>
          <td align="right" style="padding:12px 16px;font:12px -apple-system,Segoe UI,Arial,sans-serif;color:${emailPalette.muted}">{{hostname}}</td>
        </tr>
      </table>
    </td>
  </tr>
  <tr>
    <td>{{content}}</td>
  </tr>
  <tr>
    <td style="padding:22px 0 0;border-top:1px solid ${emailPalette.border};font:12px -apple-system,Segoe UI,Arial,sans-serif;line-height:1.6;color:${emailPalette.muted}">
      ${footerNote[key]}<br>HYN-view &middot; agent {{version}}
    </td>
  </tr>
</table>`;
}

// Realistic sample bodies, built with the same functions the real senders use, so
// the admin preview is the actual email rather than a placeholder rectangle.
export function sampleContentFor(key: NotificationTemplateKey): string {
  const now = new Date().toISOString();
  switch (key) {
    case "alert":
      return buildIncidentContent([
        { severity: "crit", message: "disk /: 96% used, projected full in about 2 days", resolved: false, ts: now },
        { severity: "warn", message: "cpu steal 18% sustained over 15 minutes", resolved: false, ts: now },
        { severity: "warn", message: "first-hop latency recovered", resolved: true, ts: now },
      ]);
    case "report":
      return buildDailyDigestContent({
        nodeName: "mumbai-relay-01", sampleCount: 288, cpuAverage: 23.4, cpuPeak: 71.2,
        memoryAverage: 46.8, temperaturePeak: 58, downloadAverageBps: 11_500_000,
        uploadAverageBps: 4_200_000, latencyAverageMs: 18.6, uptimeSeconds: 1_209_600,
      });
    case "signin":
      return buildSignInContent({
        email: "operator@example.com", signedInAt: now,
        ip: "203.0.113.42", userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
      });
    case "device":
      return buildDeviceLinkedContent({
        nodeName: "pune-worker-02", hostname: "pune-worker-02",
        os: "Ubuntu 24.04.1 LTS", agentVersion: "1.10.0", linkedAt: now,
      });
    case "system":
    case "first_report":
      return buildSystemSummaryContent({
        nodeName: "mumbai-relay-01", os: "Ubuntu 24.04.1 LTS", agentVersion: "1.10.0", lastSeenAt: now,
        payload: {
          kernel: "6.8.0-45-generic",
          cpu: { model: "AMD Ryzen 9 7950X", cores: 16, pct: 21.5, temp_c: 54 },
          memory: { total: 67_108_864_000, pct: 44.1 },
          network: {
            iface: "enp3s0", public_ip: "203.0.113.42", local_ip: "10.0.0.12",
            connection: "Wired", link_mbps: 1000, rx_bps: 1_430_000, tx_bps: 520_000,
          },
          speedtest: { down_bps: 118_000_000, up_bps: 41_000_000, latency_us: 17_400 },
          sensors: { "nvme0": 46, "acpitz": 39 },
          highway: { present: 1, health: "ok", version: "v0.3.1", units_active: 6, units_failed: 0 },
        },
      });
  }
}
